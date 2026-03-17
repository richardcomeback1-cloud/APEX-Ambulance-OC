local ESX = exports['es_extended']:getSharedObject()

local PLAYER_CACHE = {}
local PROCESSING_LOCKS = {}
local REQUEST_RATE_LIMIT = {}
local ACTION_RATE_LIMIT = {}

local EVENT_COOLDOWN_MS = {
    setDeathStatus = 500,
    payFine = 1000,
    payFineEvent = 1000,
    giveItem = 750,
    removeItem = 300,
    addExp = 1000,
    revive = 1000,
    superRevive = 2500,
    heal = 750,
    requestTalk = 1500,
    requestAccept = 1000,
    transferPlayer = 1000
}
local WRITE_QUEUE = {
    death = {}
}

local DeathDbColumn = nil
local CoreRequestHandlers = {}

local RATE_WINDOW_MS = 1000
local REQUEST_COOLDOWN_MS = 750
local RATE_LIMIT_PER_WINDOW = (Config.CoreRateLimit and Config.CoreRateLimit.perSecond) or 10
local WRITE_FLUSH_MS = (Config.CoreWriteQueue and Config.CoreWriteQueue.flushMs) or 15000

local function oxPrepareAwait(query, params)
    if MySQL and MySQL.prepare and MySQL.prepare.await then
        return MySQL.prepare.await(query, params)
    end

    return exports.oxmysql:prepare(query, params)
end

local function getNowMs()
    return GetGameTimer()
end

local function isValidSource(src)
    return type(src) == 'number' and src > 0
end

local function getPlayerCache(src)
    if not isValidSource(src) then
        return nil
    end

    local cached = PLAYER_CACHE[src]
    if cached then
        return cached
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        return nil
    end

    local accounts = xPlayer.getAccounts and xPlayer.getAccounts() or {}
    local moneyMap = {}

    for i = 1, #accounts do
        local account = accounts[i]
        if account and account.name then
            moneyMap[account.name] = tonumber(account.money) or 0
        end
    end

    local data = {
        source = src,
        identifier = xPlayer.identifier,
        job = xPlayer.job,
        money = moneyMap,
        inventory = xPlayer.getInventory and xPlayer.getInventory(true) or {},
        isDead = xPlayer.get('isDead') or xPlayer.get('dead') or false,
        xPlayer = xPlayer
    }

    PLAYER_CACHE[src] = data
    return data
end

local function setCacheDirtyDeath(identifier, isDead)
    if not identifier or not DeathDbColumn then
        return
    end

    WRITE_QUEUE.death[identifier] = isDead and 1 or 0
end

local function flushWriteQueue()
    if not DeathDbColumn then
        return
    end

    local updates = WRITE_QUEUE.death
    WRITE_QUEUE.death = {}

    for identifier, isDead in pairs(updates) do
        exports.oxmysql:execute(
            ('UPDATE users SET %s = ? WHERE identifier = ?'):format(DeathDbColumn),
            { isDead, identifier }
        )
    end
end

CreateThread(function()
    local columns = oxPrepareAwait('SHOW COLUMNS FROM users WHERE Field IN (?, ?)', { 'is_dead', 'dead' }) or {}
    for i = 1, #columns do
        local field = columns[i].Field
        if field == 'is_dead' then
            DeathDbColumn = 'is_dead'
            break
        elseif field == 'dead' then
            DeathDbColumn = 'dead'
        end
    end

    while true do
        Wait(WRITE_FLUSH_MS)
        flushWriteQueue()
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local cached = PLAYER_CACHE[src]
    if cached then
        setCacheDirtyDeath(cached.identifier, cached.isDead)
    end

    PLAYER_CACHE[src] = nil
    PROCESSING_LOCKS[src] = nil
    REQUEST_RATE_LIMIT[src] = nil
    ACTION_RATE_LIMIT[src] = nil
end)

RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
    local src = playerId
    local resolvedXPlayer = xPlayer or ESX.GetPlayerFromId(src)
    if not resolvedXPlayer then
        return
    end

    local cached = getPlayerCache(src)
    if not cached then
        return
    end

    if DeathDbColumn then
        local dbDead = oxPrepareAwait(
            ('SELECT %s FROM users WHERE identifier = ? LIMIT 1'):format(DeathDbColumn),
            { cached.identifier }
        )

        local value = dbDead and dbDead[1] and dbDead[1][DeathDbColumn]
        local isDead = tonumber(value) == 1
        cached.isDead = isDead
        resolvedXPlayer.set('isDead', isDead)
        resolvedXPlayer.set('dead', isDead)
    end
end)

RegisterNetEvent('esx:setJob', function(playerId, job)
    local cached = PLAYER_CACHE[playerId]
    if cached then
        cached.job = job
    end
end)

local function updateMoneyCache(cached)
    local xPlayer = cached and cached.xPlayer
    if not xPlayer then return end

    local accounts = xPlayer.getAccounts and xPlayer.getAccounts() or {}
    for i = 1, #accounts do
        local account = accounts[i]
        if account and account.name then
            cached.money[account.name] = tonumber(account.money) or 0
        end
    end
end

local function updateInventoryCache(cached)
    local xPlayer = cached and cached.xPlayer
    if not xPlayer then return end
    cached.inventory = xPlayer.getInventory and xPlayer.getInventory(true) or {}
end

local function withPlayerLock(src, cb)
    if PROCESSING_LOCKS[src] then
        return false, 'processing'
    end

    PROCESSING_LOCKS[src] = true
    local ok, result = pcall(cb)
    PROCESSING_LOCKS[src] = nil

    if not ok then
        return false, result
    end

    return true, result
end


local function canRunEvent(src, key)
    local cooldown = EVENT_COOLDOWN_MS[key]
    if not cooldown then
        return true
    end

    local now = getNowMs()
    local state = ACTION_RATE_LIMIT[src]
    if not state then
        ACTION_RATE_LIMIT[src] = { [key] = now }
        return true
    end

    local last = state[key] or 0
    if (now - last) < cooldown then
        return false
    end

    state[key] = now
    return true
end

local function isTargetNearSource(src, target, maxDistance)
    if not isValidSource(src) or not isValidSource(target) then
        return false
    end

    local srcPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(target)
    if srcPed <= 0 or targetPed <= 0 then
        return false
    end

    local srcCoords = GetEntityCoords(srcPed)
    local targetCoords = GetEntityCoords(targetPed)
    if not srcCoords or not targetCoords then
        return false
    end

    local dx = srcCoords.x - targetCoords.x
    local dy = srcCoords.y - targetCoords.y
    local dz = srcCoords.z - targetCoords.z
    local distSq = (dx * dx) + (dy * dy) + (dz * dz)
    local maxDist = tonumber(maxDistance) or 4.0
    return distSq <= (maxDist * maxDist)
end
local function rateLimitOkay(src)
    local now = getNowMs()
    local state = REQUEST_RATE_LIMIT[src]

    if not state then
        REQUEST_RATE_LIMIT[src] = { windowStart = now, count = 1, lastRequest = now }
        return true
    end

    if (now - (state.lastRequest or 0)) < REQUEST_COOLDOWN_MS then
        return false
    end

    state.lastRequest = now

    if (now - state.windowStart) >= RATE_WINDOW_MS then
        state.windowStart = now
        state.count = 1
        return true
    end

    if state.count >= RATE_LIMIT_PER_WINDOW then
        return false
    end

    state.count = state.count + 1
    return true
end

exports('GetPlayer', function(src)
    local cached = getPlayerCache(src)
    if not cached then return nil end

    return {
        source = cached.source,
        identifier = cached.identifier,
        job = cached.job,
        money = cached.money,
        inventory = cached.inventory,
        isDead = cached.isDead
    }
end)

exports('GetInventory', function(src)
    local cached = getPlayerCache(src)
    return cached and cached.inventory or {}
end)

exports('HasItem', function(src, itemName, minCount)
    if type(itemName) ~= 'string' or itemName == '' then
        return false
    end

    local cached = getPlayerCache(src)
    if not cached then return false end

    local needed = tonumber(minCount) or 1
    local entry = cached.inventory[itemName]
    local count = entry and tonumber(entry.count) or 0
    return count >= needed
end)

exports('AddMoney', function(src, amount, account)
    local cached = getPlayerCache(src)
    if not cached then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local accountName = account == 'money' and 'money' or 'bank'
    cached.xPlayer.addAccountMoney(accountName, amount)
    updateMoneyCache(cached)
    return true
end)

exports('RemoveMoney', function(src, amount, account)
    local cached = getPlayerCache(src)
    if not cached then return false end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local accountName = account == 'money' and 'money' or 'bank'
    local current = cached.money[accountName] or 0
    if current < amount then
        return false
    end

    cached.xPlayer.removeAccountMoney(accountName, amount)
    updateMoneyCache(cached)
    return true
end)

local function isAmbulance(cached)
    return cached and cached.job and cached.job.name == 'ambulance'
end

local dynamicTimerConfig = Config.DynamicEarlyRespawnTimer or {}
local function getFallbackMinutes()
    return math.max(1, math.floor((Config.EarlyRespawnTimer or 600000) / 60000))
end

local dynamicRespawnMinutes = {
    player = {
        oneEms = tonumber((dynamicTimerConfig.player and dynamicTimerConfig.player.oneEmsMinutes) or dynamicTimerConfig.oneEmsMinutes) or 5,
        multiEms = tonumber((dynamicTimerConfig.player and dynamicTimerConfig.player.multiEmsMinutes) or dynamicTimerConfig.multiEmsMinutes) or getFallbackMinutes()
    },
    ems = {
        oneEms = tonumber(dynamicTimerConfig.ems and dynamicTimerConfig.ems.oneEmsMinutes) or 3,
        multiEms = tonumber(dynamicTimerConfig.ems and dynamicTimerConfig.ems.multiEmsMinutes) or 8
    }
}

local function getOnlineAmbulanceCount()
    local count = 0
    for _, src in ipairs(GetPlayers()) do
        local cached = getPlayerCache(tonumber(src))
        if isAmbulance(cached) then
            count = count + 1
        end
    end
    return count
end

CoreRequestHandlers.getDeathStatus = function(src)
    local cached = getPlayerCache(src)
    return cached and cached.isDead or false
end

CoreRequestHandlers.getDynamicRespawnTimer = function(src)
    local cached = getPlayerCache(src)
    local emsCount = getOnlineAmbulanceCount()
    local timerMs = Config.EarlyRespawnTimerNoEms or (3 * 60 * 1000)

    if emsCount >= 1 then
        timerMs = Config.EarlyRespawnTimer or (35 * 60 * 1000)
        if dynamicTimerConfig.enabled then
            local mode = isAmbulance(cached) and 'ems' or 'player'
            local modeConfig = dynamicRespawnMinutes[mode]
            if emsCount == 1 then
                timerMs = math.max(1, modeConfig.oneEms) * 60 * 1000
            elseif emsCount > 1 then
                timerMs = math.max(1, modeConfig.multiEms) * 60 * 1000
            end
        end
    end

    return {
        timerMs = timerMs,
        emsCount = emsCount
    }
end

CoreRequestHandlers.getAmbulanceBlipTargets = function(src)
    local requester = getPlayerCache(src)
    if not isAmbulance(requester) then
        return {}
    end

    local targets = {}
    for _, id in ipairs(GetPlayers()) do
        local serverId = tonumber(id)
        local cached = getPlayerCache(serverId)
        if isAmbulance(cached) then
            targets[#targets + 1] = {
                id = serverId,
                name = GetPlayerName(serverId) or tostring(serverId)
            }
        end
    end

    return targets
end

CoreRequestHandlers.checkBalance = function(src)
    local cached = getPlayerCache(src)
    if not cached then return false end

    local amount = Config.EarlyRespawnFineAmount or 0
    return ((cached.money.bank or 0) + (cached.money.money or 0)) >= amount
end

CoreRequestHandlers.hasItem = function(src, payload)
    return exports[GetCurrentResourceName()]:HasItem(src, payload and payload.itemName, payload and payload.minCount)
end

CoreRequestHandlers.getDynamicRespawnSettings = function()
    return {
        enabled = dynamicTimerConfig.enabled and true or false,
        player = {
            oneEmsMinutes = dynamicRespawnMinutes.player.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.player.multiEms
        },
        ems = {
            oneEmsMinutes = dynamicRespawnMinutes.ems.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.ems.multiEms
        }
    }
end

RegisterNetEvent('apex_core:serverRequest', function(requestId, action, payload)
    local src = source
    if not rateLimitOkay(src) then
        TriggerClientEvent('apex_core:serverResponse', src, requestId, false, 'rate_limited')
        return
    end

    if type(requestId) ~= 'number' or type(action) ~= 'string' then
        TriggerClientEvent('apex_core:serverResponse', src, requestId, false, 'invalid_request')
        return
    end

    local handler = CoreRequestHandlers[action]
    if not handler then
        TriggerClientEvent('apex_core:serverResponse', src, requestId, false, 'unknown_action')
        return
    end

    local ok, response = pcall(handler, src, payload)
    if not ok then
        TriggerClientEvent('apex_core:serverResponse', src, requestId, false, 'handler_error')
        return
    end

    TriggerClientEvent('apex_core:serverResponse', src, requestId, true, response)
end)

RegisterNetEvent('esx_ambulancejob:setDeathStatus', function(isDead)
    local src = source
    if not canRunEvent(src, 'setDeathStatus') then return end
    local cached = getPlayerCache(src)
    if not cached then return end

    local deadState = isDead and true or false
    cached.isDead = deadState
    cached.xPlayer.set('isDead', deadState)
    cached.xPlayer.set('dead', deadState)
    setCacheDirtyDeath(cached.identifier, deadState)
end)

RegisterNetEvent('esx_ambulancejob:setDynamicRespawnSettings', function(playerOneEmsMinutes, playerMultiEmsMinutes, emsOneEmsMinutes, emsMultiEmsMinutes)
    local src = source
    local cached = getPlayerCache(src)
    if not isAmbulance(cached) then return end

    local pOne, pMulti, eOne, eMulti = tonumber(playerOneEmsMinutes), tonumber(playerMultiEmsMinutes), tonumber(emsOneEmsMinutes), tonumber(emsMultiEmsMinutes)
    if not pOne or not pMulti or not eOne or not eMulti then
        TriggerClientEvent('esx:showNotification', src, 'กรุณาใส่จำนวนนาทีให้ถูกต้อง')
        return
    end

    pOne, pMulti, eOne, eMulti = math.floor(pOne), math.floor(pMulti), math.floor(eOne), math.floor(eMulti)
    if pOne < 1 or pMulti < 1 or eOne < 1 or eMulti < 1 or pOne > 120 or pMulti > 120 or eOne > 120 or eMulti > 120 then
        TriggerClientEvent('esx:showNotification', src, 'กำหนดเวลาได้ตั้งแต่ 1 - 120 นาทีเท่านั้น')
        return
    end

    dynamicRespawnMinutes.player.oneEms = pOne
    dynamicRespawnMinutes.player.multiEms = pMulti
    dynamicRespawnMinutes.ems.oneEms = eOne
    dynamicRespawnMinutes.ems.multiEms = eMulti

    TriggerClientEvent('esx:showNotification', src, ('ตั้งเวลาเกิดใหม่เรียบร้อย\nผู้เล่น: 1 หมอ %s นาที | 2+ หมอ %s นาที\nหมอ: 1 หมอ %s นาที | 2+ หมอ %s นาที'):format(pOne, pMulti, eOne, eMulti))
end)

RegisterNetEvent('esx_ambulancejob:payFine', function()
    local src = source
    if not canRunEvent(src, 'payFine') then return end
    local cached = getPlayerCache(src)
    if not cached then return end

    local amount = math.max(0, math.floor(tonumber(Config.EarlyRespawnFineAmount) or 0))
    if amount == 0 then return end

    withPlayerLock(src, function()
        if (cached.money.bank or 0) >= amount then
            exports[GetCurrentResourceName()]:RemoveMoney(src, amount, 'bank')
        elseif (cached.money.money or 0) >= amount then
            exports[GetCurrentResourceName()]:RemoveMoney(src, amount, 'money')
        end
    end)
end)

RegisterNetEvent('esx_ambulancejob:payFineEvent', function(payType)
    local src = source
    if not canRunEvent(src, 'payFineEvent') then return end
    local cached = getPlayerCache(src)
    if not cached then return end

    local amount = math.max(0, math.floor(tonumber(Config.EventRespawnFineAmount) or 0))
    if amount == 0 then return end

    local account = payType == 'bank' and 'bank' or 'money'
    withPlayerLock(src, function()
        exports[GetCurrentResourceName()]:RemoveMoney(src, amount, account)
    end)
end)

RegisterNetEvent('esx_ambulancejob:giveItem', function(item, count)
    local src = source
    if not canRunEvent(src, 'giveItem') then return end
    local cached = getPlayerCache(src)
    if not isAmbulance(cached) then return end

    local amount = math.floor(tonumber(count) or 0)
    if type(item) ~= 'string' or item == '' or amount <= 0 or amount > 100 then return end

    withPlayerLock(src, function()
        cached.xPlayer.addInventoryItem(item, amount)
        updateInventoryCache(cached)
    end)
end)

RegisterNetEvent('esx_ambulancejob:removeItem', function(item)
    local src = source
    if not canRunEvent(src, 'removeItem') then return end
    local cached = getPlayerCache(src)
    if not cached then return end
    if type(item) ~= 'string' or item == '' then return end

    withPlayerLock(src, function()
        local invItem = cached.xPlayer.getInventoryItem(item)
        if invItem and (tonumber(invItem.count) or 0) > 0 then
            cached.xPlayer.removeInventoryItem(item, 1)
            updateInventoryCache(cached)
        end
    end)
end)

RegisterNetEvent('esx_ambulancejob:addExp', function(typeItem, count)
    local src = source
    if not canRunEvent(src, 'addExp') then return end
    local cached = getPlayerCache(src)
    if not cached then return end

    local n = math.floor(tonumber(count) or 1)
    if n < 1 or n > 10 then return end

    local itemName = Config.ItemExp
    if itemName and Config.AddItemEXP then
        Config.AddItemEXP(typeItem, cached.xPlayer, itemName, n)
        updateInventoryCache(cached)
    end
end)

RegisterNetEvent('esx_ambulancejob:revive', function(target)
    local src = source
    if not canRunEvent(src, 'revive') then return end
    if not isAmbulance(getPlayerCache(src)) then return end

    target = tonumber(target)
    if not target or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, Config.ReviveDistance or 4.0) then return end
    TriggerClientEvent('esx_ambulancejob:revive', target)
end)

RegisterNetEvent('esx_ambulancejob:superRevive', function(targetList)
    local src = source
    if not canRunEvent(src, 'superRevive') then return end
    if not isAmbulance(getPlayerCache(src)) then return end
    if type(targetList) ~= 'table' then return end

    local maxTargets = math.min(#targetList, 25)
    for i = 1, maxTargets do
        local target = tonumber(targetList[i])
        if target and target ~= src and getPlayerCache(target) and isTargetNearSource(src, target, Config.ReviveDistance or 4.0) then
            TriggerClientEvent('esx_ambulancejob:revive', target)
        end
    end
end)

RegisterNetEvent('esx_ambulancejob:heal', function(target, healType)
    local src = source
    if not canRunEvent(src, 'heal') then return end
    if not isAmbulance(getPlayerCache(src)) then return end

    target = tonumber(target)
    if not target or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, Config.ReviveDistance or 4.0) then return end

    local normalizedHealType = healType == 'big' and 'big' or 'small'
    TriggerClientEvent('esx_ambulancejob:heal', target, normalizedHealType)
end)

RegisterNetEvent('esx_ambulancejob:requestTalk', function(target)
    local src = source
    if not canRunEvent(src, 'requestTalk') then return end

    target = tonumber(target)
    if not target or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, 4.0) then return end

    TriggerClientEvent('esx_ambulancejob:requesToTalk', target, src)
end)

RegisterNetEvent('esx_ambulancejob:requestAccept', function(playerTalk, ok, time)
    local src = source
    if not canRunEvent(src, 'requestAccept') then return end

    local target = tonumber(playerTalk)
    if not target or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, 4.0) then return end

    if ok then
        TriggerClientEvent('esx_ambulancejob:updateTalk', target, tonumber(time) or 500)
    else
        TriggerClientEvent('esx_ambulancejob:updateTalk', target)
    end
end)

RegisterNetEvent('sendplayertogarage', function(target, destinationIndex)
    local src = source
    if not canRunEvent(src, 'transferPlayer') then return end

    local sender = getPlayerCache(src)
    if not sender then return end

    local transferCfg = Config.PlayerTransfer or {}
    if transferCfg.enabled == false then return end
    if transferCfg.requireAmbulanceJob ~= false and not isAmbulance(sender) then return end

    target = tonumber(target)
    if not target or target == src or not getPlayerCache(target) then return end

    local maxDistance = tonumber(transferCfg.maxUseDistance) or 3.0
    if not isTargetNearSource(src, target, maxDistance) then return end

    local destinations = transferCfg.destinations or {}
    if #destinations == 0 then return end

    local index = tonumber(destinationIndex)
    if not index or not destinations[index] then
        if transferCfg.useRandomWhenNoPick then
            index = math.random(1, #destinations)
        else
            index = 1
        end
    end

    TriggerClientEvent('sendplayertogarage', target, index)
end)

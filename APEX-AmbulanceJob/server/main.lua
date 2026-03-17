--[[
    APEX-AmbulanceJob/server/main.lua
    ----------------------------------------------------------------
    Production-oriented refactor (performance + scalability + security)

    Key architecture blocks:
    - PLAYER_CACHE  : O(1) cached player data (identifier/job/money/inventory/death)
    - PLAYER_PEDS   : cached server ped handles
    - PLAYER_STATE  : rate limit windows, cooldowns, temp states
    - JOB_INDEX     : O(1) player index by job name (no full GetPlayers loops)
    - LOCK_SYSTEM   : anti-race lock per source for state-mutating events
    - WRITE_QUEUE   : buffered DB writes (death status)
    - TASK_SCHEDULER: one lightweight scheduler thread for periodic jobs

    Notes:
    - Gameplay logic is preserved.
    - Adds strict validation for all network events.
    - Avoids direct DB writes during hot gameplay paths where possible.
]]

local ESX = exports['es_extended']:getSharedObject()

-- Localized globals for lower global table lookup cost
local GetGameTimer = GetGameTimer
local GetPlayerPed = GetPlayerPed
local GetEntityCoords = GetEntityCoords
local GetPlayerName = GetPlayerName
local TriggerClientEvent = TriggerClientEvent
local RegisterNetEvent = RegisterNetEvent
local AddEventHandler = AddEventHandler
local CreateThread = CreateThread
local Wait = Wait
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local table_concat = table.concat

-- ------------------------------------------------------------------
-- Runtime systems
-- ------------------------------------------------------------------
local PLAYER_CACHE = {} -- [src] = { source, identifier, job, money, inventory, isDead, xPlayer }
local PLAYER_PEDS = {}  -- [src] = ped handle
local PLAYER_STATE = {} -- [src] = { requestLimiter, actionCooldowns }
local JOB_INDEX = {}    -- [jobName] = { [src] = true }
local LOCK_SYSTEM = {}  -- [src] = true while processing protected mutation
local WRITE_QUEUE = {
    death = {}          -- [identifier] = 0/1
}

-- ------------------------------------------------------------------
-- Config-driven runtime constants
-- ------------------------------------------------------------------
local RATE_WINDOW_MS = 5000
local RATE_LIMIT_MAX_REQUESTS = 5
local REQUEST_COOLDOWN_MS = 250

local ACTION_COOLDOWN_MS = {
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
    transferPlayer = 1000,
    setDynamicRespawnSettings = 1000,
}

if Config.CoreRateLimit and tonumber(Config.CoreRateLimit.perSecond) then
    -- Keep compatibility with existing config knob
    RATE_LIMIT_MAX_REQUESTS = math_max(1, tonumber(Config.CoreRateLimit.perSecond))
    RATE_WINDOW_MS = 1000
end

local WRITE_FLUSH_MS = (Config.CoreWriteQueue and tonumber(Config.CoreWriteQueue.flushMs)) or 15000
local CACHE_CLEANUP_MS = 60000

local DeathDbColumn = nil
local dynamicTimerConfig = Config.DynamicEarlyRespawnTimer or {}

local dynamicRespawnMinutes = {
    player = {
        oneEms = tonumber((dynamicTimerConfig.player and dynamicTimerConfig.player.oneEmsMinutes) or dynamicTimerConfig.oneEmsMinutes) or 5,
        multiEms = tonumber((dynamicTimerConfig.player and dynamicTimerConfig.player.multiEmsMinutes) or dynamicTimerConfig.multiEmsMinutes) or math_max(1, math_floor((Config.EarlyRespawnTimer or 600000) / 60000))
    },
    ems = {
        oneEms = tonumber(dynamicTimerConfig.ems and dynamicTimerConfig.ems.oneEmsMinutes) or 3,
        multiEms = tonumber(dynamicTimerConfig.ems and dynamicTimerConfig.ems.multiEmsMinutes) or 8
    }
}

-- ------------------------------------------------------------------
-- Internal helpers
-- ------------------------------------------------------------------
local function isValidSource(src)
    return type(src) == 'number' and src > 0
end

local function isValidString(v)
    return type(v) == 'string' and v ~= ''
end

local function ensurePlayerState(src)
    local state = PLAYER_STATE[src]
    if state then return state end

    state = {
        requestLimiter = { windowStart = 0, count = 0, lastRequest = 0 },
        actionCooldowns = {},
    }

    PLAYER_STATE[src] = state
    return state
end

local function rateLimitOkay(src)
    if not isValidSource(src) then return false end

    local now = GetGameTimer()
    local limiter = ensurePlayerState(src).requestLimiter

    if (now - (limiter.lastRequest or 0)) < REQUEST_COOLDOWN_MS then
        return false
    end

    limiter.lastRequest = now

    if (now - (limiter.windowStart or 0)) >= RATE_WINDOW_MS then
        limiter.windowStart = now
        limiter.count = 1
        return true
    end

    if (limiter.count or 0) >= RATE_LIMIT_MAX_REQUESTS then
        return false
    end

    limiter.count = (limiter.count or 0) + 1
    return true
end

local function canRunEvent(src, eventKey)
    local cooldown = ACTION_COOLDOWN_MS[eventKey]
    if not cooldown then return true end

    local now = GetGameTimer()
    local state = ensurePlayerState(src)
    local last = state.actionCooldowns[eventKey] or 0

    if (now - last) < cooldown then
        return false
    end

    state.actionCooldowns[eventKey] = now
    return true
end

local function withPlayerLock(src, cb)
    if LOCK_SYSTEM[src] then
        return false, 'processing'
    end

    LOCK_SYSTEM[src] = true
    local ok, res = pcall(cb)
    LOCK_SYSTEM[src] = nil

    if not ok then
        return false, res
    end

    return true, res
end

local function oxPrepareAwait(query, params)
    if MySQL and MySQL.prepare and MySQL.prepare.await then
        return MySQL.prepare.await(query, params)
    end

    return exports.oxmysql:prepare(query, params)
end

local function oxExecute(query, params)
    if MySQL and MySQL.update then
        return MySQL.update(query, params)
    end

    return exports.oxmysql:execute(query, params)
end

local function isAmbulance(cache)
    return cache and cache.job and cache.job.name == 'ambulance'
end

local function removeFromJobIndex(src, oldJobName)
    if not isValidString(oldJobName) then return end
    local bucket = JOB_INDEX[oldJobName]
    if bucket then
        bucket[src] = nil
    end
end

local function addToJobIndex(src, jobName)
    if not isValidString(jobName) then return end
    local bucket = JOB_INDEX[jobName]
    if not bucket then
        bucket = {}
        JOB_INDEX[jobName] = bucket
    end
    bucket[src] = true
end

local function setPlayerJobIndex(src, oldJobName, newJobName)
    if oldJobName == newJobName then return end
    removeFromJobIndex(src, oldJobName)
    addToJobIndex(src, newJobName)
end

local function buildMoneyMap(xPlayer)
    local accounts = xPlayer.getAccounts and xPlayer.getAccounts() or {}
    local moneyMap = {}

    for i = 1, #accounts do
        local account = accounts[i]
        if account and account.name then
            moneyMap[account.name] = tonumber(account.money) or 0
        end
    end

    return moneyMap
end

local function createPlayerCache(src, xPlayer)
    if not xPlayer then return nil end

    local cache = {
        source = src,
        identifier = xPlayer.identifier,
        job = xPlayer.job,
        money = buildMoneyMap(xPlayer),
        inventory = xPlayer.getInventory and xPlayer.getInventory(true) or {},
        isDead = (xPlayer.get('isDead') or xPlayer.get('dead')) and true or false,
        xPlayer = xPlayer,
    }

    PLAYER_CACHE[src] = cache
    PLAYER_PEDS[src] = GetPlayerPed(src)

    local jobName = cache.job and cache.job.name or nil
    addToJobIndex(src, jobName)

    ensurePlayerState(src)
    return cache
end

local function getPlayerCache(src)
    if not isValidSource(src) then return nil end

    local cache = PLAYER_CACHE[src]
    if cache then
        return cache
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        return nil
    end

    return createPlayerCache(src, xPlayer)
end

local function updateMoneyCache(cache)
    local xPlayer = cache and cache.xPlayer
    if not xPlayer then return end
    cache.money = buildMoneyMap(xPlayer)
end

local function updateInventoryCache(cache)
    local xPlayer = cache and cache.xPlayer
    if not xPlayer then return end
    cache.inventory = xPlayer.getInventory and xPlayer.getInventory(true) or {}
end

local function setCacheDirtyDeath(identifier, isDead)
    if not isValidString(identifier) or not DeathDbColumn then
        return
    end

    WRITE_QUEUE.death[identifier] = isDead and 1 or 0
end

local function flushWriteQueue()
    if not DeathDbColumn then return end

    local deathUpdates = WRITE_QUEUE.death
    WRITE_QUEUE.death = {}

    for identifier, value in pairs(deathUpdates) do
        oxExecute(('UPDATE users SET %s = ? WHERE identifier = ?'):format(DeathDbColumn), { value, identifier })
    end
end

local function cleanupRuntimeCaches()
    -- cleanup stale memory for disconnected players (defensive)
    for src, _ in pairs(PLAYER_CACHE) do
        if not ESX.GetPlayerFromId(src) then
            PLAYER_CACHE[src] = nil
            PLAYER_PEDS[src] = nil
            PLAYER_STATE[src] = nil
            LOCK_SYSTEM[src] = nil
            for _, bucket in pairs(JOB_INDEX) do
                bucket[src] = nil
            end
        end
    end
end

local function getDistanceSquaredBetweenPlayers(src, target)
    local srcPed = PLAYER_PEDS[src] or GetPlayerPed(src)
    local targetPed = PLAYER_PEDS[target] or GetPlayerPed(target)

    PLAYER_PEDS[src] = srcPed
    PLAYER_PEDS[target] = targetPed

    if not srcPed or srcPed <= 0 or not targetPed or targetPed <= 0 then
        return nil
    end

    local srcCoords = GetEntityCoords(srcPed)
    local targetCoords = GetEntityCoords(targetPed)
    if not srcCoords or not targetCoords then
        return nil
    end

    local dx = srcCoords.x - targetCoords.x
    local dy = srcCoords.y - targetCoords.y
    local dz = srcCoords.z - targetCoords.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function isTargetNearSource(src, target, maxDistance)
    if not isValidSource(src) or not isValidSource(target) then
        return false
    end

    local distSq = getDistanceSquaredBetweenPlayers(src, target)
    if not distSq then return false end

    local d = tonumber(maxDistance) or 4.0
    return distSq <= (d * d)
end

local function getOnlineAmbulanceCount()
    local bucket = JOB_INDEX.ambulance
    if not bucket then return 0 end

    local count = 0
    for src, _ in pairs(bucket) do
        if PLAYER_CACHE[src] or ESX.GetPlayerFromId(src) then
            count = count + 1
        end
    end
    return count
end

local function getAmbulanceTargetList()
    local bucket = JOB_INDEX.ambulance
    if not bucket then return {} end

    local targets = {}
    for src, _ in pairs(bucket) do
        if getPlayerCache(src) then
            targets[#targets + 1] = {
                id = src,
                name = GetPlayerName(src) or tostring(src)
            }
        end
    end

    return targets
end

-- ------------------------------------------------------------------
-- Scheduler (single thread)
-- ------------------------------------------------------------------
local TASK_SCHEDULER = {
    tasks = {
        {
            name = 'flushDatabaseQueue',
            interval = WRITE_FLUSH_MS,
            nextRun = 0,
            fn = flushWriteQueue,
        },
        {
            name = 'cleanupRuntimeCaches',
            interval = CACHE_CLEANUP_MS,
            nextRun = 0,
            fn = cleanupRuntimeCaches,
        }
    }
}

CreateThread(function()
    local columns = oxPrepareAwait('SHOW COLUMNS FROM users WHERE Field IN (?, ?)', { 'is_dead', 'dead' }) or {}
    for i = 1, #columns do
        local field = columns[i] and columns[i].Field
        if field == 'is_dead' then
            DeathDbColumn = 'is_dead'
            break
        elseif field == 'dead' then
            DeathDbColumn = 'dead'
        end
    end

    while true do
        local now = GetGameTimer()
        local nearest = 500

        for i = 1, #TASK_SCHEDULER.tasks do
            local task = TASK_SCHEDULER.tasks[i]
            if now >= task.nextRun then
                task.nextRun = now + task.interval
                pcall(task.fn)
            end

            local remain = task.nextRun - now
            if remain > 0 and remain < nearest then
                nearest = remain
            end
        end

        Wait(math_max(100, nearest))
    end
end)

-- ------------------------------------------------------------------
-- Lifecycle hooks
-- ------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local cache = PLAYER_CACHE[src]
    if cache then
        setCacheDirtyDeath(cache.identifier, cache.isDead)
        removeFromJobIndex(src, cache.job and cache.job.name or nil)
    end

    PLAYER_CACHE[src] = nil
    PLAYER_PEDS[src] = nil
    PLAYER_STATE[src] = nil
    LOCK_SYSTEM[src] = nil
end)

RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
    local src = tonumber(playerId)
    if not isValidSource(src) then return end

    local resolvedXPlayer = xPlayer or ESX.GetPlayerFromId(src)
    if not resolvedXPlayer then return end

    local cache = createPlayerCache(src, resolvedXPlayer)
    if not cache then return end

    if DeathDbColumn then
        local dbDead = oxPrepareAwait(('SELECT %s FROM users WHERE identifier = ? LIMIT 1'):format(DeathDbColumn), { cache.identifier })
        local value = dbDead and dbDead[1] and dbDead[1][DeathDbColumn]
        local isDead = tonumber(value) == 1
        cache.isDead = isDead
        resolvedXPlayer.set('isDead', isDead)
        resolvedXPlayer.set('dead', isDead)
    end
end)

RegisterNetEvent('esx:setJob', function(playerId, job)
    local src = tonumber(playerId)
    if not isValidSource(src) then return end

    local cache = getPlayerCache(src)
    if not cache then return end
    if type(job) ~= 'table' then return end

    local oldJobName = cache.job and cache.job.name or nil
    local newJobName = job.name
    cache.job = job

    setPlayerJobIndex(src, oldJobName, newJobName)
end)

-- ------------------------------------------------------------------
-- Exports
-- ------------------------------------------------------------------
exports('GetPlayer', function(src)
    local cache = getPlayerCache(tonumber(src))
    if not cache then return nil end

    return {
        source = cache.source,
        identifier = cache.identifier,
        job = cache.job,
        money = cache.money,
        inventory = cache.inventory,
        isDead = cache.isDead
    }
end)

exports('GetInventory', function(src)
    local cache = getPlayerCache(tonumber(src))
    return cache and cache.inventory or {}
end)

exports('HasItem', function(src, itemName, minCount)
    if not isValidString(itemName) then return false end

    local cache = getPlayerCache(tonumber(src))
    if not cache then return false end

    local needed = tonumber(minCount) or 1
    local entry = cache.inventory[itemName]
    local count = entry and tonumber(entry.count) or 0
    return count >= needed
end)

exports('AddMoney', function(src, amount, account)
    local cache = getPlayerCache(tonumber(src))
    if not cache then return false end

    amount = math_floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local accountName = account == 'money' and 'money' or 'bank'
    cache.xPlayer.addAccountMoney(accountName, amount)
    updateMoneyCache(cache)
    return true
end)

exports('RemoveMoney', function(src, amount, account)
    local cache = getPlayerCache(tonumber(src))
    if not cache then return false end

    amount = math_floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local accountName = account == 'money' and 'money' or 'bank'
    local current = cache.money[accountName] or 0
    if current < amount then
        return false
    end

    cache.xPlayer.removeAccountMoney(accountName, amount)
    updateMoneyCache(cache)
    return true
end)

-- ------------------------------------------------------------------
-- Core request handlers
-- ------------------------------------------------------------------
local CoreRequestHandlers = {}

CoreRequestHandlers.getDeathStatus = function(src)
    local cache = getPlayerCache(src)
    return cache and cache.isDead or false
end

CoreRequestHandlers.getDynamicRespawnTimer = function(src)
    local cache = getPlayerCache(src)
    local emsCount = getOnlineAmbulanceCount()
    local timerMs = Config.EarlyRespawnTimerNoEms or (3 * 60 * 1000)

    if emsCount >= 1 then
        timerMs = Config.EarlyRespawnTimer or (35 * 60 * 1000)

        if dynamicTimerConfig.enabled then
            local mode = isAmbulance(cache) and 'ems' or 'player'
            local modeCfg = dynamicRespawnMinutes[mode]

            if emsCount == 1 then
                timerMs = math_max(1, tonumber(modeCfg.oneEms) or 1) * 60 * 1000
            else
                timerMs = math_max(1, tonumber(modeCfg.multiEms) or 1) * 60 * 1000
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

    return getAmbulanceTargetList()
end

CoreRequestHandlers.checkBalance = function(src)
    local cache = getPlayerCache(src)
    if not cache then return false end

    local amount = tonumber(Config.EarlyRespawnFineAmount) or 0
    return ((cache.money.bank or 0) + (cache.money.money or 0)) >= amount
end

CoreRequestHandlers.hasItem = function(src, payload)
    return exports[GetCurrentResourceName()]:HasItem(src, payload and payload.itemName, payload and payload.minCount)
end

CoreRequestHandlers.getDynamicRespawnSettings = function()
    return {
        enabled = dynamicTimerConfig.enabled and true or false,
        player = {
            oneEmsMinutes = dynamicRespawnMinutes.player.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.player.multiEms,
        },
        ems = {
            oneEmsMinutes = dynamicRespawnMinutes.ems.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.ems.multiEms,
        }
    }
end

RegisterNetEvent('apex_core:serverRequest', function(requestId, action, payload)
    local src = source
    if not isValidSource(src) then return end

    if not rateLimitOkay(src) then
        TriggerClientEvent('apex_core:serverResponse', src, requestId, false, 'rate_limited')
        return
    end

    if type(requestId) ~= 'number' or not isValidString(action) then
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

-- ------------------------------------------------------------------
-- Gameplay events (validated + anti exploit)
-- ------------------------------------------------------------------
RegisterNetEvent('esx_ambulancejob:setDeathStatus', function(isDead)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'setDeathStatus') then return end

    local cache = getPlayerCache(src)
    if not cache then return end
    if type(isDead) ~= 'boolean' then return end

    cache.isDead = isDead
    cache.xPlayer.set('isDead', isDead)
    cache.xPlayer.set('dead', isDead)
    setCacheDirtyDeath(cache.identifier, isDead)
end)

RegisterNetEvent('esx_ambulancejob:setDynamicRespawnSettings', function(playerOneEmsMinutes, playerMultiEmsMinutes, emsOneEmsMinutes, emsMultiEmsMinutes)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'setDynamicRespawnSettings') then return end

    local cache = getPlayerCache(src)
    if not isAmbulance(cache) then return end

    local pOne = tonumber(playerOneEmsMinutes)
    local pMulti = tonumber(playerMultiEmsMinutes)
    local eOne = tonumber(emsOneEmsMinutes)
    local eMulti = tonumber(emsMultiEmsMinutes)

    if not pOne or not pMulti or not eOne or not eMulti then
        TriggerClientEvent('esx:showNotification', src, 'กรุณาใส่จำนวนนาทีให้ถูกต้อง')
        return
    end

    pOne, pMulti, eOne, eMulti = math_floor(pOne), math_floor(pMulti), math_floor(eOne), math_floor(eMulti)
    if pOne < 1 or pMulti < 1 or eOne < 1 or eMulti < 1 or pOne > 120 or pMulti > 120 or eOne > 120 or eMulti > 120 then
        TriggerClientEvent('esx:showNotification', src, 'กำหนดเวลาได้ตั้งแต่ 1 - 120 นาทีเท่านั้น')
        return
    end

    dynamicRespawnMinutes.player.oneEms = pOne
    dynamicRespawnMinutes.player.multiEms = pMulti
    dynamicRespawnMinutes.ems.oneEms = eOne
    dynamicRespawnMinutes.ems.multiEms = eMulti

    TriggerClientEvent('esx:showNotification', src,
        ('ตั้งเวลาเกิดใหม่เรียบร้อย\nผู้เล่น: 1 หมอ %s นาที | 2+ หมอ %s นาที\nหมอ: 1 หมอ %s นาที | 2+ หมอ %s นาที'):format(pOne, pMulti, eOne, eMulti)
    )
end)

RegisterNetEvent('esx_ambulancejob:payFine', function()
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'payFine') then return end

    local cache = getPlayerCache(src)
    if not cache then return end

    local amount = math_max(0, math_floor(tonumber(Config.EarlyRespawnFineAmount) or 0))
    if amount == 0 then return end

    withPlayerLock(src, function()
        if (cache.money.bank or 0) >= amount then
            exports[GetCurrentResourceName()]:RemoveMoney(src, amount, 'bank')
        elseif (cache.money.money or 0) >= amount then
            exports[GetCurrentResourceName()]:RemoveMoney(src, amount, 'money')
        end
    end)
end)

RegisterNetEvent('esx_ambulancejob:payFineEvent', function(payType)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'payFineEvent') then return end

    local cache = getPlayerCache(src)
    if not cache then return end

    local amount = math_max(0, math_floor(tonumber(Config.EventRespawnFineAmount) or 0))
    if amount == 0 then return end

    local account = payType == 'bank' and 'bank' or 'money'
    withPlayerLock(src, function()
        exports[GetCurrentResourceName()]:RemoveMoney(src, amount, account)
    end)
end)

RegisterNetEvent('esx_ambulancejob:giveItem', function(item, count)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'giveItem') then return end

    local cache = getPlayerCache(src)
    if not isAmbulance(cache) then return end

    local amount = math_floor(tonumber(count) or 0)
    if not isValidString(item) or amount <= 0 or amount > 100 then return end

    withPlayerLock(src, function()
        cache.xPlayer.addInventoryItem(item, amount)
        updateInventoryCache(cache)
    end)
end)

RegisterNetEvent('esx_ambulancejob:removeItem', function(item)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'removeItem') then return end

    local cache = getPlayerCache(src)
    if not cache then return end
    if not isValidString(item) then return end

    withPlayerLock(src, function()
        local invItem = cache.xPlayer.getInventoryItem(item)
        if invItem and (tonumber(invItem.count) or 0) > 0 then
            cache.xPlayer.removeInventoryItem(item, 1)
            updateInventoryCache(cache)
        end
    end)
end)

RegisterNetEvent('esx_ambulancejob:addExp', function(typeItem, count)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'addExp') then return end

    local cache = getPlayerCache(src)
    if not cache then return end

    local n = math_floor(tonumber(count) or 1)
    if n < 1 or n > 10 then return end

    local itemName = Config.ItemExp
    if itemName and Config.AddItemEXP then
        Config.AddItemEXP(typeItem, cache.xPlayer, itemName, n)
        updateInventoryCache(cache)
    end
end)

RegisterNetEvent('esx_ambulancejob:revive', function(target)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'revive') then return end

    local sender = getPlayerCache(src)
    if not isAmbulance(sender) then return end

    target = tonumber(target)
    if not isValidSource(target) or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, Config.ReviveDistance or 4.0) then return end

    TriggerClientEvent('esx_ambulancejob:revive', target)
end)

RegisterNetEvent('esx_ambulancejob:superRevive', function(targetList)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'superRevive') then return end

    local sender = getPlayerCache(src)
    if not isAmbulance(sender) then return end
    if type(targetList) ~= 'table' then return end

    local maxTargets = math_min(#targetList, 25)
    local maxDistance = Config.ReviveDistance or 4.0

    for i = 1, maxTargets do
        local target = tonumber(targetList[i])
        if isValidSource(target) and target ~= src and getPlayerCache(target) and isTargetNearSource(src, target, maxDistance) then
            TriggerClientEvent('esx_ambulancejob:revive', target)
        end
    end
end)

RegisterNetEvent('esx_ambulancejob:heal', function(target, healType)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'heal') then return end

    local sender = getPlayerCache(src)
    if not isAmbulance(sender) then return end

    target = tonumber(target)
    if not isValidSource(target) or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, Config.ReviveDistance or 4.0) then return end

    local normalizedHealType = healType == 'big' and 'big' or 'small'
    TriggerClientEvent('esx_ambulancejob:heal', target, normalizedHealType)
end)

RegisterNetEvent('esx_ambulancejob:requestTalk', function(target)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'requestTalk') then return end

    target = tonumber(target)
    if not isValidSource(target) or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, 4.0) then return end

    TriggerClientEvent('esx_ambulancejob:requesToTalk', target, src)
end)

RegisterNetEvent('esx_ambulancejob:requestAccept', function(playerTalk, ok, time)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'requestAccept') then return end

    local target = tonumber(playerTalk)
    if not isValidSource(target) or target == src or not getPlayerCache(target) then return end
    if not isTargetNearSource(src, target, 4.0) then return end

    if ok then
        TriggerClientEvent('esx_ambulancejob:updateTalk', target, tonumber(time) or 500)
    else
        TriggerClientEvent('esx_ambulancejob:updateTalk', target)
    end
end)

RegisterNetEvent('sendplayertogarage', function(target, destinationIndex)
    local src = source
    if not isValidSource(src) then return end
    if not canRunEvent(src, 'transferPlayer') then return end

    local sender = getPlayerCache(src)
    if not sender then return end

    local transferCfg = Config.PlayerTransfer or {}
    if transferCfg.enabled == false then return end
    if transferCfg.requireAmbulanceJob ~= false and not isAmbulance(sender) then return end

    target = tonumber(target)
    if not isValidSource(target) or target == src or not getPlayerCache(target) then return end

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

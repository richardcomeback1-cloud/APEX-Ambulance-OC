ESX = ESX or exports['es_extended']:getSharedObject()

local function getXPlayer(source)
    return ESX.GetPlayerFromId(source)
end

ESX.RegisterServerCallback('esx_ambulancejob:getDeathStatus', function(source, cb)
    local xPlayer = getXPlayer(source)
    local isDead = false
    if xPlayer then
        isDead = xPlayer.get('isDead') or xPlayer.get('dead') or false
    end
    cb(isDead)
end)

RegisterNetEvent('esx_ambulancejob:setDeathStatus', function(isDead)
    local src = source
    local xPlayer = getXPlayer(src)
    if xPlayer then
        xPlayer.set('isDead', isDead and true or false)
        xPlayer.set('dead', isDead and true or false)
    end
end)

ESX.RegisterServerCallback('esx_ambulancejob:checkBalance', function(source, cb)
    local xPlayer = getXPlayer(source)
    if not xPlayer then
        cb(false)
        return
    end
    local amount = Config.EarlyRespawnFineAmount or 0
    local bank = xPlayer.getAccount('bank') and xPlayer.getAccount('bank').money or 0
    local cash = xPlayer.getAccount('money') and xPlayer.getAccount('money').money or 0
    cb((bank + cash) >= amount)
end)

ESX.RegisterServerCallback('esx_ambulancejob:hasItem', function(source, cb, itemName, minCount)
    local xPlayer = getXPlayer(source)
    if not xPlayer or not itemName or itemName == '' then
        cb(false)
        return
    end

    local need = tonumber(minCount) or 1
    local inv = xPlayer.getInventoryItem and xPlayer.getInventoryItem(itemName) or nil
    local count = inv and (tonumber(inv.count) or 0) or 0

    cb(count >= need)
end)

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

local function isAmbulance(xPlayer)
    return xPlayer and xPlayer.job and xPlayer.job.name == 'ambulance'
end

local function getOnlineAmbulanceCount()
    local count = 0

    if ESX.GetExtendedPlayers then
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            if isAmbulance(xPlayer) then
                count = count + 1
            end
        end
        return count
    end

    if ESX.GetPlayers then
        for _, playerId in ipairs(ESX.GetPlayers()) do
            local xPlayer = getXPlayer(playerId)
            if isAmbulance(xPlayer) then
                count = count + 1
            end
        end
    end

    return count
end

ESX.RegisterServerCallback('esx_ambulancejob:getDynamicRespawnTimer', function(source, cb)
    local xPlayer = getXPlayer(source)
    local emsCount = getOnlineAmbulanceCount()
    local timerMs = Config.EarlyRespawnTimerNoEms or (3 * 60 * 1000)

    if emsCount >= 1 then
        timerMs = Config.EarlyRespawnTimer or (35 * 60 * 1000)

        if dynamicTimerConfig.enabled then
            local mode = isAmbulance(xPlayer) and 'ems' or 'player'
            local modeConfig = dynamicRespawnMinutes[mode]

            if emsCount == 1 then
                timerMs = math.max(1, modeConfig.oneEms) * 60 * 1000
            elseif emsCount > 1 then
                timerMs = math.max(1, modeConfig.multiEms) * 60 * 1000
            end
        end
    end

    cb(timerMs, emsCount)
end)


ESX.RegisterServerCallback('esx_ambulancejob:getAmbulanceBlipTargets', function(source, cb)
    local requester = getXPlayer(source)
    if not requester or not isAmbulance(requester) then
        cb({})
        return
    end

    local targets = {}

    if ESX.GetPlayers then
        for _, playerId in ipairs(ESX.GetPlayers()) do
            local xPlayer = getXPlayer(playerId)
            if isAmbulance(xPlayer) then
                table.insert(targets, {
                    id = tonumber(playerId),
                    name = (xPlayer.getName and xPlayer.getName()) or GetPlayerName(playerId) or tostring(playerId)
                })
            end
        end
    end

    cb(targets)
end)

ESX.RegisterServerCallback('esx_ambulancejob:getDynamicRespawnSettings', function(source, cb)
    cb({
        enabled = dynamicTimerConfig.enabled and true or false,
        player = {
            oneEmsMinutes = dynamicRespawnMinutes.player.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.player.multiEms
        },
        ems = {
            oneEmsMinutes = dynamicRespawnMinutes.ems.oneEms,
            multiEmsMinutes = dynamicRespawnMinutes.ems.multiEms
        }
    })
end)

RegisterNetEvent('esx_ambulancejob:setDynamicRespawnSettings', function(playerOneEmsMinutes, playerMultiEmsMinutes, emsOneEmsMinutes, emsMultiEmsMinutes)
    local src = source
    local xPlayer = getXPlayer(src)
    if not isAmbulance(xPlayer) then
        return
    end

    local pOne = tonumber(playerOneEmsMinutes)
    local pMulti = tonumber(playerMultiEmsMinutes)
    local eOne = tonumber(emsOneEmsMinutes)
    local eMulti = tonumber(emsMultiEmsMinutes)

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
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    local amount = Config.EarlyRespawnFineAmount or 0
    local bank = xPlayer.getAccount('bank') and xPlayer.getAccount('bank').money or 0
    if bank >= amount then
        xPlayer.removeAccountMoney('bank', amount)
    else
        xPlayer.removeAccountMoney('money', amount)
    end
end)

RegisterNetEvent('esx_ambulancejob:payFineEvent', function(payType)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    local amount = Config.EventRespawnFineAmount or 0
    if payType == 'bank' then
        xPlayer.removeAccountMoney('bank', amount)
    else
        xPlayer.removeAccountMoney('money', amount)
    end
end)

RegisterNetEvent('esx_ambulancejob:giveItem', function(item, count)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if xPlayer.job and xPlayer.job.name == 'ambulance' and item and count and count > 0 then
        xPlayer.addInventoryItem(item, count)
    end
end)

RegisterNetEvent('esx_ambulancejob:removeItem', function(item)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if item then
        xPlayer.removeInventoryItem(item, 1)
    end
end)

RegisterNetEvent('esx_ambulancejob:addExp', function(typeItem, count)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    local itemName = Config.ItemExp
    local n = tonumber(count) or 1
    if itemName and Config.AddItemEXP then
        Config.AddItemEXP(typeItem, xPlayer, itemName, n)
    end
end)

RegisterNetEvent('esx_ambulancejob:revive', function(target)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if xPlayer.job and xPlayer.job.name == 'ambulance' and target then
        TriggerClientEvent('esx_ambulancejob:revive', target)
    end
end)

RegisterNetEvent('esx_ambulancejob:superRevive', function(targetList)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if xPlayer.job and xPlayer.job.name == 'ambulance' and type(targetList) == 'table' then
        for _, t in ipairs(targetList) do
            TriggerClientEvent('esx_ambulancejob:revive', t)
        end
    end
end)

RegisterNetEvent('esx_ambulancejob:heal', function(target, healType)
    local src = source
    local xPlayer = getXPlayer(src)
    if not xPlayer then return end
    if xPlayer.job and xPlayer.job.name == 'ambulance' and target then
        TriggerClientEvent('esx_ambulancejob:heal', target, healType or 'small')
    end
end)

RegisterNetEvent('esx_ambulancejob:requestTalk', function(target)
    local src = source
    if target then
        TriggerClientEvent('esx_ambulancejob:requesToTalk', target, src)
    end
end)

RegisterNetEvent('esx_ambulancejob:requestAccept', function(playerTalk, ok, time)
    if playerTalk then
        if ok then
            TriggerClientEvent('esx_ambulancejob:updateTalk', playerTalk, tonumber(time) or 500)
        else
            TriggerClientEvent('esx_ambulancejob:updateTalk', playerTalk)
        end
    end
end)

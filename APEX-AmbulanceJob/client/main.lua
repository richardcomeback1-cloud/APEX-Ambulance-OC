Keys = {
	["ESC"] = 322, ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F5"] = 166, ["F6"] = 167, ["F7"] = 168, ["F8"] = 169, ["F9"] = 56, ["F10"] = 57,
	["~"] = 243, ["1"] = 157, ["2"] = 158, ["3"] = 160, ["4"] = 164, ["5"] = 165, ["6"] = 159, ["7"] = 161, ["8"] = 162, ["9"] = 163, ["-"] = 84, ["="] = 83, ["BACKSPACE"] = 177,
	["TAB"] = 37, ["Q"] = 44, ["W"] = 32, ["E"] = 38, ["R"] = 45, ["T"] = 245, ["Y"] = 246, ["U"] = 303, ["P"] = 199, ["["] = 39, ["]"] = 40, ["ENTER"] = 18,
	["CAPS"] = 137, ["A"] = 34, ["S"] = 8, ["D"] = 9, ["F"] = 23, ["G"] = 47, ["H"] = 74, ["K"] = 311, ["L"] = 182,
	["LEFTSHIFT"] = 21, ["Z"] = 20, ["X"] = 73, ["C"] = 26, ["V"] = 0, ["B"] = 29, ["N"] = 249, ["M"] = 244, [","] = 82, ["."] = 81,
	["LEFTCTRL"] = 36, ["LEFTALT"] = 19, ["SPACE"] = 22, ["RIGHTCTRL"] = 70,
	["HOME"] = 213, ["PAGEUP"] = 10, ["PAGEDOWN"] = 11, ["DELETE"] = 178,
	["LEFT"] = 174, ["RIGHT"] = 175, ["TOP"] = 27, ["DOWN"] = 173,
	["NENTER"] = 201, ["N4"] = 108, ["N5"] = 60, ["N6"] = 107, ["N+"] = 96, ["N-"] = 97, ["N7"] = 117, ["N8"] = 61, ["N9"] = 118
}

local FirstSpawn, PlayerLoaded = true, false
local action = false
IsDead = false

ESX = nil

local talk = false
local bodywarp = false
local ClearBody = false
local AmbulanceBlipTargets = {}
local clearAmbulancePlayerBlips = function() end
local setDeathRemainState = function(_) end

Citizen.CreateThread(function()
	while ESX == nil do
        ESX = exports['es_extended']:getSharedObject()
        Citizen.Wait(100)
    end

	while ESX.PlayerData == nil or ESX.PlayerData.job == nil do
		Citizen.Wait(100)
	end

	PlayerLoaded = true
	Citizen.Wait(2000)
	closeUi()
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
	Wait(2000)
	ESX.PlayerData = xPlayer
	PlayerLoaded = true
	closeUi()
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
	if ESX.PlayerData then
		ESX.PlayerData.job = job
	end

    if not job or job.name ~= 'ambulance' then
        AmbulanceBlipTargets = {}
        clearAmbulancePlayerBlips()
    end
end)

AddEventHandler('esx:onPlayerSpawn', function()
	while not PlayerLoaded do Wait(250) end
	Wait(500)

    pcall(function()
        exports['lizz_playerhud']:toggleHUD(true)
    end)

	IsDead = false
	bodywarp = false
	ClearBody = false
	setDeathRemainState(nil)
	closeUi()
	if FirstSpawn then
        exports.spawnmanager:setAutoSpawn(false) -- ปิด auto respawn
        FirstSpawn = false

		ESX.TriggerServerCallback('esx_ambulancejob:getDeathStatus', function(isDead)
			if isDead and Config.AntiCombatLog then
				Wait(5000)
				pcall(function()
                    exports['lizz_playerhud']:toggleHUD(false)
                end)
				SetEntityHealth(PlayerPedId(), 0)
                Wait(100)
				ESX.ShowNotification(_U('combatlog_message'))
			else
                IsDead = false
            end
        end)
    else
        IsDead = false
    end

    -- RESET UI เมื่อฟื้น
    requestTalk(false)
    sendSignalUi(false)
    gangRequest(false)
    clearBodyUi(false)
    talkingSetui(false)
end)

-- ใช้ Config จากไฟล์แยก (Cache เพื่อประสิทธิภาพ)
local ZONE_CONFIGS = Config.Zones
local ACTION_MAP = Config.ActionMap
local ZONE_DETECTION = Config.ZoneDetection


-- Cache สำหรับประสิทธิภาพ
local ZONE_PRIORITY = {"training", "airdrop", "stelshop", "replight", "waterpipe", "megacement"}

setDeathRemainState = function(seconds)
    local sec = tonumber(seconds)
    if sec and sec >= 0 then
        LocalPlayer.state:set('ambulanceRespawnRemain', math.ceil(sec), true)
    else
        LocalPlayer.state:set('ambulanceRespawnRemain', nil, true)
    end
end

local function getDeathKey(name, fallback)
    local configured = (Config.DeathKeybinds and Config.DeathKeybinds[name]) or fallback
    if not Keys[configured] then
        configured = fallback
    end
    return configured, Keys[configured]
end


local function getDeathKeyCooldownMs(actionName, fallbackSec)
    local tableCooldown = Config.DeathKeyCooldownSec and tonumber(Config.DeathKeyCooldownSec[actionName]) or nil
    local sec = tableCooldown

    if sec == nil and actionName == 'distress' then
        sec = tonumber(Config.DistressSignalCooldownSec)
    end

    if sec == nil then
        sec = fallbackSec or 0
    end

    if sec < 0 then
        sec = 0
    end

    return math.floor(sec * 1000)
end

-- ฟังก์ชันร่วมสำหรับการจัดการ death ในแต่ละ zone
local function handleZoneDeath(zoneType, config, zoneIndex)
    IsDead = true
    ClearBody = config.clearBody
    talk = false

    pcall(function()
        exports["lizz_playerhud"]:toggleHUD(false)
    end)

    Citizen.Wait(100)

    -- ตรวจสอบการตายซ้ำแบบยืดหยุ่น (ถ้าเปิดใช้งาน)
    if Config.EnableDuplicateCheck and config.checks and config.checks.duplicate and config.checks.duplicate.enabled then
        if config.checks.duplicate.indexParam and zoneIndex then
            -- ใช้ export function จาก resource ที่เกี่ยวข้อง
            local isDuplicate = false
            if zoneType == "replight" then
                pcall(function()
                    isDuplicate = exports["lizz_replight"]:checkReplightDeathTracking(zoneIndex)
                end)
            elseif zoneType == "waterpipe" then
                pcall(function()
                    isDuplicate = exports["lizz_waterpipe"]:checkWaterpipeDeathTracking(zoneIndex)
                end)
            elseif zoneType == "megacement" then
                pcall(function()
                    isDuplicate = exports["lizz_megacement"]:checkMegacementDeathTracking(zoneIndex)
                end)
            end
            
            if isDuplicate then
                OnPlayerDeath()
                return false
            end
        end
    end

    local uiDelay = Config.DeathUIDelay
    Citizen.Wait(uiDelay)

    -- ส่ง NUI Message
    SendNUIMessage({
        type = "ui",
        status = true,
        title_show = config.title
    })

    -- เริ่มระบบเวลาปกติ (นับเวลา 35 นาที/3 นาที) ยกเว้น Training Zone
    if zoneType ~= "training" then
        ESX.TriggerServerCallback('esx_ambulancejob:getDynamicRespawnTimer', function(dynamicTimerMs, emsCount)
            if (tonumber(emsCount) or 0) >= 1 then
                startDeathTimer(dynamicTimerMs)
            else
                startNoAmbulanceTimer()
            end
        end)
    end
    
    -- เรียก actions ตาม config (ปรับปรุงประสิทธิภาพ)
    local actions = config.actions
    
    -- เรียก specialButton action ก่อน (ส่ง zoneIndex ถ้ามี)
    if actions.specialButton then
        local actionFunc = ACTION_MAP[actions.specialButton]
        if actionFunc then
            -- ตรวจสอบว่าฟังก์ชันต้องการ parameter หรือไม่
            if zoneIndex and (
                actions.specialButton == "startReplightSpecialButton" or
                actions.specialButton == "startWaterpipeSpecialButton" or
                actions.specialButton == "startMegacementSpecialButton"
            ) then
                actionFunc(zoneIndex)
            else
                actionFunc()
            end
        end
    end
    
    -- เรียก actions อื่นๆ
    for actionType, actionData in pairs(actions) do
        if actionType ~= "specialButton" then
            if type(actionData) == "table" then
                -- ถ้าเป็น array ของ actions
                for _, actionName in ipairs(actionData) do
                    local actionFunc = ACTION_MAP[actionName]
                    if actionFunc then
                        actionFunc()
                    end
                end
            else
                -- ถ้าเป็น action เดียว
                local actionFunc = ACTION_MAP[actionData]
                if actionFunc then
                    actionFunc()
                end
            end
        end
    end

    return true
end

local isWarzoneTimerActive = false
function startWarzoneTimer()
    if isWarzoneTimerActive then return end
    isWarzoneTimerActive = true

    local noAmbulanceTimer = ESX.Math.Round(Config.EarlyRespawnTimerWarzone / 1000)
    local noAmbulanceTimerMax = noAmbulanceTimer
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            Citizen.Wait(250)

            if noAmbulanceTimer > 0 then
                noAmbulanceTimer = noAmbulanceTimer - 0.25
                local percent = (noAmbulanceTimer / noAmbulanceTimerMax) * 100
                SendNUIMessage({
                    type = "progress",
                    percent = percent
                })
                RespawnTime(_U("respawn_available_in", secondsToClock(math.ceil(noAmbulanceTimer))))
            else
                RespawnTime("00:00")
                if not shownG then
                    shownG = true
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G'))
                    })
                end

                -- เช็คปุ่ม G ให้เนียน
                Citizen.CreateThread(function()
                    while IsDead and not isPress do
                        Citizen.Wait(5)
                        if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) then
                            isPress = true
                            TriggerEvent('esx_ambulancejob:reviveinwarzone')
                            Citizen.Wait(1000)
                            isWarzoneTimerActive = false
                            break
                        end
                    end
                end)

                break
            end
        end
        isWarzoneTimerActive = false
    end)
end

function startAirdropSpecialButton()
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            if not shownG then
                shownG = true
                SendNUIMessage({
                    action = select(1, getDeathKey('respawn', 'G'))
                })
            end

            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                isPress = true

                -- เรียก exit function
                local success, errors = exports["xcore-airdrop"]:useExit()
                if success == false then
                    local errorMessage = 'ไม่สามารถออกจาก แอร์ดรอป ได้'
                    if errors and errors.status then
                        if errors.status == 'NOT_IN_AIRDROP' then
                            errorMessage = 'คุณไม่อยู่ในแอร์ดรอป'
                        elseif errors.status == 'INVALID_AIRDROP' then
                            errorMessage = 'ไม่พบแอร์ดรอป ที่คุณอยู่'
                        elseif errors.status == 'TELEPORT_DISABLED' then
                            errorMessage = 'ระบบแอร์ดรอป นี้ถูกปิดไว้'
                        end
                    end
                    ESX.ShowNotification(errorMessage, 'error')
                    isPress = false
                elseif success then
                    ESX.ShowNotification('โหลดข้อมูลของท่านเสร็จสิ้น', 'success')
                end

                break
            end
        end
    end)
end

function startStelshopSpecialButton()
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            if not shownG then
                shownG = true
                SendNUIMessage({
                    action = select(1, getDeathKey('respawn', 'G'))
                })
            end

            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                local playerPed = PlayerPedId()
                local cashMoney = ESX.GetAccountMoney("money")
                local bankMoney = ESX.GetAccountMoney("bank")
                local fineAmount = Config.EventRespawnFineAmount
                
                if cashMoney >= fineAmount then
                    -- มีเงินในตัวพอ
                    isPress = true
                    TriggerEvent("esx_ambulancejob:revive")
                    Wait(1000)
                    TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                    local formattedCoords = {
                        x = Config.RespawnPoint.coords.x,
                        y = Config.RespawnPoint.coords.y,
                        z = Config.RespawnPoint.coords.z
                    }
                    ESX.SetPlayerData('lastPosition', formattedCoords)
                    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                    RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                    Wait(600)
                    TriggerServerEvent("esx_ambulancejob:payFineEvent", "money")
                    exports['ishop_stelshops']:exit()
                    exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)
                    break
                elseif bankMoney >= fineAmount then
                    -- มีเงินในธนาคารพอ
                    isPress = true
                    TriggerEvent("esx_ambulancejob:revive")
                    Wait(1000)
                    TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                    local formattedCoords = {
                        x = Config.RespawnPoint.coords.x,
                        y = Config.RespawnPoint.coords.y,
                        z = Config.RespawnPoint.coords.z
                    }
                    ESX.SetPlayerData('lastPosition', formattedCoords)
                    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                    RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                    Wait(600)
                    TriggerServerEvent("esx_ambulancejob:payFineEvent", "bank")
                    exports['ishop_stelshops']:exit()
                    exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)
                    break
                else
                    -- ไม่มีเงินทั้งสอง
                    ESX.ShowNotification('เงินของคุณไม่เพียงพอ', 'error')
                    Wait(1000)
                end
            end
        end
    end)
end

function startReplightSpecialButton(replightIndex)
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            if not shownG then
                shownG = true
                SendNUIMessage({
                    action = select(1, getDeathKey('respawn', 'G'))
                })
            end

            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                local playerPed = PlayerPedId()
                
                -- ตรวจสอบว่ามีหมอออนไลน์หรือไม่
                local emsData = nil
                local ems = 0
                pcall(function()
                    emsData = ESX.GetOnlineJobs('ambulance')
                end)
                if emsData and emsData.onlineTotal then
                    ems = tonumber(emsData.onlineTotal) or 0
                end
                
                if ems >= 1 then
                    -- มีหมอออนไลน์ → ย้ายไปโรงพยาบาลแต่ไม่ Revive และไม่เสียเงิน
                    isPress = true
                    local formattedCoords = {
                        x = Config.EventTeleport.coords.x,
                        y = Config.EventTeleport.coords.y,
                        z = Config.EventTeleport.coords.z
                    }
                    ESX.SetPlayerData('lastPosition', formattedCoords)
                    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                    -- ย้ายไปโรงพยาบาลโดยไม่ revive
                    SetEntityCoordsNoOffset(playerPed, formattedCoords.x, formattedCoords.y, formattedCoords.z, false, false, false, true)
                    SetEntityHeading(playerPed, Config.EventTeleport.heading)
                    -- ปิด UI ปุ่ม G
                    shownG = false
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G')),
                        hide = true
                    })
                    Wait(600)
                    exports['lizz_freezeplayer']:TeleportTo(Config.EventTeleport.coords)

                    -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                    if Config.EnableDuplicateCheck and replightIndex then
                        pcall(function()
                            exports["lizz_replight"]:setReplightDeathTracking(replightIndex)
                        end)
                    end
                    break
                else
                    -- ไม่มีหมอออนไลน์ → ทำเหมือนเดิม (Revive + เสียเงิน)
                    local cashMoney = ESX.GetAccountMoney("money")
                    local bankMoney = ESX.GetAccountMoney("bank")
                    local fineAmount = Config.EventRespawnFineAmount
                    
                    if cashMoney >= fineAmount then
                        -- มีเงินในตัวพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "money")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and replightIndex then
                            pcall(function()
                                exports["lizz_replight"]:setReplightDeathTracking(replightIndex)
                            end)
                        end
                        break
                    elseif bankMoney >= fineAmount then
                        -- มีเงินในธนาคารพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "bank")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and replightIndex then
                            pcall(function()
                                exports["lizz_replight"]:setReplightDeathTracking(replightIndex)
                            end)
                        end
                        break
                    else
                        -- ไม่มีเงินทั้งสอง
                        ESX.ShowNotification('เงินของคุณไม่เพียงพอ', 'error')
                        Wait(1000)
                    end
                end
            end
        end
    end)
end

function startWaterpipeSpecialButton(waterpipeIndex)
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            if not shownG then
                shownG = true
                SendNUIMessage({
                    action = select(1, getDeathKey('respawn', 'G'))
                })
            end

            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                local playerPed = PlayerPedId()
                
                -- ตรวจสอบว่ามีหมอออนไลน์หรือไม่
                local emsData = nil
                local ems = 0
                pcall(function()
                    emsData = ESX.GetOnlineJobs('ambulance')
                end)
                if emsData and emsData.onlineTotal then
                    ems = tonumber(emsData.onlineTotal) or 0
                end
                
                if ems >= 1 then
                    -- มีหมอออนไลน์ → ย้ายไปโรงพยาบาลแต่ไม่ Revive และไม่เสียเงิน
                    isPress = true
                    local formattedCoords = {
                        x = Config.EventTeleport.coords.x,
                        y = Config.EventTeleport.coords.y,
                        z = Config.EventTeleport.coords.z
                    }
                    ESX.SetPlayerData('lastPosition', formattedCoords)
                    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                    -- ย้ายไปโรงพยาบาลโดยไม่ revive
                    SetEntityCoordsNoOffset(playerPed, formattedCoords.x, formattedCoords.y, formattedCoords.z, false, false, false, true)
                    SetEntityHeading(playerPed, Config.EventTeleport.heading)
                    -- ปิด UI ปุ่ม G
                    shownG = false
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G')),
                        hide = true
                    })
                    Wait(600)
                    exports['lizz_freezeplayer']:TeleportTo(Config.EventTeleport.coords)

                    -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                    if Config.EnableDuplicateCheck and waterpipeIndex then
                        pcall(function()
                            exports["lizz_waterpipe"]:setWaterpipeDeathTracking(waterpipeIndex)
                        end)
                    end
                    break
                else
                    -- ไม่มีหมอออนไลน์ → ทำเหมือนเดิม (Revive + เสียเงิน)
                    local cashMoney = ESX.GetAccountMoney("money")
                    local bankMoney = ESX.GetAccountMoney("bank")
                    local fineAmount = Config.EventRespawnFineAmount
                    
                    if cashMoney >= fineAmount then
                        -- มีเงินในตัวพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "money")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and waterpipeIndex then
                            pcall(function()
                                exports["lizz_waterpipe"]:setWaterpipeDeathTracking(waterpipeIndex)
                            end)
                        end
                        break
                    elseif bankMoney >= fineAmount then
                        -- มีเงินในธนาคารพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "bank")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and waterpipeIndex then
                            pcall(function()
                                exports["lizz_waterpipe"]:setWaterpipeDeathTracking(waterpipeIndex)
                            end)
                        end
                        break
                    else
                        -- ไม่มีเงินทั้งสอง
                        ESX.ShowNotification('เงินของคุณไม่เพียงพอ', 'error')
                        Wait(1000)
                    end
                end
            end
        end
    end)
end

function startMegacementSpecialButton(megacementIndex)
    local isPress = false
    local shownG = false

    Citizen.CreateThread(function()
        while IsDead do
            if not shownG then
                shownG = true
                SendNUIMessage({
                    action = select(1, getDeathKey('respawn', 'G'))
                })
            end

            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                local playerPed = PlayerPedId()
                
                -- ตรวจสอบว่ามีหมอออนไลน์หรือไม่
                local emsData = nil
                local ems = 0
                pcall(function()
                    emsData = ESX.GetOnlineJobs('ambulance')
                end)
                if emsData and emsData.onlineTotal then
                    ems = tonumber(emsData.onlineTotal) or 0
                end
                
                if ems >= 1 then
                    -- มีหมอออนไลน์ → ย้ายไปโรงพยาบาลแต่ไม่ Revive และไม่เสียเงิน
                    isPress = true
                    local formattedCoords = {
                        x = Config.EventTeleport.coords.x,
                        y = Config.EventTeleport.coords.y,
                        z = Config.EventTeleport.coords.z
                    }
                    ESX.SetPlayerData('lastPosition', formattedCoords)
                    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                    -- ย้ายไปโรงพยาบาลโดยไม่ revive
                    SetEntityCoordsNoOffset(playerPed, formattedCoords.x, formattedCoords.y, formattedCoords.z, false, false, false, true)
                    SetEntityHeading(playerPed, Config.EventTeleport.heading)
                    -- ปิด UI ปุ่ม G
                    shownG = false
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G')),
                        hide = true
                    })
                    Wait(600)
                    exports['lizz_freezeplayer']:TeleportTo(Config.EventTeleport.coords)

                    -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                    if Config.EnableDuplicateCheck and megacementIndex then
                        pcall(function()
                            exports["lizz_megacement"]:setMegacementDeathTracking(megacementIndex)
                        end)
                    end
                    break
                else
                    -- ไม่มีหมอออนไลน์ → ทำเหมือนเดิม (Revive + เสียเงิน)
                    local cashMoney = ESX.GetAccountMoney("money")
                    local bankMoney = ESX.GetAccountMoney("bank")
                    local fineAmount = Config.EventRespawnFineAmount
                    
                    if cashMoney >= fineAmount then
                        -- มีเงินในตัวพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "money")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and megacementIndex then
                            pcall(function()
                                exports["lizz_megacement"]:setMegacementDeathTracking(megacementIndex)
                            end)
                        end
                        break
                    elseif bankMoney >= fineAmount then
                        -- มีเงินในธนาคารพอ
                        isPress = true
                        TriggerEvent("esx_ambulancejob:revive")
                        Wait(1000)
                        TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)

                        local formattedCoords = {
                            x = Config.RespawnPoint.coords.x,
                            y = Config.RespawnPoint.coords.y,
                            z = Config.RespawnPoint.coords.z
                        }
                        ESX.SetPlayerData('lastPosition', formattedCoords)
                        TriggerServerEvent('esx:updateLastPosition', formattedCoords)
                        RespawnPed(playerPed, formattedCoords, Config.RespawnPoint.heading)
                        Wait(600)
                        TriggerServerEvent("esx_ambulancejob:payFineEvent", "bank")
                        exports['lizz_freezeplayer']:TeleportTo(Config.RespawnPoint.coords)

                        -- บันทึกสถานะการตาย (ถ้าเปิดใช้งานและมี index)
                        if Config.EnableDuplicateCheck and megacementIndex then
                            pcall(function()
                                exports["lizz_megacement"]:setMegacementDeathTracking(megacementIndex)
                            end)
                        end
                        break
                    else
                        -- ไม่มีเงินทั้งสอง
                        ESX.ShowNotification('เงินของคุณไม่เพียงพอ', 'error')
                        Wait(1000)
                    end
                end
            end
        end
    end)
end

AddEventHandler('esx:onPlayerDeath', function(data)
    if IsDead then return end

    local detectedZones = {}
    -- ตรวจสอบ zone ต่างๆ ตาม config (ปรับปรุงประสิทธิภาพ)
    for _, zoneName in ipairs(ZONE_PRIORITY) do
        local detectionFunc = ZONE_DETECTION[zoneName]
        if detectionFunc then
            local result = detectionFunc()
            if result then
                detectedZones[zoneName] = true
                break -- หยุดเมื่อเจอ zone แรก (ตาม priority)
            end
        end
    end

    -- ถ้าไม่ได้อยู่ใน zone ใดๆ
    if not next(detectedZones) then
        if not IsDead then
            IsDead = true
            OnPlayerDeath()
        end
        return
    end

    -- จัดการ zone ที่เจอ
    for zoneName, _ in pairs(detectedZones) do
        local zoneIndex = nil
        local detectionFunc = ZONE_DETECTION[zoneName]
        if detectionFunc then
            local result = detectionFunc()
            -- ถ้า result เป็น number (index) หรือ string (locationId) ให้ใช้เป็น zoneIndex
            if type(result) == "number" or type(result) == "string" then
                zoneIndex = result
            end
        end
        handleZoneDeath(zoneName, ZONE_CONFIGS[zoneName], zoneIndex)
        return
    end
end)

function stabilizeBody()
    local syncCfg = Config.DeathBodySync or {}
    if not syncCfg.enabled then
        return
    end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return
    end

    ClearPedTasksImmediately(ped)

    local coords = GetEntityCoords(ped)
    local found, coordsZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z)
    if found then
        local targetZ = coordsZ + 0.15
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, targetZ, true, true, true)
    end
end

local function syncDeadLastPosition()
    local ped = PlayerPedId()
    if not ped or not DoesEntityExist(ped) then
        return
    end

    local coords = GetEntityCoords(ped)
    local formattedCoords = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }

    ESX.SetPlayerData('lastPosition', formattedCoords)
    TriggerServerEvent('esx:updateLastPosition', formattedCoords)
end

local function playClearBodyBounce()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return
    end

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    -- เด้งศพ: ลุกขึ้นสั้น ๆ แล้วกลับไปสถานะตายเดิม เพื่อรีเซ็ตตำแหน่งให้ตรงกัน
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    SetEntityHealth(ped, 1)
    Citizen.Wait(50)
    SetEntityHealth(ped, 0)
    SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
    syncDeadLastPosition()
end

function startBodyStabilizationSequence()
    local syncCfg = Config.DeathBodySync or {}

    -- ปิดระบบนี้ค่าเริ่มต้นเพื่อเลี่ยงตำแหน่งศพไม่ตรงระหว่าง client
    if not syncCfg.enabled then
        ClearBody = true
        clearBodyUi(false)
        return
    end

    local firstDelay = tonumber(syncCfg.firstDelayMs) or 3500
    local secondDelay = tonumber(syncCfg.secondDelayMs) or 7000
    local finalDelay = tonumber(syncCfg.finalDelayMs) or 4000

    SetTimeout(firstDelay, function()
        if IsDead then
            local playerPed = PlayerPedId()
            if IsEntityDead(playerPed) then
                stabilizeBody()
            end
            SetTimeout(secondDelay, function()
                if IsEntityDead(playerPed) and IsDead then
                    stabilizeBody()
                    SetTimeout(finalDelay, function()
                        ClearBody = true
                        clearBodyUi(false)
                    end)
                end
            end)
        end
    end)
end

function OnPlayerDeath()
	IsDead = true
    talk = false
    ESX.UI.Menu.CloseAll()
    TriggerServerEvent('esx_ambulancejob:setDeathStatus', true)
    pcall(function ()
        exports['lizz_playerhud']:toggleHUD(false)
    end)
    
    SetTimeout(Config.DeathUIDelay, function()
        if IsInBlockZone() then
            -- ส่ง NUI แจ้งว่าอยู่ BlockZone โดยไม่เปิด keymap
            SendNUIMessage({
                type = 'blockzone',
                status = true
            })
        else
            -- นอก BlockZone ใช้ ui ปกติ
            SendNUIMessage({
                type = 'ui',
                status = true
            })
        end
    end)

    ESX.TriggerServerCallback('esx_ambulancejob:getDynamicRespawnTimer', function(dynamicTimerMs, emsCount)
        if (tonumber(emsCount) or 0) >= 1 then
            startDeathTimer(dynamicTimerMs)
            startDistressSignal()
            startDistressSignalGang()
            clearBodyVoice()
        else
            startNoAmbulanceTimer()
            clearBodyVoice()
            SetTimeout(500, function()
                sendSignalUi(true)
                gangRequest(true)
            end)
        end
    end)

	startBodyStabilizationSequence()
end

-- Create blips
Citizen.CreateThread(function()
	for k, v in pairs(Config.Hospitals) do
		local blip = AddBlipForCoord(v.Blip.coords)

		SetBlipSprite(blip, v.Blip.sprite)
		SetBlipScale(blip, v.Blip.scale)
		SetBlipColour(blip, v.Blip.color)
		SetBlipAsShortRange(blip, true)

		BeginTextCommandSetBlipName('STRING')
		AddTextComponentString('<font face="dbheavent">Hospital</font>')
		EndTextCommandSetBlipName(blip)
	end
end)

local AmbulancePlayerBlips = {}
local AmbulanceBlipFlashState = false

local function toBool(value, default)
    if type(value) == 'boolean' then
        return value
    end

    if type(value) == 'number' then
        return value ~= 0
    end

    if type(value) == 'string' then
        local normalized = string.lower(value)
        if normalized == 'true' or normalized == '1' or normalized == 'yes' or normalized == 'on' then
            return true
        end
        if normalized == 'false' or normalized == '0' or normalized == 'no' or normalized == 'off' then
            return false
        end
    end

    return default
end

local function getAmbulancePlayerBlipConfig()
    local cfg = Config.AmbulancePlayerBlip or {}
    local display = cfg.display or {}
    local colors = cfg.colors or {}
    local text = cfg.text or {}

    return {
        enabled = toBool(cfg.enabled, true),
        refreshTargetsMs = tonumber(cfg.refreshTargetsMs) or 5000,
        refreshBlipMs = tonumber(cfg.refreshBlipMs) or 500,
        flashColorA = tonumber(cfg.flashColorA) or 1,
        flashColorB = tonumber(cfg.flashColorB) or 3,
        sprite = tonumber(display.sprite) or 1,
        helicopterSprite = tonumber(display.helicopterSprite) or 43,
        scale = tonumber(display.scale) or 0.9,
        category = tonumber(display.category) or 7,
        shortRange = toBool(display.shortRange, false),
        colorOnFoot = tonumber(colors.onFoot) or 2,
        colorInVehicle = tonumber(colors.inVehicle) or 3,
        colorInHelicopter = tonumber(colors.inHelicopter) or 5,
        textPrefix = text.prefix or 'EMS',
        textOnFoot = text.onFoot or 'เดินเท้า',
        textInVehicle = text.inVehicle or 'อยู่บนรถ',
        textInHelicopter = text.inHelicopter or 'อยู่บนเฮลิคอปเตอร์',
        silentLightSuffix = text.silentLightSuffix or ' (Silent Light)'
    }
end

clearAmbulancePlayerBlips = function()
    for _, blip in pairs(AmbulancePlayerBlips) do
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    AmbulancePlayerBlips = {}
end

local function getMedicBlipStatus(ped, blipCfg)
    local statusText = blipCfg.textOnFoot
    local blipColor = blipCfg.colorOnFoot
    local blipSprite = blipCfg.sprite

    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        local vehModel = GetEntityModel(veh)
        local isHeli = IsThisModelAHeli(vehModel) or GetVehicleClass(veh) == 15

        if isHeli then
            statusText = blipCfg.textInHelicopter
            blipColor = blipCfg.colorInHelicopter
            blipSprite = blipCfg.helicopterSprite
        else
            statusText = blipCfg.textInVehicle
            blipColor = blipCfg.colorInVehicle
        end

        if IsVehicleSirenOn(veh) then
            statusText = statusText .. blipCfg.silentLightSuffix
            blipColor = AmbulanceBlipFlashState and blipCfg.flashColorA or blipCfg.flashColorB
        end
    end

    return statusText, blipColor, blipSprite
end

Citizen.CreateThread(function()
    while true do
        local blipCfg = getAmbulancePlayerBlipConfig()
        if blipCfg.enabled and ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name == 'ambulance' then
            ESX.TriggerServerCallback('esx_ambulancejob:getAmbulanceBlipTargets', function(targets)
                AmbulanceBlipTargets = targets or {}
            end)
            Citizen.Wait(math.max(500, blipCfg.refreshTargetsMs))
        else
            AmbulanceBlipTargets = {}
            clearAmbulancePlayerBlips()
            Citizen.Wait(2000)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        local blipCfg = getAmbulancePlayerBlipConfig()
        if blipCfg.enabled and ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name == 'ambulance' then
            AmbulanceBlipFlashState = not AmbulanceBlipFlashState
            local activeTarget = {}

            for _, target in ipairs(AmbulanceBlipTargets) do
                local serverId = tonumber(target.id)
                if serverId and serverId ~= GetPlayerServerId(PlayerId()) then
                    activeTarget[serverId] = true
                    local playerId = GetPlayerFromServerId(serverId)

                    if playerId and playerId ~= -1 and NetworkIsPlayerActive(playerId) then
                        local ped = GetPlayerPed(playerId)
                        if ped and ped ~= 0 and DoesEntityExist(ped) then
                            local blip = AmbulancePlayerBlips[serverId]
                            if not blip or not DoesBlipExist(blip) then
                                blip = AddBlipForEntity(ped)
                                AmbulancePlayerBlips[serverId] = blip
                                SetBlipSprite(blip, blipCfg.sprite)
                                SetBlipScale(blip, blipCfg.scale)
                                SetBlipCategory(blip, blipCfg.category)
                                SetBlipAsShortRange(blip, blipCfg.shortRange)
                            end

                            local statusText, blipColor, blipSprite = getMedicBlipStatus(ped, blipCfg)
                            SetBlipSprite(blip, blipSprite)
                            SetBlipScale(blip, blipCfg.scale)
                            SetBlipCategory(blip, blipCfg.category)
                            SetBlipAsShortRange(blip, blipCfg.shortRange)
                            SetBlipColour(blip, blipColor)

                            local playerName = target.name or GetPlayerName(playerId) or ('ID ' .. tostring(serverId))
                            BeginTextCommandSetBlipName('STRING')
                            AddTextComponentString(('%s %s - %s'):format(blipCfg.textPrefix, playerName, statusText))
                            EndTextCommandSetBlipName(blip)
                        end
                    end
                end
            end

            for serverId, blip in pairs(AmbulancePlayerBlips) do
                if not activeTarget[serverId] then
                    if blip and DoesBlipExist(blip) then
                        RemoveBlip(blip)
                    end
                    AmbulancePlayerBlips[serverId] = nil
                end
            end

            Citizen.Wait(math.max(100, blipCfg.refreshBlipMs))
        else
            clearAmbulancePlayerBlips()
            Citizen.Wait(1000)
        end
    end
end)

-- Disable most inputs when dead
Citizen.CreateThread(function()
    while true do
        if not IsDead then
            Citizen.Wait(500)
        else
            local playerPed = PlayerPedId()
            if not playerPed or not DoesEntityExist(playerPed) then
                Citizen.Wait(1000)
            else
                DisableAllControlActions(0)

                -- อนุญาตให้หมุนกล้องได้ตลอด แม้กด ESC เข้า/ออกเมนู
                EnableControlAction(0, 1, true)
                EnableControlAction(0, 2, true)
                EnableControlAction(1, 1, true)
                EnableControlAction(1, 2, true)
                EnableControlAction(0, 322, true)

                if IsInBlockZone() then
                    -- ถ้าอยู่ใน BlockZone
                    EnableControlAction(0, select(2, getDeathKey('clearBody', 'X')), true)
                    EnableControlAction(0, select(2, getDeathKey('forceRespawn', 'DELETE')), true)
                else
                    -- ถ้าอยู่นอก BlockZone
                    EnableControlAction(0, select(2, getDeathKey('requestTalk', 'R')), true)
                    EnableControlAction(0, select(2, getDeathKey('clearBody', 'X')), true)
                    EnableControlAction(0, select(2, getDeathKey('respawn', 'G')), true)
                    EnableControlAction(0, select(2, getDeathKey('distress', 'M')), true)
                    EnableControlAction(0, select(2, getDeathKey('forceRespawn', 'DELETE')), true)
                    EnableControlAction(0, select(2, getDeathKey('gang', 'Q')), true)
                    EnableControlAction(0, select(2, getDeathKey('ragdoll', 'SPACE')), true)
                    if talk then
                        EnableControlAction(0, select(2, getDeathKey('talk', 'N')), true)
                    end
                end
            end
            Citizen.Wait(5)
        end
    end
end)

function clearBodyVoice()
    local isClearingBody = false
    local isRequestingTalk = false
    local lastLogicCheck = GetGameTimer()

    Citizen.CreateThread(function()
        while IsDead do
            Citizen.Wait(5)

            -- ปุ่ม X
            if IsDisabledControlPressed(0, select(2, getDeathKey('clearBody', 'X'))) and ClearBody and not isClearingBody then
                isClearingBody = true
                ClearBody = false
                clearBodyUi(true)
                local playerPed = PlayerPedId()
                FreezeEntityPosition(playerPed, false)
                ClearPedTasksImmediately(playerPed)
                playClearBodyBounce()

                local clearBodyCooldownMs = getDeathKeyCooldownMs('clearBody', 30)
                SetTimeout(clearBodyCooldownMs, function()
                    if IsDead then
                        clearBodyUi(false)
                        ClearBody = true
                    end
                    isClearingBody = false
                end)
            end

            -- ปุ่ม R
            if IsDisabledControlPressed(0, select(2, getDeathKey('requestTalk', 'R'))) and not talk and not isRequestingTalk then
                local now = GetGameTimer()
                if now - lastLogicCheck >= 1000 then
                    local player, distance = ESX.Game.GetClosestPlayer()
                    if player ~= -1 and distance < 3.0 then
                        isRequestingTalk = true
                        requestTalk(true)
                        TriggerServerEvent('esx_ambulancejob:requestTalk', GetPlayerServerId(player))

                        local requestTalkCooldownMs = getDeathKeyCooldownMs('requestTalk', 180)
                        SetTimeout(requestTalkCooldownMs, function()
                            requestTalk(false)
                            isRequestingTalk = false
                        end)
                    else
                        ESX.ShowNotification(_U('no_players'))
                    end
                    lastLogicCheck = now
                end
            end
        end
    end)
end

RegisterNetEvent('esx_ambulancejob:requesToTalk')
AddEventHandler('esx_ambulancejob:requesToTalk', function(playerTalk)
	local elements = {
		{ label = "อนุญาตให้พูด", value = 500 },
		{ label = "ไม่อนุญาตให้พูด", value = "no" }
	}

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'requesToTalk', {
		title = 'ผู้เล่น ' .. tostring(playerTalk) .. ' ขออนุญาตพูด',
		align = 'bottom-right',
		elements = elements
	}, function(data, menu)
		if not data.current or not data.current.value then
			menu.close()
			return
		end

		if data.current.value == "no" then
			TriggerServerEvent('esx_ambulancejob:requestAccept', playerTalk, false)
		else
			local time = tonumber(data.current.value)
			if time then
				TriggerServerEvent('esx_ambulancejob:requestAccept', playerTalk, true, time)
			end
		end
		menu.close()
	end, function(data, menu)
		menu.close()
	end)
end)

RegisterNetEvent('esx_ambulancejob:updateTalk')
AddEventHandler('esx_ambulancejob:updateTalk', function(time)
	local description = ''
	local types = 'success'

    if time == 500 then
        talk = true
        description = 'ได้รับอนุญาตให้พูดแล้ว'
        requestTalk(true) -- disable ปุ่ม R ตลอด
		talkingSetui(true)
        ESX.ShowNotification(description, types)

    else
        description = 'ไม่ได้รับอนุญาตให้พูด'
        types = 'error'
        requestTalk(true) -- disable ปุ่ม R ตลอด
		talkingSetui(false)
        SetTimeout(3 * 60 * 1000, function() -- รอ 3 นาที reset
            requestTalk(false)
        end)
        ESX.ShowNotification(description, types)
    end
end)

RegisterNetEvent('esx_ambulancejob:useItem')
AddEventHandler('esx_ambulancejob:useItem', function(itemName)
	ESX.UI.Menu.CloseAll()
	while action do
		Wait(500)
	end
	action = true
	if itemName == 'medikit' then
		exports['mythic_progbar']:Progress({
			name = "unique_action_name",
			duration = 5000,
			label = 'Use Medkit',
			useWhileDead = true,
			canCancel = false,
			controlDisables = {
				disableMovement = false,
				disableCarMovement = true,
				disableMouse = false,
				disableCombat = true,
			},
			animation = {
				animDict = "missheistdockssetup1clipboard@idle_a",
				anim = "idle_a",
				flags = 49,
			},
			prop = {
				model = "prop_ld_health_pack",
			},
		}, function(cancelled)
			if not cancelled then
				TriggerEvent('esx_ambulancejob:heal', 'big', true)
				action = false
			else
				action = false
			end
		end)
	elseif itemName == 'plaster' then
		exports['mythic_progbar']:Progress({
			name = "unique_action_name",
			duration = 5000,
			label = 'Use Plaster',
			useWhileDead = true,
			canCancel = false,
			controlDisables = {
				disableMovement = false,
				disableCarMovement = true,
				disableMouse = false,
				disableCombat = true,
			},
			animation = {
				animDict = "missheistdockssetup1clipboard@idle_a",
				anim = "idle_a",
				flags = 49,
			},
			prop = {
				model = "prop_ld_health_pack",
			},
		}, function(cancelled)
			if not cancelled then
				TriggerEvent('esx_ambulancejob:heal', 'small', true)
				action = false
			else
				action = false
			end
		end)
	end
end)

function startDistressSignal()
    local nextAllowedTime = 0

    Citizen.CreateThread(function()
        while IsDead do
            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('distress', 'M'))) then
                local now = GetGameTimer()
                if now < nextAllowedTime then
                    local remainSec = math.ceil((nextAllowedTime - now) / 1000)
                    ESX.ShowNotification(('รออีก %s วินาที ถึงจะกดแจ้งเคสได้อีกครั้ง'):format(remainSec), 'error')
                else
                    local cooldownMs = getDeathKeyCooldownMs('distress', 180)
                    if cooldownMs < 1000 then cooldownMs = 1000 end

                    nextAllowedTime = now + cooldownMs
                    sendSignalUi(true)

                    local alertPayload = {
                        type = 'normal',
                        text = 'ผู้เล่นต้องการความช่วยเหลือด่วน'
                    }

                    if bodywarp then
                        pcall(function()
                            exports.Giant_Policereport:PoliceReport('bodybag')
                        end)
                        alertPayload.type = 'bodybag'
                        alertPayload.text = 'แจ้งเคสอุ้มศพ'
                    end

                    local sentToMedic = pcall(function()
                        exports['APEX-MedicReport']:SendAlert(alertPayload)
                    end)

                    if not sentToMedic then
                        ESX.ShowNotification('ไม่สามารถส่งเคสไปยังระบบหมอได้', 'error')
                    end

                    SetTimeout(cooldownMs, function()
                        if IsDead then
                            sendSignalUi(false)
                        end
                    end)
                end
            end
        end
    end)
end

function startDistressSignalGang()
    local nextAllowedTime = 0

    Citizen.CreateThread(function()
        while IsDead do
            Citizen.Wait(5)
            if IsDisabledControlPressed(0, select(2, getDeathKey('gang', 'Q'))) then
                local now = GetGameTimer()
                if now < nextAllowedTime then
                    local remainSec = math.ceil((nextAllowedTime - now) / 1000)
                    ESX.ShowNotification(('รออีก %s วินาที ถึงจะส่งสัญญาณแก๊งได้อีกครั้ง'):format(remainSec), 'error')
                else
                    local gangData = exports['xcore-gang']:GetPlayerGangId()
                    if not gangData then
                        gangRequest(true)
                        ESX.ShowNotification('คุณไม่มีแก๊ง ไม่สามารถส่งสัญญาณได้', 'error')
                    else
                        local requiredItems = { "gps_gang" }
                        local hasAnyItem = false
                        for _, item in ipairs(requiredItems) do
                            if checkHasItem(item, 1) then
                                hasAnyItem = true
                                break
                            end
                        end

                        if not hasAnyItem then
                            gangRequest(true)
                            ESX.ShowNotification('คุณไม่มีอุปกรณ์ส่งสัญญาณ', 'error')
                        else
                            local gangCooldownMs = getDeathKeyCooldownMs('gang', 180)
                            if gangCooldownMs < 1000 then gangCooldownMs = 1000 end

                            nextAllowedTime = now + gangCooldownMs
                            gangRequest(true)

                            if bodywarp then
                                TriggerEvent("lizz_gangalert:alertNet", "bodybag")
                            else
                                TriggerEvent("lizz_gangalert:alertNet", "gps")
                            end

                            SetTimeout(gangCooldownMs, function()
                                gangRequest(false)
                            end)
                        end
                    end
                end
            end
        end
    end)
end
function secondsToClock(seconds)
    local seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return "00", "00"
    end

    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    return string.format("%02d", mins), string.format("%02d", secs)
end

local function respawnAtConfiguredPoint()
    local playerPed = PlayerPedId()
    local coords = Config.RespawnPoint.coords
    local heading = Config.RespawnPoint.heading or 0.0

    local formattedCoords = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }

    TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)
    ESX.SetPlayerData('lastPosition', formattedCoords)
    TriggerServerEvent('esx:updateLastPosition', formattedCoords)

    RespawnPed(playerPed, formattedCoords, heading)
    Wait(600)
    pcall(function()
        exports['lizz_freezeplayer']:TeleportTo(coords)
    end)
    SetEntityHeading(playerPed, heading)
end


function startNoAmbulanceTimer()
    local noAmbulanceTimer = ESX.Math.Round(Config.EarlyRespawnTimerNoEms / 1000)
    local noAmbulanceTimerMax = noAmbulanceTimer
    local isPress = false
    local shownG = false

    -- update progress bar
    Citizen.CreateThread(function()
        while IsDead and noAmbulanceTimer > 0 do
            Citizen.Wait(1000)
            noAmbulanceTimer = noAmbulanceTimer - 1
            setDeathRemainState(noAmbulanceTimer)
            local percent = (noAmbulanceTimer / noAmbulanceTimerMax) * 100
            SendNUIMessage({
                type = "progress",
                percent = percent
            })
        end
    end)

    -- update text + key
    Citizen.CreateThread(function()
        while IsDead do
            if noAmbulanceTimer > 0 then
                Citizen.Wait(250)
                RespawnTime(_U("respawn_available_in", secondsToClock(math.ceil(noAmbulanceTimer))))
            else
                if not shownG then
                    shownG = true
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G'))
                    })
                end

                RespawnTime("00:00")
                setDeathRemainState(0)

                Citizen.Wait(5)
                if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                    isPress = true
                    respawnAtConfiguredPoint()
                    break
                end
            end
        end
    end)
end

local maxTimeSpawn
local maxTimeBleedout
local earlySpawnTimer
local bleedoutTimer

function startDeathTimer(dynamicTimerMs)
    local canPayFine = false
    local shownG = false
    local isPress = false

    if Config.EarlyRespawnFine then
        ESX.TriggerServerCallback('esx_ambulancejob:checkBalance', function(canPay)
            canPayFine = canPay
        end)
    end

    local baseRespawnTimer = tonumber(dynamicTimerMs) or Config.EarlyRespawnTimer
    local dynamicTimerEnabled = Config.DynamicEarlyRespawnTimer and Config.DynamicEarlyRespawnTimer.enabled and tonumber(dynamicTimerMs) ~= nil

    maxTimeSpawn     = ESX.Math.Round(baseRespawnTimer / 1000)
    maxTimeBleedout  = ESX.Math.Round(Config.BleedoutTimer / 1000)
    earlySpawnTimer  = maxTimeSpawn
    bleedoutTimer    = maxTimeBleedout

    Citizen.CreateThread(function()
        while IsDead do
            Citizen.Wait(250)

            -- early respawn
            if earlySpawnTimer > 0 then
                earlySpawnTimer = earlySpawnTimer - 0.25
                setDeathRemainState(earlySpawnTimer)
                local percent = (earlySpawnTimer / maxTimeSpawn) * 100
                SendNUIMessage({
                    type = "progress",
                    percent = percent
                })
                RespawnTime(_U("respawn_available_in", secondsToClock(math.ceil(earlySpawnTimer))))
            else
                if dynamicTimerEnabled and not shownG then
                    shownG = true
                    SendNUIMessage({
                        action = select(1, getDeathKey('respawn', 'G'))
                    })
                end

                if dynamicTimerEnabled then
                    RespawnTime("00:00")
                    setDeathRemainState(bleedoutTimer)

                    if IsDisabledControlPressed(0, select(2, getDeathKey('respawn', 'G'))) and not isPress then
                        isPress = true
                        RemoveItemsAfterRPDeath()
                        break
                    end
                elseif bleedoutTimer > 0 then
                    bleedoutTimer = bleedoutTimer - 0.25
                    setDeathRemainState(bleedoutTimer)
                    local percent = (bleedoutTimer / maxTimeBleedout) * 100
                    SendNUIMessage({
                        type = "progress",
                        percent = percent
                    })
                    RespawnTime(_U("respawn_bleedout_in", secondsToClock(math.ceil(bleedoutTimer))))
                else
                    -- bleedout หมดเวลา
                    RespawnTime("00:00")
                    setDeathRemainState(0)
                    RemoveItemsAfterRPDeath()
                    break
                end

                if dynamicTimerEnabled and bleedoutTimer > 0 then
                    bleedoutTimer = bleedoutTimer - 0.25
                    if bleedoutTimer <= 0 then
                        RemoveItemsAfterRPDeath()
                        break
                    end
                elseif dynamicTimerEnabled and maxTimeBleedout <= 0 then
                    -- ไม่มี bleedout timer ก็ให้กด G เกิดได้ทันทีตามระบบ Dynamic
                end
            end
        end
    end)

    bodywarp = false
end

function RemoveItemsAfterRPDeath()
    TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)
    setDeathRemainState(nil)

    Citizen.CreateThread(function()
        if bodywarp then
            -- กรณีศพโดนห่อ
            Wait(200)
            TriggerEvent('esx_ambulancejob:revive')
            TriggerServerEvent("Bu.Bodybag:RemoveItems")
            Wait(1000)
            TriggerServerEvent('PG_JAILANDBILL:JailDeadbag', 1, 2, 3) -- 1 นาที | 2, 3 จุดเอ๋อ
        else
            -- ศพปกติ
            TriggerServerEvent('esx_ambulancejob:payFine')

            respawnAtConfiguredPoint()
        end
    end)
end

function RespawnPed(ped, coords, heading, health)
    ped = ped or PlayerPedId()

    local heal = health or Config.HealBase

    local pos
    if type(coords) == "table" and coords.x and coords.y and coords.z then
        pos = coords
    else
        pos = GetEntityCoords(ped)
    end

    SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false, true)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading or 0.0, true, false)

    ClearPedTasksImmediately(ped)
    SetPlayerInvincible(ped, false)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, heal)

    ESX.UI.Menu.CloseAll()

    TriggerEvent('esx:onPlayerSpawn', pos.x, pos.y, pos.z)
    TriggerEvent('playerSpawned', pos.x, pos.y, pos.z)

    -- RESET UI เมื่อฟื้น
    requestTalk(false)
    sendSignalUi(false)
    gangRequest(false)
    clearBodyUi(false)
    talkingSetui(false)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

	local playerPed = PlayerPedId()
	if IsEntityDead(playerPed) then
		RespawnPed(playerPed, GetEntityCoords(playerPed), 0.0)
	end
end)

AddEventHandler('onResourceStart', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end
	pcall(function()
		exports['lizz_playerhud']:toggleHUD(true)
	end)
end)

RegisterNetEvent('esx_ambulancejob:reviveinwarzone')
AddEventHandler('esx_ambulancejob:reviveinwarzone', function()
    local playerPed = PlayerPedId()

	TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)
	setDeathRemainState(nil)

	Citizen.CreateThread(function()
        DoScreenFadeOut(800)
        while not IsScreenFadedOut() do Wait(50) end

        local spawnCoords = GetEntityCoords(playerPed)
		ESX.SetPlayerData('lastPosition', spawnCoords)
		TriggerServerEvent('esx:updateLastPosition', spawnCoords)
		RespawnPed(playerPed, spawnCoords, 0.0)

		StopScreenEffect('SwitchHUDIn')
		DoScreenFadeIn(800)
		Citizen.Wait(500)
		SetEntityHealth(playerPed, 200)
	end)
end)

RegisterNetEvent('esx_ambulancejob:revive')
AddEventHandler('esx_ambulancejob:revive', function()
    local playerPed = PlayerPedId()

	TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)
	setDeathRemainState(nil)

	Citizen.CreateThread(function()
        DoScreenFadeOut(800)
        while not IsScreenFadedOut() do Wait(50) end

        local spawnCoords = GetEntityCoords(playerPed)

		ESX.SetPlayerData('lastPosition', spawnCoords)
		TriggerServerEvent('esx:updateLastPosition', spawnCoords)
		RespawnPed(playerPed, spawnCoords, 0.0)

		StopScreenEffect('SwitchHUDIn')
        DoScreenFadeIn(800)
        SetEntityHealth(playerPed, 140)
        FreezeEntityPosition(playerPed, false)
	end)
end)

RegisterNetEvent('esx_ambulancejob:reviveall')
AddEventHandler('esx_ambulancejob:reviveall', function()
	local playerPed = PlayerPedId()
 	if IsDead  then
		TriggerServerEvent('esx_ambulancejob:setDeathStatus', false)
		setDeathRemainState(nil)

		Citizen.CreateThread(function()
			DoScreenFadeOut(800)
			while not IsScreenFadedOut() do Wait(50) end

			local spawnCoords = GetEntityCoords(playerPed)

			ESX.SetPlayerData('lastPosition', spawnCoords)
			TriggerServerEvent('esx:updateLastPosition', spawnCoords)
			RespawnPed(playerPed, spawnCoords, 0.0)

			StopScreenEffect('SwitchHUDIn')
			DoScreenFadeIn(800)
	    end)
    end
end)

-- Load unloaded IPLs
if Config.LoadIpl then
	Citizen.CreateThread(function()
		RequestIpl('Coroner_Int_on') -- Morgue
	end)
end

function IsInBlockZone()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    for _, zone in pairs(Config.BlockZone) do
        local dist = #(playerCoords - zone.coords)
        if dist <= zone.radius then
            return true
        end
    end
    return false
end

function talkingSetui(bool)
	SendNUIMessage({
		action = 'talk',
		bool = bool
	})
end

closeUi = function ()
	SendNUIMessage({
		type = 'ui',
		status = false
	})
end

RegisterCommand('emsrespawntimer', function()
    if not ESX.PlayerData.job or ESX.PlayerData.job.name ~= 'ambulance' then
        ESX.ShowNotification('คำสั่งนี้สำหรับหมอเท่านั้น', 'error')
        return
    end

    ESX.TriggerServerCallback('esx_ambulancejob:getDynamicRespawnSettings', function(settings)
        if not settings or not settings.enabled then
            ESX.ShowNotification('ระบบปรับเวลาเกิดอัตโนมัติถูกปิดอยู่', 'error')
            return
        end

        local input = lib.inputDialog('ตั้งเวลาเกิดใหม่ (แยกระบบ ผู้เล่น/หมอ)', {
            { type = 'number', label = 'ผู้เล่นทั่วไป: หมอออนไลน์ = 1 คน (นาที)', required = true, default = tonumber(settings.player and settings.player.oneEmsMinutes) or 5, min = 1, max = 120 },
            { type = 'number', label = 'ผู้เล่นทั่วไป: หมอออนไลน์ > 1 คน (นาที)', required = true, default = tonumber(settings.player and settings.player.multiEmsMinutes) or 15, min = 1, max = 120 },
            { type = 'number', label = 'หมอ: หมอออนไลน์ = 1 คน (นาที)', required = true, default = tonumber(settings.ems and settings.ems.oneEmsMinutes) or 3, min = 1, max = 120 },
            { type = 'number', label = 'หมอ: หมอออนไลน์ > 1 คน (นาที)', required = true, default = tonumber(settings.ems and settings.ems.multiEmsMinutes) or 8, min = 1, max = 120 }
        })

        if not input then
            return
        end

        local playerOne = tonumber(input[1])
        local playerMulti = tonumber(input[2])
        local emsOne = tonumber(input[3])
        local emsMulti = tonumber(input[4])

        if not playerOne or not playerMulti or not emsOne or not emsMulti then
            ESX.ShowNotification('กรุณาใส่เวลาเป็นตัวเลข', 'error')
            return
        end

        TriggerServerEvent('esx_ambulancejob:setDynamicRespawnSettings', playerOne, playerMulti, emsOne, emsMulti)
    end)
end, false)

sendSignalUi = function (A)
	SendNUIMessage({
		type = 'sendsignal',
		status = A,
	})
end

clearBodyUi = function (A)
	SendNUIMessage({
		type = 'addclass',
		status = A,
	})
end

requestTalk = function (A)
	SendNUIMessage({
		type = 'requestTalk',
		status = A,
	})
end

gangRequest = function (A)
	SendNUIMessage({
		type = 'gang',
		status = A,
	})
end

policeRequest = function (A)
	SendNUIMessage({
		type = 'police',
		status = A,
	})
end

RespawnTime = function (text)
	SendNUIMessage({
		type = 'time',
		time = text
	})
end

exports('setTalk',talkingSetui)

exports('isDead',function()
	return IsDead
end)

-- RegisterCommand('die', function ()
-- 	SetEntityHealth(PlayerPedId(), 0)
-- end)

AddEventHandler("Bu.Bodybag:SetTime", function(Time)
    Citizen.Wait(300) -- กัน UI โหลดไม่ทัน
    if IsDead and not bodywarp then
        earlySpawnTimer = Time
        bodywarp = true
    end
end)

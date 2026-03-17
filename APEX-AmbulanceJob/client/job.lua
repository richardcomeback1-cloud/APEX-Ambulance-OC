local CurrentAction, CurrentActionMsg, CurrentActionData = nil, '', {}
local HasAlreadyEnteredMarker, LastHospital, LastPart, LastPartNum
local IsBusy                                             = false
local spawnedVehicles, isInShopMenu                      = {}, false
local hasRope                                            = true
local AmbulanceMenuState                                  = {
	open = false,
	level = 'none', -- none | main | submenu
	previousOpener = nil
}

local function safeCloseMenu(menu)
	if menu and type(menu.close) == 'function' then
		menu.close()
	end
end

function OpenAmbulanceActionsMenu()
	local elements = {
		{ label = 'เปลี่ยนชุด', value = 'cloakroom' }
	}

	local jobData = ESX.PlayerData and ESX.PlayerData.job
	if jobData and (jobData.grade_name == 'boss' or jobData.grade_name == 'mini_boss') then
		table.insert(elements, { label = 'เมนูผอ.', value = 'boss_actions' })
	end

	ESX.UI.Menu.CloseAll()

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'ambulance_actions', {
		title    = _U('ambulance'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)
		if data.current.value == 'cloakroom' then
			OpenCloakroomMenu()
		elseif data.current.value == 'boss_actions' then
			TriggerEvent('esx_society:openBossMenu', 'ambulance', function(data, menu)
				TriggerEvent('esx_ambulancejob:updateBlip')
				safeCloseMenu(menu)
			end, { wash = false })
		end
	end, function(data, menu)
		safeCloseMenu(menu)
	end)
end



local function pushNotify(text, notifyType, notifyTime)
	exports['APEX-AllNotify']:AddNotify({
		type = notifyType or 'info',
		text = text,
		time = notifyTime or 3000
	})
end


local ReviveTargetMarker = {
	playerId = nil,
	enabled = false,
	showHeadMarker = true,
	showRangeMarker = false,
	rangeRadius = 3.0
}

local function setReviveTargetMarker(playerId)
	if playerId and playerId ~= -1 then
		ReviveTargetMarker.playerId = playerId
		ReviveTargetMarker.enabled = true
	else
		ReviveTargetMarker.playerId = nil
		ReviveTargetMarker.enabled = false
	end
end

local function setReviveRangeMarker(radius)
	ReviveTargetMarker.showRangeMarker = true
	ReviveTargetMarker.rangeRadius = tonumber(radius) or 3.0
end

local function clearReviveTargetMarker()
	ReviveTargetMarker.playerId = nil
	ReviveTargetMarker.enabled = false
	ReviveTargetMarker.showHeadMarker = true
	ReviveTargetMarker.showRangeMarker = false
	ReviveTargetMarker.rangeRadius = 3.0
end

local function getNearbyDeadPlayersForRevive(maxDistance)
	local players = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), maxDistance or 3.0)
	local elements = {}

	for _, playerId in ipairs(players) do
		if playerId ~= PlayerId() then
			local targetPed = GetPlayerPed(playerId)
			if targetPed and DoesEntityExist(targetPed) and IsPedDeadOrDying(targetPed, true) then
				table.insert(elements, {
					label = string.format('%s | ID : %s', GetPlayerName(playerId), GetPlayerServerId(playerId)),
					value = playerId
				})
			end
		end
	end

	return elements
end


local function isPedHealable(targetPed)
	if not targetPed or not DoesEntityExist(targetPed) then
		return false
	end

	local health = GetEntityHealth(targetPed)
	local maxHealth = GetEntityMaxHealth(targetPed)
	if maxHealth <= 0 then
		maxHealth = 200
	end

	return health > 0 and health < maxHealth
end

local function getNearbyAlivePlayersForHeal(maxDistance)
	local players = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), maxDistance or 3.0)
	local elements = {}

	for _, playerId in ipairs(players) do
		if playerId ~= PlayerId() then
			local targetPed = GetPlayerPed(playerId)
			if targetPed and isPedHealable(targetPed) then
				table.insert(elements, {
					label = string.format('%s | ID : %s', GetPlayerName(playerId), GetPlayerServerId(playerId)),
					value = playerId
				})
			end
		end
	end

	return elements
end


local function getClosestPlayerWithin(maxDistance)
	local closestPlayer, closestDistance = ESX.Game.GetClosestPlayer()
	if closestPlayer == -1 or closestDistance > maxDistance then
		pushNotify('No Player Nearby.', 'error', 3000)
		return nil
	end

	return closestPlayer
end

local function sendMedicBill(targetPlayer, amount, billName)
	if amount and amount > 0 and targetPlayer and targetPlayer ~= -1 then
		TriggerServerEvent('esx_billing:sendBill', GetPlayerServerId(targetPlayer), 'society_ambulance', amount, billName or 'Fine: Ambulance')
	end
end

local function getMedicActionItem(actionType)
	local required = Config and Config.RequiredMedicItems and Config.RequiredMedicItems[actionType] or nil
	if not required or not required.name or required.name == '' then
		return nil, nil
	end

	local itemName = tostring(required.name)
	local itemLabel = (required.label and tostring(required.label)) or itemName
	return itemName, itemLabel
end

local function canUseMedicActionItem(actionType)
	local itemName, itemLabel = getMedicActionItem(actionType)
	if not itemName then
		pushNotify(('Missing Config.RequiredMedicItems.%s.name'):format(tostring(actionType)), 'error', 4000)
		return false, nil
	end

	if _CHKHASITEM(itemName) <= 0 then
		pushNotify(('You do not have %s.'):format(itemLabel), 'error', 3000)
		return false, itemName
	end
	return true, itemName
end

local function withMedicActionItem(actionType, onSuccess)
	local itemName, itemLabel = getMedicActionItem(actionType)
	if not itemName then
		pushNotify(('Missing Config.RequiredMedicItems.%s.name'):format(tostring(actionType)), 'error', 4000)
		return
	end

	ESX.TriggerServerCallback('esx_ambulancejob:hasItem', function(hasItem)
		if not hasItem then
			pushNotify(('You do not have %s.'):format(itemLabel), 'error', 3000)
			return
		end

		if onSuccess then
			onSuccess(itemName)
		end
	end, itemName, 1)
end


local function getBillingMenuConfig()
	local defaults = {
		Revive = {
			{ label = 'ชุบชีวิตทั่วไป', value = 1000 },
			{ label = 'ชุบนอกเมือง', value = 1500 },
			{ label = 'ชุบเมืองบน', value = 2000 },
			{ label = 'ชุบพื้นที่เข้าถึงยาก', value = 3000 },
			{ label = 'ชุบทั้งหมดพื้นที่สุ่มเสี่ยง', value = 4000 },
		},
		MassRevive = {
			{ label = 'ชุบหมู่ทั่วไป', value = 1000 },
			{ label = 'ชุบหมู่นอกเมือง', value = 1500 },
			{ label = 'ชุบหมู่เมืองบน', value = 2000 },
			{ label = 'ชุบหมู่พื้นที่เข้าถึงยาก', value = 3000 },
			{ label = 'ชุบหมู่พื้นที่สุ่มเสี่ยง', value = 4000 },
		},
		Heal = {
			single = { label = 'ฉีดยาเดี่ยว', value = 500 },
			mass = { label = 'ฉีดยาหมู่', value = 500 },
		},
		ReviveSelectRadius = 3.0,
		HealSelectRadius = 3.0
	}

	if not Config or not Config.BillingMenu then
		return defaults
	end

	local billing = Config.BillingMenu
	return {
		Revive = billing.Revive or defaults.Revive,
		MassRevive = billing.MassRevive or defaults.MassRevive,
		Heal = {
			single = (billing.Heal and billing.Heal.single) or defaults.Heal.single,
			mass = (billing.Heal and billing.Heal.mass) or defaults.Heal.mass,
		},
		ReviveSelectRadius = tonumber(billing.ReviveSelectRadius) or defaults.ReviveSelectRadius,
		HealSelectRadius = tonumber(billing.HealSelectRadius) or defaults.HealSelectRadius
	}
end

local function runReviveAnimation(callback)
	if IsBusy then return end
	IsBusy = true

	local lib, anim = 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest'
	local breakanim = false
	TriggerEvent("mythic_progbar:client:progress", {
		name = "unique_action_name",
		duration = 8000,
		label = "Revive",
		useWhileDead = false,
		canCancel = true,
		controlDisables = {
			disableMovement = true,
			disableCarMovement = true,
			disableMouse = false,
			disableCombat = true,
		},
	}, function(status)
		breakanim = true
		if not status and callback then callback() end
		IsBusy = false
	end)

	for _ = 1, 16, 1 do
		StopAnimTask(PlayerPedId(), lib, anim, 3.0)
		ESX.Streaming.RequestAnimDict(lib, function()
			TaskPlayAnim(PlayerPedId(), lib, anim, 8.0, -8.0, -1, 0, 0, false, false, false)
		end)
		Citizen.Wait(500)
		if breakanim then break end
	end
end

local function runHealAnimation(callback)
	if IsBusy then return end
	IsBusy = true
	local playerPed = PlayerPedId()
	TaskStartScenarioInPlace(playerPed, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)

	TriggerEvent("mythic_progbar:client:progress", {
		name = "unique_action_name",
		duration = 5000,
		label = "Healing",
		useWhileDead = false,
		canCancel = true,
		controlDisables = {
			disableMovement = true,
			disableCarMovement = true,
			disableMouse = false,
			disableCombat = true,
		},
	}, function(status)
		if not status and callback then callback() end
		ClearPedTasks(playerPed)
		IsBusy = false
	end)

	Citizen.Wait(5000)
	ClearPedTasks(playerPed)
end

local function doSingleRevive(targetPlayer, billAmount)
	withMedicActionItem('revive', function(reviveItem)
		local targetPed = GetPlayerPed(targetPlayer)
		if not IsPedDeadOrDying(targetPed, 1) then return end

		runReviveAnimation(function()
			TriggerServerEvent('esx_ambulancejob:removeItem', reviveItem)
			TriggerServerEvent('esx_ambulancejob:revive', GetPlayerServerId(targetPlayer))
			sendMedicBill(targetPlayer, billAmount, "Fine: Revive")
		end)
	end)
end

local function doMassRevive(radius, billAmount)
	withMedicActionItem('revive', function(reviveItem)
		local nearbyPlayers = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), radius or 5.0)
		local deadTargets = {}
		for _, playerId in ipairs(nearbyPlayers) do
			if playerId ~= PlayerId() then
				local ped = GetPlayerPed(playerId)
				if IsPedDeadOrDying(ped, 1) then table.insert(deadTargets, playerId) end
			end
		end

		if #deadTargets == 0 then
			pushNotify('No dead player nearby.', 'error', 3000)
			return
		end

		runReviveAnimation(function()
			TriggerServerEvent('esx_ambulancejob:removeItem', reviveItem)
			for _, playerId in ipairs(deadTargets) do
				TriggerServerEvent('esx_ambulancejob:revive', GetPlayerServerId(playerId))
				sendMedicBill(playerId, billAmount, "Fine: Mass Revive")
			end
		end)
	end)
end

local function doSingleHeal(targetPlayer, billAmount)
	withMedicActionItem('heal', function(healItem)
		local targetPed = GetPlayerPed(targetPlayer)
		if not isPedHealable(targetPed) then
			pushNotify('ผู้เล่นนี้เลือดเต็มแล้ว ไม่สามารถฉีดยาได้', 'error', 3000)
			return
		end

		runHealAnimation(function()
			TriggerServerEvent('esx_ambulancejob:removeItem', healItem)
			TriggerServerEvent('esx_ambulancejob:heal', GetPlayerServerId(targetPlayer), 'big')
			sendMedicBill(targetPlayer, billAmount, "Fine: Heal")
		end)
	end)
end

local function doMassHeal(radius, billAmount)
	withMedicActionItem('heal', function(healItem)
		local nearbyPlayers = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), radius or 5.0)
		local aliveTargets = {}
		for _, playerId in ipairs(nearbyPlayers) do
			if playerId ~= PlayerId() then
				local ped = GetPlayerPed(playerId)
				if isPedHealable(ped) then table.insert(aliveTargets, playerId) end
			end
		end

		if #aliveTargets == 0 then
			pushNotify('ไม่พบผู้เล่นที่ต้องฉีดยาในระยะ (ผู้เล่นเลือดเต็มจะไม่ถูกฉีด)', 'error', 3000)
			return
		end

		runHealAnimation(function()
			TriggerServerEvent('esx_ambulancejob:removeItem', healItem)
			for _, playerId in ipairs(aliveTargets) do
				TriggerServerEvent('esx_ambulancejob:heal', GetPlayerServerId(playerId), 'big')
				sendMedicBill(playerId, billAmount, "Fine: Mass Heal")
			end
		end)
	end)
end

local function OpenReviveTypeMenu()
	AmbulanceMenuState.open = true
	AmbulanceMenuState.level = 'submenu'
	AmbulanceMenuState.previousOpener = OpenMobileAmbulanceActionsMenu
	local billing = getBillingMenuConfig()
	local reviveRadius = tonumber(billing.ReviveSelectRadius) or 3.0
	local elements = {}
	for _, v in ipairs(billing.Revive) do
		table.insert(elements, { label = string.format('%s - %s$', v.label, v.value), value = v.value })
	end

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'revive_type_menu', {
		title = 'ชุบชีวิต',
		align = 'top-right',
		elements = elements
	}, function(data, menu)
		local billAmount = tonumber(data.current.value) or 0
		local deadPlayers = getNearbyDeadPlayersForRevive(reviveRadius)

		if #deadPlayers == 0 then
			pushNotify('ไม่พบผู้เล่นที่สลบอยู่ในระยะใกล้', 'error', 3000)
			clearReviveTargetMarker()
			return
		end

		local targetElements = {
			{ label = string.format('ทั้งหมดในระยะ %.1f เมตร', reviveRadius), value = 'all' }
		}
		for _, deadPlayer in ipairs(deadPlayers) do
			table.insert(targetElements, deadPlayer)
		end

		AmbulanceMenuState.level = 'submenu'
		ReviveTargetMarker.showHeadMarker = false
		setReviveRangeMarker(reviveRadius)

		ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'revive_target_menu', {
			title = 'เลือกผู้เล่นที่จะชุบชีวิต',
			align = 'top-right',
			elements = targetElements
		}, function(targetData, targetMenu)
			local selectedValue = targetData.current.value
			if selectedValue == 'all' then
				ReviveTargetMarker.showHeadMarker = false
				setReviveTargetMarker(nil)
				doMassRevive(reviveRadius, billAmount)
			else
				local targetPlayer = tonumber(selectedValue)
				if targetPlayer then
					ReviveTargetMarker.showHeadMarker = true
					setReviveTargetMarker(targetPlayer)
					doSingleRevive(targetPlayer, billAmount)
				end
			end
			safeCloseMenu(targetMenu)
			clearReviveTargetMarker()
		end, function(_, targetMenu)
			safeCloseMenu(targetMenu)
			clearReviveTargetMarker()
			if AmbulanceMenuState.open then
				AmbulanceMenuState.level = 'submenu'
			end
		end, function(changeData, _)
			if changeData.current.value == 'all' then
				ReviveTargetMarker.showHeadMarker = false
				setReviveTargetMarker(nil)
			else
				ReviveTargetMarker.showHeadMarker = true
				setReviveTargetMarker(tonumber(changeData.current.value))
			end
		end)
	end, function(_, menu)
		safeCloseMenu(menu)
		clearReviveTargetMarker()
		if AmbulanceMenuState.open then
			AmbulanceMenuState.level = 'main'
		end
	end)
end

local function OpenHealTypeMenu()
	AmbulanceMenuState.open = true
	AmbulanceMenuState.level = 'submenu'
	AmbulanceMenuState.previousOpener = OpenMobileAmbulanceActionsMenu
	local billing = getBillingMenuConfig()
	local healRadius = tonumber(billing.HealSelectRadius) or 3.0
	local elements = {
		{ label = string.format('%s - %s$', billing.Heal.single.label, billing.Heal.single.value), value = 'single', amount = billing.Heal.single.value },
		{ label = string.format('%s - %s$', billing.Heal.mass.label, billing.Heal.mass.value), value = 'mass', amount = billing.Heal.mass.value },
	}

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'heal_type_menu', {
		title = 'ฉีดยา',
		align = 'top-right',
		elements = elements
	}, function(data, menu)
		local billAmount = tonumber(data.current.amount) or 0
		local alivePlayers = getNearbyAlivePlayersForHeal(healRadius)

		if #alivePlayers == 0 then
			pushNotify('ไม่พบผู้เล่นที่ยังมีชีวิตอยู่ในระยะใกล้', 'error', 3000)
			clearReviveTargetMarker()
			return
		end

		local targetElements = {
			{ label = string.format('ทั้งหมดในระยะ %.1f เมตร', healRadius), value = 'all' }
		}
		for _, alivePlayer in ipairs(alivePlayers) do
			table.insert(targetElements, alivePlayer)
		end

		AmbulanceMenuState.level = 'submenu'
		ReviveTargetMarker.showHeadMarker = false
		setReviveRangeMarker(healRadius)

		ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'heal_target_menu', {
			title = 'เลือกผู้เล่นที่จะฉีดยา',
			align = 'top-right',
			elements = targetElements
		}, function(targetData, targetMenu)
			local selectedValue = targetData.current.value
			if selectedValue == 'all' then
				ReviveTargetMarker.showHeadMarker = false
				setReviveTargetMarker(nil)
				doMassHeal(healRadius, billAmount)
			else
				local targetPlayer = tonumber(selectedValue)
				if targetPlayer then
					ReviveTargetMarker.showHeadMarker = true
					setReviveTargetMarker(targetPlayer)
					doSingleHeal(targetPlayer, billAmount)
				end
			end
			safeCloseMenu(targetMenu)
			clearReviveTargetMarker()
		end, function(_, targetMenu)
			safeCloseMenu(targetMenu)
			clearReviveTargetMarker()
			if AmbulanceMenuState.open then
				AmbulanceMenuState.level = 'submenu'
			end
		end, function(changeData, _)
			if changeData.current.value == 'all' then
				ReviveTargetMarker.showHeadMarker = false
				setReviveTargetMarker(nil)
			else
				ReviveTargetMarker.showHeadMarker = true
				setReviveTargetMarker(tonumber(changeData.current.value))
			end
		end)
	end, function(_, menu)
		safeCloseMenu(menu)
		clearReviveTargetMarker()
		if AmbulanceMenuState.open then
			AmbulanceMenuState.level = 'main'
		end
	end)
end

function OpenMobileAmbulanceActionsMenu()
	ESX.UI.Menu.CloseAll()
	AmbulanceMenuState.open = true
	AmbulanceMenuState.level = 'main'
	AmbulanceMenuState.previousOpener = nil
	El = {
		{ label = 'ชุบชีวิต', value = 'revive_menu' },
		{ label = 'ฉีดยา', value = 'heal_menu' },
		{ label = 'ตรวจบัตรประชาชน', value = 'identity_card' },
		{ label = 'นำคนไข้ขึนรถ', value = 'put_in_vehicle' },
		{ label = 'นำคนไข้ออกรถ', value = 'put_out_vehicle' },
		{ label = 'เมนูบิล', value = 'billed' },
		{ label = 'ส่งตัวผู้เล่น', value = 'sendgarage' },
	}
	local currentJob = ESX.GetPlayerData() and ESX.GetPlayerData().job
	if currentJob and currentJob.grade_name == 'boss' then
		table.insert(El, { label = 'ผู้จัดการสูงสุด', value = 'ManagePerson' })
	end

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'mobile_ambulance_actions', {
		title    = _U('ambulance'),
		align    = 'top-right',
		elements = El
	}, function(data, menu)
		if data.current.value == 'ManagePerson' then
			TriggerEvent('APEX-BossAction:openMenu', 'ambulance')
			return
		elseif data.current.value == 'revive_menu' then
			OpenReviveTypeMenu()
		elseif data.current.value == 'heal_menu' then
			OpenHealTypeMenu()
		elseif data.current.value == 'identity_card' then
			local closestPlayer = getClosestPlayerWithin(3.0)
			if not closestPlayer then return end
			TriggerServerEvent('jsfour-idcard:forceShowIdCard', GetPlayerServerId(closestPlayer))
			TriggerServerEvent('cdc5be83-c880-48c9-93a8-c57db0c8f87e',
				GetPlayerServerId(closestPlayer), GetPlayerServerId(PlayerId()))
			TriggerServerEvent('esx_policejob:message', 'error', GetPlayerServerId(closestPlayer),
				'You have been your ID checked.')
		elseif data.current.value == 'sendgarage' then
			local closestPlayer = getClosestPlayerWithin(3.0)
			if not closestPlayer then return end
			AmbulanceMenuState.level = 'submenu'
			AmbulanceMenuState.previousOpener = OpenMobileAmbulanceActionsMenu
			ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'send_garage', {
				title    = "SEND PLAYER TO GARAGE",
				align    = 'top-right',
				elements = {
					{ label = 'ตงลง', value = 'YES' },
					{ label = 'ยกเลิก', value = 'NO' },
				}
			}, function(dataa, menuu)
				if dataa.current.value == "YES" then
					safeCloseMenu(menuu)
					TriggerServerEvent('sendplayertogarage', GetPlayerServerId(closestPlayer))
				else
					safeCloseMenu(menuu)
				end
			end, function(_, menuu)
				safeCloseMenu(menuu)
				if AmbulanceMenuState.open then
					AmbulanceMenuState.level = 'main'
				end
			end)
		elseif data.current.value == 'put_in_vehicle' then
			local closestPlayer = getClosestPlayerWithin(3.0)
			if not closestPlayer then return end
			TriggerServerEvent('esx_ambulancejob:putInVehicle', GetPlayerServerId(closestPlayer))
		elseif data.current.value == 'put_out_vehicle' then
			local closestPlayer = getClosestPlayerWithin(3.0)
			if not closestPlayer then return end
			TriggerServerEvent('esx_ambulancejob:outVehicle', GetPlayerServerId(closestPlayer))
		elseif data.current.value == 'billed' then
			local closestPlayer = getClosestPlayerWithin(2.0)
			if not closestPlayer then return end
			OpenCreateBilling(closestPlayer)
		end
	end, function(_, menu)
		safeCloseMenu(menu)
		AmbulanceMenuState.open = false
		AmbulanceMenuState.level = 'none'
		AmbulanceMenuState.previousOpener = nil
	end)
end

function FastTravel(coords, heading)
	local playerPed = PlayerPedId()

	DoScreenFadeOut(800)

	while not IsScreenFadedOut() do
		Citizen.Wait(500)
	end

	ESX.Game.Teleport(playerPed, coords, function()
		DoScreenFadeIn(800)

		if heading then
			SetEntityHeading(playerPed, heading)
		end
	end)
end


CreateThread(function()
	while true do
		local isRangeVisible = ReviveTargetMarker.showRangeMarker and (ReviveTargetMarker.rangeRadius or 0.0) > 0.0
		local isHeadVisible = ReviveTargetMarker.enabled and ReviveTargetMarker.showHeadMarker and ReviveTargetMarker.playerId

		if isRangeVisible then
			local playerCoords = GetEntityCoords(PlayerPedId())
			local radius = ReviveTargetMarker.rangeRadius or 3.0
			DrawMarker(1, playerCoords.x, playerCoords.y, playerCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
				radius * 2.0, radius * 2.0, 0.25, 80, 255, 80, 90, false, false, 2, false, nil, nil, false)
		end

		if isHeadVisible then
			local targetPed = GetPlayerPed(ReviveTargetMarker.playerId)
			if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
				local boneIndex = GetPedBoneIndex(targetPed, 0x796e)
				local markerCoords = GetPedBoneCoords(targetPed, boneIndex, 0.0, 0.0, 0.25)
				DrawMarker(2, markerCoords.x, markerCoords.y, markerCoords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
					0.18, 0.18, 0.18, 80, 255, 80, 190, false, true, 2, false, nil, nil, false)
			else
				setReviveTargetMarker(nil)
			end
		end

		if isRangeVisible or isHeadVisible then
			Wait(0)
		else
			Wait(250)
		end
	end
end)

-- Draw markers & Marker logic
Citizen.CreateThread(function()
	while true do
		local sleep = 1200
		local playerCoords = GetEntityCoords(PlayerPedId())
		local letSleep, isInMarker, hasExited = true, false, false
		local currentHospital, currentPart, currentPartNum

		for hospitalNum, hospital in pairs(Config.Hospitals) do
			-- Ambulance Actions
			for k, v in ipairs(hospital.AmbulanceActions or {}) do
				local distance = GetDistanceBetweenCoords(playerCoords, v, true)

				if distance < 7 then
					sleep = 0
					DrawMarker(Config.Marker.type, v, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Config.Marker.x, Config.Marker.y,
						Config.Marker.z, Config.Marker.r, Config.Marker.g, Config.Marker.b, Config.Marker.a, false, true,
						2, true, false, false, false)
					letSleep = false
				end

				if distance < Config.Marker.x then
					isInMarker, currentHospital, currentPart, currentPartNum = true, hospitalNum, 'AmbulanceActions', k
				end
			end

			--Pharmacies
			for k, v in ipairs(hospital.Pharmacies or {}) do
				local distance = GetDistanceBetweenCoords(playerCoords, v, true)

				if distance < 7 then
					sleep = 0
					DrawMarker(Config.Marker.type, v, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Config.Marker.x, Config.Marker.y,
						Config.Marker.z, Config.Marker.r, Config.Marker.g, Config.Marker.b, Config.Marker.a, false, false,
						2, true, false, false, false)
					letSleep = false
				end

				if distance < Config.Marker.x then
					isInMarker, currentHospital, currentPart, currentPartNum = true, hospitalNum, 'Pharmacy', k
				end
			end

			-- Vehicle Spawners
			for k, v in ipairs(hospital.Vehicles or {}) do
				local distance = GetDistanceBetweenCoords(playerCoords, v.Spawner, true)

				if distance < 10 then
					sleep = 0
					DrawMarker(v.Marker.type, v.Spawner, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, v.Marker.x, v.Marker.y, v.Marker
						.z, v.Marker.r, v.Marker.g, v.Marker.b, v.Marker.a, false, false, 2, v.Marker.rotate, nil, nil,
						false)
					letSleep = false
				end

				if distance < v.Marker.x then
					isInMarker, currentHospital, currentPart, currentPartNum = true, hospitalNum, 'Vehicles', k
				end
			end

			-- Helicopter Spawners
			for k, v in ipairs(hospital.Helicopters or {}) do
				local distance = GetDistanceBetweenCoords(playerCoords, v.Spawner, true)

				if distance < 20 then
					sleep = 0
					DrawMarker(v.Marker.type, v.Spawner, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, v.Marker.x, v.Marker.y, v.Marker
						.z, v.Marker.r, v.Marker.g, v.Marker.b, v.Marker.a, false, false, 2, v.Marker.rotate, nil, nil,
						false)
					letSleep = false
				end

				if distance < v.Marker.x then
					isInMarker, currentHospital, currentPart, currentPartNum = true, hospitalNum, 'Helicopters', k
				end
			end

			-- Fast Travels
			for k, v in ipairs(hospital.FastTravels or {}) do
				local distance = GetDistanceBetweenCoords(playerCoords, v.From, true)

				if distance < 20 then
					sleep = 0
					DrawMarker(v.Marker.type, v.From, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, v.Marker.x, v.Marker.y, v.Marker.z,
						v.Marker.r, v.Marker.g, v.Marker.b, v.Marker.a, false, false, 2, v.Marker.rotate, nil, nil, false)
					letSleep = false
				end


				if distance < v.Marker.x then
					FastTravel(v.To.coords, v.To.heading)
				end
			end
		end

		-- Logic for exiting & entering markers
		if isInMarker and not HasAlreadyEnteredMarker or (isInMarker and (LastHospital ~= currentHospital or LastPart ~= currentPart or LastPartNum ~= currentPartNum)) then
			if
				(LastHospital ~= nil and LastPart ~= nil and LastPartNum ~= nil) and
				(LastHospital ~= currentHospital or LastPart ~= currentPart or LastPartNum ~= currentPartNum)
			then
				TriggerEvent('esx_ambulancejob:hasExitedMarker', LastHospital, LastPart, LastPartNum)
				hasExited = true
			end

			HasAlreadyEnteredMarker, LastHospital, LastPart, LastPartNum = true, currentHospital, currentPart,
				currentPartNum

			TriggerEvent('esx_ambulancejob:hasEnteredMarker', currentHospital, currentPart, currentPartNum)
		end

		if not hasExited and not isInMarker and HasAlreadyEnteredMarker then
			HasAlreadyEnteredMarker = false
			TriggerEvent('esx_ambulancejob:hasExitedMarker', LastHospital, LastPart, LastPartNum)
		end

		if letSleep then
			sleep = 500
		end

		Citizen.Wait(sleep)
	end
end)

AddEventHandler('esx_ambulancejob:hasEnteredMarker', function(hospital, part, partNum)
	local playerJob = ESX.PlayerData and ESX.PlayerData.job
	if playerJob and playerJob.name == 'ambulance' then
		if part == 'AmbulanceActions' then
			CurrentAction = part
			CurrentActionMsg = _U('actions_prompt')
			CurrentActionData = {}
		elseif part == 'Pharmacy' then
			CurrentAction = part
			CurrentActionMsg = _U('open_pharmacy')
			CurrentActionData = {}
		elseif part == 'Vehicles' then
			CurrentAction = part
			CurrentActionMsg = _U('garage_prompt')
			CurrentActionData = { hospital = hospital, partNum = partNum }
		elseif part == 'Helicopters' then
			CurrentAction = part
			CurrentActionMsg = _U('helicopter_prompt')
			CurrentActionData = { hospital = hospital, partNum = partNum }
		elseif part == 'FastTravelsPrompt' then
			local travelItem = Config.Hospitals[hospital][part][partNum]

			CurrentAction = part
			CurrentActionMsg = travelItem.Prompt
			CurrentActionData = { to = travelItem.To.coords, heading = travelItem.To.heading }
		end
	end
end)

AddEventHandler('esx_ambulancejob:hasExitedMarker', function(hospital, part, partNum)
	if not isInShopMenu then
		ESX.UI.Menu.CloseAll()
	end

	CurrentAction = nil
end)

-- Key Controls
Citizen.CreateThread(function()
	while true do
		local sleep = 250

		if IsControlJustReleased(0, Keys['BACKSPACE']) then
			if AmbulanceMenuState.open then
				if AmbulanceMenuState.level == 'submenu' and AmbulanceMenuState.previousOpener then
					local previousOpener = AmbulanceMenuState.previousOpener
					ESX.UI.Menu.CloseAll()
					Citizen.SetTimeout(0, function()
						previousOpener()
					end)
				else
					ESX.UI.Menu.CloseAll()
					AmbulanceMenuState.open = false
					AmbulanceMenuState.level = 'none'
					AmbulanceMenuState.previousOpener = nil
					CurrentAction = nil
				end
			else
				ESX.UI.Menu.CloseAll()
				CurrentAction = nil
			end
		end

		if CurrentAction then
			sleep = 0
			pcall(function()
				exports['AFU.Toastify']:show({
					{ type = 'text', prop = 'PRESS' },
					{ type = 'key',  prop = 'E' },
					{ type = 'text', prop = 'TO OPEN MENU' },
				})
			end)

			if IsControlJustReleased(0, Keys['E']) then
				if CurrentAction == 'AmbulanceActions' then
					OpenAmbulanceActionsMenu()
				elseif CurrentAction == 'Pharmacy' then
					OpenPharmacyMenu()
				elseif CurrentAction == 'Vehicles' then
					OpenVehicleSpawnerMenu(CurrentActionData.hospital, CurrentActionData.partNum)
				elseif CurrentAction == 'Helicopters' then
					OpenHelicopterSpawnerMenu(CurrentActionData.hospital, CurrentActionData.partNum)
				elseif CurrentAction == 'FastTravelsPrompt' then
					FastTravel(CurrentActionData.to, CurrentActionData.heading)
				end

				CurrentAction = nil
			end
		elseif ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name == 'ambulance' and not IsDead then
			sleep = 0
			if IsControlJustReleased(0, Keys['F6']) then
				OpenMobileAmbulanceActionsMenu()
			end
		end

		Citizen.Wait(sleep)
	end
end)

Citizen.CreateThread(function()
	while true do
		local sleep = 500
		if isInShopMenu then
			sleep = 5
			DisableControlAction(0, 75, true)
			DisableControlAction(27, 75, true)
		end
		Citizen.Wait(sleep)
	end
end)

RegisterNetEvent('esx_ambulancejob:putInVehicle')
AddEventHandler('esx_ambulancejob:putInVehicle', function()
	local playerPed = PlayerPedId()
	local coords = GetEntityCoords(playerPed)

	if IsAnyVehicleNearPoint(coords, 5.0) then
		local vehicle = GetClosestVehicle(coords, 5.0, 0, 71)

		if DoesEntityExist(vehicle) then
			local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(vehicle)

			for i = maxSeats - 1, 0, -1 do
				if IsVehicleSeatFree(vehicle, i) then
					freeSeat = i
					break
				end
			end

			if freeSeat then
				TaskWarpPedIntoVehicle(playerPed, vehicle, freeSeat)
			end
		end
	end
end)

function OpenCloakroomMenu()
	local playerPed = PlayerPedId()
	local jobData = ESX.PlayerData and ESX.PlayerData.job
	if not jobData then
		ESX.ShowNotification('Job data not ready')
		return
	end
	local grade = jobData.grade_name
	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'cloakroom', {
		title    = _U('cloakroom'),
		align    = 'top-right',
		elements = {
			{ label = '<i class="fa-sharp fa-solid fa-shirt"></i>  :  ชุดประชาชน', value = 'citizen_wear' },
			{ label = '<i class="fa-sharp fa-solid fa-shirt"></i>  :  ชุดหน่วยงาน', uniform = grade }
		}
	}, function(data, menu)
		if data.current.value == 'citizen_wear' then
			ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)
				TriggerEvent('skinchanger:loadSkin', skin)
			end)
		end
		if data.current.uniform then
			setUniform(data.current.uniform, playerPed)
		end
		safeCloseMenu(menu)
	end, function(data, menu)
		safeCloseMenu(menu)
	end)
end

function setUniform(uniform, playerPed)
	TriggerEvent('skinchanger:getSkin', function(skin)
		local uniformObject

		if skin.sex == 0 then
			uniformObject = Config.Uniforms[uniform].male
		else
			uniformObject = Config.Uniforms[uniform].female
		end

		if uniformObject then
			TriggerEvent('skinchanger:loadClothes', skin, uniformObject)

			if uniform == 'bullet_wear' then
				SetPedArmour(playerPed, 100)
			end
		else
			ESX.ShowNotification(_U('no_outfit'))
		end
	end)
end

function OpenVehicleSpawnerMenu(hospital, partNum)
	local playerCoords = GetEntityCoords(PlayerPedId())
	local elements = {
		{ label = '<i class="fa-sharp fa-solid fa-dollar-sign"></i>  :  ซื้อรถ', action = 'buy_vehicle' }
	}

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'vehicle', {
		title    = _U('garage_title'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)
		if data.current.action == 'buy_vehicle' then
			local shopCoords = Config.Hospitals[hospital].Vehicles[partNum].InsideShop
			local shopElements = {}

			local jobData = ESX.PlayerData and ESX.PlayerData.job
			if not jobData then
				return
			end

			local authorizedVehicles = Config.AuthorizedVehicles[jobData.grade_name] or {}

			if #authorizedVehicles > 0 then
				for k, vehicle in ipairs(authorizedVehicles) do
					table.insert(shopElements, {
						label = ('%s - <span style="color:green;">%s</span>'):format(vehicle.label,
							_U('shop_item', ESX.Math.GroupDigits(vehicle.price))),
						name  = vehicle.label,
						model = vehicle.model,
						price = vehicle.price,
						type  = 'car'
					})
				end
			else
				return
			end

			OpenShopMenu(shopElements, playerCoords, shopCoords)
		end
	end, function(data, menu)
		safeCloseMenu(menu)
	end)
end

function OpenHelicopterSpawnerMenu(hospital, partNum)
	local playerCoords = GetEntityCoords(PlayerPedId())
	ESX.PlayerData = ESX.GetPlayerData()
	local elements = {
		{ label = '<i class="fa-sharp fa-solid fa-dollar-sign"></i>  :  ซื้อฮอ', action = 'buy_helicopter' }
	}

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'helicopter_spawner', {
		title    = _U('helicopter_title'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)
		if data.current.action == 'buy_helicopter' then
			local shopCoords = Config.Hospitals[hospital].Helicopters[partNum].InsideShop
			local shopElements = {}

			local jobData = ESX.PlayerData and ESX.PlayerData.job
			if not jobData then
				return
			end

			local authorizedHelicopters = Config.AuthorizedHelicopters[jobData.grade_name] or {}

			if #authorizedHelicopters > 0 then
				for k, helicopter in ipairs(authorizedHelicopters) do
					table.insert(shopElements, {
						label = ('%s - <span style="color:green;">%s</span>'):format(helicopter.label,
							_U('shop_item', ESX.Math.GroupDigits(helicopter.price))),
						name  = helicopter.label,
						model = helicopter.model,
						price = helicopter.price,
						type  = 'helicopter'
					})
				end
			else
				exports.nc_notify:PushNotification({
					title = 'Shopping Error',
					description =
					'ผิดพลาด : <btn style="background-color: rgba(0, 0, 0, .8); color:white;">คุณไม่มีสิทธิ์ในการซื้อเฮริคอบเตอร์...</btn> ',
					icon = 'car',
					type = 'error',
					duration = 3000
				})
				return
			end

			OpenShopheli(shopElements, playerCoords, shopCoords)
		end
	end, function(data, menu)
		safeCloseMenu(menu)
	end)
end

function OpenShopMenu(elements, restoreCoords, shopCoords)
	local playerPed = PlayerPedId()
	isInShopMenu = true

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'vehicle_shop', {
		title    = _U('vehicleshop_title'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)

		ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'vehicle_shop_confirm', {
			title    = _U('vehicleshop_confirm', data.current.name, data.current.price),
			align    = 'top-right',
			elements = {
				{ label = _U('confirm_no'), value = 'no' },
				{ label = _U('confirm_yes'), value = 'yes' }
			}
		}, function(data2, menu2)

			if data2.current.value == 'yes' then
				local newPlate = exports['Everything_Vehicle.Shop']:GeneratePlate()
				local vehicle  = GetVehiclePedIsIn(playerPed, false)
				local props    = ESX.Game.GetVehicleProperties(vehicle)
				props.plate    = newPlate

				ESX.TriggerServerCallback('esx_ambulancejob:buyJobVehicle', function (bought)
					if bought then
						exports.nc_notify:PushNotification({
							title = 'Shopping Success',
							description = 'แจ้งเตือน : <btn style="background-color: rgba(0, 0, 0, .8); color:white;">คุณได้ซื้อรถเรียบร้อย...</btn> ',
							icon = 'car',
							type = 'success',
							duration = 3000
						})

						pcall(function() exports.nc_garage:SyncVehicle(vehicle) end)
						exports.nc_inventory:AddItem({
							name = newPlate,
							type = 'vehicle_key'
						})
						exports.nc_inventory:UpdateItems('vehicle_key')

						isInShopMenu = false
						ESX.UI.Menu.CloseAll()

						DeleteSpawnedVehicles()
						FreezeEntityPosition(playerPed, false)
						SetEntityVisible(playerPed, true)

						ESX.Game.Teleport(playerPed, restoreCoords)
					else
						exports.nc_notify:PushNotification({
							title = 'Shopping Error',
							description = 'ผิดพลาด : <btn style="background-color: rgba(0, 0, 0, .8); color:white;">คุณไม่สามารถซื้อรถได้...</btn> ',
							icon = 'car',
							type = 'error',
							duration = 3000
						})
						safeCloseMenu(menu2)
					end
				end, props, data.current.type)
			else
				safeCloseMenu(menu2)
			end

		end, function(data2, menu2)
			safeCloseMenu(menu2)
		end)

		end, function(data, menu)
		isInShopMenu = false
		ESX.UI.Menu.CloseAll()

		DeleteSpawnedVehicles()
		FreezeEntityPosition(playerPed, false)
		SetEntityVisible(playerPed, true)

		ESX.Game.Teleport(playerPed, restoreCoords)
	end, function(data, menu)
		DeleteSpawnedVehicles()

		WaitForVehicleToLoad(data.current.model)
		ESX.Game.SpawnLocalVehicle(data.current.model, shopCoords, 0.0, function(vehicle)
			table.insert(spawnedVehicles, vehicle)
			TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
			FreezeEntityPosition(vehicle, true)
		end)
	end)

	WaitForVehicleToLoad(elements[1].model)
	ESX.Game.SpawnLocalVehicle(elements[1].model, shopCoords, 0.0, function(vehicle)
		table.insert(spawnedVehicles, vehicle)
		TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
		FreezeEntityPosition(vehicle, true)
	end)
end

function OpenShopheli(elements, restoreCoords, shopCoords)
	local playerPed = PlayerPedId()
	isInShopMenu = true

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'vehicle_shop', {
		title    = _U('vehicleshop_title'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)
		ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'vehicle_shop_confirm', {
			title    = _U('vehicleshop_confirm', data.current.name, data.current.price),
			align    = 'top-right',
			elements = {
				{ label = _U('confirm_no'),  value = 'no' },
				{ label = _U('confirm_yes'), value = 'yes' }
			}
		}, function(data2, menu2)
			if data2.current.value == 'yes' then
				local newPlate = exports['Everything_Vehicle.Shop']:GeneratePlate()
				local vehicle  = GetVehiclePedIsIn(playerPed, false)
				local props    = ESX.Game.GetVehicleProperties(vehicle)
				props.plate    = newPlate

				ESX.TriggerServerCallback('esx_ambulancejob:buyJobheli', function(bought)
					if bought then
						exports.nc_notify:PushNotification({
							title = 'Shopping Success',
							description =
							'แจ้งเตือน : <btn style="background-color: rgba(0, 0, 0, .8); color:white;">คุณได้ซื้อรถเรียบร้อย...</btn> ',
							icon = 'car',
							type = 'success',
							duration = 3000
						})

						pcall(function() exports.nc_garage:SyncVehicle(vehicle) end)
						exports.nc_inventory:AddItem({
							name = newPlate,
							type = 'vehicle_key'
						})
						exports.nc_inventory:UpdateItems('vehicle_key')

						isInShopMenu = false
						ESX.UI.Menu.CloseAll()

						DeleteSpawnedVehicles()
						FreezeEntityPosition(playerPed, false)
						SetEntityVisible(playerPed, true)

						ESX.Game.Teleport(playerPed, restoreCoords)
					else
						exports.nc_notify:PushNotification({
							title = 'Shopping Error',
							description =
							'ผิดพลาด : <btn style="background-color: rgba(0, 0, 0, .8); color:white;">คุณไม่สามารถซื้อรถได้...</btn> ',
							icon = 'car',
							type = 'error',
							duration = 3000
						})
						safeCloseMenu(menu2)
					end
				end, props, data.current.type)
			else
				safeCloseMenu(menu2)
			end
		end, function(data2, menu2)
			safeCloseMenu(menu2)
		end)
	end, function(data, menu)
		isInShopMenu = false
		ESX.UI.Menu.CloseAll()

		DeleteSpawnedVehicles()
		FreezeEntityPosition(playerPed, false)
		SetEntityVisible(playerPed, true)

		ESX.Game.Teleport(playerPed, restoreCoords)
	end, function(data, menu)
		DeleteSpawnedVehicles()

		WaitForVehicleToLoad(data.current.model)
		ESX.Game.SpawnLocalVehicle(data.current.model, shopCoords, 0.0, function(vehicle)
			table.insert(spawnedVehicles, vehicle)
			TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
			FreezeEntityPosition(vehicle, true)
		end)
	end)

	WaitForVehicleToLoad(elements[1].model)
	ESX.Game.SpawnLocalVehicle(elements[1].model, shopCoords, 0.0, function(vehicle)
		table.insert(spawnedVehicles, vehicle)
		TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
		FreezeEntityPosition(vehicle, true)
	end)
end

function DeleteSpawnedVehicles()
	while #spawnedVehicles > 0 do
		local vehicle = spawnedVehicles[1]
		ESX.Game.DeleteVehicle(vehicle)
		table.remove(spawnedVehicles, 1)
	end
end

function WaitForVehicleToLoad(modelHash)
	modelHash = (type(modelHash) == 'number' and modelHash or GetHashKey(modelHash))

	if not HasModelLoaded(modelHash) then
		RequestModel(modelHash)

		while not HasModelLoaded(modelHash) do
			Citizen.Wait(5)

			DisableControlAction(0, Keys['TOP'], true)
			DisableControlAction(0, Keys['DOWN'], true)
			DisableControlAction(0, Keys['LEFT'], true)
			DisableControlAction(0, Keys['RIGHT'], true)
			DisableControlAction(0, 176, true)
			DisableControlAction(0, Keys['BACKSPACE'], true)

			drawLoadingText(_U('vehicleshop_awaiting_model'), 255, 255, 255, 255)
		end
	end
end

function drawLoadingText(text, red, green, blue, alpha)
	SetTextFont(4)
	SetTextProportional(0)
	SetTextScale(0.0, 0.5)
	SetTextColour(red, green, blue, alpha)
	SetTextDropShadow(0, 0, 0, 0, 255)
	SetTextEdge(1, 0, 0, 0, 255)
	SetTextDropShadow()
	SetTextOutline()
	SetTextCentre(true)

	BeginTextCommandDisplayText("STRING")
	AddTextComponentSubstringPlayerName(text)
	EndTextCommandDisplayText(0.5, 0.5)
end

function OpenPharmacyMenu()
	ESX.UI.Menu.CloseAll()

	local elements = {}
	local pharmacyItems = (Config and Config.PharmacyItems) or {}

	for _, itemData in ipairs(pharmacyItems) do
		table.insert(elements, {
			label = ('<i class="fa-sharp fa-solid fa-dollar-sign"></i>  :  %s'):format(itemData.label or itemData.item),
			value = itemData.item,
			count = tonumber(itemData.count) or 1
		})
	end

	if #elements == 0 then
		elements = {
			{ label = '<i class="fa-sharp fa-solid fa-dollar-sign"></i>  :  First Aid Kit', value = 'ag_medikit', count = 1 },
			{ label = '<i class="fa-sharp fa-solid fa-dollar-sign"></i>  :  Oxygen Mask', value = 'ag_scuba', count = 1 },
		}
	end

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'pharmacy', {
		title    = _U('pharmacy_menu_title'),
		align    = 'top-right',
		elements = elements
	}, function(data, menu)
		TriggerServerEvent('esx_ambulancejob:giveItem', data.current.value, tonumber(data.current.count) or 1)
	end, function(data, menu)
		safeCloseMenu(menu)
	end)
end

RegisterNetEvent('esx_ambulancejob:heal')
AddEventHandler('esx_ambulancejob:heal', function(healType, quiet)
	local playerPed = PlayerPedId()
	local maxHealth = GetEntityMaxHealth(playerPed)

	if healType == 'small' then
		local health = GetEntityHealth(playerPed)
		local newHealth = math.min(maxHealth, math.floor(health + maxHealth / 8))
		local ped = GetPlayerPed(-1)
		SetEntityHealth(playerPed, newHealth)
	elseif healType == 'big' then
		local ped = GetPlayerPed(-1)
		SetPedMaxHealth(ped, 200)
		SetEntityHealth(ped, GetEntityHealth(ped) + 200)
	end

	if not quiet then
	end
end)

function _CHKHASITEM(Item)
	if not Item or Item == '' then
		return 0
	end

	local itemName = string.lower(tostring(Item))

	if ESX.SearchInventory then
		local ok, result = pcall(function()
			return ESX.SearchInventory(itemName, true)
		end)
		if ok and result ~= nil then
			return tonumber(result) or 0
		end
	end

	local inventory = ESX.GetPlayerData() and ESX.GetPlayerData().inventory or {}
	for _, value in pairs(inventory) do
		local invName = value and value.name and string.lower(tostring(value.name)) or nil
		if invName == itemName then
			return tonumber(value.count) or 0
		end
	end
	return 0
end

RegisterNetEvent('esx_ambulancejob:outVehicle')
AddEventHandler('esx_ambulancejob:outVehicle', function()
	local playerPed = PlayerPedId()

	if not IsPedSittingInAnyVehicle(playerPed) then
		return
	end

	local vehicle = GetVehiclePedIsIn(playerPed, false)
	TaskLeaveVehicle(playerPed, vehicle, 16)
end)

RegisterNetEvent('sendplayertogarage')
AddEventHandler('sendplayertogarage', function()
	RdmPoint = math.random(1, #Config.RandomPointSendPlayer)

	SetEntityCoords(PlayerPedId(), Config.RandomPointSendPlayer[RdmPoint].x, Config.RandomPointSendPlayer[RdmPoint].y,
		Config.RandomPointSendPlayer[RdmPoint].z + 1)
	SetEntityHeading(PlayerPedId(), Config.RandomPointSendPlayer[RdmPoint].h)
end)

function OpenCreateBilling(player)
	if AmbulanceMenuState.open then
		AmbulanceMenuState.level = 'submenu'
		AmbulanceMenuState.previousOpener = OpenMobileAmbulanceActionsMenu
	end
	El = {}
	for k, v in pairs(Config.BILL) do
		table.insert(El, { label = v.label .. " - " .. v.value .. "$", value = v.value })
	end

	ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'fine',
		{
			title    = _U('billing'),
			align    = 'top-right',
			elements = El
		}, function(data, menu)
			if data.current.value then
				if player < 0 then
					return
				end
				TriggerServerEvent('esx_billing:sendBill', GetPlayerServerId(player), 'society_ambulance', tonumber(data.current.value), 'Fine: Ambulance')
				pushNotify('Send Fine To Player Id ' .. GetPlayerServerId(player), 'success', 3000)
				safeCloseMenu(menu)
			end
		end, function(data, menu)
			safeCloseMenu(menu)
			if AmbulanceMenuState.open then
				AmbulanceMenuState.level = 'main'
			end
		end)
end

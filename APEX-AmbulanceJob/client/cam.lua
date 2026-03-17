local cam = nil
local isDead = false
local camLoopRunning = false
local lastDeadState = false

local angleY = 0.0
local angleZ = 0.0

local CAMERA_FOV = 50.0
local CAMERA_RADIUS = 6.0
local CAMERA_EXTRA_RADIUS = 0.5
local CAMERA_RAYCAST_INTERVAL = 150

local function startCamLoop()
    if camLoopRunning then return end
    camLoopRunning = true

    CreateThread(function()
        local lastRaycastTime = 0

        while isDead and cam do
            local currentTime = GetGameTimer()
            ProcessCamControls(currentTime, lastRaycastTime)
            Wait(0)
            if currentTime - lastRaycastTime > CAMERA_RAYCAST_INTERVAL then
                lastRaycastTime = currentTime
            end
        end

        camLoopRunning = false
    end)
end

function StartDeathCam()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    ClearFocus()
    cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", coords, 0.0, 0.0, 0.0, CAMERA_FOV)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, false)
    startCamLoop()
end

function EndDeathCam()
    ClearFocus()
    RenderScriptCams(false, false, 0, true, false)
    if cam then
        DestroyCam(cam, false)
        cam = nil
    end
end

function ProcessCamControls(currentTime, lastRaycastTime)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    DisableFirstPersonCamThisFrame()
    local newPos = ProcessNewPosition(playerCoords, currentTime, lastRaycastTime)
    SetFocusArea(newPos.x, newPos.y, newPos.z, 0.0, 0.0, 0.0)
    SetCamCoord(cam, newPos.x, newPos.y, newPos.z)
    PointCamAtCoord(cam, playerCoords.x, playerCoords.y, playerCoords.z + 0.5)
end

function ProcessNewPosition(pCoords, currentTime, lastRaycastTime)
    local mouseX = GetDisabledControlNormal(1, 1) * (IsInputDisabled(0) and 8.0 or 1.5)
    local mouseY = GetDisabledControlNormal(1, 2) * (IsInputDisabled(0) and 8.0 or 1.5)

    angleZ = angleZ - mouseX
    angleY = math.max(-89.0, math.min(89.0, angleY + mouseY))

    local cosY, sinY = Cos(angleY), Sin(angleY)
    local cosZ, sinZ = Cos(angleZ), Sin(angleZ)
    local Rpad = CAMERA_RADIUS + CAMERA_EXTRA_RADIUS

    local behindCam = vector3(pCoords.x + (cosZ * cosY) * Rpad, pCoords.y + (sinZ * cosY) * Rpad, pCoords.z + (sinY) * Rpad)

    local maxRadius = CAMERA_RADIUS
    if currentTime - lastRaycastTime > CAMERA_RAYCAST_INTERVAL then
        local rayHandle = StartShapeTestRay(pCoords.x, pCoords.y, pCoords.z + 0.5, behindCam.x, behindCam.y, behindCam.z, -1, PlayerPedId(), 0)
        local _, hitBool, hitCoords = GetShapeTestResult(rayHandle)
        if hitBool then
            local dist = #(vector3(pCoords.x, pCoords.y, pCoords.z + 0.5) - hitCoords)
            if dist < Rpad then
                maxRadius = dist
            end
        end
    end

    return vector3(
        pCoords.x + (cosZ * cosY) * maxRadius,
        pCoords.y + (sinZ * cosY) * maxRadius,
        pCoords.z + (sinY) * maxRadius
    )
end

-- ใช้ OnPlayerData callback แทน polling เพื่อลด CPU usage
function OnPlayerData(key, val)
    if key == 'dead' then
        local dead = val or false
        if dead and not lastDeadState then
            isDead = true
            StartDeathCam()
            lastDeadState = true
        elseif not dead and lastDeadState then
            isDead = false
            EndDeathCam()
            lastDeadState = false
        end
    end
end

-- Fallback: ตรวจสอบเมื่อเริ่มต้น (กรณีที่ OnPlayerData ยังไม่ถูกเรียก)
CreateThread(function()
    while not ESX or not ESX.PlayerData do
        Wait(100)
    end
    
    -- ตรวจสอบสถานะเริ่มต้น
    local initialDead = ESX.PlayerData.dead or false
    if initialDead and not lastDeadState then
        isDead = true
        StartDeathCam()
        lastDeadState = true
    end
end)

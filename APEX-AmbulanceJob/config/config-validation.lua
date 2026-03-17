Config = Config or {}

local function ensureNumber(path, value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    return n
end

function Config.ValidateEnterpriseConfig()
    Config.Performance = Config.Performance or {}
    Config.Security = Config.Security or {}
    Config.Feature = Config.Feature or {}
    Config.UI = Config.UI or {}
    Config.Debug = Config.Debug or {}

    Config.Performance.EventRateWindowMs = math.max(1000, ensureNumber('Performance.EventRateWindowMs', Config.Performance.EventRateWindowMs, 10000))
    Config.Performance.EventQueueSoftLimit = math.max(1, ensureNumber('Performance.EventQueueSoftLimit', Config.Performance.EventQueueSoftLimit, 64))

    Config.Security.DefaultEventLimit = math.max(1, ensureNumber('Security.DefaultEventLimit', Config.Security.DefaultEventLimit, 15))
    Config.Security.MaxBatchTargets = math.max(1, ensureNumber('Security.MaxBatchTargets', Config.Security.MaxBatchTargets, 20))

    Config.UI.NotificationThrottleMs = math.max(250, ensureNumber('UI.NotificationThrottleMs', Config.UI.NotificationThrottleMs, 1500))

    if type(Config.Debug.LogLevel) ~= 'string' then
        Config.Debug.LogLevel = 'INFO'
    end
end

Config.ValidateEnterpriseConfig() -- ตรวจสอบคอนฟิกเมื่อโหลดไฟล์เพื่อบังคับใช้ค่า fallback ที่ปลอดภัย

-- Zone Configuration System
-- ไฟล์นี้ใช้สำหรับตั้งค่า zone ต่างๆ ในระบบ death handling

Config = Config or {}

Config.EnableDuplicateCheck       = true  -- เปิด/ปิดระบบตรวจสอบการตายซ้ำ

Config.Zones = {
    -- Training Zone Configuration
    training = {
        clearBody = true,
        title = "Please wait for the respawn timer to finish",
        actions = {
            ui = {"sendSignalUi", "gangRequest"},
            voice = "clearBodyVoice",
            specialButton = "startWarzoneTimer"
        }
    },

    -- Airdrop Zone Configuration
    airdrop = {
        clearBody = false,
        title = "กด G เพื่อออกจากโซนแอร์ดรอป ไปจุดเดิมก่อนเข้าแอร์ดรอป",
        actions = {
            ui = {"sendSignalUi", "gangRequest"},
            voice = "clearBodyVoice",
            body = "startBodyStabilizationSequence",
            specialButton = "startAirdropSpecialButton"
        }
    },

    -- Stelshop Zone Configuration
    stelshop = {
        clearBody = false,
        title = "กด G เพื่อออกจากโซนงัดร้าน เกิดโรงพยาบาล ต้องมีเงิน 1,500$",
        actions = {
            ui = {"gangRequest"},
            voice = "clearBodyVoice",
            signal = "startDistressSignal",
            body = "startBodyStabilizationSequence",
            specialButton = "startStelshopSpecialButton"
        }
    },

    -- Replight Zone Configuration
    replight = {
        clearBody = false,
        title = "กด G เพื่อออกจากโซนซ่อมไฟ เกิดโรงพยาบาล ต้องมีเงิน 1,500$",
        checks = {
            duplicate = {
                enabled = true,
                indexParam = true          -- ใช้ locationId (string) เป็น parameter สำหรับ tracking
            }
        },
        actions = {
            voice = "clearBodyVoice",
            signal = {"startDistressSignal", "startDistressSignalGang"},
            body = "startBodyStabilizationSequence",
            specialButton = "startReplightSpecialButton"
        }
    },

    -- Waterpipe Zone Configuration
    waterpipe = {
        clearBody = false,
        title = "กด G เพื่อออกจากโซนซ่อมท่อน้ำ เกิดโรงพยาบาล ต้องมีเงิน 1,500$",
        checks = {
            duplicate = {
                enabled = true,
                indexParam = true          -- ใช้ locationId (string) เป็น parameter สำหรับ tracking
            }
        },
        actions = {
            voice = "clearBodyVoice",
            signal = {"startDistressSignal", "startDistressSignalGang"},
            body = "startBodyStabilizationSequence",
            specialButton = "startWaterpipeSpecialButton"
        }
    },

    -- Megacement Zone Configuration
    megacement = {
        clearBody = false,
        title = "กด G เพื่อออกจากโซนชิงกองปูน เกิดโรงพยาบาล ต้องมีเงิน 1,500$",
        checks = {
            duplicate = {
                enabled = true,
                indexParam = true          -- ใช้ locationId (string) เป็น parameter สำหรับ tracking
            }
        },
        actions = {
            voice = "clearBodyVoice",
            signal = {"startDistressSignal", "startDistressSignalGang"},
            body = "startBodyStabilizationSequence",
            specialButton = "startMegacementSpecialButton"
        }
    }
}

-- Action Mapping Configuration
-- กำหนดการ map ระหว่างชื่อ action กับฟังก์ชันจริง
Config.ActionMap = {
    -- UI Actions
    sendSignalUi = function() sendSignalUi(true) end,
    gangRequest = function() gangRequest(true) end,
    
    -- Voice Actions
    clearBodyVoice = function() clearBodyVoice() end,
    
    -- Body Actions
    startBodyStabilizationSequence = function() startBodyStabilizationSequence() end,
    
    -- Signal Actions
    startDistressSignal = function() startDistressSignal() end,
    startDistressSignalGang = function() startDistressSignalGang() end,
    
    -- Timer Actions (ใช้ฟังก์ชัน Timer เดิม)
    startWarzoneTimer = function() startWarzoneTimer() end,
    
    -- Special Button Actions (ปุ่ม G พิเศษ)
    startAirdropSpecialButton = function() startAirdropSpecialButton() end,
    startStelshopSpecialButton = function() startStelshopSpecialButton() end,
    startReplightSpecialButton = function(index) startReplightSpecialButton(index) end,
    startWaterpipeSpecialButton = function(index) startWaterpipeSpecialButton(index) end,
    startMegacementSpecialButton = function(index) startMegacementSpecialButton(index) end,
}

-- Timer Configuration System (ไม่ใช้แล้ว - ใช้ฟังก์ชันเดิมแทน)
-- Config.TimerConfigs = { ... }

-- Zone Detection Configuration
-- กำหนดการตรวจสอบ zone ต่างๆ
Config.ZoneDetection = {
    training = function()
        local result = false
        pcall(function()
            result = exports["lizz_training"]:CheckTrainingZone()
        end)
        return result
    end,
    
    airdrop = function()
        local result = false
        pcall(function()
            result = exports["xcore-airdrop"]:getPlayerInAirdrop()
        end)
        return result
    end,
    
    stelshop = function()
        local result = false
        pcall(function()
            result = exports["ishop_stelshops"]:inEvent()
        end)
        return result
    end,
    
    replight = function()
        local result = nil
        pcall(function()
            result = exports["lizz_replight"]:getClosestReplightIndex()
        end)
        -- Validate result: รับทั้ง number (index) และ string (locationId)
        if result and type(result) ~= "number" and type(result) ~= "string" then
            result = nil
        end
        return result
    end,

    waterpipe = function()
        local result = nil
        pcall(function()
            result = exports["lizz_waterpipe"]:getClosestWaterpipeIndex()
        end)
        -- Validate result: รับทั้ง number (index) และ string (locationId)
        if result and type(result) ~= "number" and type(result) ~= "string" then
            result = nil
        end
        return result
    end,
    
    megacement = function()
        local result = nil
        pcall(function()
            result = exports["lizz_megacement"]:getClosestMegaCementIndex()
        end)
        -- Validate result: รับทั้ง number (index) และ string (locationId)
        if result and type(result) ~= "number" and type(result) ~= "string" then
            result = nil
        end
        return result
    end
}

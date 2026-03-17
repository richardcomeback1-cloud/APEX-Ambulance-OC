Config = {}

local second = 1000
local minute = 60 * second

Config.DrawDistance               = 8.0 	-- ระยะที่ผู้เล่นต้องเข้าใกล้ก่อนระบบจะวาด Marker (หน่วย GTA)
Config.Marker                     = { type = 32, x = 1.0, y = 1.0, z = 1.0, r = 239, g = 112, b = 169, a = 150, rotate = true }

Config.ReviveReward 			  = 0		-- เงินรางวัลเมื่อชุบชีวิต (ตั้ง 0 เพื่อปิด)
Config.AntiCombatLog 			  = true	-- เปิดระบบกันหนีตอนสลบ/ตาย (กัน combat log)
Config.LoadIpl 					  = true	-- โหลด IPL ของโรงพยาบาล (ปิดได้ถ้าใช้ระบบโหลด IPL อื่น)

Config.Locale = 'th'
Config.DeathUIDelay               = 2 * second -- ดีเลย์ก่อนแสดง UI เมื่อตาย
Config.DeathBodySync = {
    enabled = false,      -- ปิดเป็นค่าเริ่มต้น เพื่อลดปัญหาศพไม่ตรงตำแหน่งระหว่างผู้เล่น
    firstDelayMs = 3500,
    secondDelayMs = 7000,
    finalDelayMs = 4000
}
Config.DistressSignalCooldownSec   = 180 -- คูลดาวน์ปุ่มส่งเคสตอนตาย (วินาที, ปรับได้)
Config.DeathKeyCooldownSec = {
    distress = 180,  -- คูลดาวน์ปุ่มส่งเคสหาหมอ
    gang = 180,      -- คูลดาวน์ปุ่มส่งสัญญาณแก๊ง
    requestTalk = 180, -- คูลดาวน์ปุ่มขอคุย
    clearBody = 30   -- คูลดาวน์ปุ่มเคลียร์/ขยับศพ
}
Config.DeathKeybinds = {
    respawn = 'G',      -- ปุ่มกดเกิด/ออกจากโหมดพิเศษตอนตาย
    distress = 'M',     -- ปุ่มส่งเคสหาหมอ
    gang = 'Q',         -- ปุ่มส่งสัญญาณหาแก๊ง
    clearBody = 'X',    -- ปุ่มขยับ/เคลียร์ศพ
    requestTalk = 'R',  -- ปุ่มขอคุย
    talk = 'N',         -- ปุ่มคุยระหว่างกำลังคุย
    forceRespawn = 'DELETE', -- ปุ่มที่ยังอนุญาตให้กดตอนตายใน block zone
    ragdoll = 'SPACE'   -- ปุ่มที่อนุญาตระหว่างตาย
}


Config.AmbulancePlayerBlip = {
    enabled = true,
    refreshTargetsMs = 5000,
    refreshBlipMs = 500,
    flashColorA = 1, -- red
    flashColorB = 3, -- blue
    display = {
        sprite = 1,
        helicopterSprite = 353, -- radar_police_heli_spin
        scale = 0.9,
        category = 7,
        shortRange = false
    },
    colors = {
        onFoot = 0,
        inVehicle = 3,
        inHelicopter = 0
    },
    text = {
        prefix = 'EMS',
        onFoot = 'เดินเท้า',
        inVehicle = 'อยู่บนรถ',
        inHelicopter = 'อยู่บนเฮลิคอปเตอร์',
        silentLightSuffix = ' (Silent Light)'
    }
}

Config.EarlyRespawnTimerNoEms     = 5 * minute --เวลาไม่มีหมอ
Config.EarlyRespawnTimerWarzone   = 5 * second --เวลากดเกิดวอโซน

Config.EarlyRespawnTimer          = 35 * minute --เวลามีหมอ (ค่าเริ่มต้น)
Config.BleedoutTimer              = 0 * minute --เวลาก่อนที่จะเอ๋อ

-- ระบบเวลาเกิดใหม่แบบแยก 2 ระบบตามจำนวนหมอออนไลน์
-- 1) player : เวลาของผู้เล่นทั่วไปที่ตาย
-- 2) ems    : เวลาของหมอที่ตาย
-- enabled = true  : เปิดใช้งานระบบเวลาแบบแยก
Config.DynamicEarlyRespawnTimer = {
    enabled = true,
    player = {
        oneEmsMinutes = 15,    -- ผู้เล่นทั่วไป: มีหมอออนไลน์ 1 คน
        multiEmsMinutes = 15  -- ผู้เล่นทั่วไป: มีหมอออนไลน์มากกว่า 1 คน
    },
    ems = {
        oneEmsMinutes = 3,    -- หมอ: มีหมอออนไลน์ 1 คน
        multiEmsMinutes = 8   -- หมอ: มีหมอออนไลน์มากกว่า 1 คน
    }
}

Config.RemoveWeaponsAfterRPDeath  = true
Config.RemoveCashAfterRPDeath     = true
Config.RemoveItemsAfterRPDeath    = true

-- ระบบค่าปรับตอนเลือกเกิดใหม่ (หักเงินเมื่อผู้เล่นมีเงินเพียงพอ)
Config.EarlyRespawnFine           = false
Config.EarlyRespawnFineAmount     = 5000
Config.EventRespawnFineAmount     = 1500

-- จุดเกิดหลักหลังตาย/วาปกลับ (ปรับพิกัดและหันทิศได้)
Config.RespawnPoint = { coords = vector3(1147.19, -1522.02, 34.84), heading = 270.0 }
-- จุดวาปสำหรับโหมด/อีเวนต์พิเศษ
Config.EventTeleport = { coords = vector3(1155.32, -1523.37, 34.84), heading = 145.0 }

Config.HealBase = 140 -- เลือดพื้นฐานที่ผู้เล่นจะได้รับหลังฟื้น
Config.SuperReviveArea = 10.0 -- รัศมีชุบหมู่ (เมตร)

-- ราคาค่าบริการจากเมนู F6 ของหมอ (ใช้กับระบบบิลอัตโนมัติในเมนูใหม่)
Config.AmbulanceMenuPrices = {
    revive = {
        config = 0,
        city = 1500,
        forest = 2000,
        nearHospital = 1000,
        other = 2500
    },
    superRevive = {
        config = 0,
        city = 2500,
        forest = 3000,
        nearHospital = 2000,
        other = 3500
    },
    heal = {
        city = 500,
        forest = 700,
        nearHospital = 400,
        other = 900
    }
}

Config["SuperReviveEffect"] = {
	enabled = true,
	fxdict = "scr_ie_tw",
	fxname = 'scr_impexp_tw_take_zone',
	fxsize = 1.0
}
-----------------------------------------------------------------------------------
-- ระบบรางวัลไอเท็ม EXP จากการรักษา/ชุบ
Config.ItemExp = 'coin_xp'
Config.MaxEXPPerUse = 50 -- ค่าจำกัดสูงสุดต่อครั้ง
Config.AddItemEXP = function(typeItem, xPlayer, itemName, count)
	count = count or 1

	local multiplier = 1
	if typeItem == "superrevive" then
		multiplier = 30
	elseif typeItem == "revive" then
		multiplier = 20
	elseif typeItem == "heal" then
		multiplier = 10
	end

	local total = multiplier * count
	total = math.min(total, Config.MaxEXPPerUse or 50) -- จำกัดไม่เกิน MaxEXPPerUse
	xPlayer.addInventoryItem(itemName, total)
end
-----------------------------------------------------------------------------------

-- กำหนดตำแหน่งโรงพยาบาล, จุดเปิดเมนูหมอ และจุดเบิกยา
Config.Hospitals = {

	CentralLosSantos = {

		Blip = {
			coords = vector3(1150.16, -1549.96, 35.38),
			sprite = 846,
			scale = 1.0,
			color = 0
		},

		AmbulanceActions = {
			vector3(1126.04, -1557.19, 35.38)
		},

		Pharmacies = {
			vector3(1127.69, -1565.40, 35.38)
		},
	},

	Pillbox2 = {

		Blip = {
			coords = vector3(1831.24, 3679.83, 34.27),
			sprite = 846,
			scale = 1.0,
			color = 0
		},

		AmbulanceActions = {
			--vector3(335.27, -576.33, 51.49)
		},

		Pharmacies = {
			--vector3(335.27, -576.33, 51.49)
		},
	}
}

-- รายการชุดยูนิฟอร์มหมอ (male/female) ที่เมนูจะดึงไปใช้
Config.UniformsList = {
    {
        title = 'เสื้อวอม',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 534, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 216, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 575, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 250, ['arms_2'] = 0,
            ['pants_1'] = 216, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อยืด',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 535, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 576, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 250, ['arms_2'] = 0,
            ['pants_1'] = 208, ['pants_2'] = 0,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อฮู้ด',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 536, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 86, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 578, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อฮู้ดคลุมหัว',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 537, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 580, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อโปโล',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 538, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 581, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 100, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อโปโลแขนยาว',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 539, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 86, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 582, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 250, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อไอดอล',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 759, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 88, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 1165, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 221, ['pants_2'] = 0,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อไอดอลฮูด',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 760, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 88, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 1166, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 221, ['pants_2'] = 0,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อฮู้ดใหม่ (มีวอ)',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 532, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 216, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 573, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'เสื้อฮู้ดใหม่ (ไม่มีวอ)',
        male = {
            ['tshirt_1'] = 15, ['tshirt_2'] = 0,
            ['torso_1'] = 533, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 85, ['arms_2'] = 0,
            ['pants_1'] = 216, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 14, ['tshirt_2'] = 0,
            ['torso_1'] = 574, ['torso_2'] = 2,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 251, ['arms_2'] = 0,
            ['pants_1'] = 219, ['pants_2'] = 5,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'สูท-ไม่ติดกระดุม',
        male = {
            ['tshirt_1'] = 34, ['tshirt_2'] = 0,
            ['torso_1'] = 528, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 88, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 255, ['tshirt_2'] = 1,
            ['torso_1'] = 565, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 250, ['arms_2'] = 0,
            ['pants_1'] = 207, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
    {
        title = 'สูท-ติดกระดุม',
        male = {
            ['tshirt_1'] = 36, ['tshirt_2'] = 0,
            ['torso_1'] = 529, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 88, ['arms_2'] = 0,
            ['pants_1'] = 195, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        },
        female = {
            ['tshirt_1'] = 255, ['tshirt_2'] = 1,
            ['torso_1'] = 566, ['torso_2'] = 3,
            ['decals_1'] = 0, ['decals_2'] = 0,
            ['arms'] = 250, ['arms_2'] = 0,
            ['pants_1'] = 207, ['pants_2'] = 1,
            ['chain_1'] = 0, ['chain_2'] = 0,
            ['bproof_1'] = 0, ['bproof_2'] = 0
        }
    },
}

Config.BlockZone = {
    { coords = vector3(5072.898, -1307.25684, 20.4144783), radius = 175 },
}
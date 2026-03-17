--[[
    config-transfer.lua
    หมวด: ระบบส่งตัวผู้เล่น (เมนู F6 ของหมอ)
    จุดเด่น:
    - เพิ่ม/ลบจุดส่งตัวได้จากไฟล์นี้ไฟล์เดียว
    - รองรับการสุ่มหรือกำหนดจุดแบบเจาะจง
    - มีคอมเมนต์ภาษาไทยให้อ่านง่าย
]]

Config.PlayerTransfer = {
    enabled = true,              -- เปิด/ปิดเมนูส่งตัวผู้เล่น
    requireAmbulanceJob = true,  -- จำกัดให้ใช้งานได้เฉพาะอาชีพ ambulance
    maxUseDistance = 3.0,        -- ระยะสูงสุดระหว่างหมอกับคนไข้ก่อนกดส่งตัว
    useRandomWhenNoPick = false, -- ถ้าไม่ได้เลือกจุดเอง ให้สุ่มจาก destinations

    -- รายการจุดส่งตัว (เพิ่มได้เรื่อย ๆ)
    -- key: ชื่อภายในระบบ (ไม่ซ้ำ)
    -- label: ชื่อที่แสดงในเมนู
    -- coords/heading: จุดวาปปลายทาง
    destinations = {
        {
            key = 'hospital_front',
            label = 'หน้าโรงพยาบาลหลัก',
            coords = vector3(1155.32, -1523.37, 34.84),
            heading = 145.0
        },
        {
            key = 'hospital_lobby',
            label = 'ล็อบบี้โรงพยาบาล',
            coords = vector3(1147.19, -1522.02, 34.84),
            heading = 270.0
        }
    }
}

-- backward compatibility: โค้ดเก่าบางส่วนยังอ้าง Config.RandomPointSendPlayer
-- สร้าง list นี้จาก destinations อัตโนมัติ เพื่อไม่ให้สคริปต์เก่าพัง
Config.RandomPointSendPlayer = {}
for i = 1, #(Config.PlayerTransfer.destinations or {}) do
    local destination = Config.PlayerTransfer.destinations[i]
    Config.RandomPointSendPlayer[i] = {
        x = destination.coords.x,
        y = destination.coords.y,
        z = destination.coords.z,
        h = destination.heading or 0.0
    }
end

Config = Config or {}

Config.Security = {
    EnableRateLimit = true, -- เปิดระบบป้องกัน event spam ต่อผู้เล่น
    DefaultEventLimit = 15, -- จำนวนครั้งสูงสุดของ event ทั่วไปใน 1 ช่วงเวลา
    StrictTypeValidation = true, -- เปิดการตรวจสอบชนิดข้อมูลที่รับจาก client อย่างเข้มงวด
    MaxBatchTargets = 20, -- จำนวนเป้าหมายสูงสุดที่อนุญาตใน event แบบ batch
    RejectUnknownPlayers = true -- ปฏิเสธค่าที่ไม่ได้อ้างอิงผู้เล่นที่ออนไลน์จริง
}

Config = Config or {}

Config.ConfigVersion = '2.0.0' -- เวอร์ชันโครงสร้างคอนฟิกของ resource
Config.ConfigSchemaVersion = 1 -- เวอร์ชัน schema สำหรับตรวจสอบความถูกต้องคอนฟิก
Config.MaxSupportedPlayers = 1024 -- จำนวนผู้เล่นสูงสุดที่ระบบนี้ออกแบบให้รองรับ
Config.Framework = 'esx' -- เฟรมเวิร์กหลักที่ใช้ในเซิร์ฟเวอร์
Config.UseStateBags = true -- เปิดใช้ state bag สำหรับการซิงก์สถานะ
Config.EnableCompatibilityLayer = true -- เปิดเลเยอร์รองรับ event/export เก่าเพื่อไม่ให้สคริปต์เดิมพัง

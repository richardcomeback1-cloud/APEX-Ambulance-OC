Config.BillingMenu = Config.BillingMenu or {}

Config.BillingMenu.Revive = {
    { label = 'ชุบชีวิตทั่วไป', value = 1000 },
    { label = 'ชุบนอกเมือง', value = 1500 },
    { label = 'ชุบเมืองบน', value = 2000 },
    { label = 'ชุบพื้นที่เข้าถึงยาก', value = 3000 },
    { label = 'ชุบทั้งหมดพื้นที่สุ่มเสี่ยง', value = 4000 },
}

Config.BillingMenu.MassRevive = {
    { label = 'ชุบหมู่ทั่วไป', value = 1000 },
    { label = 'ชุบหมู่นอกเมือง', value = 1500 },
    { label = 'ชุบหมู่เมืองบน', value = 2000 },
    { label = 'ชุบหมู่พื้นที่เข้าถึงยาก', value = 3000 },
    { label = 'ชุบหมู่พื้นที่สุ่มเสี่ยง', value = 4000 },
}

Config.BillingMenu.Heal = {
    single = { label = 'ฉีดยาเดี่ยว', value = 500 },
    mass = { label = 'ฉีดยาหมู่', value = 500 },
}

Config.BillingMenu.ReviveSelectRadius = 3.0 -- ระยะสำหรับเมนูเลือกชุบ (เมตร) และวง Marker รอบตัวหมอ
Config.BillingMenu.HealSelectRadius = 3.0 -- ระยะสำหรับเมนูเลือกฉีดยา (เมตร) และวง Marker รอบตัวหมอ

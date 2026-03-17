Config = Config or {}

Config.UI = {
    NotificationThrottleMs = 1500, -- เว้นช่วงขั้นต่ำของการแจ้งเตือนประเภทเดียวกันต่อผู้เล่น
    ShowSecurityWarnings = true, -- แสดงข้อความเตือนเมื่อพบพฤติกรรมผิดปกติที่ถูกบล็อก
    MetricsOverlay = false -- เปิด overlay สำหรับดีบักสถิติ (ควรปิดใน production)
}

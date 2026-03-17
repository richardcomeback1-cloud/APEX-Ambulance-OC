Config = Config or {}

Config.Debug = {
    Enabled = false, -- เปิดโหมดดีบักเชิงลึกของ resource
    LogLevel = 'INFO', -- ระดับ log เริ่มต้น (DEBUG/INFO/WARN/ERROR)
    PrintRateLimitHits = false -- พิมพ์ log เมื่อมีการชน rate limit
}

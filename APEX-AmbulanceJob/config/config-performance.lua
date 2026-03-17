Config = Config or {}

Config.Performance = {
    EventRateWindowMs = 10000, -- ช่วงเวลาที่ใช้คำนวณ rate limit ต่อผู้เล่น (มิลลิวินาที)
    EventQueueSoftLimit = 64, -- จำนวนงานเบื้องต้นที่ยอมรับก่อนเริ่มลดโหลด non-critical
    EnableAdaptiveDelays = true, -- เปิดใช้แนวคิด adaptive delay ในจุดที่มี loop
    TargetedEventOnly = true -- บังคับแนวทางส่ง event แบบเจาะจงเป้าหมายแทน broadcast
}

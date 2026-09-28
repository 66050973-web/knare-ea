#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#ifndef __KNARES_SMC_INPUTS_MQH__
#define __KNARES_SMC_INPUTS_MQH__

//+------------------------------------------------------------------+
//| SMC Inputs - การตั้งค่าระบบ SMC และความปลอดภัย                          |
//| รวบรวมพารามิเตอร์ทั้งหมดสำหรับการควบคุมระบบ Smart Money Concepts        |
//+------------------------------------------------------------------+

input group "--- 6. SMART MONEY CONCEPTS (SMC) ---"
input bool   EnableSMCFilter              = true;   // เปิดใช้ตัวกรอง SMC (ช่วยลดความเสี่ยงจากการเทรดผิดโซนราคา)
input ENUM_TIMEFRAMES SMCStructureTF      = PERIOD_M5;   // ไทม์เฟรมหลักที่ใช้ในการวิเคราะห์โครงสร้างราคา (BOS/CHoCH)
input ENUM_TIMEFRAMES SMCHigherTF         = PERIOD_M15;  // ไทม์เฟรมที่สูงกว่าเพื่อใช้ยืนยันแนวโน้ม (HTF Confirmation)
input bool   SMCUseBOSFilter              = true;   // เปิดใช้การกรองด้วย BOS (Break of Structure)
input bool   SMCUseCHoCHFilter            = true;   // เปิดใช้การกรองด้วย CHoCH (Change of Character)
input bool   SMCUsePremiumDiscountFilter  = true;   // เปิดใช้การกรองด้วยโซน Premium/Discount (ซื้อถูก/ขายแพง)
input bool   SMCBlockBuyInPremium         = true;   // ห้ามเข้าซื้อ (Buy) ในโซนราคาที่แพงเกินไป
input bool   SMCBlockSellInDiscount       = true;   // ห้ามเข้าขาย (Sell) ในโซนราคาที่ถูกเกินไป
input bool   SMCStrictSellFilter          = true;   // เปิดใช้ระบบกรองฝั่งขายแบบเข้มงวดเป็นพิเศษ

input group "--- 7. SMC QUALITY GATE & RESCUE ---"
input bool   EnableBuyContinuationPipelineRescue = true; // เปิดระบบช่วยเหลือเพื่อให้เข้าเทรดต่อได้หากเทรนด์ยังดีมาก
input bool   EnableRescueSMCQualityGate = true;          // เปิดใช้ด่านตรวจคุณภาพ SMC สำหรับการกู้คืนสัญญาณ
input double RescueMinSMCQuality = 0.60;                 // ระดับคุณภาพขั้นต่ำที่ยอมรับได้ (0.0 - 1.0)
input bool   EnableRescuePerformanceGuard            = true; // ตรวจสอบประสิทธิภาพของพอร์ตก่อนอนุญาตให้กู้คืนสัญญาณ
input int    RescuePerfWindowTrades                  = 5;    // จำนวนไม้ย้อนหลังที่จะนำมาพิจารณาประสิทธิภาพ
input double RescuePerfMinPF                         = 1.00; // ค่า Profit Factor ขั้นต่ำที่ต้องการในช่วงที่ตรวจสอบ

input group "--- 8. SAFETY: DAILY LOSS & CLUSTER ---"
input bool   EnableDailyLossClusterGuard              = true; // ระบบหยุดเทรดอัตโนมัติเมื่อขาดทุนสะสมในวันเดียวถึงเกณฑ์
input int    DailyLossClusterBadExitCount             = 4;    // จำนวนไม้ที่แพ้ติดกันจนต้องสั่งหยุดพักระบบ
input double DailyLossClusterNetLossUSD               = 8.0;  // จำนวนเงินขาดทุนรวม (USD) ที่ถึงจุดต้องหยุดพัก
input int    DailyLossClusterPauseMinutes             = 240;  // ระยะเวลาที่จะหยุดพักระบบ (นาที) หลังโดน Cluster Guard
input bool   EnableHardSLCooldown = true;                     // หยุดพักระบบชั่วคราวเมื่อโดนลากจนถึง Hard Stop Loss
input int    HardSLCooldownCount = 2;                         // จำนวน Hard SL ที่เกิดขึ้นต่อเนื่องจนต้องสั่งหยุด
input int    HardSLPauseMinutes = 180;                        // ระยะเวลาหยุดพักหลังโดน Hard SL (นาที)

input group "--- 9. EXIT: CONTEXT & INVALIDATION ---"
input bool   EnableContextExitRescueCooldown = true;   // เปิดระบบหยุดพักชั่วคราวหลังปิดไม้ด้วยเหตุผลทางบริบทตลาด
input bool   EnableContextDeteriorationExit          = true;   // ปิดไม้ทันทีเมื่อบริบทตลาดเริ่มแย่ลง (เช่น เทรนด์กลับตัว)
input bool   EnableMicroInvalidation             = true;      // ปิดไม้เมื่อสัญญาณในกรอบเวลาย่อยผิดทาง
input bool   EnableIntermediateInvalidationExit       = true;  // ปิดไม้เมื่อสัญญาณในกรอบเวลากลางผิดทาง
input bool   EnableContextGivebackExit                = true;  // ปิดไม้เพื่อรักษากำไรเมื่อตลาดเริ่มเสียทรง

input group "--- 10. VISUALS & DASHBOARD ---"
input bool   ShowSMCIndicator          = true;   // แสดงตัวบ่งชี้ SMC บนกราฟราคา
input bool   ShowSMCDashboard          = false;  // แสดงกระดานข้อมูลสรุป SMC (Dashboard)
input bool   ShowSMCZones              = true;   // แสดงพื้นที่โซน Premium/Discount บนกราฟ
input bool   CompactIndicatorPanes             = true; // ใช้รูปแบบการแสดงผลแบบประหยัดพื้นที่เพื่อให้กราฟดูไม่อึดอัด

// --- ส่วนของการตั้งค่าขั้นสูง (Advanced Tuning)
input group "--- ADVANCED: SMC TUNING ---"
input bool   EnableSMCAsEntryEngine       = false;   // (ยังไม่แนะนำ) ใช้ SMC เป็นตัวเปิดไม้โดยตรง
input bool   SMCUseLiquidityTarget        = true;    // ใช้จุดสภาพคล่อง (Liquidity) เป็นเป้าหมายราคา
input bool   SMCRequireHTFAlignment       = true;    // บังคับให้สัญญาณต้องสอดคล้องกับไทม์เฟรมที่สูงกว่าเสมอ
input bool   SMCBlockBiasConflict         = true;    // บล็อกสัญญาณที่ขัดแย้งกับทิศทางโครงสร้างราคา SMC
input int    SMCSwingLookbackBars         = 20;      // จำนวนแท่งเทียนที่ใช้หา Swing High/Low ในกรอบใหญ่
input int    SMCInternalLookbackBars      = 8;       // จำนวนแท่งเทียนที่ใช้หาโครงสร้างภายในกรอบย่อย
input double SMCScoreBoostAligned         = 0.05;    // คะแนนโบนัสเพิ่มหากสัญญาณสอดคล้องกับ SMC
input double SMCScorePenaltyConflict      = 0.10;    // คะแนนหักออกหากสัญญาณขัดแย้งกับ SMC
input double SMCPremiumLevel              = 0.70;    // ระดับราคาที่เริ่มถือว่าเป็นโซน Premium (0.0-1.0)
input double SMCDiscountLevel             = 0.30;    // ระดับราคาที่เริ่มถือว่าเป็นโซน Discount
input double SMCNeutralBand               = 0.10;    // ช่วงราคาแถวเส้นกลางที่ถือเป็นสถานะเป็นกลาง (Neutral)
input int    SMCZoneFilterMode            = 2;       // โหมดการกรองโซน (0: บล็อกเด็ดขาด, 1: หักคะแนน, 2: แบบผสม Hybrid)
input double SMCZoneHybridADX             = 30.0;    // ค่า ADX ที่ใช้ตัดสินในโหมด Hybrid
input double SMCZonePenalty               = 0.03;    // คะแนนที่หักเมื่อราคาอยู่ในโซนที่ไม่เหมาะสม

input group "--- ADVANCED: RESCUE TUNING ---"
input double RescueStrongQuality = 0.70;             // ระดับคุณภาพ SMC สำหรับการกู้คืนแบบเต็มสูบ
input double RescueSoftQuality = 0.60;               // ระดับคุณภาพสำหรับการกู้คืนแบบลดความเสี่ยง (Soft Rescue)
input double RescueSoftRiskFactor = 0.50;            // สัดส่วนการลด Lot size ในโหมด Soft Rescue
input bool   BlockSoftRescueWhenCannotReduceLot = true; // บล็อกการกู้คืนแบบ Soft หากไม่สามารถลด Lot ได้อีก
input double SoftRescueMinQualityAtMinLot = 0.70;    // คุณภาพขั้นต่ำที่ต้องการหากต้องใช้ Lot ต่ำสุดเทรด
input double BuyRescueMinADX                    = 25.0; // ค่า ADX ขั้นต่ำสำหรับการเข้าช่วยฝั่งซื้อ
input double BuyRescueMinSlope                  = 0.0035; // ความชันขั้นต่ำที่ต้องการ
input double BuyRescueMaxSMCPos                 = 0.98;   // ตำแหน่งราคาในกรอบสูงสุดที่ยอมให้ช่วยซื้อ
input double BuyRescueMinScore                  = 0.74;   // คะแนนพื้นฐานขั้นต่ำ
input double BuyRescueMinConfidence             = 0.76;   // คะแนนความมั่นใจขั้นต่ำ
input double BuyRescueScoreSlack                = 0.06;   // ช่วงคะแนนที่ผ่อนปรนให้
input double BuyRescueConfidenceSlack           = 0.05;   // ช่วงความมั่นใจที่ผ่อนปรนให้

input group "--- ADVANCED: EXIT TUNING ---"
input double ContextDeteriorationMinLossR           = 0.10;  // การขาดทุนขั้นต่ำ (R) ที่จะเริ่มพิจารณาปิดไม้เพราะบริบทเสีย
input double MicroInvalidationMinLossR           = 0.20;    // การขาดทุนที่ยอมรับได้ในกรอบย่อย
input int    ContextExitCooldownCount = 2;                  // จำนวนไม้ที่ปิดด้วยบริบทต่อเนื่องกันจนต้องหยุดพัก
input int    ContextExitRescuePauseMinutes = 180;           // ระยะเวลาหยุดพัก (นาที)
input int    HardSLCooldownWindowMinutes = 120;            // ช่วงเวลาที่ใช้ตรวจสอบ Hard SL ต่อเนื่อง
input bool   HardSLCooldownPauseRescueOnly = true;          // หยุดเฉพาะระบบกู้คืน (Rescue) เมื่อติดคูลดาวน์

input group "--- ADVANCED: TESTER SCORING ---"
enum ENUM_TESTER_SCORE_MODE
{
   TESTER_SCORE_QUICK = 0,    // เน้นการทดสอบที่รวดเร็ว
   TESTER_SCORE_OPTIMIZE = 1, // เน้นการเพิ่มประสิทธิภาพสูงสุด
   TESTER_SCORE_ROBUST = 2    // เน้นความเสถียรและความแข็งแกร่งของพารามิเตอร์
};
input ENUM_TESTER_SCORE_MODE TesterScoreMode = TESTER_SCORE_QUICK; // โหมดการให้คะแนนในระบบ Tester
input int    MinTesterTrades = 20;                          // จำนวนไม้ขั้นต่ำที่ต้องการเพื่อให้คะแนนมีความน่าเชื่อถือ
input bool   PenalizeLowTesterTrades = true;                // หักคะแนนหากจำนวนไม้ในผลทดสอบน้อยเกินไป

// --- ตัวแปรภายในระบบ (ไม่ได้แสดงในหน้าจอตั้งค่า)
bool   SMCUseOrderBlockFilter       = false;   // เปิดใช้ตัวกรอง Order Block
bool   SMCUseFVGFilter              = false;   // เปิดใช้ตัวกรอง Fair Value Gap (FVG)
bool   SMCBlockWhenNoStructure      = false;   // บล็อกการเทรดหากหาโครงสร้างราคาไม่เจอ
int    SMCChochConfirmBars          = 2;       // จำนวนแท่งเทียนที่ใช้ยืนยันการเกิด CHoCH
int    SMCBosConfirmBars            = 1;       // จำนวนแท่งเทียนที่ใช้ยืนยันการเกิด BOS
bool   SMCStrictSellRequireBearishBias = true; // ฝั่งขายต้องมี Bias เป็นขาลงเท่านั้น
bool   SMCStrictSellRequireBearishHTF  = true; // ฝั่งขายต้องมี HTF เป็นขาลงเท่านั้น
bool   SMCBlockSellInTrendUp        = true;    // ห้ามขายสวนเทรนด์ขาขึ้น
double SMCTrendMinADX               = 25.0;    // ADX ขั้นต่ำสำหรับระบบเทรนด์
bool   SMCUseGradedADXFilter         = true;    // ใช้ระบบคัดกรอง ADX แบบแบ่งระดับ
double SMCADXHardBlockBelow          = 18.0;    // บล็อกเด็ดขาดหาก ADX ต่ำกว่านี้
double SMCADXRequireContextBelow     = 30.0;    // ต้องการบริบทเสริมหาก ADX ต่ำกว่านี้
double SMCWeakADXPenalty             = 0.02;    // บทลงโทษสำหรับ ADX ที่อ่อนแอ
double SMCWeakADXContextPenalty      = 0.02;    // บทลงโทษเพิ่มเติมหากบริบทไม่ดี
bool   SMCStrictSellRequireRuntimeTrendDown = true; // ฝั่งขายต้องเป็นขาลงในระบบ Runtime
bool   SMCStrictSellBlockRange       = true;    // ห้ามขายในช่วงไซด์เวย์ (Range)
bool   SMCStrictSellBlockUnknown     = true;    // ห้ามขายในสภาวะไม่ชัดเจน
bool   SMCStrictSellRequireBearishSlope = true; // ต้องการความชันขาลงสำหรับการขาย
double SMCStrictSellMinBearishSlope  = 0.0015;  // ความชันขาลงขั้นต่ำ
double SMCStrictSellMinADX           = 25.0;    // ADX ขั้นต่ำสำหรับการขาย
bool   SMCBuyPremiumAllowTrendUpPenalty = true; // อนุญาตให้ซื้อในโซนแพงแต่จะโดนหักคะแนน
double SMCBuyPremiumAllowADX         = 20.0;    // ADX ขั้นต่ำที่จะยอมให้ซื้อในโซนแพง
double SMCSellMinPositionInRange     = 0.70;    // ตำแหน่งราคาต่ำสุดที่จะยอมให้ขาย (ต้องเป็นโซนบนของกรอบ)
double SMCBuyPremiumExtremePos             = 0.99;   // ระดับราคาที่สูงที่สุดที่จะบล็อกการซื้อแบบเด็ดขาด
double SMCBuyMaxPremiumPositionWithoutBreakout = 0.96; // ระดับราคาสูงสุดที่ยอมให้ซื้อหากไม่มีการเบรคเอาท์ยืนยัน
bool   SMCBuyPremiumExtremeBlockHTFBearish = true;   // บล็อกการซื้อในโซนสูงสุดโต่งหาก HTF ขัดแย้ง
bool   SMCBuyPremiumExtremeRequireBreakout = true;   // ต้องการการเบรคเอาท์เพื่อซื้อในโซนสูงสุดโต่ง
bool   SMCStrictSellPremiumOnly            = true;  // บังคับขายเฉพาะในโซน Premium เท่านั้น
bool   EnableStaleProfitProtect            = true;  // เปิดระบบป้องกันกำไรเมื่อราคานิ่ง (Stale Profit)
int    StaleProfitProtectBars              = 20;    // จำนวนแท่งเทียนที่ยอมให้ราคานิ่ง
double StaleProfitProtectMFER              = 0.30;  // ค่า MFE ขั้นต่ำที่จะเริ่มปกป้อง
double StaleProfitProtectPullbackR         = 0.10;  // ระยะย่อตัวที่ยอมรับได้
double StaleProfitProtectExitR             = 0.20;  // ระยะกำไรขั้นต่ำที่จะปิด
bool   EnableLotAwarePartialFallback = true;        // ระบบลดความเสี่ยงตามขนาด Lot
double SmallLotThreshold = 0.02;                   // เกณฑ์ตัดสินว่าเป็น Lot ขนาดเล็ก
double SmallLotFallbackLockR = 0.20;               // การล็อคกำไรสำหรับ Lot เล็ก
double LargeLotFallbackLockR = 0.35;               // การล็อคกำไรสำหรับ Lot ใหญ่
double PartialFallbackLockR                 = 0.20;  // ระยะล็อคกำไรพื้นฐาน
int    MicroInvalidationMaxBars            = 8;      // จำนวนแท่งสูงสุดที่จะตรวจสอบในกรอบย่อย
double MicroInvalidationMaxMFER            = 0.10;   // MFE สูงสุดที่ยอมให้ปิดเร็ว
double MicroInvalidationMAER               = 0.30;   // ระยะลากติดลบที่ยอมรับได้ในกรอบย่อย
bool   MicroInvalidationRequireContextLoss = true;    // ต้องการการเสียทรงของบริบทก่อนปิด
int    ContextDeteriorationMinBars            = 5;      // จำนวนแท่งขั้นต่ำก่อนพิจารณาปิด
double ContextDeteriorationMaxMFER            = 0.60;   // MFE สูงสุดที่จะยอมให้ปิด
bool   ContextDeteriorationRequireRegimeFlip  = true;   // ต้องการการสลับของ Regime
bool   ContextDeteriorationRequireSlopeFlip   = true;   // ต้องการการสลับของความชัน
double ContextDeteriorationSlopeThreshold     = 0.00030; // เกณฑ์ความชันที่ใช้ตัดสิน
bool   ContextDeteriorationAllowHTFConflict   = true;   // อนุญาตหากมีความขัดแย้งใน HTF
bool   ContextDeteriorationAllowStrongFlipOverride = true; // อนุญาตให้ปิดทันทีหากมีการสลับทางอย่างรุนแรง
bool   EnableSessionProfitGivebackGuard   = true;   // ระบบรักษากำไรของเซสชั่นไม่ให้คืนตลาดมากเกินไป
double SessionProfitLockStartUSD          = 10.0;   // กำไรเริ่มล็อค (USD)
double SessionMaxGivebackPct              = 0.50;   // สัดส่วนกำไรที่ยอมให้คืนได้ (0.0-1.0)
int    SessionPauseAfterGivebackMinutes   = 1440;   // พักระบบนาน (นาที) หลังคืนกำไรถึงเกณฑ์
bool   EnableMicroInvalidationCooldown    = true;   // ระบบคูลดาวน์หลังโดนปิดด้วย Micro Invalidation
int    MicroInvalidationCooldownCount     = 2;
int    MicroInvalidationCooldownWindowMinutes = 60;
int    MicroInvalidationPauseMinutes      = 90;
bool   SMCBuyPremiumExtremeRequireBullishBias = false; // บังคับโครงสร้างขาขึ้นสำหรับการซื้อในโซนแพง
bool   SMCBuyUltraExtremeRequireBullishBias = true;    // บังคับโครงสร้างขาขึ้นสำหรับการซื้อในโซนแพงสูงสุดโต่ง
double SMCBuyUltraExtremePos             = 0.99;
double SMCBuyNeutralBiasMinADX            = 30.0;
double SMCBuyNeutralBiasMinSlope          = 0.0035;
bool   SMCBuyNeutralBiasStrengthFilter    = true;
bool   SMCBuyNeutralBiasUsePenalty        = true;
double SMCBuyNeutralBiasPenalty           = 0.03;
int    IntermediateInvalidationMinBars          = 4;
int    IntermediateInvalidationMaxBars          = 10;
double IntermediateInvalidationMAER             = 0.35;
double IntermediateInvalidationMinLossR         = 0.25;
bool   IntermediateInvalidationRequireContextLoss = true;
bool   IntermediateInvalidationRequireSlopeOrRegime = true;
double ContextGivebackMinMFER                   = 0.40;
double ContextGivebackExitBelowR                = 0.00;
double ContextGivebackRequireMFEAboveR          = 0.30;
bool   ContextGivebackRequireRegimeAndSlopeFlip = true;
bool   ContextGivebackUseHTFConflict            = true;
bool   EnableMicroInvalidationSoftTighten       = true; // เข้มงวดขึ้นหลังโดนปิดบ่อย
int    MicroInvalidationSoftTightenCount        = 1;
int    MicroInvalidationSoftTightenWindowMinutes = 120;
double SoftTightenBuyMinADX                     = 35.0;
double SoftTightenBuyMinSlope                   = 0.0050;
bool   SoftTightenBuyPremiumRequireBullishBias  = true;
bool   SoftTightenBuyNeutralRequireStrongTrend  = true;
int    DailyLossClusterWindowMinutes            = 240;
bool   DailyLossClusterCountMicro               = true;
bool   DailyLossClusterCountContext             = true;
bool   DailyLossClusterCountHardSL              = true;
bool   DailyLossClusterCountEarlyInv            = true;
bool   EnableEarlyInvalidationDetailLog         = true;
double EarlyInvalidationSafetyMaxLossR          = 0.50;
double SMCProfitLockTargetDistanceATR = 0.75;
double SMCProfitLockTargetGapR        = 0.35;
double SMCProfitLockMinTargetR        = 0.50;
bool   ShowSMCZoneFill           = false;  // ระบายสีพื้นหลังโซน SMC
bool   ShowSMCStructureLabels    = false;  // แสดงข้อความกำกับโครงสร้าง (BOS/CHoCH)
bool   ShowSMCBlockLabels        = false;  // แสดงข้อความกำกับ Order Block
bool   ShowSMCOnlyOnNewBar       = true;   // อัปเดตการแสดงผลเฉพาะเมื่อเริ่มแท่งใหม่เท่านั้น
int    SMCVisualUpdateSeconds    = 15;     // ความถี่การอัปเดตกราฟ (วินาที)
int    SMCVisualDashboardX       = 10;
int    SMCVisualDashboardY       = 20;
int    SMCVisualZoneLookbackBars = 120;    // จำนวนแท่งย้อนหลังที่ใช้แสดงโซน
int    SMCVisualZoneForwardBars  = 20;     // จำนวนแท่งไปข้างหน้าที่ใช้แสดงโซน
color  SMCVisualPremiumColor     = clrTomato;
color  SMCVisualEquilibriumColor = clrGray;
color  SMCVisualDiscountColor    = clrLime;
int    CompactIndicatorPaneHeightPx      = 18;     // ความสูงของพาเนลตัวบ่งชี้แบบคอมแพค
int    CompactMainChartMinHeightPx       = 720;    // ความสูงขั้นต่ำของหน้าจอกราฟหลัก
int    CompactIndicatorLayoutUpdateSeconds = 2;    
bool   CompactIndicatorLayoutLogOnce     = true;
int    CompactIndicatorLayoutPasses      = 5;    
bool   EnablePipelineScoreSummary         = true; // แสดงสรุปคะแนนในระบบประมวลผลสัญญาณ
bool   EnablePipelineRejectReasonBreakdown = true; // แสดงเหตุผลของการปฏิเสธสัญญาณโดยละเอียด
double PipelineNearPassScoreBand          = 0.03; // ช่วงคะแนน "เกือบผ่าน" ที่จะให้แจ้งเตือน
double PipelineNearPassConfBand           = 0.03; // ช่วงความมั่นใจ "เกือบผ่าน"
bool   EnablePipelineStarvationWarning    = true; // แจ้งเตือนหากไม่มีสัญญาณผ่านระบบมานานเกินไป
int    PipelineStarvationMinSMCPass       = 1000;
int    PipelineStarvationConsecutiveIntervals = 4;
bool   PipelineStarvationRequireNoOrdersSent  = true;
bool   EnableExitDetailLog                    = true; // บันทึกข้อมูลการปิดไม้โดยละเอียด
bool   EnableRescueOutcomeAttribution          = true; // ติดตามผลลัพธ์ของไม้ที่เกิดจากการกู้คืนสัญญาณ
int    RescuePauseMinutes                      = 120;
bool   SMCUseDisplacementConfirm = true;         // ใช้ระบบยืนยันด้วยการเคลื่อนที่ราคาที่รุนแรง
double SMCDisplacementBodyATR = 0.45;           // เกณฑ์ความยาวของเนื้อเทียนเทียบกับ ATR
double SMCDisplacementCloseTopPct = 0.70;        // เกณฑ์การปิดใกล้จุดสูงสุด
bool   SMCUseRetestConfirmForRescue = true;      // ใช้ระบบยืนยันด้วยการ Retest สำหรับโหมด Rescue
int    SMCRetestLookbackBars = 5;               // จำนวนแท่งย้อนหลังที่ใช้หาการ Retest
double SMCRetestToleranceATR = 0.25;            // ค่าความยืดหยุ่นในการ Retest
bool   SMCUseLiquiditySweepConfirm = true;      // ใช้ระบบยืนยันด้วยการกวาดสภาพคล่อง
int    SMCLiquiditySweepLookback = 10;          // จำนวนแท่งย้อนหลังที่ใช้ตรวจสอบการกวาดสภาพคล่อง
bool   SMCUseOrderBlockQuality = false;
bool   SMCUseFVGQuality = false;
int    ContextExitCooldownWindowMinutes = 120;
bool   EnableNoTradeDetailLogs = false;  
double LowTradePenaltyPerTrade = 10.0;
int    QuickTesterMinTrades = 10;
double QuickLowTradePenaltyPerTrade = 5.0;

#endif // __KNARES_SMC_INPUTS_MQH__

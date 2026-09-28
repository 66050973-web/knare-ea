#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "SMCInputs.mqh"

//+------------------------------------------------------------------+
//| Config Module - ศูนย์รวมการตั้งค่าและพารามิเตอร์ทั้งหมดของระบบ KNARES      |
//| ทำหน้าที่: กำหนดค่าตัวแปรควบคุม (Control Variables) ทั้งหมดที่ใช้ในลอจิก |
//| เพื่อให้ง่ายต่อการปรับจูน (Tuning) และรักษาความปลอดภัยของระบบ            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Input Parameters - พารามิเตอร์ที่แสดงในหน้าต่างตั้งค่า (User Inputs)      |
//+------------------------------------------------------------------+

input group "--- 1. BASIC TRADING & RISK (การตั้งค่าพื้นฐานและความเสี่ยง) ---"
input string Symbols               = "EURUSD,GBPUSD,XAUUSD"; // รายชื่อคู่เงินที่ต้องการให้ EA ทำงาน (ใช้เครื่องหมายจุลภาคคั่น)
input ENUM_TIMEFRAMES MainTF       = PERIOD_M1;              // ไทม์เฟรมหลักที่ใช้ในการวิเคราะห์สัญญาณ (Signal Timeframe)
input ENUM_TIMEFRAMES HigherTF     = PERIOD_H1;              // ไทม์เฟรมที่สูงกว่าเพื่อใช้ดูทิศทางเทรนด์ใหญ่ (Filter Timeframe)
input ENUM_LOT_MODE LotMode         = LOT_FIXED;             // รูปแบบการคำนวณลอต (LOT_FIXED: คงที่, LOT_RISK_PCT: ตามความเสี่ยง %)
input double FixedLotSize          = 0.01;                   // ขนาดลอตที่ใช้เมื่อตั้งเป็นโหมดคงที่ (Fixed Lot)
input double RiskPerTradePct       = 0.005;                  // ความเสี่ยงสูงสุดต่อไม้ (0.005 = 0.5% ของ Equity)
input ulong  MagicNumber           = 20260429;               // รหัสประจำตัวออเดอร์ของ EA เพื่อป้องกันการเทรดปนกับตัวอื่น

input group "--- 2. CORE STRATEGY TOGGLES (เปิด/ปิด ระบบหลัก) ---"
input bool   EnableTrendEngine     = true;                   // เปิดใช้งานกลยุทธ์ตามเทรนด์ (Trend Following)
input bool   EnableBreakoutEngine  = false;                  // เปิดใช้งานกลยุทธ์เบรคเอาท์ (Breakout Strategy)
input bool   EnableMeanRevEngine   = false;                  // เปิดใช้งานกลยุทธ์สวนเทรนด์หาค่าเฉลี่ย (Mean Reversion)
input bool   EnableSmartRecovery   = true;                   // เปิดใช้งานระบบแก้พอร์ตอัตโนมัติ (Recovery Mode)
input bool   EnableDynamicRisk     = true;                   // เปิดใช้งานการปรับลดความเสี่ยงอัตโนมัติเมื่อพอร์ตเริ่มเสียหาย
input int    LossStreakLimit       = 5;                      // จำนวนไม้ที่แพ้ติดต่อกันก่อนที่ระบบจะเริ่มลดขนาดความเสี่ยงลง

input group "--- 3. TAKE PROFIT & STOP LOSS (เป้าหมายกำไรและจุดตัดขาดทุน) ---"
input double TakeProfitR           = 2.00;                   // เป้าหมายกำไรมาตรฐาน คิดเป็นจำนวนเท่าของความเสี่ยง (RRR)
input double DynamicTPHighConvictionR = 2.50;               // เป้าหมายกำไรพิเศษสำหรับไม้ที่มีความมั่นใจสูงมาก
input double ATRStopMultiple       = 3.0;                    // ตัวคูณ ATR สำหรับคำนวณระยะ Stop Loss ตามความผันผวนของตลาด
input int    MinStopDistancePoints = 400;                  // ระยะตัดขาดทุนขั้นต่ำ (Points) เพื่อป้องกันกรณี Spread ถ่าง

input group "--- 4. PORTFOLIO & SAFETY GUARDS (ระบบป้องกันความปลอดภัยพอร์ต) ---"
input double MaxTotalDrawdownPercent = 30.0;                 // ขีดจำกัด Drawdown รวมของพอร์ตที่ระบบจะหยุดทำงาน (Hard Stop)
input double EquityKillSwitchPct   = 0.50;                   // จุดตัดการทำงานทันที (Kill Switch) หากพอร์ตเสียหายเกิน 50%
input double PortfolioHeatCapPct   = 0.15;                   // ความเสี่ยงรวมสูงสุดของทุกออเดอร์ที่ค้างอยู่ในพอร์ต (15% ของทุน)
input double MaxLotsPerTradeXAU    = 0.40;                   // ขนาดลอตสูงสุดที่อนุญาตให้เปิดได้สำหรับทองคำ (ป้องกัน Over-leveraging)
input double MinMarginLevelPct     = 800.0;                  // ระดับมาร์จิ้นขั้นต่ำที่ยอมให้เปิดไม้ใหม่ได้
input bool   EnableNewsFilter      = true;                   // เปิดใช้งานระบบป้องกันช่วงข่าวเศรษฐกิจสำคัญ (News Filter)

input group "--- 5. SESSION CONTROL (การควบคุมช่วงเวลาทำงาน) ---"
input int    StartHour             = 0;                      // ชั่วโมงที่เริ่มทำงาน (Server Time)
input int    EndHour               = 24;                     // ชั่วโมงที่สิ้นสุดการทำงาน
input bool   TradeOnFridayClose    = true;                   // อนุญาตให้ถือออเดอร์ข้ามคืนวันศุกร์หรือไม่

input group "--- 5B. NEWS SENTIMENT FILTER (ตัวกรองความรู้สึกตลาดจากข่าว) ---"
input bool   EnableSentimentFilter = false;                  // เปิดใช้งานระบบกรองตาม Sentiment ข่าว (false = ไม่สน sentiment เลย เทรดตามปกติ)
input double SentimentSkipThreshold = 0.35;                  // ค่า |sentiment score| ขั้นต่ำที่ถือว่า "สวนทางแรงพอ" ให้ข้าม (0.0-1.0)
input int    SentimentCacheMaxAgeMin = 90;                   // อายุไฟล์ sentiment สูงสุดที่ยอมรับ (นาที) เกินกว่านี้ถือว่าข้อมูลเก่า ไม่ใช้กรอง
input string SentimentCacheFileName = "KNARES_SentimentCache.json"; // ชื่อไฟล์ cache (ต้องอยู่ใน MQL5\Files ของ terminal)

input group "--- ADVANCED: ENGINE TUNING (การปรับจูนระบบวิเคราะห์เชิงลึก) ---"
input double TrendEngineATRStopMultiple = 2.5;              // ระยะ SL พิเศษเฉพาะกลยุทธ์ Trend
input double TrendEngineTakeProfitR     = 2.0;              // เป้าหมายกำไรเฉพาะกลยุทธ์ Trend
input int    TrendMinStopDistancePoints = 400;              // ระยะ SL ขั้นต่ำของกลยุทธ์ Trend
input int    BreakoutMinStopDistancePoints = 150;           // ระยะ SL ขั้นต่ำของกลยุทธ์ Breakout
input int    MeanRevMinStopDistancePoints = 250;            // ระยะ SL ขั้นต่ำของกลยุทธ์ Mean Reversion
input double HighConvictionScoreThreshold = 0.90;           // เกณฑ์คะแนนที่ถือว่ามีความมั่นใจสูงมาก (> 0.90)

input group "--- ADVANCED: RISK & RECOVERY (การจัดการความเสี่ยงและระบบกู้คืน) ---"
input double RecoveryDrawdownR     = 0.40;                   // ระดับการติดลบ (หน่วย R) ที่จะเริ่มเปิดระบบกู้คืน (Smart Recovery)
input double RecoveryMinConfidence = 0.88;                   // ระดับความมั่นใจ AI ขั้นต่ำที่ต้องการสำหรับไม้แก้
input double RecoveryLotMultiplier = 1.10;                   // ตัวคูณเพื่อเพิ่มขนาดลอตเล็กน้อยสำหรับไม้แก้
input int    RecoveryMaxAttempts   = 2;                      // จำนวนครั้งสูงสุดที่จะพยายามแก้ไม้ในหนึ่งรอบสภาวะตลาด
input double RiskReductionFactor     = 0.50;                 // สัดส่วนการลดลอตในโหมดป้องกัน (Defensive Mode)
input double RiskRestoreStep         = 0.10;                 // ขั้นในการค่อยๆ เพิ่มความเสี่ยงกลับมาในโหมดฟื้นฟู (Recovery Mode)

input group "--- ADVANCED: PARTIAL CLOSE (การแบ่งปิดกำไรบางส่วน) ---"
input bool   EnablePartialClose    = true;                   // เปิดใช้งานระบบแบ่งขายทำกำไรระหว่างทาง
input double PartialCloseLevelR     = 1.00;                  // ระดับกำไรที่ถึงเป้าหมายแรก (1R) แล้วจะทำการแบ่งปิด
input double EarlyBreakEvenR        = 0.75;                  // ระดับกำไรที่ระบบจะเริ่มเลื่อน SL มาคุ้มทุน (Breakeven)
input double PartialCloseSizePct   = 0.5;                    // เปอร์เซ็นต์ของลอตที่จะปิดทำกำไรก่อน (เช่น 0.5 = ปิดครึ่งหนึ่ง)
input double PartialCloseMinLots   = 0.01;                   // ขนาดลอตต่ำสุดที่โบรกเกอร์ยอมให้แบ่งปิดได้

input group "--- ADVANCED: TECHNICAL FILTERS (ตัวกรองทางเทคนิคเชิงลึก) ---"
input bool   EnableVolumeFilter    = true;                   // เปิดใช้งานตัวกรองวอลลุ่ม (ป้องกันการเทรดในตลาดที่ไม่มีคนเล่น)
input double MinVolumePercentile   = 5.0;                    // เปอร์เซ็นไทล์วอลลุ่มขั้นต่ำ (เพื่อเลี่ยงช่วงตลาดหยุดพัก)
input bool   EnableVolatilityFilter = true;                  // เปิดใช้งานตัวกรองความผันผวน
input double MinAtrMultiplier      = 0.3;                    // ตัวคูณ ATR ขั้นต่ำเพื่อเลี่ยงตลาดนิ่ง (Low Volatility)
input double MaxSpreadPointsXAU    = 40.0;                   // ค่า Spread สูงสุดที่อนุญาตให้เทรดทองคำได้ (Points)
input double RiskOffSpreadPoints    = 500.0;                  // Spread (Points) ที่ถือว่า RISK_OFF ห้ามเข้าเทรด (broker ทศนิยม 2 ตำแหน่ง ~50, ทศนิยม 3 ตำแหน่ง ~500)
input bool   UseRuleScoreWhenAIOff   = true;                   // เมื่อ AI (ONNX/Neural Bridge) ปิดหรือใช้ไม่ได้ ให้ใช้คะแนน rule-based ของ Engine เป็นค่าความมั่นใจ แทนค่ากลาง 0.5 (ถ้าเป็น false EA จะไม่เปิดออเดอร์เลยเพราะ 0.5 < MinEntryConfidence)
input int    EnginePausedCooldownHours = 24;                  // ชั่วโมงที่พัก Engine เมื่อ Rolling PF ต่ำกว่า 0.65 ก่อนกลับมาลองเทรดใหม่ (เดิมพักถาวรจนกว่าจะรีสตาร์ท EA)
input int    EngineResumeGraceTrades   = 10;                  // จำนวนไม้ที่ยกเว้นการตรวจ Rolling PF หลังกลับมาจากการพัก (ให้มีเทรดใหม่มาปรับค่า PF)

input group "--- ADVANCED: DIAGNOSTICS & LOGS (การแจ้งเตือนและการบันทึกข้อมูล) ---"
input bool   EnableTradeAlerts     = true;                   // แจ้งเตือนผ่านหน้าจอ (Alert Popup) เมื่อมีการเทรด
input bool   EnablePushNotifications = false;                // ส่งแจ้งเตือนผ่าน Mobile Push Notification
input bool   EnableDebugLogs       = true;                   // บันทึกรายละเอียดการตัดสินใจเชิงลึกใน Log (สำหรับ Debug)
input int    KpiLogIntervalSec = 900;                        // ช่วงเวลาในการสรุปสถิติผลงานลงใน Log (วินาที)
input bool   EnableDecisionTrace = true;                    // บันทึกทุกขั้นตอนการคิดของ EA เพื่อย้อนรอยความผิดพลาด

// --- ตัวแปรควบคุมภายใน (Internal Control Variables - สำหรับ Developer) ---
// ส่วนนี้เป็นตัวแปรที่ไม่แสดงในหน้า GUI แต่มีความสำคัญต่อลอจิกการทำงานเชิงลึก

bool   EnablePerformanceMaxSafe = true;                      // เน้นประสิทธิภาพควบคู่ความปลอดภัยสูงสุด (Stability Mode)
double G_DOM_VETO_THRESHOLD = 0.6;                           // เกณฑ์การยกเลิกสัญญาณจากข้อมูล DOM Imbalance
int    G_ICEBERG_SLICES     = 10;                            // จำนวนไม้ที่จะแบ่งส่งในระบบพรางตัว (Iceberg Algorithm)
double G_HMM_RISK_TOLERANCE  = 0.75;                         // ขีดจำกัดความเสี่ยงจากการพยากรณ์ด้วย Hidden Markov Model
string G_STATARB_PAIR_B     = "GBPUSD";                      // คู่เงินรองสำหรับการทำสถิติอาบิทราจ (Stat-Arb)
double G_STATARB_Z_ENTRY    = 2.2;                           // ค่า Z-score ของส่วนต่างราคาที่เริ่มทำการ Arbitrage

double DailySoftLossPct      = 1.00;                         // ระดับขาดทุนรายวันที่เริ่มส่งแจ้งเตือน (Soft Alert)
double DailyHardLossPct      = 1.05;                         // ระดับขาดทุนรายวันที่ต้องหยุดเทรดประจำวัน (Hard Stop)
double TrendBonusADXThreshold = 35.0;                        // เกณฑ์ค่า ADX ที่เริ่มให้แต้มพิเศษสำหรับเทรนด์แข็งแรง
double TrendBonusSlopeThreshold = 0.005;                     // เกณฑ์ความชัน EMA ที่เริ่มให้คะแนนโบนัส
double TrendStrengthBonus     = 0.05;                        // โบนัสคะแนนที่เพิ่มให้เมื่อเทรนด์ชัดเจน
bool   EnableAggregateProfitExit = false;                    // เปิดใช้การปิดทุกไม้เมื่อผลกำไรรวมถึงเป้า (Basket Close)
double AggregateProfitExitR      = 0.70;                     // เป้าหมายกำไรรวมของตระกร้าออเดอร์ (หน่วย R)
bool   EnableScaleIn         = false;                        // เปิดใช้งานการเปิดไม้เพิ่มตามเทรนด์ (Scaling)
double ScaleInSuperSignalScore   = 0.92;                     // คะแนนสัญญาณที่สูงมากสำหรับการเปิดไม้เพิ่ม
double ScaleInMinProfitR     = 0.30;                         // กำไรขั้นต่ำของไม้แรกที่ต้องมีก่อนเปิดไม้ใหม่
double ScaleInMinScore       = 0.80;                         // คะแนนสัญญาณขั้นต่ำสำหรับการพิจารณาเปิดไม้ใหม่
int    ModifyThrottleSeconds = 10;                           // ระยะห่างเวลาขั้นต่ำในการส่งคำสั่งแก้ไข (Modify) เพื่อป้องกันระบบโดนแบน
int    ModifyMinDeltaPoints  = 1000;                         // ระยะการขยับราคาขั้นต่ำที่จะอนุญาตให้ส่งคำสั่ง Modify (ปรับ x10 ให้ตรงกับ broker ทศนิยม 3 ตำแหน่ง)
double DoubleEngineBonusScore = 0.05;                        // โบนัสพิเศษเมื่อ 2 กลยุทธ์ส่งสัญญาณไปในทิศทางเดียวกัน
bool   EnableSilentThrottling = true;                        // ลดการพิมพ์ Log เมื่อติด Cooldown เพื่อไม่ให้ Log รก
bool   ModifyOncePerBar      = true;                         // จำกัดการแก้ไขออเดอร์ได้เพียง 1 ครั้งต่อแท่งเทียน
double SpreadMedianMultiple  = 1.2;                          // กรองสัญญาณโดยใช้ค่ากลางของ Spread ย้อนหลัง
double ScoreFloorEpsilon      = 0.005;                       // ค่าเผื่อความคลาดเคลื่อนสำหรับการเปรียบเทียบคะแนน
double HMMShiftRiskBlockThreshold = 0.80;                    // บล็อกการเทรดหาก HMM แจ้งว่าความเสี่ยงสภาวะตลาดเปลี่ยนสูงเกินไป
bool   TrendRequireBothHTF   = false;                        // บังคับว่าต้องเทรนด์ตรงกันทั้ง H1 และ H4 (ถ้าเป็นเท็จ จะใช้แค่ H1)
bool   TrendUseH1OnlyRelaxed = true;                         // ใช้เพียง H1 ในการกรองเทรนด์เพื่อให้มีโอกาสเทรดมากขึ้น
double TrendH4MismatchPenalty = 0.04;                        // ค่าปรับที่หักออกหากเทรนด์ H4 ขัดแย้งกับสัญญาณ
bool   EnableTrendHtfPenaltyFallback = true;                 // ใช้ระบบหักคะแนนแทนการบล็อกทันทีหากเทรนด์ใหญ่ไม่ตรง
double TrendHtfConflictPenalty = 0.10;                       // คะแนนที่หักเมื่อเทรนด์ใหญ่ขัดแย้ง
double BreakoutNearBandAtrFactor = 0.35;                     // ระยะราคาที่ถือว่าใกล้ขอบ Donchian เพื่อเตรียมเบรคเอาท์
double MeanRevReentryToleranceATR = 0.05;                    // ระยะห่างที่ยอมให้เข้าเทรดซ้ำในจุดใกล้เดิม
bool   EnableMeanRevInTrendSelective = false;                // กรองการเทรดสวนเทรนด์เฉพาะในสภาวะที่มีความน่าจะเป็นสูง
double MeanRevTrendZScoreMin = 2.30;                         // ค่า Z-score ขั้นต่ำที่จะอนุญาตให้สวนเทรนด์ได้
double MeanRevTrendBandProximityATR = 0.20;                  // ระยะประชิดขอบแบนด์ที่ต้องการสำหรับการสวนกลับ
bool   EnableUnknownRegimeBuilderBypass = true;              // ยอมรับสัญญาณแม้สภาวะตลาดจะไม่ชัดเจน (ถ้าตัวกรองอื่นผ่าน)
double UnknownRegimeMinADX = 16.0;                           // ค่า ADX ขั้นต่ำในสภาวะ Unknown
double UnknownRegimeMinATR = 1.10;                           // ค่า ATR ขั้นต่ำในสภาวะ Unknown
double UnknownBreakoutMinAbsZ = 0.85;                        // ค่า Z-score ขั้นต่ำสำหรับเบรคเอาท์ในสภาวะ Unknown
double UnknownMeanRevMinAbsZ = 2.10;                         // ค่า Z-score ขั้นต่ำสำหรับสวนเทรนด์ในสภาวะ Unknown
bool   EnableOnnxOverlay     = false;                        // เชื่อมต่อโมดูล AI ภายนอก (ONNX)
bool   EnableNeuralBridge    = false;                        // เชื่อมต่อระบบโครงข่ายประสาทเทียมภายนอก
double AIConfidenceThreshold = 0.50;                         // เกณฑ์ความเชื่อมั่นที่ต้องการจากโมดูล AI
double MinEntryScore         = 0.78;                         // คะแนนสัญญาณรวมขั้นต่ำที่จะอนุญาตให้เปิดออเดอร์
double MinEntryConfidence    = 0.75;                         // ความเชื่อมั่นรวมขั้นต่ำที่จะอนุญาตให้เปิดออเดอร์
double LowScoreThreshold     = 0.80;                         // คะแนนระดับล่างที่ต้องใช้ตัวกรองอื่นช่วยยืนยันเป็นพิเศษ
double LowScoreMinConfidence = 0.80;                         // ความเชื่อมั่นที่ต้องการเพิ่มขึ้นหากคะแนนสัญญาณค่อนข้างต่ำ
double MeanRevMaxADX         = 35.0;                         // ADX สูงสุดที่ยอมให้สวนเทรนด์ (ถ้าสูงกว่านี้เทรนด์แรงไป ห้ามสวน)
double MinPostPenaltyScoreTrendHighQual = 0.72;              // คะแนนขั้นต่ำหลังหักค่าปรับสำหรับ Trend คุณภาพสูง
double MinPostPenaltyScoreTrendBreakout = 0.78;              // คะแนนขั้นต่ำหลังหักค่าปรับสำหรับ Trend-Breakout
double MinPostPenaltyScoreBreakout      = 0.65;              // คะแนนขั้นต่ำหลังหักค่าปรับสำหรับกลยุทธ์ Breakout
double MeanRevMinEntryScore  = 0.72;                         // คะแนนขั้นต่ำสำหรับกลยุทธ์ Mean Reversion
bool   EnforceHTFAlignment   = false;                        // บังคับเข้มงวดให้เทรดตามเทรนด์ใหญ่เท่านั้น
bool   EnableHTFSoftPenalty  = true;                         // ใช้การหักคะแนนแทนการบล็อกสัญญาณเมื่อขัดแย้งเทรนด์ใหญ่
double HTFScorePenalty       = 0.01;                         // คะแนนที่หักเมื่อขัดแย้งกับ Higher TF
double HTFConfidencePenalty  = 0.02;                         // ความเชื่อมั่นที่หักเมื่อขัดแย้งกับ Higher TF
bool   EnableUnknownRegimePenalty = true;                    // หักคะแนนพิเศษเมื่อตลาดอยู่ในสภาวะคลุมเครือ (Unknown)
double UnknownRegimeScorePenalty = 0.01;                     // คะแนนที่หักในสภาวะ Unknown
double UnknownRegimeConfPenalty  = 0.02;                     // ความเชื่อมั่นที่หักในสภาวะ Unknown
double MaxCombinedScorePenalty = 0.02;                       // เพดานรวมของการหักคะแนนทุกกรณี (เพื่อไม่ให้คะแนนร่วงมากเกินไป)
bool   EnablePriceActionFilter = false;                      // เปิดใช้การตรวจสอบรูปแบบแท่งเทียน (Candlestick Patterns)
double MinAdxSlope           = 0.0000;                       // ความชันขั้นต่ำของ ADX (เพื่อยืนยันว่ากำลังมีรอบการเล่น)
double XAUAdaptiveSpreadFloor = 55.0;                        // เพดาน Spread พื้นฐานสำหรับทองคำ
double XAUAdaptiveSpreadMedianMult = 2.0;                    // ตัวคูณค่ากลาง Spread สำหรับระบบ Adaptive ในทองคำ
bool   EnableTestForceEntry  = false;                        // (สำหรับ DEV) บังคับเข้าเทรดไม้ทดสอบทันทีเมื่อเริ่มโปรแกรม
double TestForceLots         = 0.01;                         // (สำหรับ DEV) ขนาดลอตของไม้ทดสอบ
bool   EnableEmergencyGuards = true;                         // เปิดใช้งานระบบป้องกันภัยพิบัติของพอร์ต (Portfolio Guards)
bool   EnableStopLoss        = true;                         // เปิดใช้งานระบบ Stop Loss (ควรเปิดไว้เสมอในบัญชีจริง)
bool   DisableIcebergTemporarily = true;                     // ปิดระบบ Iceberg ชั่วคราว (ใช้การส่งไม้เดียวปกติ)
int    RegimeExitSymbolLockSec = 0;                          // พักการเทรดคู่เงินเดิม x วินาทีหลังจากเพิ่งปิดไม้ตามสภาวะตลาด
int    RegimeExitStormWindowSec = 0;                         // หน้าต่างเวลาสำหรับตรวจจับการปิดไม้ถล่มทลาย (Storm Guard)
int    RegimeExitStormThreshold = 999;                       // จำนวนไม้เสียในหน้าต่างเวลาที่จะสั่งระงับการเทรดทั้งพอร์ต
int    RegimeExitStormPauseSec = 0;                          // ระยะเวลาระงับการเทรดเมื่อเจอสภาวะ Storm
bool   CorrelationBlockEnabled = true;                       // บล็อกการเข้าเทรดคู่เงินที่มีความสัมพันธ์กันสูง (ป้องกันความเสี่ยงซ้อน)
bool   TradeOnlyChartSymbol = true;                          // เทรดเฉพาะสัญลักษณ์บนกราฟที่รัน EA อยู่ (แนะนำให้เปิด)
int    RegimeExitEntryCooldownSec = 0;                       // ระยะเวลารอหลังเปิดไม้ก่อนที่จะอนุญาตให้ปิดตามสภาวะตลาด
double UnknownRegimeMinScore      = 0.78;                    // คะแนนขั้นต่ำที่ต้องการในสภาวะตลาด Unknown
double UnknownRegimeMinAIConf     = 0.70;                    // ความเชื่อมั่น AI ขั้นต่ำที่ต้องการในสภาวะ Unknown
int    RegimeExitConfirmBars = 1;                            // จำนวนแท่งเทียนที่ต้องยืนยันสัญญาณกลับตัวก่อนสั่งปิดตาม Regime
bool   EnableAutoGuard = false;                              // เปิดระบบหยุดเทรดอัตโนมัติหากโบรกเกอร์ Reject คำสั่งรัวๆ
int    AutoGuardRejectStreak = 0;                            // จำนวนครั้งที่โดน Reject ก่อนเริ่มงาน
int    AutoGuardPauseSec = 0;                                // ระยะเวลาหยุดเทรดชั่วคราว
int    DecisionTraceIntervalSec = 60;                        // ความถี่ในการสรุปขั้นตอนการคิดลงใน Log (วินาที)
bool   EnableEnginePerformanceGuard = false;                // ตรวจสอบประสิทธิภาพราย Engine และปิดตัวที่ทำผลงานแย่
int    EnginePerfMinTrades = 60;                             // จำนวนไม้เทรดขั้นต่ำก่อนเริ่มประเมินผลงาน Engine
double EnginePerfDisablePF = 0.75;                           // ระดับ Profit Factor ที่จะสั่งระงับการใช้งาน Engine นั้น
double TrailingProfitLockR     = 0.20;                       // สัดส่วนกำไรขั้นต่ำที่ต้องการล็อกไว้ (หน่วย R)
double TrailingProfitTriggerR  = 1.25;                       // ระดับกำไรที่เริ่มสั่งให้ Trailing Stop ทำงาน
double TrailingProfitGapR      = 0.60;                       // ระยะห่างของจุด Stop Loss จากราคาปัจจุบัน (หน่วย R)
double TrailingProfitLockMinR  = 0.10;                       // ล็อกกำไรขั้นต่ำสุดที่อนุญาต
double TrailingProfitLockMaxR  = 2.00;                       // ล็อกกำไรสูงสุดที่จะตามราคาไป
double TrailingProfitLockStepR = 0.05;                       // ขั้นการขยับของกำไรที่ล็อก (เพื่อลดภาระการส่งคำสั่ง)
double TrendEarlyInvMinLossR   = 0.25;                       // ระดับขาดทุนที่เริ่มตรวจสอบสัญญาณเสียทรงเทรนด์ (Early Exit)
double TrendEarlyInvSlopeThreshold = 0.0015;                 // เกณฑ์ความชันที่บ่งบอกว่าเทรนด์เดิมเริ่มเสียทรงแล้ว
int    TrendEarlyInvConfirmBars = 2;                         // จำนวนแท่งเทียนยืนยันการเสียทรง
int    TrendEarlyInvMinBarsOpen = 3;                         // จำนวนแท่งเทียนขั้นต่ำที่ต้องถือไว้ก่อนจะตรวจเช็คสัญญาณเสียทรง
bool   TrendEarlyInvRequireOpposingRegime = true;            // ต้องการสภาวะตลาดฝั่งตรงข้ามมายืนยันการปิดหนีสัญญาณเสีย
double RegimeExitMinProfitR    = 0.20;                       // กำไรขั้นต่ำที่จะยอมให้ปิดออเดอร์เมื่อสภาวะตลาดเปลี่ยนทิศ
double RegimeExitLossCutR      = 0.50;                       // จุดตัดขาดทุนเมื่อตลาดเปลี่ยนทิศรุนแรง (ตัดขาดทุนไวกว่า SL ปกติ)
int    RegimeExitLossConfirmBars = 4;                        // จำนวนแท่งที่ยืนยันการเปลี่ยนทิศก่อนตัดขาดทุน
double TrendMinADXFloor        = 30.0;                       // ค่า ADX ต่ำสุดที่ยอมรับว่าเป็นเทรนด์ที่แข็งแรง
bool   EnableDOMSoftVeto = true;                             // เปิดระบบคัดค้านสัญญาณเทรดด้วยแรงต้านใน Order Book (DOM)
bool   EnableDOMHardBlockInTester = false;                    // เปิดการบล็อกด้วย DOM ในโหมดทดสอบย้อนหลัง (ถ้ามีข้อมูล)
double DOMVetoSevereThreshold = 0.85;                       // ระดับเปอร์เซ็นต์แรงต้านรุนแรงจาก DOM ที่จะสั่งยกเลิกสัญญาณทันที
int    DOMVetoPersistentBars = 2;                            // จำนวนแท่งเทียนที่แรงต้านต้องอยู่ต่อเนื่องกันจึงจะบล็อก
bool   EnableSingleInstanceGuard = true;                     // ป้องกันไม่ให้เปิด EA ตัวเดิมซ้ำกันในกราฟคู่เงินเดียว
int    SingleInstanceHeartbeatSec = 30;                      // ความถี่ในการส่งสัญญาณชีพเพื่อยืนยันการทำงาน
int    SingleInstanceStaleSec = 120;                         // เวลาที่ถือว่าหน้าต่างเดิมค้างหรือหยุดทำงานไปแล้ว
double MinPositionDistanceATR   = 1.5;                       // ระยะห่างขั้นต่ำ (หน่วย ATR) ระหว่างไม้ในคู่เงินเดียวกัน
double UnknownBreakoutMinVolumeMult = 1.3;                   // ตัวคูณวอลลุ่มที่ต้องการหากจะเทรดเบรคเอาท์ในตลาดไม่ชัดเจน
double GlobalProfitExitUSD      = 50.0;                       // เป้าหมายกำไรรวมพอร์ต (เงินจริง) ที่จะสั่งปิดทุกออเดอร์ทันที
double WeeklyProfitTargetPct    = 100.0;                      // เป้าหมายกำไรรายสัปดาห์เทียบกับทุน (%)
bool   EnableWeeklyLock         = false;                      // ล็อกกำไรพอร์ตและหยุดเทรดเมื่อถึงเป้าสัปดาห์
double VolatilityShockMultiplier = 3.5;                      // ตัวคูณความผันผวนที่จะเข้าสู่ภาวะตลาดช็อก (Volatility Shock)
int    VolatilityPauseHours      = 1;                         // จำนวนชั่วโมงที่จะหยุดเทรดหลังเกิดภาวะช็อก
double VolStormScoreIncrease    = 0.05;                       // คะแนนที่ระบบจะ "เข้มงวด" ขึ้นในช่วงตลาดผันผวนสูง
int    ModifySafetyBufferPoints = 500;                       // ระยะปลอดภัย (Points) เพื่อป้องกัน Error ในการส่งคำสั่ง Modify (ปรับ x10 ให้ตรงกับ broker ทศนิยม 3 ตำแหน่ง)
bool   EnableAcceleratedTrailing = true;                     // เร่งการขยับ Stop Loss ให้ไวขึ้นเมื่อกำไรพุ่งแรง
double AcceleratedTrailingProfitR = 1.50;                    // ระดับกำไรที่เริ่มเข้าสู่โหมด Trailing เร่งด่วน
double AcceleratedTrailingGapR   = 0.40;                     // ระยะห่างที่แคบลงในโหมดเร่งด่วน
int    CommissionBufferPoints    = 200;                      // ระยะ Points ที่กันไว้สำหรับครอบคลุมค่าคอมมิชชั่น (ปรับ x10 ให้ตรงกับ broker ทศนิยม 3 ตำแหน่ง)
double MaxDailyDrawdownPercent = 5.0;                        // ขีดจำกัด Drawdown รายวันที่ยอมรับได้
int    RollingWindowTrades     = 50;                         // หน้าต่างจำนวนออเดอร์ที่ใช้คำนวณผลงานล่าสุด
int    MaxHoldingMinutes       = 2880;                       // ระยะเวลาถือออเดอร์สูงสุด (2 วัน) หากไม่กำไรจะถูกปิดอัตโนมัติ
double MinProfitForHold        = -0.10;                      // กำไรขั้นต่ำที่อนุญาตให้ถือออเดอร์ต่อแม้จะครบกำหนดเวลาแล้ว
double VolatilityShockExitMult = 3.5;                        // ตัวคูณความผันผวนที่จะสั่งให้ปิดออเดอร์หนีวิกฤต
int    RollingPFWindow         = 50;                         // หน้าต่างออเดอร์สำหรับคำนวณ Profit Factor
bool   EnableEngineAutoPause   = true;                       // เปิดระบบหยุดพัก Engine อัตโนมัติหากทำผลงานได้ต่ำกว่าเกณฑ์
double EngineAutoPausePF       = 0.90;                       // PF ที่จะเริ่มสั่งพักการใช้งาน Engine ชั่วคราว
int    EnginePauseBars         = 100;                        // จำนวนแท่งเทียนที่จะพัก Engine ไว้
double ExposureCapEquityMultipleFX = 10.0;                   // เพดานการถือครองรวมต่อทุนสำหรับคู่เงินทั่วไป (Leverage Cap)
double ExposureCapEquityMultipleXAU = 25.0;                  // เพดานการถือครองรวมต่อทุนสำหรับทองคำ
bool   EnableOnlyNewBarEntry = false;                       // บังคับให้เข้าเทรดได้เฉพาะในจังหวะเริ่มแท่งเทียนใหม่เท่านั้น
int    MaxPositionsPerSymbol = 5;                           // จำกัดจำนวนออเดอร์สูงสุดต่อหนึ่งคู่เงิน
bool   EnableOpenMarketIncrementalCaps = true;               // ขยายเพดานความเสี่ยงเพิ่มขึ้นเล็กน้อยเมื่อพอร์ตเริ่มมีกำไรและไม้ค้าง
double IncrementalExposureStepPerPos = 2.0;                 // สัดส่วนการขยาย Exposure ต่อหนึ่งไม้
double IncrementalExposureMaxAdd = 8.0;                     // ขีดจำกัดสูงสุดของการขยาย Exposure เพิ่มเติม
double IncrementalHeatStepPerPos = 0.15;                    // สัดส่วนการขยาย Heat ต่อหนึ่งไม้
double IncrementalHeatMaxAdd = 0.50;                        // ขีดจำกัดสูงสุดของการขยาย Heat เพิ่มเติม
bool   EnableRegimeDiagnostics = true;                      // บันทึกวิเคราะห์สภาวะตลาดอย่างละเอียดลง Log
bool   EnableRegimeUnknownCooldownBypass = true;             // อนุญาตให้ข้าม Cooldown ในตลาด Unknown (ถ้าความมั่นใจสูง)
int    RegimeUnknownBypassCooldownSec = 180;                 // ระยะ Cooldown ที่ปรับลดลงในกรณีพิเศษ
double UnknownRegimeMinConfidenceBypass = 0.84;              // ความเชื่อมั่น AI ขั้นต่ำที่ยอมให้ข้าม Cooldown ได้
bool   EnableRangeSoftEntry = true;                         // เปิดใช้งานการเข้าเทรดแบบประนีประนอมในตลาดไซด์เวย์ (Range)
double RangeSoftEntryMinScore = 0.89;                       // คะแนนขั้นต่ำสำหรับการเข้าแบบ Soft Entry
double RangeSoftEntryMinConfidence = 0.64;                  // ความเชื่อมั่น AI ขั้นต่ำสำหรับ Soft Entry
int    FastEMA               = 50;                           // คาบเวลา EMA เส้นเร็ว
int    SlowEMA               = 200;                          // คาบเวลา EMA เส้นช้า
int    ADXPeriod             = 14;                           // คาบเวลาคำนวณ ADX
double ADXTrendThreshold     = 35.0;                         // ระดับที่ถือว่าเทรนด์แข็งแรง
int    ATRPeriod             = 14;                           // คาบเวลาคำนวณ ATR
int    RSIPeriod             = 14;                           // คาบเวลาคำนวณ RSI
double RSIOversold           = 28.0;                         // จุด Oversold
double RSIOverbought         = 72.0;                         // จุด Overbought
int    ROCPeriod             = 12;                           // คาบเวลาคำนวณ Rate of Change
int    DonchianLookback      = 20;                           // คาบเวลาสำหรับ Donchian Channels (Breakout)
bool   EnableTrailingStop    = false;                        // เปิดใช้งานระบบ Trailing Stop มาตรฐาน


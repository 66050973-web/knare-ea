#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

//+------------------------------------------------------------------+
//| Types Module - การกำหนดโครงสร้างข้อมูลและค่าคงที่ (Global Types)        |
//| ทำหน้าที่: รวบรวม Enum และ Struct ทั้งหมดที่ใช้ร่วมกันในระบบ KNARES      |
//+------------------------------------------------------------------+

// --- การกำหนดชุดตัวเลือก (Enumerations) ---

/**
 * โหมดการคำนวณขนาดการเทรด (Lot Size Calculation Mode)
 * ใช้สำหรับเลือกว่าจะใช้ขนาดลอตคงที่หรือคำนวณตามความเสี่ยง
 */
enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,     // ใช้ขนาดลอตคงที่ตามที่ผู้ใช้ระบุในตั้งค่า
   LOT_RISK_PCT = 1   // คำนวณลอตอัตโนมัติตาม % ความเสี่ยงเทียบกับจุดตัดขาดทุน (SL)
};

/**
 * ประเภทของสภาวะตลาด (Market Regime Types)
 * ใช้สำหรับระบุพฤติกรรมราคาปัจจุบันเพื่อเลือกใช้กลยุทธ์ที่เหมาะสม
 */
enum ENUM_REGIME_TYPE
{
   REGIME_UNKNOWN = 0,      // ไม่สามารถระบุสภาวะตลาดที่แน่นอนได้ (ควรใช้ความระมัดระวัง)
   REGIME_TREND_UP,         // ตลาดกำลังอยู่ในแนวโน้มขาขึ้นที่แข็งแรง
   REGIME_TREND_DOWN,       // ตลาดกำลังอยู่ในแนวโน้มขาลงที่แข็งแรง
   REGIME_RANGE,            // ตลาดเคลื่อนที่ในกรอบแคบๆ (Sideway)
   REGIME_BREAKOUT_READY,   // ตลาดบีบตัวและพร้อมที่จะระเบิดทิศทาง (เบรคเอาท์)
   REGIME_VOLATILITY_SHOCK, // เกิดความผันผวนรุนแรงฉับพลันผิดปกติ (สภาวะช็อก)
   REGIME_RISK_OFF,         // สภาวะเลี่ยงความเสี่ยงสูง ตลาดมีความไม่แน่นอนสูง
   REGIME_TRANSITION,       // สภาวะรอยต่อ กำลังจะเปลี่ยนแนวโน้ม (เช่น จากขึ้นเป็นลง)
   REGIME_CHOPPY,           // ตลาดสะเปะสะปะ ไร้ทิศทาง (ควรหยุดเทรด)
   REGIME_TREND_VOLATILE,   // เป็นเทรนด์แต่มีความผันผวนของราคาสูง
   REGIME_RANGE_CHOPPY,     // แกว่งตัวในกรอบแต่ราคาเหวี่ยงแรงไม่สม่ำเสมอ
   REGIME_BREAKOUT_PREP     // ตลาดเริ่มเงียบเพื่อสะสมแรงก่อนเคลื่อนไหวใหญ่
};

/**
 * โหมดการบริหารความเสี่ยงแบบไดนามิก (Dynamic Risk Modes)
 * ใช้สำหรับปรับระดับความเสี่ยงตามสถานการณ์ของพอร์ต
 */
enum ENUM_RISK_MODE
{
   RISK_MODE_NORMAL = 0,    // สภาวะปกติ: ใช้ความเสี่ยงเต็มอัตราที่ตั้งค่าไว้
   RISK_MODE_DEFENSIVE = 1, // สภาวะป้องกัน: ลดขนาดการเทรดลงเมื่อเริ่มมีการขาดทุนสะสม
   RISK_MODE_RECOVERY = 2   // สภาวะฟื้นฟู: ค่อยๆ เพิ่มขนาดการเทรดกลับคืนเมื่อพอร์ตเริ่มฟื้นตัว
};

/**
 * ทิศทางของสัญญาณเทรด (Signal Directions)
 * ระบุว่าเป็นสัญญาณซื้อ ขาย หรือไม่มีสัญญาณ
 */
enum ENUM_SIGNAL_DIRECTION
{
   SIGNAL_NONE = 0, // ไม่มีทิศทาง (ถือเงินสด)
   SIGNAL_BUY,      // สัญญาณฝั่งซื้อ (Long)
   SIGNAL_SELL      // สัญญาณฝั่งขาย (Short)
};

/**
 * ระดับสิทธิ์ในการอนุญาตเข้าเทรด (Trade Permissions)
 * ผลลัพธ์จากการตรวจสอบความปลอดภัยของพอร์ต
 */
enum ENUM_TRADE_PERMISSION
{
   TRADE_BLOCKED = 0,     // ไม่อนุญาตให้เปิดออเดอร์ (เนื่องจากติดกฎความปลอดภัย)
   TRADE_ALLOWED,         // อนุญาตให้เทรดได้ตามปกติ
   TRADE_REDUCED_SIZE     // อนุญาตให้เทรดได้แต่ต้องลดขนาดลอตลงเพื่อความปลอดภัย
};

// --- การกำหนดโครงสร้างข้อมูล (Structures) ---

/**
 * MarketSnapshot: สรุปข้อมูลดิบและตัวชี้วัดทางเทคนิคของตลาดรายคู่เงิน
 * ใช้เก็บข้อมูลสถานะปัจจุบันของตลาดเพื่อนำไปวิเคราะห์ต่อ
 */
struct MarketSnapshot
{
   string symbol;          // ชื่อคู่เงิน (เช่น EURUSD)
   datetime time;          // เวลาที่บันทึกข้อมูล
   double bid;             // ราคาเสนอซื้อปัจจุบัน
   double ask;             // ราคาเสนอขายปัจจุบัน
   double spread_points;   // ค่าส่วนต่างราคาในหน่วยจุด (Point)
   double atr;             // ค่าความผันผวนเฉลี่ย (Average True Range)
   double atr_percentile;  // ระดับความผันผวนคิดเป็นเปอร์เซ็นไทล์เทียบกับประวัติ
   double adx;             // ดัชนีทิศทางเฉลี่ย (ความแรงของแนวโน้ม)
   double adx_slope;       // ความชันของ ADX (บ่งบอกการเร่งหรือชะลอของแรง)
   double rsi;             // ดัชนีกำลังสัมพัทธ์ (Relative Strength Index)
   double roc;             // อัตราการเปลี่ยนแปลงราคา (Rate of Change)
   double obv;             // ปริมาณการซื้อขายสะสม (On-Balance Volume)
   double obv_slope;       // ความชันของ OBV (บ่งบอกแรงซื้อขายแฝง)
   double ema_fast;        // ค่าเฉลี่ยเคลื่อนที่แบบเร็ว (Exponential Moving Average)
   double ema_slow;        // ค่าเฉลี่ยเคลื่อนที่แบบช้า
   double ema_slope;       // ความชันของเส้นค่าเฉลี่ย (บอกแนวโน้มปัจจุบัน)
   double bb_upper;        // ขอบบน Bollinger Bands
   double bb_lower;        // ขอบล่าง Bollinger Bands
   double bb_mid;          // เส้นกลาง Bollinger Bands
   double donchian_high;   // ราคาสูงสุดในช่วง Donchian Channel
   double donchian_low;    // ราคาต่ำสุดในช่วง Donchian Channel
   double zscore;          // ค่าสถิติบ่งบอกความผิดปกติของราคาเทียบกับค่าเฉลี่ย
   double htf_trend;       // แนวโน้มจากไทม์เฟรมใหญ่ (Higher Timeframe)
   long   volume;          // ปริมาณการซื้อขายในปัจจุบัน
   double dom_imbalance;   // ความไม่สมดุลของปริมาณคำสั่งซื้อ/ขายใน Order Book
   double bid_depth_total; // ผลรวมปริมาณคำสั่งซื้อใน Market Depth
   double ask_depth_total; // ผลรวมปริมาณคำสั่งขายใน Market Depth
   double vol_median;      // ค่ากลางของปริมาณการซื้อขายย้อนหลัง
   double atr_median;      // ค่ากลางของความผันผวนย้อนหลัง
};

/**
 * PairSnapshot: ข้อมูลความสัมพันธ์ระหว่างคู่เงินสองคู่ (Correlation/Spread Analysis)
 * ใช้สำหรับการวิเคราะห์ความสัมพันธ์และหาโอกาสเทรดจากส่วนต่างราคา
 */
struct PairSnapshot
{
   string symbol_a;        // สัญลักษณ์คู่ที่ 1
   string symbol_b;        // สัญลักษณ์คู่ที่ 2
   double price_a;         // ราคาคู่ที่ 1
   double price_b;         // ราคาคู่ที่ 2
   double ratio;           // อัตราส่วนราคาระหว่างคู่ A และ B
   double ratio_zscore;    // ความผิดปกติของอัตราส่วนราคาปัจจุบันเทียบกับค่าเฉลี่ย
};

/**
 * SignalPack: รายละเอียดทั้งหมดของสัญญาณเทรดที่ผ่านการวิเคราะห์แล้ว
 * รวบรวมข้อมูลที่จำเป็นสำหรับการเปิดออเดอร์
 */
struct SignalPack
{
   string symbol;          // คู่เงินที่เกิดสัญญาณ
   ENUM_SIGNAL_DIRECTION direction; // ทิศทางสัญญาณ (Buy/Sell)
   double score;           // คะแนนความน่าจะเป็น (0.0 - 1.0)
   double confidence;      // ความมั่นใจของระบบวิเคราะห์ (0.0 - 1.0)
   double entry_price;     // ระดับราคาที่ควรเข้าเทรด
   double stop_price;      // ระดับราคาตัดขาดทุน (Stop Loss)
   double take_profit_price; // ระดับราคาทำกำไร (Take Profit)
   double risk_r;          // สัดส่วนกำไรต่อความเสี่ยง (RRR)
   string engine_name;     // ชื่อโมดูลวิเคราะห์ที่สร้างสัญญาณนี้
   string reason;          // เหตุผลประกอบการตัดสินใจของสัญญาณ

   // --- SMC Integration Fields ---
   // ใช้เป็น input tensor ให้ ONNX (input[4]–[7]) และ NeuralBridge (TRN/INF message)
   // ต้อง populate จาก SMCContext ก่อน ResolveSignals() เสมอ
   double smc_bias;         // ทิศทาง SMC หลัก: BEARISH=-1, NEUTRAL=0, BULLISH=1 (จาก ENUM_SMC_BIAS)
   double smc_zone;         // โซนราคาปัจจุบัน: UNKNOWN=0, DISCOUNT=1, EQUILIBRIUM=2, PREMIUM=3
   double smc_buy_quality;  // คะแนนคุณภาพการเทรดฝั่งซื้อจาก SMC (0.0 – 1.0)
   double smc_sell_quality; // คะแนนคุณภาพการเทรดฝั่งขายจาก SMC (0.0 – 1.0)
};

/**
 * RiskDecision: ผลลัพธ์จากการประเมินความเสี่ยงและคำนวณเงินทุน
 * ใช้กำหนดขนาดลอตและความเสี่ยงที่เป็นเงินจริง
 */
struct RiskDecision
{
   bool allowed;           // อนุญาตให้เทรดไม้สัญลักษณ์นี้หรือไม่
   double lots;            // ขนาดลอตที่ผ่านการคำนวณและ Normalize แล้ว
   double risk_money;      // จำนวนเงินสูงสุดที่จะเสียหายหากชน SL
   double expected_loss;   // การขาดทุนที่คาดหวังตามโมเดลความน่าจะเป็น
   string reason;          // เหตุผลสนับสนุนการตัดสินใจด้านความเสี่ยง
};

/**
 * LimitGateResult: สรุปผลการตรวจสอบกฎเหล็กความปลอดภัยในทุกลำดับชั้น
 * ใช้ควบคุมไม่ให้พอร์ตมีความเสี่ยงเกินขีดจำกัด
 */
struct LimitGateResult
{
   bool portfolio_pass;      // ผ่านเกณฑ์ความปลอดภัยพอร์ตโดยรวมหรือไม่
   bool exposure_cap_pass;   // ไม่เกินขีดจำกัดการถือครองสินทรัพย์รวมหรือไม่
   bool heat_cap_pass;       // ไม่เกินขีดจำกัดความเสี่ยงรวมของพอร์ตหรือไม่
   bool price_clustering_pass; // ผ่านเกณฑ์การไม่กระจุกตัวของราคาหรือไม่
   bool max_positions_pass;  // ไม่เกินจำนวนออเดอร์สูงสุดต่อหนึ่งคู่เงินหรือไม่

   double exposure_actual;   // มูลค่าการถือครองจริงปัจจุบัน
   double exposure_max;      // ขีดจำกัดมูลค่าถือครองสูงสุด
   double heat_actual;       // ความเสี่ยงรวมจริงในปัจจุบัน
   double heat_max;          // ขีดจำกัดความเสี่ยงรวมสูงสุด
   
   string exp_fail_reason;   // ข้อความระบุสาเหตุถ้าไม่ผ่านเกณฑ์ Exposure
   string heat_fail_reason;  // ข้อความระบุสาเหตุถ้าไม่ผ่านเกณฑ์ Risk Heat
};

/**
 * ประเภทของอัลกอริทึมการส่งคำสั่งซื้อขาย (Execution Algorithm Types)
 * กำหนดรูปแบบการส่งคำสั่งเข้าสู่ตลาด
 */
enum ENUM_ALGO_TYPE
{
   ALGO_NONE = 0,     // การส่งคำสั่งไม้เดียวปกติ (Standard Entry)
   ALGO_ICEBERG,      // ระบบ Iceberg: การแบ่งไม้ใหญ่เป็นไม้เล็กทยอยส่งเพื่อซ่อนขนาดจริง
   ALGO_TWAP,         // ระบบ TWAP: การกระจายส่งตามช่วงเวลาคงที่
   ALGO_VWAP          // ระบบ VWAP: การส่งตามสัดส่วนวอลลุ่มของตลาดจริง
};

/**
 * สถานะการทำงานของโมดูลวิเคราะห์ (Engine Status)
 * ระบุว่าแต่ละกลยุทธ์อยู่ในสถานะใด (เช่น ทำงานอยู่ หรือหยุดพัก)
 */
enum ENUM_ENGINE_STATUS
{
   ENGINE_ACTIVE = 0,                // ทำงานปกติ ค้นหาสัญญาณต่อเนื่อง
   ENGINE_PAUSED_BY_ROLLING_PF = 1,  // หยุดพักชั่วคราวเนื่องจากผลงานล่าสุด (PF) ลดต่ำลง
   ENGINE_DISABLED_BY_CONFIG = 2,    // ถูกปิดใช้งานโดยผู้ใช้ในการตั้งค่า
   ENGINE_DISABLED_BY_GUARD = 3,     // ถูกปิดโดยระบบป้องกันความปลอดภัยอัตโนมัติ
   ENGINE_COOLDOWN = 4               // อยู่ในระยะพักงานหลังจากเพิ่งจบไม้เทรดไป
};

/**
 * รายละเอียดเชิงลึกของเหตุผลการปิดออเดอร์ (Close Reason Details)
 * ใช้สำหรับนำไปทำ Statistical Analysis เพื่อปรับปรุงระบบ
 */
enum ENUM_KNARES_CLOSE_DETAIL
{
   CLOSE_HARD_SL_LOSS = 0,        // ปิดเพราะชนจุดตัดขาดทุนเริ่มต้น (Hard SL)
   CLOSE_SL_BREAKEVEN = 1,        // ปิดเท่าทุน (ขยับ SL มาบังทุนสำเร็จ)
   CLOSE_SL_PROFIT_LOCK = 2,      // ปิดโดยระบบล็อคกำไร (Profit Lock)
   CLOSE_SL_TRAILING = 3,         // ปิดโดยระบบเลื่อนจุดตัดขาดทุน (Standard Trailing)
   CLOSE_SL_ACCELERATED_TRAILING = 4, // ปิดโดยระบบ Trailing แบบเร่งความเร็ว
   CLOSE_TP = 5,                  // ปิดเมื่อราคาพุ่งชนเป้าหมายกำไรเต็มจำนวน (Take Profit)
   CLOSE_PARTIAL_TP = 6,          // แบ่งขายทำกำไรเพียงบางส่วน
   CLOSE_REGIME_EXIT = 7,         // ปิดเพราะสภาวะตลาดเปลี่ยนทิศทางไปจากเดิม
   CLOSE_TIMEOUT = 8,             // ปิดเพราะถือออเดอร์นานเกินเวลาที่กำหนดไว้
   CLOSE_VOL_SHOCK_EXIT = 9,      // ปิดเพื่อหนีความผันผวนที่รุนแรงผิดปกติ (วิกฤต)
   CLOSE_GLOBAL_PROFIT_EXIT = 10, // ปิดเพราะกำไรรวมของทุกคู่เงินถึงเป้าหมายรวมที่ตั้งไว้
   CLOSE_EARLY_INVALIDATION = 11, // ปิดก่อนกำหนดเนื่องจากโครงสร้างราคาเริ่มเสียทรง
   CLOSE_OTHER = 99               // ปิดด้วยสาเหตุอื่นๆ (เช่น ผู้ใช้ปิดเองด้วยมือ)
};

/**
 * ประเภทของการดำเนินการในการจัดการออเดอร์ที่ถืออยู่ (Exit Actions)
 * กำหนดรูปแบบการจัดการออเดอร์ที่เปิดอยู่
 */
enum ENUM_EXIT_ACTION
{
   EXIT_ACTION_NONE = 0,          // ไม่มีการดำเนินการใดๆ
   EXIT_ACTION_CLOSE_FORCED,      // บังคับปิดทันที (ความสำคัญสูงสุด)
   EXIT_ACTION_CLOSE_REGIME,      // ปิดตามการเปลี่ยนแปลงของสภาวะตลาด
   EXIT_ACTION_CLOSE_EARLYINV,    // ปิดเนื่องจากสัญญาณเริ่มผิดเพี้ยนไปจากเดิม
   EXIT_ACTION_MOD_PROFITLOCK,    // แก้ไขออเดอร์เพื่อขยับจุดล็อคกำไร
   EXIT_ACTION_MOD_PARTIAL,       // ดำเนินการแบ่งปิดกำไรหรือขยับมาคุ้มทุน
   EXIT_ACTION_MOD_ATR_TRAIL      // แก้ไข SL ตามค่าความผันผวน ATR
};

/**
 * ExitIntent: โครงสร้างบันทึกแผนการดำเนินการกับออเดอร์ (Decision Packet)
 * ใช้สื่อสารระหว่างฝ่ายวิเคราะห์การออกและฝ่ายดำเนินการจัดการออเดอร์
 */
struct ExitIntent
{
   ENUM_EXIT_ACTION action; // รูปแบบการดำเนินการที่เลือก
   int    priority;         // ลำดับความสำคัญของการตัดสินใจ (สูงกว่าจะได้รับเลือกก่อน)
   double new_sl;           // ระดับราคา SL ใหม่ (กรณีมีการแก้ไข)
   double new_tp;           // ระดับราคา TP ใหม่ (กรณีมีการแก้ไข)
   string reason;           // คำอธิบายเหตุผลในการตัดสินใจ
   string comment;          // คอมเมนต์ที่จะระบุในออเดอร์เมื่อมีการส่งคำสั่ง
};

/**
 * AlgoOrderState: โครงสร้างข้อมูลสำหรับติดตามสถานะการทำงานของคำสั่งซื้อขายแบบอัลกอริทึม
 * เก็บข้อมูลความคืบหน้าของการส่งไม้ย่อย (Iceberg)
 */
struct AlgoOrderState
{
   string symbol;               // ชื่อคู่เงิน
   ENUM_SIGNAL_DIRECTION direction; // ทิศทาง (Buy/Sell)
   ENUM_ALGO_TYPE type;         // ประเภทอัลกอริทึม (เช่น Iceberg)
   double total_lots;           // ขนาดลอตรวมทั้งหมดที่ต้องการเปิด
   double filled_lots;          // ขนาดลอตที่เปิดสำเร็จไปแล้ว
   double remaining_lots;       // ขนาดลอตที่ยังคงเหลือรอเปิด
   double slice_lots;           // ขนาดลอตเฉลี่ยต่อหนึ่งไม้ย่อย
   double limit_price;          // ราคาจำกัดที่อนุญาตให้ส่งคำสั่ง (ถ้ามี)
   double sl;                   // ราคา Stop Loss สำหรับแต่ละไม้ย่อย
   double tp;                   // ราคา Take Profit สำหรับแต่ละไม้ย่อย
   double stop_distance;        // ระยะ SL ในหน่วยราคาดิบ
   double tp_distance;          // ระยะ TP ในหน่วยราคาดิบ
   double max_slippage_points;  // ค่า Slippage สูงสุดที่ยอมให้แต่ละไม้ย่อย
   int    total_slices;         // จำนวนไม้ย่อยที่วางแผนไว้ทั้งหมด
   int    filled_slices;        // จำนวนไม้ย่อยที่ส่งไปแล้ว
   datetime next_execution;     // เวลาที่จะส่งไม้ย่อยครั้งถัดไป
   bool   is_active;            // สถานะการทำงานปัจจุบัน (กำลังรัน/จบแล้ว)
   string engine_name;          // ชื่อ Engine ที่เป็นเจ้าของแผนการเทรดนี้
   int    random_seed;          // ค่าสุ่มเพื่อสร้างความไม่แน่นอนในการเทรด (กันการโดนจับทาง)
   int    invalid_stops_streak; // จำนวนครั้งที่การส่งคำสั่งผิดพลาดต่อเนื่อง
   datetime cooldown_until;     // เวลาที่จะระงับการส่งชั่วคราวกรณีเกิดปัญหา
};

/**
 * ExposureInfo: โครงสร้างข้อมูลสำหรับเก็บสถานะการถือครองหลักทรัพย์ (Exposure)
 */
struct ExposureInfo
{
   double actual;    // มูลค่าการถือครองปัจจุบัน
   double projected; // มูลค่าการถือครองที่คาดการณ์ (รวมไม้ใหม่)
   double max;       // ขีดจำกัดสูงสุดที่อนุญาต
};

/**
 * HeatInfo: โครงสร้างข้อมูลสำหรับเก็บสถานะความเสี่ยงรวมของพอร์ต (Portfolio Heat)
 */
struct HeatInfo
{
   double actual;    // ความเสี่ยงปัจจุบัน
   double projected; // ความเสี่ยงที่คาดการณ์ (รวมไม้ใหม่)
   double max;       // ขีดจำกัดสูงสุดที่อนุญาต
};

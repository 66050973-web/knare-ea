#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "RegimeClassifier.mqh"
#include "MarketData.mqh"
#include "FeatureEngine.mqh"

//+------------------------------------------------------------------+
//| Sample Export - บันทึกข้อมูลสำหรับฝึกโมเดล (ฟีเจอร์ตอนเข้า + ผลตอนออก)   |
//| เขียน 2 ไฟล์ใน Common\Files\KNARES_Research:                          |
//|   Entry_<symbol>_<tag>.csv  หนึ่งแถวต่อออเดอร์ที่เปิด (ฟีเจอร์ ณ จุดเข้า)   |
//|   Exit_<symbol>_<tag>.csv   หนึ่งแถวต่อดีลปิด (ปิดบางส่วนได้หลายแถว)       |
//| นำสองไฟล์มา join ด้วย PosId แล้วคำนวณ R = sum(Pnl) / RiskMoney          |
//+------------------------------------------------------------------+

bool g_sample_inited = false; // ล้างไฟล์เก่าครั้งเดียวต่อการรัน (เฉพาะ Strategy Tester)

string SampleFileName(const string kind, const string symbol)
{
   string tag = SampleExportTag;
   StringReplace(tag, "\r", "");
   StringReplace(tag, "\n", "");
   StringTrimLeft(tag);
   StringTrimRight(tag);
   if(tag == "") tag = "run";
   return "KNARES_Research\\" + kind + "_" + symbol + "_" + tag + ".csv";
}

void SampleAppend(const string kind, const string symbol, const string header, const string row)
{
   FolderCreate("KNARES_Research", FILE_COMMON);

   if(!g_sample_inited)
   {
      g_sample_inited = true;
      if(MQLInfoInteger(MQL_TESTER))
      {
         FileDelete(SampleFileName("Entry", symbol), FILE_COMMON);
         FileDelete(SampleFileName("Exit", symbol), FILE_COMMON);
      }
   }

   string fname = SampleFileName(kind, symbol);
   int h = FileOpen(fname, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) { LogWarning(StringFormat("SampleExport: FileOpen failed (%s) err=%d", fname, GetLastError())); return; }
   if(FileSize(h) == 0) FileWriteString(h, header + "\r\n");
   FileSeek(h, 0, SEEK_END);
   uint wrote = FileWriteString(h, row + "\r\n");
   FileClose(h);
   static int dbg = 0;
   if(dbg < 3) { dbg++; Print("SampleExport DEBUG kind=", kind, " file=", fname, " wrote=", wrote, " err=", GetLastError(), " tester=", MQLInfoInteger(MQL_TESTER)); }
}

string SampleNum(const double v, const int digits = 6)
{
   return MathIsValidNumber(v) ? DoubleToString(v, digits) : "0";
}

/**
 * SampleExportEntry: เรียกทันทีหลังส่งคำสั่งเปิดออเดอร์สำเร็จ
 * บันทึกฟีเจอร์ ณ จุดเข้า รวมฟีเจอร์ 8 ตัวที่ ONNX รับ (ADX, RSI, ATR*1000/ask, EMA diff, SMC x4)
 * และฟีเจอร์สัมพัทธ์เพิ่มเติม เพื่อไม่ให้โมเดลเพี้ยนเมื่อระดับราคาทองเปลี่ยน
 */
void SampleExportEntry(const ulong pos_id, const SignalPack &signal, const RiskDecision &risk, const double fill_price)
{
   if(!EnableSampleExport || pos_id == 0) return;

   MarketSnapshot s;
   if(!GetMarketSnapshot(signal.symbol, s)) { LogWarning("SampleExport: GetMarketSnapshot failed"); return; }
   ComputeFeatures(signal.symbol, s);

   double ref   = (s.ask > 0.0) ? s.ask : fill_price;
   double atr   = s.atr;
   double bbw   = s.bb_upper - s.bb_lower;
   double dcw   = s.donchian_high - s.donchian_low;
   double px    = (fill_price > 0.0) ? fill_price : ref;
   double dir   = (signal.direction == SIGNAL_BUY) ? 1.0 : -1.0;

   string header = "Time,PosId,Symbol,TF,Engine,Dir,Regime,Score,Confidence,Entry,SL,TP,RiskMoney,Lots,SpreadPts,"
                   "ADX,ADXSlope,RSI,ROC,ATR,ATRx1000,ATRPercentile,EMADiff,EMADiffATR,EMASlopePct,BBPos,BBWidthATR,"
                   "DonchianPos,DonchianWidthATR,ZScore,HTFTrend,OBVSlope,VolRatio,SLDistATR,"
                   "SMCBias,SMCZone,SMCBuyQ,SMCSellQ";

   string row = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "," + (string)pos_id + "," + signal.symbol + "," +
                EnumToString(MainTF) + "," + signal.engine_name + "," + (string)((int)dir) + "," +
                (string)((int)DetectRegime(s)) + "," +
                SampleNum(signal.score, 4) + "," + SampleNum(signal.confidence, 4) + "," +
                SampleNum(px, 5) + "," + SampleNum(signal.stop_price, 5) + "," + SampleNum(signal.take_profit_price, 5) + "," +
                SampleNum(risk.risk_money, 2) + "," + SampleNum(risk.lots, 2) + "," + SampleNum(s.spread_points, 1) + "," +
                SampleNum(s.adx, 3) + "," + SampleNum(s.adx_slope, 4) + "," + SampleNum(s.rsi, 3) + "," + SampleNum(s.roc, 5) + "," +
                SampleNum(atr, 5) + "," + SampleNum(ref > 0.0 ? atr / ref * 1000.0 : 0.0, 5) + "," + SampleNum(s.atr_percentile, 4) + "," +
                SampleNum(s.ema_fast - s.ema_slow, 5) + "," + SampleNum(atr > 0.0 ? (s.ema_fast - s.ema_slow) / atr : 0.0, 5) + "," +
                SampleNum(s.ema_slope, 5) + "," +
                SampleNum(bbw > 0.0 ? (px - s.bb_lower) / bbw : 0.5, 5) + "," + SampleNum(atr > 0.0 ? bbw / atr : 0.0, 5) + "," +
                SampleNum(dcw > 0.0 ? (px - s.donchian_low) / dcw : 0.5, 5) + "," + SampleNum(atr > 0.0 ? dcw / atr : 0.0, 5) + "," +
                SampleNum(s.zscore, 5) + "," + SampleNum(s.htf_trend, 1) + "," + SampleNum(s.obv_slope, 3) + "," +
                SampleNum(s.vol_median > 0.0 ? (double)s.volume / s.vol_median : 0.0, 4) + "," +
                SampleNum(atr > 0.0 ? MathAbs(px - signal.stop_price) / atr : 0.0, 4) + "," +
                SampleNum(signal.smc_bias, 1) + "," + SampleNum(signal.smc_zone, 1) + "," +
                SampleNum(signal.smc_buy_quality, 4) + "," + SampleNum(signal.smc_sell_quality, 4);

   SampleAppend("Entry", signal.symbol, header, row);
}

/**
 * SampleExportExit: เรียกทุกครั้งที่มีดีลปิด (ENTRY_OUT) บันทึกกำไรสุทธิ (รวมค่าคอม/swap) และเหตุผลที่ปิด
 */
void SampleExportExit(const ulong pos_id, const string symbol, const datetime t, const double volume,
                      const double price, const double pnl, const long deal_reason, const int close_reason_idx,
                      const string comment)
{
   if(!EnableSampleExport || pos_id == 0) return;

   string header = "Time,PosId,Symbol,Volume,Price,Pnl,DealReason,CloseReasonIdx,Comment";
   string c = comment;
   StringReplace(c, ",", ";");
   string row = TimeToString(t, TIME_DATE|TIME_SECONDS) + "," + (string)pos_id + "," + symbol + "," +
                SampleNum(volume, 2) + "," + SampleNum(price, 5) + "," + SampleNum(pnl, 2) + "," +
                (string)deal_reason + "," + (string)close_reason_idx + "," + c;
   SampleAppend("Exit", symbol, header, row);
}

//+------------------------------------------------------------------+
//| Feature Export Module - ระบบส่งออกข้อมูลเพื่อนำไปสอน AI (ML Training) |
//| ทำหน้าที่: บันทึกข้อมูล Snapshot ตลาดและผลการเทรดจริงลงในไฟล์ CSV        |
//| เพื่อใช้เป็น Dataset สำหรับการฝึกสอนหรือปรับปรุงโมเดล Machine Learning |
//+------------------------------------------------------------------+

/**
 * ExportFeatures: ฟังก์ชันสำหรับบันทึกชุดข้อมูล (Features & Labels) ลงในไฟล์
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบและสร้างโฟลเดอร์ "KNARES_Research" ในพื้นที่จัดเก็บข้อมูลของ Terminal
 * 2. กำหนดชื่อไฟล์แยกตามคู่เงิน (เช่น Features_GOLD.csv)
 * 3. เปิดไฟล์ในโหมด CSV (ถ้าเป็นไฟล์ใหม่จะเขียนหัวตาราง Header ก่อน)
 * 4. บันทึกข้อมูลสำคัญ 8 รายการ:
 *    - Time: เวลาที่เกิดสัญญาณ
 *    - ADX: ความแข็งแกร่งของเทรนด์
 *    - RSI: โมเมนตัมของราคา
 *    - ATR_Pct: ความผันผวนในเชิงเปอร์เซ็นต์ (Normalized)
 *    - EMA_Diff: ระยะห่างระหว่างเส้นค่าเฉลี่ย
 *    - Regime: สภาวะตลาด ณ ตอนนั้น (Trend/Range/etc.)
 *    - SignalDir: ทิศทางที่เข้าเทรด (Buy/Sell)
 *    - Result_R: ผลลัพธ์กำไร/ขาดทุนในหน่วย R-Multiple (ใช้เป็น Label สำหรับ ML)
 * 5. ปิดไฟล์เพื่อบันทึกข้อมูลลง Disk
 */
void ExportFeatures(const MarketSnapshot &features, ENUM_SIGNAL_DIRECTION dir, double result_r)
{
   string folder = "KNARES_Research";
   
   // 1. ตรวจสอบหรือสร้างโฟลเดอร์สำหรับเก็บข้อมูลการวิจัย ถ้าสร้างไม่ได้ให้หยุดทำงาน
   if(!FolderCreate(folder, TERMINAL_DATA_PATH)) return;

   // 2. กำหนดชื่อไฟล์ตามสัญลักษณ์คู่เงินที่เทรด
   string filename = folder + "\\Features_" + _Symbol + ".csv";
   bool file_exists = FileIsExist(filename);

   // 3. เปิดไฟล์เพื่อเขียนข้อมูลต่อท้าย (Append mode)
   int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(handle != INVALID_HANDLE)
   {
      // 4. กรณีเป็นไฟล์ใหม่ ให้เขียนหัวตาราง (CSV Header) เพื่อให้โปรแกรม ML อ่านได้ง่าย
      if(!file_exists)
      {
         FileWrite(handle, 
            "Time", "ADX", "RSI", "ATR_Pct", "EMA_Diff", "Regime", "SignalDir", "Result_R");
      }

      // เลื่อนตัวชี้ตำแหน่งไปที่ท้ายไฟล์เพื่อเขียนข้อมูลใหม่
      FileSeek(handle, 0, SEEK_END);

      // 5. บันทึกข้อมูลคุณลักษณะตลาด (Features) และผลลัพธ์ (Label) ลงในแถวใหม่
      FileWrite(handle,
         TimeToString(features.time),                             // วันเวลาที่บันทึก
         DoubleToString(features.adx, 2),                         // ค่าความแรงของเทรนด์
         DoubleToString(features.rsi, 2),                         // ค่า RSI
         DoubleToString(features.ask > 0 ? (features.atr / features.ask * 100.0) : 0, 4), // ความผันผวนสัมพัทธ์
         DoubleToString(features.ema_fast - features.ema_slow, 5), // ระยะห่างของเส้นค่าเฉลี่ย
         (string)DetectRegime(features),                          // ประเภทสภาวะตลาด
         (string)dir,                                             // ทิศทาง Buy=1, Sell=2
         DoubleToString(result_r, 2)                              // ผลลัพธ์กำไรขาดทุนในหน่วย R
      );

      // 6. ปิดไฟล์เพื่อความปลอดภัยของข้อมูล
      FileClose(handle);
   }
}

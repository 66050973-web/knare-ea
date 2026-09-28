#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "RegimeClassifier.mqh"

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

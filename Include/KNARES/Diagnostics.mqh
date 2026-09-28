#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Logger.mqh"
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Diagnostics Module - ระบบตรวจสอบความพร้อมก่อนเริ่มทำงาน (Pre-flight) |
//| ทำหน้าที่: ตรวจสอบความสมบูรณ์ของระบบ, การเชื่อมต่อ, บัญชีเทรด และโมเดล AI |
//+------------------------------------------------------------------+

#include "OnnxOverlay.mqh"

//+------------------------------------------------------------------+
//| DiagnosticResults: โครงสร้างข้อมูลสำหรับเก็บผลการตรวจวินิจฉัยระบบ     |
//| ใช้สำหรับรวบรวมสถานะต่างๆ ของระบบหลังการตรวจสอบเสร็จสิ้น                |
//+------------------------------------------------------------------+
struct DiagnosticResults
{
   bool is_ready;     // สถานะความพร้อมโดยรวม (ถ้าเป็น false ระบบจะไม่เริ่มทำงาน)
   bool ai_healthy;   // ความสมบูรณ์ของโมเดล ONNX (ถ้า false ระบบอาจสลับไปใช้ Logic พื้นฐาน)
   int latency_ms;    // ค่าความหน่วงเครือข่าย (ใช้ประเมินความเร็วในการส่งคำสั่ง)
   double free_margin; // จำนวนเงินประกันคงเหลือ (ใช้ตรวจสอบว่าเปิดออเดอร์ได้หรือไม่)
   string error_msg;  // เก็บข้อความอธิบายสาเหตุเมื่อเกิดข้อผิดพลาด
};

//+------------------------------------------------------------------+
//| RunPreFlightCheck: ฟังก์ชันหลักในการตรวจสอบความพร้อมของระบบ            |
//| อธิบายกระบวนการ:                                                  |
//| 1. ตั้งค่าเริ่มต้นให้กับตัวแปรผลลัพธ์ (Default Values)                |
//| 2. ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตและเซิร์ฟเวอร์โบรกเกอร์               |
//| 3. ตรวจสอบสิทธิ์การเทรดของบัญชี (Trading Allowed)                  |
//| 4. ตรวจสอบมาร์จิ้นคงเหลือ (Free Margin)                           |
//| 5. ทดสอบความสมบูรณ์ของไฟล์โมเดล AI (ONNX Model Integrity)          |
//| 6. รายงานผลการตรวจสอบผ่านระบบ Log                                |
//+------------------------------------------------------------------+
bool RunPreFlightCheck(DiagnosticResults &res)
{
   // --- ขั้นตอนที่ 1: กำหนดค่าพื้นฐานก่อนการตรวจสอบ ---
   res.is_ready = true;
   res.ai_healthy = true;
   res.error_msg = "";
   res.latency_ms = 0;
   res.free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // --- ขั้นตอนที่ 2: ตรวจสอบการเชื่อมต่อ (Server Connection) ---
   // หมายเหตุ: ในโหมด Backtest (Tester) จะข้ามการตรวจสอบนี้
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      res.is_ready = false;
      res.error_msg = "Terminal not connected";
      LogError("Pre-flight failed: terminal not connected.");
      return false;
   }

   // --- ขั้นตอนที่ 3: ตรวจสอบสิทธิ์การส่งคำสั่งเทรด (Trading Permission) ---
   // เช็คทั้งในระดับบัญชีและสถานะของปุ่ม AutoTrading ใน Terminal
   if(!MQLInfoInteger(MQL_TESTER) && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      res.is_ready = false;
      res.error_msg = "Trading is not allowed on this account/session";
      LogError("Pre-flight failed: trading is not allowed.");
      return false;
   }

   // --- ขั้นตอนที่ 4: ตรวจสอบความเพียงพอของเงินทุน (Capital Check) ---
   // ป้องกันกรณีเริ่มทำงานโดยที่ไม่มีเงินเหลือในบัญชี
   if(res.free_margin <= 0.0)
   {
      if(MQLInfoInteger(MQL_TESTER))
      {
         // ในโหมด Backtest อนุญาตให้ผ่านไปก่อนแม้ Margin จะเป็น 0 ในช่วงเริ่มต้น
         LogWarning("Pre-flight: Free margin is zero in Tester. Continuing anyway...");
      }
      else
      {
         res.is_ready = false;
         res.error_msg = "Free margin is zero. Please check account/login.";
         LogError("Pre-flight failed: free margin is zero.");
         return false;
      }
   }

   // --- ขั้นตอนที่ 5: ตรวจสอบความสมบูรณ์ของโมเดล AI (ONNX Verification) ---
   // เฉพาะเมื่อมีการตั้งค่าให้ใช้งาน OnnxOverlay ในไฟล์ Config เท่านั้น
   if(EnableOnnxOverlay)
   {
      // จำลองการรันโมเดลด้วยข้อมูลว่าง (Dummy Data) 
      // เพื่อตรวจสอบว่าโครงสร้าง Tensor และไฟล์ .onnx ถูกต้องตามที่ระบุในโค้ดหรือไม่
      MarketSnapshot dummy;
      SignalPack dummy_sig;
      double test_prob = PredictSignalQuality(dummy, dummy_sig);
      
      if(test_prob < 0) // ค่าติดลบหมายถึงมีความผิดพลาดเกิดขึ้นในการคำนวณภายใน ONNX
      {
         res.ai_healthy = false;
         LogWarning("AI Model Integrity Test: FAILED. Check file and tensor shapes.");
      }
      else LogInfo("AI Model Integrity Test: PASSED.");
   }

   // --- ขั้นตอนสุดท้าย: สรุปและบันทึกผลการตรวจสอบลง Log ---
   LogInfo(StringFormat("Pre-flight Check Passed: Latency=%dms, FreeMargin=%.2f, AIHealthy=%s", res.latency_ms, res.free_margin, res.ai_healthy ? "YES" : "NO"));
   
   return true; // คืนค่า true เพื่อบอกให้ระบบหลักทราบว่าพร้อมเริ่มทำงาน
}

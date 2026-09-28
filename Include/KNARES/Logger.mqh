#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"

//+------------------------------------------------------------------+
//| Logging Utilities - ระบบบันทึกข้อมูลและแจ้งเตือน                      |
//| ทำหน้าที่: บันทึกเหตุการณ์สำคัญ, ข้อผิดพลาด และการแจ้งเตือนต่างๆ         |
//| เพื่อช่วยในการตรวจสอบการทำงานของ EA และวิเคราะห์ปัญหาภายหลัง           |
//+------------------------------------------------------------------+

/**
 * LogInfo: บันทึกข้อมูลการทำงานทั่วไป (Information)
 * อธิบายกระบวนการ:
 * 1. แสดงข้อความในหน้าต่าง Experts ของ Terminal ด้วย "KNARES INFO: "
 * 2. เปิดไฟล์ Log (KNARES_Diagnostic_Log.txt) ในโฟลเดอร์ Common (แชร์ได้ทุก Terminal)
 * 3. เลื่อนตัวชี้ไปท้ายไฟล์และบันทึกเวลาพร้อมข้อความ
 * 4. ปิดไฟล์เพื่อบันทึกข้อมูล
 */
void LogInfo(string message)
{
   Print("KNARES INFO: ", message);
   // ใน Strategy Tester ไม่เขียนไฟล์ Common (ช้ามาก และปนกับ log ของ EA ตัวจริง) ใช้ journal ของ tester แทน
   if(MQLInfoInteger(MQL_TESTER)) return;
   // ใช้ FILE_COMMON เพื่อให้ Log นี้เข้าถึงได้จากทุก Instance ของ MT5 บนเครื่องเดียวกัน
   int h = FileOpen("KNARES_Diagnostic_Log.txt", FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "INFO: " + TimeToString(TimeCurrent()) + " | " + message);
      FileClose(h);
   }
}

/**
 * LogWarning: บันทึกข้อความเตือน (Warning)
 * อธิบายกระบวนการ:
 * - ทำงานเหมือน LogInfo แต่ใช้หัวข้อ "KNARES WARNING: " และ "WARN: "
 * - ใช้แจ้งเตือนเหตุการณ์ที่ผิดปกติแต่ยังไม่ถึงขั้นทำให้ระบบหยุดทำงาน
 */
void LogWarning(string message)
{
   Print("KNARES WARNING: ", message);
   // ใน Strategy Tester ไม่เขียนไฟล์ Common (ช้ามาก และปนกับ log ของ EA ตัวจริง) ใช้ journal ของ tester แทน
   if(MQLInfoInteger(MQL_TESTER)) return;
   int h = FileOpen("KNARES_Diagnostic_Log.txt", FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "WARN: " + TimeToString(TimeCurrent()) + " | " + message);
      FileClose(h);
   }
}

/**
 * LogError: บันทึกข้อผิดพลาด (Error)
 * อธิบายกระบวนการ:
 * - ใช้แจ้งเตือนข้อผิดพลาดรุนแรง เช่น การส่งคำสั่งล้มเหลว หรือไฟล์โมเดลหาย
 * - หัวข้อคือ "KNARES ERROR: " และบันทึกลงไฟล์ด้วย "ERROR: "
 */
void LogError(string message)
{
   Print("KNARES ERROR: ", message);
   // ใน Strategy Tester ไม่เขียนไฟล์ Common (ช้ามาก และปนกับ log ของ EA ตัวจริง) ใช้ journal ของ tester แทน
   if(MQLInfoInteger(MQL_TESTER)) return;
   int h = FileOpen("KNARES_Diagnostic_Log.txt", FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "ERROR: " + TimeToString(TimeCurrent()) + " | " + message);
      FileClose(h);
   }
}

/**
 * LogDebug: บันทึกข้อมูลสำหรับการตรวจสอบเชิงลึก (Debugging)
 * อธิบายกระบวนการ:
 * - รับพารามิเตอร์ enable เพื่อควบคุมการแสดงผล
 * - จะแสดงผลในหน้าต่าง Experts เฉพาะเมื่อผู้ใช้เปิดโหมด Debug ในการตั้งค่าเท่านั้น
 */
void LogDebug(string message, bool enable)
{
   if(enable) Print("KNARES DEBUG: ", message);
}

/**
 * SendKNARESAlert: ส่งการแจ้งเตือนแบบ Push Notification
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบว่าผู้ใช้เปิดใช้งาน EnableTradeAlerts และ EnablePushNotifications หรือไม่
 * 2. ตรวจสอบชื่อคู่เงินเพื่อระบุแหล่งที่มาของข้อความ
 * 3. ส่งข้อความไปยังแอป MetaTrader บนมือถือผ่านฟังก์ชัน SendNotification
 * 4. หากส่งไม่สำเร็จ จะบันทึกข้อผิดพลาดลงใน LogError
 */
void SendKNARESAlert(string message)
{
   if(!EnableTradeAlerts) return;
   if(!EnablePushNotifications) return;

   string full_msg = "KNARES [" + _Symbol + "]: " + message;
   
   if(!SendNotification(full_msg))
      LogError("Failed to send Push Notification");
}

/**
 * LogTrade: บันทึกและแจ้งเตือนผลการเทรด
 * อธิบายกระบวนการ:
 * 1. รวบรวมข้อมูล คู่เงิน, การกระทำ (เช่น OPEN/CLOSE) และสถานะ (สำเร็จ/ล้มเหลว)
 * 2. แสดงผลในหน้าต่าง Experts ของ Terminal
 * 3. หากการเทรดสำเร็จ (success=true) จะเรียกฟังก์ชัน SendKNARESAlert เพื่อแจ้งเตือนเข้ามือถือทันที
 */
void LogTrade(string symbol, string action, bool success, string message)
{
   string status = success ? "SUCCESS" : "FAILED";
   string log_msg = StringFormat("TRADE [%s] %s %s: %s", symbol, action, status, message);
   Print("KNARES ", log_msg);
   
   if(success) SendKNARESAlert(log_msg);
}

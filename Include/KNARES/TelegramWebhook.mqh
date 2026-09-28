#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Telegram Webhook Bridge                                          |
//| ทำหน้าที่ส่ง WebRequest ไปยัง Python Flask Server ที่เรารันไว้       |
//+------------------------------------------------------------------+

// ตั้งค่า URL ของ Python Webhook Server (ตรวจสอบว่าตั้งค่าใน Tools -> Options -> Expert Advisors -> Allow WebRequest)
string WEBHOOK_URL = "http://127.0.0.1:5000/webhook";

/**
 * SendTelegramWebhook: ฟังก์ชันยิง WebRequest เพื่อแจ้งเตือน Telegram
 * @param symbol  คู่เงินที่เกิดเหตุการณ์
 * @param action  ประเภทเหตุการณ์ (เช่น BUY, SELL, CLOSE, STOPLOSS)
 * @param message ข้อความรายละเอียดเพิ่มเติม
 * @param profit  กำไรขาดทุน (ถ้ามี)
 */
void SendTelegramWebhook(string symbol, string action, string message, string profit="")
{
   // 1. สร้าง JSON String ด้วยวิธี Manual อย่างง่าย
   string json_payload = StringFormat(
      "{\"symbol\":\"%s\",\"action\":\"%s\",\"message\":\"%s\",\"profit\":\"%s\"}",
      symbol, action, message, profit
   );

   // 2. เตรียม Header และ Timeout
   char post_data[];
   char result[];
   string result_headers;
   string headers = "Content-Type: application/json\r\n";
   int timeout = 3000; // 3 วินาที

   StringToCharArray(json_payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);

   // ลบ Null Terminator ออกจาก Array เพื่อไม่ให้รบกวน JSON Format
   int data_size = ArraySize(post_data);
   if(data_size > 0 && post_data[data_size-1] == 0)
      ArrayResize(post_data, data_size-1);

   // 3. ยิง WebRequest ไปยัง Python Server
   int res = WebRequest("POST", WEBHOOK_URL, headers, timeout, post_data, result, result_headers);
   
   if(res == 200)
   {
      LogInfo("Telegram Webhook sent successfully.");
   }
   else
   {
      LogWarning(StringFormat("Failed to send Webhook. Error: %d (Is Python server running on port 5000?)", GetLastError()));
   }
}

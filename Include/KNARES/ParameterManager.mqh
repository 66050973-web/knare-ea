#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Parameter Manager - ระบบจัดการพารามิเตอร์ประสิทธิภาพสูงสุด (Hot-Reload) |
//+------------------------------------------------------------------+

// โครงสร้างข้อมูลสำหรับเก็บพารามิเตอร์เฉพาะของแต่ละคู่เงิน
struct SymbolParams
{
   string symbol;    // ชื่อคู่เงิน
   int    ema_fast;  // ค่าเฉลี่ย EMA เส้นเร็ว
   int    ema_slow;  // ค่าเฉลี่ย EMA เส้นช้า
   double rsi_low;   // ขอบเขต RSI ล่าง (Oversold)
   double rsi_high;  // ขอบเขต RSI บน (Overbought)
   double atr_mult;  // ตัวคูณ ATR สำหรับคำนวณ Stop Loss/Take Profit
};

// อาร์เรย์เก็บพารามิเตอร์ของทุกคู่เงินที่โหลดเข้ามา
SymbolParams g_symbol_params[];
// ตัวแปรเก็บเวลาการแก้ไขไฟล์ล่าสุด เพื่อใช้ตรวจสอบการเปลี่ยนแปลง
datetime     g_last_param_update = 0;

/**
 * ฟังก์ชันเฝ้าสังเกตการณ์การอัปเดตไฟล์พารามิเตอร์ (Hot-Reload)
 * ตรวจสอบว่าไฟล์พารามิเตอร์ในดิสก์มีการเปลี่ยนแปลงหรือไม่ หากมีจะทำการโหลดใหม่ทันทีโดยไม่ต้องหยุด EA
 */
void MonitorParameterUpdate()
{
   string filename = "KNARES_Params.csv";
   // ตรวจสอบความมีอยู่ของไฟล์ในโฟลเดอร์ Common Files
   if(!FileIsExist(filename, FILE_COMMON)) return;

   // ดึงเวลาแก้ไขล่าสุดของไฟล์
   datetime current_mod = (datetime)FileGetInteger(filename, FILE_MODIFY_DATE, FILE_COMMON);
   
   // หากเวลาการแก้ไขล่าสุดเปลี่ยนไป (ใหม่กว่าที่บันทึกไว้) ให้ทำการโหลดข้อมูลใหม่
   if(current_mod > g_last_param_update)
   {
      LogInfo("Hot-Reload Triggered: Updating parameters from disk...");
      if(LoadSymbolParameters())
      {
         g_last_param_update = current_mod;
         SendKNARESAlert("Parameters updated successfully via Hot-Reload.");
      }
   }
}

/**
 * โหลดข้อมูลพารามิเตอร์จากไฟล์ CSV เข้าสู่หน่วยความจำ
 * @return true หากโหลดสำเร็จ, false หากไม่พบไฟล์หรือเกิดข้อผิดพลาด
 */
bool LoadSymbolParameters()
{
   string filename = "KNARES_Params.csv";
   if(!FileIsExist(filename, FILE_COMMON))
   {
      LogWarning("Parameter file not found. Using default Config inputs.");
      return false;
   }

   // เปิดไฟล์ CSV ในโหมดอ่านข้อมูลจากโฟลเดอร์ Common
   int handle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return false;

   // ล้างข้อมูลเดิมในอาร์เรย์
   ArrayResize(g_symbol_params, 0);
   FileReadString(handle); // ข้ามหัวตาราง (Header)

   // อ่านข้อมูลทีละบรรทัดจนจบไฟล์
   while(!FileIsEnding(handle))
   {
      int size = ArraySize(g_symbol_params);
      ArrayResize(g_symbol_params, size + 1);
      
      // อ่านและบันทึกค่าลงในโครงสร้างข้อมูล
      g_symbol_params[size].symbol   = FileReadString(handle);
      g_symbol_params[size].ema_fast = (int)FileReadNumber(handle);
      g_symbol_params[size].ema_slow = (int)FileReadNumber(handle);
      g_symbol_params[size].rsi_low  = FileReadNumber(handle);
      g_symbol_params[size].rsi_high = FileReadNumber(handle);
      g_symbol_params[size].atr_mult = FileReadNumber(handle);
   }

   FileClose(handle);
   LogInfo(StringFormat("Parameter Manager: Loaded custom settings for %d symbols.", ArraySize(g_symbol_params)));
   return true;
}

/**
 * ค้นหาพารามิเตอร์เฉพาะของคู่เงินที่ต้องการ
 * @param symbol ชื่อคู่เงินที่ต้องการหา
 * @param out_params ตัวแปรสำหรับรับค่าพารามิเตอร์ที่ค้นพบ
 * @return true หากพบข้อมูล, false หากไม่พบ
 */
bool GetParamsForSymbol(string symbol, SymbolParams &out_params)
{
   for(int i=0; i<ArraySize(g_symbol_params); i++)
   {
      if(g_symbol_params[i].symbol == symbol)
      {
         out_params = g_symbol_params[i];
         return true;
      }
   }
   return false;
}

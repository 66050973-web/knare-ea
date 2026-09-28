#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Logger.mqh"
#include "HandleCache.mqh"

//+------------------------------------------------------------------+
//| Market Data Module - โมดูลจัดการและวิเคราะห์ข้อมูลตลาด                 |
//| ทำหน้าที่: รวบรวมข้อมูลราคาแบบ Real-time, วิเคราะห์ค่า Spread ย้อนหลัง,     |
//| และตรวจสอบความพร้อมของข้อมูลก่อนเริ่มกระบวนการเทรด                       |
//+------------------------------------------------------------------+

// ตัวแปรสำหรับเก็บประวัติค่า Spread เพื่อนำมาคำนวณค่ากลาง (Median)
// ใช้สำหรับกรองช่วงเวลาที่ตลาดมีความผันผวนสูงหรือ Spread ถ่างผิดปกติ
double spread_history[];
const int max_spread_samples = 100; // จำนวนตัวอย่างที่ใช้คำนวณ Median
double g_last_median_spread_points = 0.0;

/**
 * MarketDataInit: ฟังก์ชันเริ่มต้นการทำงานของโมดูล Market Data
 * อธิบายกระบวนการ:
 * 1. ล้างข้อมูลในอาเรย์ spread_history เพื่อเริ่มเก็บข้อมูลใหม่
 * 2. รีเซ็ตค่ามัธยฐาน (Median) ล่าสุดให้เป็นศูนย์
 */
bool MarketDataInit()
{
   ArrayResize(spread_history, 0);
   g_last_median_spread_points = 0.0;
   LogInfo("MarketData Module initialized: Spread analytics ready.");
   return true;
}

/**
 * MarketDataDeinit: ฟังก์ชันปิดการทำงานของโมดูล
 * อธิบายกระบวนการ:
 * - คืนหน่วยความจำที่ใช้จองอาเรย์ประวัติ Spread เพื่อป้องกัน Memory Leak
 */
void MarketDataDeinit()
{
   ArrayFree(spread_history);
   HC_ReleaseAll();
   LogInfo("MarketData Module deinitialized.");
}

/**
 * IsDataReady: ฟังก์ชันตรวจสอบความพร้อมของข้อมูล (Data Warmup Check)
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบจำนวนแท่งเทียนที่มีอยู่ใน Terminal เทียบกับจำนวนที่ต้องการใช้คำนวณ Indicators
 * 2. ตรวจสอบสถานะการเชื่อมต่อและ Synchronized ของคู่เงินกับ Server ของโบรกเกอร์
 * 3. หากข้อมูลไม่พร้อม (เช่น พึ่งเปิดโปรแกรมใหม่) จะแจ้งเตือนและคืนค่า false เพื่อให้ระบบรอ
 */
bool IsDataReady(string symbol, ENUM_TIMEFRAMES period, int required_bars)
{
   // 1. ตรวจสอบจำนวนแท่งเทียนที่มีอยู่ในประวัติ
   int available_bars = Bars(symbol, period);
   if(available_bars < required_bars)
   {
      LogWarning(StringFormat("Data not ready for %s: Available=%d, Required=%d", symbol, available_bars, required_bars));
      return false;
   }
   
   // 2. ตรวจสอบความถูกต้องของข้อมูล (Sync Check)
   if(!SymbolIsSynchronized(symbol))
   {
      LogWarning("Symbol " + symbol + " is not synchronized.");
      return false;
   }

   return true;
}

/**
 * GetMedianSpread: ฟังก์ชันคำนวณค่ากลาง (Median) ของ Spread แบบ Rolling Window
 * อธิบายกระบวนการ:
 * 1. รับค่า Spread ปัจจุบันเข้าไปเก็บในอาเรย์ spread_history
 * 2. หากข้อมูลเต็ม 100 ค่า จะทำการเลื่อนข้อมูลเก่าที่สุดออก (FIFO)
 * 3. คัดลอกข้อมูลไปยังอาร์เรย์ชั่วคราวเพื่อทำการจัดเรียง (Sort) ตามความกว้างจากน้อยไปมาก
 * 4. หาค่าตรงกลาง (Median) เพื่อใช้เป็นเกณฑ์ตัดสินว่า Spread ปัจจุบัน "ปกติ" หรือ "ถ่าง" เกินไป
 */
double GetMedianSpread(double current_spread)
{
   int size = ArraySize(spread_history);
   
   // จัดการขนาดอาร์เรย์แบบ Rolling Window (เลื่อนข้อมูลเก่าออกเมื่อเต็ม)
   if(size >= max_spread_samples)
      ArrayCopy(spread_history, spread_history, 0, 1, size - 1);
   else
      ArrayResize(spread_history, size + 1);
   
   spread_history[ArraySize(spread_history)-1] = current_spread;

   // ใช้การเรียงลำดับเพื่อหาค่ามัธยฐาน (Median) ซึ่งมีความเสถียรมากกว่าค่าเฉลี่ยปกติ (Average)
   double temp[];
   ArrayCopy(temp, spread_history);
   ArraySort(temp);
   
   int mid = ArraySize(temp) / 2;
   // คำนวณค่าตรงกลาง (มัธยฐาน)
   return (ArraySize(temp) % 2 != 0) ? temp[mid] : (temp[mid-1] + temp[mid]) / 2.0;
}

/**
 * GetTrendDirection: ฟังก์ชันระบุทิศทางแนวโน้มพื้นฐาน (Baseline Trend)
 * อธิบายกระบวนการ:
 * 1. เรียกใช้เส้นค่าเฉลี่ย EMA 20 และ EMA 100
 * 2. ดึงราคาปิดของเส้น EMA ทั้งสองเส้น
 * 3. เปรียบเทียบตำแหน่ง: หากเส้นสั้น (20) อยู่เหนือเส้นยาว (100) = ขาขึ้น (1) หากสลับกัน = ขาลง (-1)
 * 4. ปล่อย Handle อินดิเคเตอร์ทันทีเพื่อลดภาระเครื่อง
 */
int GetTrendDirection(string symbol, ENUM_TIMEFRAMES period)
{
   double ema_fast[];
   double ema_slow[];
   
   // สร้าง Handle สำหรับ EMA 20 (เร็ว) และ 100 (ช้า)
   int h_fast = HC_MA(symbol, period, 20);
   int h_slow = HC_MA(symbol, period, 100);
   
   if(h_fast == INVALID_HANDLE || h_slow == INVALID_HANDLE) return 0;
   
   // คัดลอกราคาล่าสุดจาก Buffer
   if(CopyBuffer(h_fast, 0, 0, 1, ema_fast) <= 0) return 0;
   if(CopyBuffer(h_slow, 0, 0, 1, ema_slow) <= 0) return 0;
   
   // ตัดสินใจทิศทางตามหลักการ EMA Crossover
   int direction = (ema_fast[0] > ema_slow[0]) ? 1 : -1;
   
   // ปล่อย Handle ทันทีหลังใช้งานเสร็จ (Memory Optimization)
   
   return direction;
}

/**
 * GetMarketSnapshot: ฟังก์ชันดึงข้อมูลราคาปัจจุบันและตรวจสอบสถานะสภาพคล่อง
 * อธิบายกระบวนการ:
 * 1. ดึงราคา Bid/Ask ล่าสุดจากระบบ
 * 2. คำนวณค่า Spread ปัจจุบันในหน่วย Points (Tick Size)
 * 3. ส่งค่า Spread ไปอัปเดตในระบบ Median Analytics (GetMedianSpread)
 * 4. บันทึกผลลัพธ์ลงในโครงสร้างข้อมูล MarketSnapshot เพื่อให้โมดูลอื่นใช้งานต่อ
 */
bool GetMarketSnapshot(string symbol, MarketSnapshot &snapshot)
{
   MqlTick tick;
   // ดึงข้อมูลราคา Tick ล่าสุด
   if(!SymbolInfoTick(symbol, tick)) return false;

   snapshot.bid = tick.bid;
   snapshot.ask = tick.ask;
   // คำนวณ Spread เป็นหน่วยจุด (Points)
   snapshot.spread_points = (tick.ask - tick.bid) / (SymbolInfoDouble(symbol, SYMBOL_POINT) > 0 ? SymbolInfoDouble(symbol, SYMBOL_POINT) : 0.00001);
   
   // อัปเดตและบันทึกค่ากลางของ Spread ล่าสุด
   double median = GetMedianSpread(snapshot.spread_points);
   g_last_median_spread_points = median;
   
   // ตรวจสอบความผิดปกติของ Spread (หากถ่างเกิน 2 เท่าของค่ากลาง จะเริ่มมีการแจ้งเตือน)
   if(snapshot.spread_points > median * SpreadMedianMultiple)
   {
      // LogWarning(StringFormat("High Spread Detected: %.1f (Median: %.1f)", snapshot.spread_points, median));
   }

   return true;
}

/**
 * GetLastMedianSpreadPoints: ดึงค่า Median Spread ล่าสุด
 */
double GetLastMedianSpreadPoints()
{
   return g_last_median_spread_points;
}

/**
 * IsNewBar: ฟังก์ชันตรวจสอบการเปิดแท่งเทียนใหม่ (New Bar Detection)
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบวันเวลาเปิดของแท่งเทียนล่าสุด (Time 0)
 * 2. เปรียบเทียบกับข้อมูลเดิมที่เก็บไว้ในอาเรย์ Static (last_bar_times)
 * 3. หากเวลาเปลี่ยนไป แสดงว่าเกิดแท่งใหม่ ให้บันทึกเวลาใหม่และคืนค่า true
 * 4. ระบบนี้รองรับการตรวจสอบหลายคู่เงินและหลายไทม์เฟรมพร้อมกัน (Multi-Symbol & Multi-TF Support)
 */
bool IsNewBar(string symbol, ENUM_TIMEFRAMES period)
{
   // ตัวแปร Static จะจดจำค่าไว้ตลอดการทำงานของโปรแกรม (จนกว่าจะปิด EA)
   static string keys[];
   static datetime last_bar_times[];

   // สร้างคีย์เพื่อระบุตัวตนของคู่เงินและไทม์เฟรม
   string key = symbol + "#" + IntegerToString((int)period);
   datetime current_bar_time = (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);
   if(current_bar_time <= 0) return false;

   // ค้นหาดัชนีของคีย์นี้ในรายการประวัติ
   int idx = -1;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      if(keys[i] == key)
      {
         idx = i;
         break;
      }
   }

   // กรณีพบเป็นครั้งแรก ให้ลงทะเบียนใหม่และคืนค่า true
   if(idx < 0)
   {
      idx = ArraySize(keys);
      ArrayResize(keys, idx + 1);
      ArrayResize(last_bar_times, idx + 1);
      keys[idx] = key;
      last_bar_times[idx] = current_bar_time;
      return true;
   }

   // ตรวจสอบว่าเวลาของแท่งเทียนขยับไปจากเดิมหรือไม่
   if(current_bar_time != last_bar_times[idx])
   {
      last_bar_times[idx] = current_bar_time;
      return true;
   }

   return false;
}

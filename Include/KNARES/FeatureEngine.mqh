#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Indicator Handles - ตัวแปรเก็บตำแหน่งอ้างอิงของอินดิเคเตอร์             |
//| ใช้สำหรับเก็บค่า Handle ที่ได้จากฟังก์ชัน iMA, iATR, iRSI ฯลฯ              |
//+------------------------------------------------------------------+
int handle_ema_fast = INVALID_HANDLE;
int handle_ema_slow = INVALID_HANDLE;
int handle_atr      = INVALID_HANDLE;
int handle_adx      = INVALID_HANDLE;
int handle_rsi      = INVALID_HANDLE;
int handle_htf_ema  = INVALID_HANDLE; 
int handle_obv      = INVALID_HANDLE; 
int handle_bb       = INVALID_HANDLE; 

//+------------------------------------------------------------------+
//| Feature Engine Module - ระบบคำนวณคุณลักษณะของตลาด (Features)        |
//| ทำหน้าที่: เตรียมข้อมูลดิบจาก Indicators และข้อมูลราคา เพื่อแปลงเป็นฟีเจอร์ |
//| ที่ระบบ AI และกลยุทธ์ต่างๆ สามารถนำไปใช้ในการตัดสินใจได้อย่างแม่นยำ       |
//+------------------------------------------------------------------+

/**
 * FeatureEngineInit: ฟังก์ชันเริ่มต้นการทำงานของระบบคำนวณฟีเจอร์
 * อธิบายกระบวนการ:
 * 1. สร้าง Handle สำหรับ Indicators พื้นฐาน (EMA, ATR, ADX, RSI)
 * 2. สร้าง Handle สำหรับ Indicators ขั้นสูง (OBV สำหรับ Volume, Bollinger Bands สำหรับ Volatility)
 * 3. สร้าง Handle สำหรับ Higher Timeframe (HTF) เพื่อเช็คแนวโน้มภาพใหญ่
 * 4. ตรวจสอบว่า Handle ทุกตัวถูกสร้างสำเร็จหรือไม่ (ถ้าไม่สำเร็จระบบจะแจ้งเตือนและหยุดทำงาน)
 */
bool FeatureEngineInit()
{
   // ลงทะเบียนอินดิเคเตอร์ในหน่วยความจำของ Terminal
   handle_ema_fast = iMA(_Symbol, MainTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema_slow = iMA(_Symbol, MainTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr      = iATR(_Symbol, MainTF, ATRPeriod);
   handle_adx      = iADX(_Symbol, MainTF, ADXPeriod);
   handle_rsi      = iRSI(_Symbol, MainTF, RSIPeriod, PRICE_CLOSE);
   handle_obv      = iOBV(_Symbol, MainTF, VOLUME_TICK);
   handle_bb       = iBands(_Symbol, MainTF, 20, 0, 2.0, PRICE_CLOSE);
   
   // เช็คแนวโน้มหลักจากไทม์เฟรมที่ใหญ่กว่า (เช่น H4 หากเทรด M15)
   handle_htf_ema  = iMA(_Symbol, HigherTF, 50, 0, MODE_EMA, PRICE_CLOSE);

   // ตรวจสอบความถูกต้องของ Handles ทั้งหมด
   if(handle_ema_fast == INVALID_HANDLE || handle_ema_slow == INVALID_HANDLE ||
      handle_atr      == INVALID_HANDLE || handle_adx      == INVALID_HANDLE ||
      handle_rsi      == INVALID_HANDLE || handle_htf_ema  == INVALID_HANDLE ||
      handle_obv      == INVALID_HANDLE || handle_bb       == INVALID_HANDLE)
   {
      LogError("Failed to create indicator handles.");
      return false;
   }

   LogInfo("FeatureEngine Expanded: OBV and Bollinger Bands added.");
   return true;
}

/**
 * FeatureEngineDeinit: ฟังก์ชันคืนทรัพยากรหน่วยความจำ
 * อธิบายกระบวนการ:
 * - สั่ง Release ทุก Handle ที่เคยสร้างไว้ เพื่อไม่ให้เครื่องทำงานหนักหรือเกิด Memory Leak
 */
void FeatureEngineDeinit()
{
   if(handle_ema_fast != INVALID_HANDLE) IndicatorRelease(handle_ema_fast);
   if(handle_ema_slow != INVALID_HANDLE) IndicatorRelease(handle_ema_slow);
   if(handle_atr      != INVALID_HANDLE) IndicatorRelease(handle_atr);
   if(handle_adx      != INVALID_HANDLE) IndicatorRelease(handle_adx);
   if(handle_rsi      != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   if(handle_obv      != INVALID_HANDLE) IndicatorRelease(handle_obv);
   if(handle_bb       != INVALID_HANDLE) IndicatorRelease(handle_bb);
   if(handle_htf_ema  != INVALID_HANDLE) IndicatorRelease(handle_htf_ema);
   
   LogInfo("FeatureEngine Module handles released.");
}

/**
 * ComputeFeatures: ฟังก์ชันหลักในการดึงข้อมูลและคำนวณฟีเจอร์ตลาด
 * อธิบายกระบวนการ:
 * 1. ดึงข้อมูลจาก Buffer ของ Indicators แต่ละตัว:
 *    - EMA Slope: คำนวณความชันของเส้น EMA เพื่อดูความเร่งของราคา
 *    - ADX & OBV Slope: วิเคราะห์การเคลื่อนไหวของโมเมนตัมและปริมาณการซื้อขาย
 *    - Bollinger Bands: ดึงค่า Upper, Lower, Mid เพื่อดูขอบเขตความผันผวน
 * 2. วิเคราะห์ Higher Timeframe (HTF):
 *    - เปรียบเทียบราคาปัจจุบันกับเส้น EMA ในไทม์เฟรมใหญ่ เพื่อระบุทิศทางเทรนด์หลัก (1.0 = ขึ้น, -1.0 = ลง)
 * 3. รวบรวมข้อมูลราคา:
 *    - ดึง Tick Volume ล่าสุด
 *    - หาค่าสูงสุด/ต่ำสุด (Donchian High/Low) ในช่วงเวลาที่กำหนด
 * 4. คำนวณค่าสถิติเปรียบเทียบ (Moving Median):
 *    - คำนวณค่าเฉลี่ยของ Volume และ ATR ย้อนหลัง 50 แท่ง เพื่อใช้เป็นเกณฑ์ตัดสินความผิดปกติของสภาวะตลาด
 * 5. คำนวณ Z-Score:
 *    - วัดระยะห่างระหว่างราคากับเส้นค่าเฉลี่ย (Mean) โดยหารด้วย ATR เพื่อใช้ในกลยุทธ์ Mean Reversion
 */
bool ComputeFeatures(string symbol, MarketSnapshot &snapshot)
{
   double buffer[3]; 
   
   // --- ขั้นตอนที่ 1: ดึงค่าและคำนวณความชัน (Slope Analysis) ---
   if(CopyBuffer(handle_ema_fast, 0, 0, 2, buffer) > 1) 
   {
      snapshot.ema_fast = buffer[1];
      // คำนวณเปอร์เซ็นต์การเปลี่ยนแปลงของ EMA เพื่อดูแรงส่ง
      snapshot.ema_slope = (buffer[1] - buffer[0]) / (buffer[0] > 0 ? buffer[0] : 1.0) * 100.0;
   }
   
   if(CopyBuffer(handle_adx, 0, 0, 2, buffer) > 1)
   {
      snapshot.adx = buffer[1];
      snapshot.adx_slope = buffer[1] - buffer[0];
   }

   if(CopyBuffer(handle_obv, 0, 0, 2, buffer) > 1)
   {
      snapshot.obv = buffer[1];
      snapshot.obv_slope = buffer[1] - buffer[0];
   }

   // --- ขั้นตอนที่ 2: ดึงค่า Bollinger Bands (Volatility Range) ---
   if(CopyBuffer(handle_bb, 0, 0, 1, buffer) > 0) snapshot.bb_mid   = buffer[0];
   if(CopyBuffer(handle_bb, 1, 0, 1, buffer) > 0) snapshot.bb_upper = buffer[0];
   if(CopyBuffer(handle_bb, 2, 0, 1, buffer) > 0) snapshot.bb_lower = buffer[0];

   // --- ขั้นตอนที่ 3: ดึงค่าพื้นฐานอื่นๆ ---
   if(CopyBuffer(handle_ema_slow, 0, 0, 1, buffer) > 0) snapshot.ema_slow = buffer[0];
   if(CopyBuffer(handle_atr,      0, 0, 1, buffer) > 0) snapshot.atr      = buffer[0];
   if(CopyBuffer(handle_rsi,      0, 0, 1, buffer) > 0) snapshot.rsi      = buffer[0];

   // --- ขั้นตอนที่ 4: วิเคราะห์เทรนด์จากไทม์เฟรมใหญ่ (HTF Alignment) ---
   double htf_buffer[1];
   if(CopyBuffer(handle_htf_ema, 0, 0, 1, htf_buffer) > 0)
   {
      double htf_price = iClose(symbol, HigherTF, 0);
      snapshot.htf_trend = (htf_price > htf_buffer[0]) ? 1.0 : -1.0;
   }

   // --- ขั้นตอนที่ 5: ข้อมูลปริมาณการซื้อขายและ Donchian Channel ---
   snapshot.volume = iTickVolume(symbol, MainTF, 0);
   snapshot.donchian_high = iHigh(symbol, MainTF, iHighest(symbol, MainTF, MODE_HIGH, DonchianLookback, 1));
   snapshot.donchian_low  = iLow(symbol, MainTF, iLowest(symbol, MainTF, MODE_LOW, DonchianLookback, 1));
   
   // --- ขั้นตอนที่ 6: คำนวณค่ากลางทางสถิติ (Statistical Medians) ---
   double vol_sum = 0;
   double atr_sum = 0;
   int lookback = 50;
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(handle_atr, 0, 1, lookback, atr_buffer) >= lookback)
   {
      for(int i=0; i<lookback; i++)
      {
         vol_sum += (double)iTickVolume(symbol, MainTF, i+1);
         atr_sum += atr_buffer[i];
      }
      snapshot.vol_median = vol_sum / lookback;
      snapshot.atr_median = atr_sum / lookback;
   }
   else
   {
      // Fallback กรณีข้อมูลย้อนหลังไม่เพียงพอ
      snapshot.vol_median = (double)iTickVolume(symbol, MainTF, 1);
      snapshot.atr_median = (snapshot.atr > 0) ? snapshot.atr : 0.01;
   }

   // --- ขั้นตอนที่ 7: คำนวณ Z-Score (Mean Reversion Intensity) ---
   if(snapshot.atr > 0) snapshot.zscore = (snapshot.bid - snapshot.ema_slow) / snapshot.atr;

   return true;
}

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"

//+------------------------------------------------------------------+
//| Internal Helpers Module - ฟังก์ชันช่วยเหลือภายในการจัดการออเดอร์และ Log |
//+------------------------------------------------------------------+

/**
 * ApplyEngineStopFloor: ฟังก์ชันสำหรับบังคับระยะ Stop Loss (SL) ขั้นต่ำตามแต่ละกลยุทธ์
 * อธิบายกระบวนการ:
 * 1. ดึงค่าระยะ Stop Loss ขั้นต่ำ (หน่วยเป็นจุด) จาก Config ตามประเภทของ Engine (Trend, Breakout, MeanRev)
 * 2. คำนวณระยะห่างปัจจุบันระหว่างราคา Entry และ SL
 * 3. หากระยะปัจจุบัน "แคบกว่า" เกณฑ์ขั้นต่ำที่กำหนด ระบบจะขยับราคา SL ออกไปให้เท่ากับเกณฑ์ขั้นต่ำโดยอัตโนมัติ
 *    - สำหรับ Buy: ขยับ SL ลงด้านล่าง
 *    - สำหรับ Sell: ขยับ SL ขึ้นด้านบน
 */
void ApplyEngineStopFloor(SignalPack &sig)
{
   int engine_min_points = MinStopDistancePoints;
   // เลือกเกณฑ์ขั้นต่ำตามประเภทกลยุทธ์ที่ส่งสัญญาณมา
   if(sig.engine_name == "BreakoutEngine") engine_min_points = BreakoutMinStopDistancePoints;
   else if(sig.engine_name == "TrendEngine") engine_min_points = TrendMinStopDistancePoints;
   else if(sig.engine_name == "MeanRevEngine") engine_min_points = MeanRevMinStopDistancePoints;

   double point = SymbolInfoDouble(sig.symbol, SYMBOL_POINT);
   double min_dist = MathMax(0, engine_min_points) * point;
   double stop_dist = MathAbs(sig.entry_price - sig.stop_price);

   // หาก SL แคบเกินไป ให้ปรับให้เป็นไปตาม Floor (เกณฑ์ขั้นต่ำ) เพื่อป้องกันการโดนสะบัดกิน SL ง่ายเกินไป
   if(stop_dist < min_dist && point > 0)
   {
      if(sig.direction == SIGNAL_BUY) sig.stop_price = sig.entry_price - min_dist;
      else if(sig.direction == SIGNAL_SELL) sig.stop_price = sig.entry_price + min_dist;
   }
}

/**
 * ShouldLogWaitingNewBar: ควบคุมการบันทึก Log เมื่อรอแท่งเทียนใหม่ เพื่อป้องกัน Log ขยะ (Spam)
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบวันเวลาเริ่มต้นของแท่งเทียนปัจจุบัน (Last Bar Time)
 * 2. เปรียบเทียบกับข้อมูลล่าสุดที่เคยบันทึกไว้ในตัวแปร Static (จดจำข้ามรอบการทำงานได้)
 * 3. หากเป็นแท่งเทียนเดิมที่เคยบันทึกไปแล้ว จะคืนค่า false (ไม่ต้องบันทึกซ้ำ)
 * 4. หากเป็นแท่งเทียนใหม่ จะบันทึกเวลาใหม่ลงในระบบและคืนค่า true (อนุญาตให้บันทึก Log)
 */
bool ShouldLogWaitingNewBar(const string symbol, ENUM_TIMEFRAMES period)
{
   static string keys[]; // เก็บรายชื่อคู่เงินและไทม์เฟรม
   static datetime logged_bar_time[]; // เก็บเวลาแท่งเทียนล่าสุดที่ Log ไปแล้ว

   datetime current_bar_time = (datetime)SeriesInfoInteger(symbol, period, SERIES_LASTBAR_DATE);
   if(current_bar_time <= 0) return false;

   // สร้างคีย์ผสมเพื่อแยกแยะระหว่างคู่เงินและไทม์เฟรมที่ต่างกัน
   string key = symbol + "#" + IntegerToString((int)period);
   int idx = -1;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      if(keys[i] == key)
      {
         idx = i;
         break;
      }
   }

   // หากยังไม่เคยมีข้อมูลคู่เงินนี้ในระบบ ให้ลงทะเบียนใหม่
   if(idx < 0)
   {
      idx = ArraySize(keys);
      ArrayResize(keys, idx + 1);
      ArrayResize(logged_bar_time, idx + 1);
      keys[idx] = key;
      logged_bar_time[idx] = current_bar_time;
      return true;
   }

   // หากเป็นแท่งเทียนใหม่ (เวลาเปลี่ยนไปจากเดิม)
   if(logged_bar_time[idx] != current_bar_time)
   {
      logged_bar_time[idx] = current_bar_time;
      return true;
   }
   return false;
}

/**
 * ShouldLogSignalPenalty: ควบคุมการบันทึก Log ของการโดนหักคะแนน (Penalty) 
 * อธิบายกระบวนการ:
 * - ทำงานคล้ายกับ ShouldLogWaitingNewBar แต่เน้นไปที่การแจ้งเตือนเงื่อนไขที่ทำให้สัญญาณถูกหักคะแนน
 * - เป้าหมายคือต้องการให้แจ้งเตือนเพียง "ครั้งเดียวต่อแท่งเทียน" เพื่อความสะอาดของหน้าจอ Log
 */
bool ShouldLogSignalPenalty(const string symbol, const string tag)
{
   static string keys[];
   static datetime logged_bar_time[];

   datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
   if(bar_time <= 0) bar_time = TimeCurrent();
   
   string key = symbol + "#" + tag;
   int idx = -1;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      if(keys[i] == key) { idx = i; break; }
   }
   
   // ลงทะเบียนคีย์และแท็กใหม่หากไม่เคยพบมาก่อน
   if(idx < 0)
   {
      idx = ArraySize(keys);
      ArrayResize(keys, idx + 1);
      ArrayResize(logged_bar_time, idx + 1);
      keys[idx] = key;
      logged_bar_time[idx] = 0;
   }
   
   // ถ้าเคย Log ไปแล้วในแท่งเทียนนี้ จะคืนค่า false
   if(logged_bar_time[idx] == bar_time)
      return false;
      
   // บันทึกสถานะว่า Log ไปแล้วในแท่งเทียนนี้
   logged_bar_time[idx] = bar_time;
   return true;
}

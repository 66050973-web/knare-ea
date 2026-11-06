#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Price Action Filter - ตัวกรองรูปแบบแท่งเทียน (ใช้เมื่อ EnablePriceActionFilter)|
//| ยืนยันทิศทางสัญญาณด้วยแท่งที่ปิดล่าสุด: Engulfing หรือ Pin Bar            |
//+------------------------------------------------------------------+

/**
 * PriceActionConfirms: คืนค่า true หากแท่งเทียนที่ปิดล่าสุด (shift 1) ยืนยันทิศทางของสัญญาณ
 *  - BUY : Bullish Engulfing หรือ Bullish Pin Bar (ไส้ล่างยาว >= 60% ของช่วงแท่ง และปิดในช่วงบน)
 *  - SELL: Bearish Engulfing หรือ Bearish Pin Bar (ไส้บนยาว >= 60% ของช่วงแท่ง และปิดในช่วงล่าง)
 */
bool PriceActionConfirms(const string symbol, const ENUM_SIGNAL_DIRECTION dir)
{
   double o1 = iOpen(symbol, MainTF, 1), h1 = iHigh(symbol, MainTF, 1), l1 = iLow(symbol, MainTF, 1), c1 = iClose(symbol, MainTF, 1);
   double o2 = iOpen(symbol, MainTF, 2), c2 = iClose(symbol, MainTF, 2);
   double range1 = h1 - l1;
   if(range1 <= 0.0) return false;

   double upper_wick = h1 - MathMax(o1, c1);
   double lower_wick = MathMin(o1, c1) - l1;
   double close_pos  = (c1 - l1) / range1; // 0 = ปิดที่ต่ำสุด, 1 = ปิดที่สูงสุด

   if(dir == SIGNAL_BUY)
   {
      bool engulf = (c2 < o2) && (c1 > o1) && (c1 >= o2) && (o1 <= c2);
      bool pin    = (lower_wick >= 0.60 * range1) && (close_pos >= 0.66);
      return (engulf || pin);
   }
   if(dir == SIGNAL_SELL)
   {
      bool engulf = (c2 > o2) && (c1 < o1) && (c1 <= o2) && (o1 >= c2);
      bool pin    = (upper_wick >= 0.60 * range1) && (close_pos <= 0.34);
      return (engulf || pin);
   }
   return false;
}

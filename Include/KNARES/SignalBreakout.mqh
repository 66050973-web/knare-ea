#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Breakout Signal Engine - กลยุทธ์การเทรดเมื่อราคาทะลุแนวรับ-แนวต้าน      |
//| ใช้สำหรับดักจังหวะที่ราคาพุ่งทะลุช่วงสะสมพลัง (Price Channel)           |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน BuildBreakoutSignal: สร้างสัญญาณเทรดเมื่อราคาเกิดการ Breakout
 * @param features: ข้อมูล snapshot ของตลาด
 * @param regime: สภาวะตลาดปัจจุบัน
 * @param signal: โครงสร้างข้อมูลสำหรับเก็บผลลัพธ์ของสัญญาณ
 * @return bool: true หากพบสัญญาณเทรดที่เหมาะสม
 */
bool BuildBreakoutSignal(const MarketSnapshot &features, ENUM_REGIME_TYPE regime, SignalPack &signal)
{
   // กำหนดค่าเริ่มต้นให้กับโครงสร้างสัญญาณ
   signal.direction = SIGNAL_NONE;
   signal.engine_name = "BreakoutEngine";
   signal.reason = "";

   // --- ตรวจสอบสภาวะตลาดที่เหมาะสม (Regime Compatibility) ---
   // กลยุทธ์นี้จะทำงานเมื่อตลาดอยู่ในสภาวะพร้อมระเบิด (Breakout Ready) หรือกำลังเป็นเทรนด์
   // รวมถึงรองรับการข้ามเงื่อนไข (Bypass) หากตลาดอยู่ในสภาวะ Unknown แต่มีปัจจัยพื้นฐานแข็งแกร่ง (ADX, ATR, Z-Score)
   // เพื่อให้ระบบสามารถจับจังหวะการเคลื่อนที่แรงๆ ได้แม้ไม่ได้อยู่ในสภาวะที่ระบุชัดเจน
   bool allow_unknown = (EnableUnknownRegimeBuilderBypass &&
                         regime == REGIME_UNKNOWN &&
                         features.adx >= UnknownRegimeMinADX &&
                         features.atr >= UnknownRegimeMinATR &&
                         MathAbs(features.zscore) >= MathMax(0.1, UnknownBreakoutMinAbsZ * 0.75));
   
   // ปฏิเสธหากสภาวะตลาดไม่เหมาะสมกับกลยุทธ์ Breakout
   if(regime != REGIME_BREAKOUT_READY && regime != REGIME_TREND_UP && regime != REGIME_TREND_DOWN && !allow_unknown)
   {
      signal.reason = StringFormat("regime_mismatch(%s)", EnumToString(regime));
      return false;
   }

   // --- 1. เงื่อนไขการ Buy Breakout: ราคาทะลุหรือเข้าใกล้ขอบบนของ Donchian Channel ---
   // ใช้ near_factor ในการปรับความไวให้ส่งสัญญาณก่อนถึงเส้นจริงเล็กน้อย (Anticipation)
   double near_factor = MathMax(0.05, BreakoutNearBandAtrFactor);
   double buy_threshold = features.donchian_high - features.atr * near_factor;
   
   if(features.ask >= buy_threshold)
   {
      // Phase 23: ตรวจสอบปริมาณการซื้อขาย (Volume Filter) 
      // การ Breakout ที่มีคุณภาพควรมีปริมาณการซื้อขายที่สูงกว่าค่าเฉลี่ย (Median) เพื่อยืนยันแรงผลักดัน
      if(EnableVolumeFilter && (double)features.volume < features.vol_median * (MinVolumePercentile / 100.0))
      {
         signal.reason = StringFormat("low_volume_breakout_buy(vol=%I64d < thr=%.1f)", features.volume, features.vol_median * (MinVolumePercentile / 100.0));
         return false;
      }

      // กำหนดทิศทางและราคาเข้า
      signal.direction = SIGNAL_BUY;
      signal.entry_price = features.ask;
      
      // วาง Stop Loss (SL): เลือกจุดที่ปลอดภัยที่สุดระหว่างขอบล่างของ Donchian หรือระยะตามค่า ATR
      signal.stop_price = MathMax(features.donchian_low, features.ask - (features.atr * ATRStopMultiple));
      
      // คำนวณ Take Profit (TP): ตามสัดส่วน Reward to Risk (R) ที่กำหนดจาก Configuration
      double tp_dist = features.atr * ATRStopMultiple * TakeProfitR;
      double min_tp = 100 * SymbolInfoDouble(features.symbol, SYMBOL_POINT);
      signal.take_profit_price = features.ask + MathMax(tp_dist, min_tp);
      
      // กำหนดคะแนนความเชื่อมั่นของสัญญาณ
      signal.score = allow_unknown ? 0.88 : 0.86;
      signal.reason = "breakout_buy_pass";
      return true;
   }
   
   // --- 2. เงื่อนไขการ Sell Breakout: ราคาทะลุหรือเข้าใกล้ขอบล่างของ Donchian Channel ---
   double sell_threshold = features.donchian_low + features.atr * near_factor;
   if(features.bid <= sell_threshold)
   {
      // ตรวจสอบปริมาณการซื้อขาย (Volume Filter) สำหรับฝั่งขาย
      if(EnableVolumeFilter && (double)features.volume < features.vol_median * (MinVolumePercentile / 100.0))
      {
         signal.reason = StringFormat("low_volume_breakout_sell(vol=%I64d < thr=%.1f)", features.volume, features.vol_median * (MinVolumePercentile / 100.0));
         return false;
      }

      // กำหนดทิศทางและราคาเข้า
      signal.direction = SIGNAL_SELL;
      signal.entry_price = features.bid;
      
      // วาง Stop Loss (SL): เลือกจุดที่ปลอดภัยที่สุดระหว่างขอบบนของ Donchian หรือระยะตามค่า ATR
      signal.stop_price = MathMin(features.donchian_high, features.bid + (features.atr * ATRStopMultiple));
      
      // คำนวณ Take Profit (TP)
      double tp_dist = features.atr * ATRStopMultiple * TakeProfitR;
      double min_tp = 100 * SymbolInfoDouble(features.symbol, SYMBOL_POINT);
      signal.take_profit_price = features.bid - MathMax(tp_dist, min_tp);
      
      signal.score = allow_unknown ? 0.88 : 0.86;
      signal.reason = "breakout_sell_pass";
      return true;
   }

   // หากราคายังไม่ทะลุกรอบที่กำหนด
   signal.reason = StringFormat("range_not_broken(ask=%.5f buy_thr=%.5f bid=%.5f sell_thr=%.5f)",
                                features.ask, buy_threshold, features.bid, sell_threshold);
   return false;
}

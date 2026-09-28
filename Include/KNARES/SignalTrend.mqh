#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Trend Signal Engine - กลยุทธ์การเทรดตามแนวโน้ม (Trend Following)     |
//| ใช้สำหรับตรวจจับและส่งสัญญาณซื้อขายเมื่อตลาดมีทิศทางชัดเจน               |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน BuildTrendSignal: สร้างสัญญาณเทรดตามแนวโน้ม
 * @param features: ข้อมูล snapshot ของตลาด
 * @param regime: สภาวะตลาดปัจจุบัน
 * @param signal: โครงสร้างข้อมูลสำหรับเก็บผลลัพธ์ของสัญญาณ
 * @return bool: true หากพบสัญญาณเทรดที่เหมาะสม
 */
bool BuildTrendSignal(const MarketSnapshot &features, ENUM_REGIME_TYPE regime, SignalPack &signal)
{
   // กำหนดค่าเริ่มต้นให้กับโครงสร้างสัญญาณ
   signal.direction = SIGNAL_NONE;
   signal.engine_name = "TrendEngine";
   signal.reason = "";

   // --- การจัดการสภาวะ Unknown (Unknown Regime Bypass) ---
   // ตรวจสอบว่าอนุญาตให้เทรดในสภาวะที่ไม่ชัดเจน (Unknown) หรือไม่ เพื่อเพิ่มโอกาสในการเข้าเทรด
   bool allow_unknown = (EnableUnknownRegimeBuilderBypass && regime == REGIME_UNKNOWN);
   ENUM_REGIME_TYPE effective_regime = regime;
   
   // ถ้าอนุญาตและสภาวะปัจจุบันเป็น Unknown ให้ประเมินทิศทางจากเส้น EMA แทน (EMA Cross Heuristic)
   if(allow_unknown)
      effective_regime = (features.ema_fast >= features.ema_slow) ? REGIME_TREND_UP : REGIME_TREND_DOWN;

   // กลยุทธ์ Trend Following จะทำงานเฉพาะเมื่อตลาดเป็นเทรนด์ขาขึ้นหรือขาลงเท่านั้น
   if(effective_regime != REGIME_TREND_UP && effective_regime != REGIME_TREND_DOWN)
   {
      signal.reason = StringFormat("regime_mismatch(%s)", EnumToString(regime));
      return false;
   }

   // Phase 23: กรองคุณภาพการเข้าเทรดด้วยค่า ADX ขั้นต่ำ (ADX Floor Filter)
   // เพื่อให้มั่นใจว่าเทรนด์ที่เกิดขึ้นมีความแข็งแรงเพียงพอที่จะเข้าเทรด
   if(features.adx < TrendMinADXFloor)
   {
      signal.reason = StringFormat("low_adx_floor(%.2f < %.2f)", features.adx, TrendMinADXFloor);
      return false;
   }

   // --- 1. การยืนยันแนวโน้มหลายกรอบเวลา (Triple Timeframe Confirmation) ---
   // ตรวจสอบว่าแนวโน้มในไทม์เฟรมที่สูงกว่า (H1 และ H4) สอดคล้องกับกรอบเวลาปัจจุบันหรือไม่
   // เพื่อเพิ่มความแม่นยำและลดสัญญาณหลอก (Fake Signals)
   int h1_trend = GetTrendDirection(features.symbol, PERIOD_H1);
   int h4_trend = GetTrendDirection(features.symbol, PERIOD_H4);
   
   // เช็คการสอดคล้องของเทรนด์ (Alignment Check)
   bool h1_aligned = (effective_regime == REGIME_TREND_UP && h1_trend == 1) || (effective_regime == REGIME_TREND_DOWN && h1_trend == -1);
   bool h4_aligned = (effective_regime == REGIME_TREND_UP && h4_trend == 1) || (effective_regime == REGIME_TREND_DOWN && h4_trend == -1);
   
   bool htf_ok = false;
   double htf_penalty = 0.0;
   
   // เลือกวิธีการยืนยันตามการตั้งค่าใน Configuration
   if(TrendRequireBothHTF)
      htf_ok = (h1_aligned && h4_aligned); // ต้องตรงกันทั้ง H1 และ H4
   else if(TrendUseH1OnlyRelaxed)
   {
      htf_ok = h1_aligned; // ใช้เฉพาะ H1 เป็นหลัก
      if(h1_aligned && !h4_aligned)
         htf_penalty = MathMax(0.0, TrendH4MismatchPenalty); // หักคะแนนความมั่นใจถ้า H4 ไม่ตรง
   }
   else
      htf_ok = (h1_aligned || h4_aligned); // ตรงอย่างน้อยหนึ่งไทม์เฟรม

   // กรณีแนวโน้มไม่สอดคล้องตามเกณฑ์ที่ตั้งไว้
   if(!htf_ok)
   {
      // หากอนุญาตให้ใช้ระบบ Fallback (ลดคะแนนแทนการปฏิเสธสัญญาณทันที)
      if(EnableTrendHtfPenaltyFallback)
      {
         htf_penalty = MathMax(htf_penalty, MathMax(0.0, TrendHtfConflictPenalty));
      }
      else
      {
         // ปฏิเสธสัญญาณเนื่องจากแนวโน้มขัดแย้งกันในแต่ละไทม์เฟรม
         signal.reason = StringFormat("mtf_mismatch(h1=%d h4=%d mode=%s)", h1_trend, h4_trend,
                                      TrendRequireBothHTF ? "both" : (TrendUseH1OnlyRelaxed ? "h1_only" : "either"));
         return false;
      }
   }

   // --- 2. เงื่อนไขการเข้าเทรด (Entry Conditions) ---
   
   // กรณีตลาดเป็นเทรนด์ขาขึ้น (Bullish Trend)
   if(effective_regime == REGIME_TREND_UP)
   {
      // กำหนดระยะยืดหยุ่น (Tolerance) สำหรับกรณี Unknown Regime
      double unknown_tol = MathMax(0.0, features.atr * 0.12);
      
      // ปลดล็อกเงื่อนไขราคาถ้า Slope ชันมาก (Price Gate Liberation)
      // หากเทรนด์แรงมาก (Slope >= 0.002) จะอนุญาตให้เข้าเทรดโดยไม่ต้องรอย่อตัวมากนัก
      bool price_gate_bypass = (features.ema_slope >= 0.002); 
      
      // ตรวจสอบว่าราคาไม่อยู่ไกลจาก EMA Fast เกินไป (Pullback/Gate Check)
      bool price_ok_up = allow_unknown ? (features.ask >= (features.ema_fast - unknown_tol))
                                       : (features.ask > features.ema_fast);
      
      if(price_gate_bypass) price_ok_up = true;

      // ตรวจสอบความชัน (Slope) และค่า RSI (Overbought Guard)
      // ป้องกันการเข้าเทรดในช่วงที่ราคาสูงเกินไปหรือเริ่มหมดแรง
      bool trend_guard_up = allow_unknown
                            ? (features.ema_slope > 0.0 && features.rsi >= 30.0 && features.rsi <= 70.0)
                            : (features.ema_slope > 0.0 && features.rsi < 75.0);
      
      if(price_ok_up && trend_guard_up)
      {
         // กำหนดทิศทางและราคาเข้า
         signal.direction = SIGNAL_BUY;
         signal.entry_price = features.ask;
         // วาง Stop Loss (SL) โดยอิงตามค่า ATR (Volatility-based SL)
         signal.stop_price = features.ask - (features.atr * TrendEngineATRStopMultiple);
         
         // คำนวณคะแนนพื้นฐาน (Base Confidence Score)
         double base_score = allow_unknown ? 0.87 : 0.91;
         double unknown_floor = allow_unknown ? 0.84 : 0.68;
         signal.score = MathMax(unknown_floor, base_score - htf_penalty);
         
         // เพิ่มคะแนนพิเศษหากเทรนด์มีความแข็งแกร่งและชันสูง (Strength Bonus)
         if(features.adx >= TrendBonusADXThreshold && features.ema_slope >= TrendBonusSlopeThreshold) {
            signal.score += TrendStrengthBonus;
         }
         
         // ถ้าคะแนนความเชื่อมั่นสูงมาก ให้ผ่อนปรนเงื่อนไขราคาเข้า (Dynamic Price Acceptance)
         if(signal.score > 0.88) price_ok_up = true;
         
         if(price_ok_up) {
            // ปรับระยะ Take Profit ตามคะแนนความเชื่อมั่น (High Conviction TP Adjustment)
            double dynamic_tp_r = (signal.score >= HighConvictionScoreThreshold) ? DynamicTPHighConvictionR : TrendEngineTakeProfitR;
            double tp_dist = features.atr * TrendEngineATRStopMultiple * dynamic_tp_r;
            double min_tp = 100 * SymbolInfoDouble(features.symbol, SYMBOL_POINT);
            signal.take_profit_price = features.ask + MathMax(tp_dist, min_tp);

            // บันทึกเหตุผลในการสร้างสัญญาณ
            signal.reason = allow_unknown
                         ? StringFormat("Trend UNKNOWN bypass: dir=UP ADX=%.2f ATR=%.2f htf_penalty=%.2f",
                                        features.adx, features.atr, htf_penalty)
                         : ((htf_penalty > 0.0)
                            ? StringFormat("Trend fallback: HTF conflict penalty=%.2f", htf_penalty)
                            : "Trend Alignment (Current + HTF) + ADX Rising");
            return true;
         }
      }
      // บันทึกสาเหตุที่เข้าเงื่อนไขไม่ครบถ้วน
      signal.reason = StringFormat("entry_fail_up(ask_below_gate:%s trend_guard_fail:%s slope=%.6f rsi=%.2f tol=%.5f)",
                                   price_ok_up ? "false" : "true",
                                   trend_guard_up ? "false" : "true",
                                   features.ema_slope,
                                   features.rsi,
                                   unknown_tol);
   }
   
   // กรณีตลาดเป็นเทรนด์ขาลง (Bearish Trend)
   if(effective_regime == REGIME_TREND_DOWN)
   {
      double unknown_tol = MathMax(0.0, features.atr * 0.12);
      
      // ปลดล็อกเงื่อนไขราคาถ้า Slope ชันมาก (Price Gate Liberation)
      bool price_gate_bypass = (features.ema_slope <= -0.002);
      
      // ตรวจสอบว่าราคาไม่อยู่ต่ำกว่า EMA Fast มากเกินไป
      bool price_ok_down = allow_unknown ? (features.bid <= (features.ema_fast + unknown_tol))
                                         : (features.bid < features.ema_fast);
      
      if(price_gate_bypass) price_ok_down = true;

      // ตรวจสอบความชันและค่า RSI (Oversold Guard)
      bool trend_guard_down = allow_unknown
                              ? (features.ema_slope < 0.0 && features.rsi >= 30.0 && features.rsi <= 70.0)
                              : (features.ema_slope < 0.0 && features.rsi > 25.0);
      
      if(price_ok_down && trend_guard_down)
      {
         signal.direction = SIGNAL_SELL;
         signal.entry_price = features.bid;
         signal.stop_price = features.bid + (features.atr * TrendEngineATRStopMultiple);
         
         double base_score = allow_unknown ? 0.87 : 0.91;
         double unknown_floor = allow_unknown ? 0.84 : 0.68;
         signal.score = MathMax(unknown_floor, base_score - htf_penalty);
         
         // เพิ่มคะแนนพิเศษหากเทรนด์ขาลงมีความแข็งแกร่งและชันสูง (Strength Bonus)
         if(features.adx >= TrendBonusADXThreshold && features.ema_slope <= -TrendBonusSlopeThreshold) {
            signal.score += TrendStrengthBonus;
         }
         
         if(signal.score > 0.88) price_ok_down = true;
         
         if(price_ok_down) {
            double dynamic_tp_r = (signal.score >= HighConvictionScoreThreshold) ? DynamicTPHighConvictionR : TrendEngineTakeProfitR;
            double tp_dist = features.atr * TrendEngineATRStopMultiple * dynamic_tp_r;
            double min_tp = 100 * SymbolInfoDouble(features.symbol, SYMBOL_POINT);
            signal.take_profit_price = features.bid - MathMax(tp_dist, min_tp);

            signal.reason = allow_unknown
                         ? StringFormat("Trend UNKNOWN bypass: dir=DOWN ADX=%.2f ATR=%.2f htf_penalty=%.2f",
                                        features.adx, features.atr, htf_penalty)
                         : ((htf_penalty > 0.0)
                            ? StringFormat("Trend fallback: HTF conflict penalty=%.2f", htf_penalty)
                            : "Trend Alignment (Current + HTF) + ADX Rising");
            return true;
         }
      }
      // บันทึกสาเหตุที่เข้าเทรดไม่ได้
      signal.reason = StringFormat("entry_fail_down(bid_above_gate:%s trend_guard_fail:%s slope=%.6f rsi=%.2f tol=%.5f)",
                                   price_ok_down ? "false" : "true",
                                   trend_guard_down ? "false" : "true",
                                   features.ema_slope,
                                   features.rsi,
                                   unknown_tol);
   }

   // หากไม่มีตัวกระตุ้นให้เกิดสัญญาณ
   if(signal.reason == "") signal.reason = "no_trend_trigger";
   return false;
}

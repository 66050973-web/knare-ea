#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Mean Reversion Signal Engine - กลยุทธ์การเทรดเมื่อราคากลับเข้าหาค่าเฉลี่ย |
//| ใช้สำหรับดักจังหวะที่ราคาวิ่งออกห่างจากค่าเฉลี่ยมากเกินไปและมีแนวโน้มจะดึงกลับ |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน BuildMeanRevSignal: สร้างสัญญาณเทรดแบบ Mean Reversion (สวนเทรนด์ในกรอบ)
 * @param features: ข้อมูล snapshot ของตลาด
 * @param regime: สภาวะตลาดปัจจุบัน
 * @param signal: โครงสร้างข้อมูลสำหรับเก็บผลลัพธ์ของสัญญาณ
 * @return bool: true หากพบสัญญาณเทรดที่เหมาะสม
 */
bool BuildMeanRevSignal(const MarketSnapshot &features, ENUM_REGIME_TYPE regime, SignalPack &signal)
{
   // กำหนดค่าเริ่มต้นให้กับโครงสร้างสัญญาณ
   signal.direction = SIGNAL_NONE;
   signal.engine_name = "MeanRevEngine";
   signal.reason = "";

   // --- ตรวจสอบค่า ADX (Trend Filter) ---
   // ถ้าตลาดมีเทรนด์ที่แข็งแรงเกินไป (ADX สูงกว่าเกณฑ์) จะไม่เทรดแบบ Mean Reversion 
   // เนื่องจากราคามักจะไม่ดึงกลับมาหาค่าเฉลี่ยแต่จะวิ่งไปต่อตามเทรนด์แทน
   if(features.adx > MeanRevMaxADX) {
      signal.reason = StringFormat("adx_too_high(%.2f > %.2f)", features.adx, MeanRevMaxADX);
      return false;
   }

   // ตรวจสอบสภาวะ Unknown (Bypass) เพื่อให้สามารถเทรดได้ในสภาวะที่ไม่ชัดเจน
   bool allow_unknown = (EnableUnknownRegimeBuilderBypass && regime == REGIME_UNKNOWN);
   
   // ดึงราคาปิดของ 2 แท่งล่าสุด เพื่อตรวจสอบจังหวะการ Re-entry (ราคากลับเข้ามาในโซน Bollinger Bands)
   double close1 = iClose(features.symbol, MainTF, 1);
   double close2 = iClose(features.symbol, MainTF, 2);
   bool allow_trend_selective = false;
   
   // --- ระบบ Selective Trend Mean Reversion ---
   // ตรวจสอบเงื่อนไขพิเศษสำหรับการเทรดสวนเทรนด์เมื่อราคาวิ่งไปถึงจุดสุดโต่ง (Extremes) 
   // แม้ว่าตลาดจะถูกระบุว่าเป็นสภาวะเทรนด์ (Trend Up/Down)
   if(EnableMeanRevInTrendSelective &&
      (regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN))
   {
      // คำนวณระยะห่างจากขอบแบนด์ (Bollinger Bands) เทียบกับค่า ATR
      double dist_to_lower_atr = (features.bb_lower - close1) / MathMax(features.atr, _Point);
      double dist_to_upper_atr = (close1 - features.bb_upper) / MathMax(features.atr, _Point);
      
      // เงื่อนไข: Z-Score ต้องสูง/ต่ำมาก และราคาต้องอยู่ใกล้ขอบแบนด์
      bool near_lower_extreme = (features.zscore <= -MeanRevTrendZScoreMin && dist_to_lower_atr >= -MeanRevTrendBandProximityATR);
      bool near_upper_extreme = (features.zscore >=  MeanRevTrendZScoreMin && dist_to_upper_atr >= -MeanRevTrendBandProximityATR);
      allow_trend_selective = (near_lower_extreme || near_upper_extreme);
   }
   
   // --- ตรวจสอบ Regime ที่เหมาะสม ---
   // อนุญาตเฉพาะช่วงตลาด Sideway (Range) หรือช่วงที่กำลังจะเกิดการระเบิดของราคา (Breakout Ready)
   if(regime != REGIME_RANGE && regime != REGIME_BREAKOUT_READY && !allow_unknown && !allow_trend_selective)
   {
      signal.reason = StringFormat("regime_mismatch(%s)", EnumToString(regime));
      return false;
   }

   // กำหนดค่าความยืดหยุ่น (Tolerance) ในการวัดจุดเข้าอิงตามค่า ATR
   double tol = features.atr * MathMax(0.0, MeanRevReentryToleranceATR);

   // --- 2. ลอจิก Bollinger Bands Re-entry (จังหวะการวกกลับของราคา) ---

   // --- กรณี Buy Re-entry (ราคาเด้งขึ้นจากขอบล่าง) ---
   // เงื่อนไข: แท่งก่อนหน้าปิดต่ำกว่าขอบล่าง (Lower Band) และแท่งล่าสุดปิดกลับเข้ามาในแบนด์ (Re-entry)
   if(close2 <= (features.bb_lower + tol) && close1 >= (features.bb_lower - tol))
   {
      signal.direction = SIGNAL_BUY;
      signal.entry_price = features.ask;
      signal.stop_price = features.ask - (features.atr * ATRStopMultiple);
      
      // Extreme Exit Logic: ถ้าค่า Z-score ต่ำมาก (ราคาถูกมาก) 
      // ให้ตั้งเป้าหมายกำไร (TP) ไว้ที่ขอบบน (Opposite Band) แทนการใช้เส้นกลาง (Mid-band)
      if(features.zscore <= -2.2) {
         signal.take_profit_price = features.bb_upper;
         signal.reason = "BB Lower Re-entry (Extreme Z-Score TP)";
      } else {
         signal.take_profit_price = features.bb_mid;
         signal.reason = "BB Lower Re-entry (relaxed)";
      }
      
      signal.score = 0.88;
      return true;
   }

   // --- กรณี Sell Re-entry (ราคาวกกลับลงมาจากขอบบน) ---
   // เงื่อนไข: แท่งก่อนหน้าปิดสูงกว่าขอบบน (Upper Band) และแท่งล่าสุดปิดกลับเข้ามาในแบนด์
   if(close2 >= (features.bb_upper - tol) && close1 <= (features.bb_upper + tol))
   {
      signal.direction = SIGNAL_SELL;
      signal.entry_price = features.bid;
      signal.stop_price = features.bid + (features.atr * ATRStopMultiple);
      
      // Extreme Exit Logic: ถ้าค่า Z-score สูงมาก (ราคาแพงมาก) ให้ตั้ง TP ไว้ที่ขอบล่าง
      if(features.zscore >= 2.2) {
         signal.take_profit_price = features.bb_lower;
         signal.reason = "BB Upper Re-entry (Extreme Z-Score TP)";
      } else {
         signal.take_profit_price = features.bb_mid;
         signal.reason = "BB Upper Re-entry (relaxed)";
      }
      
      signal.score = 0.88;
      return true;
   }

   // บันทึกเหตุผลในกรณีที่ไม่เข้าเงื่อนไข Re-entry
   signal.reason = StringFormat("bb_reentry_not_met(c2=%.5f c1=%.5f lower=%.5f upper=%.5f tol=%.5f)",
                                close2, close1, features.bb_lower, features.bb_upper, tol);
   return false;
}

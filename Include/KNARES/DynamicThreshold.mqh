#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "HandleCache.mqh"

//+------------------------------------------------------------------+
//| Dynamic Threshold Module - ระบบคำนวณเกณฑ์และตัวคูณความเสี่ยงแบบไดนามิก    |
//+------------------------------------------------------------------+

/**
 * GetEngineRegimeMultiplier: คำนวณตัวคูณความเสี่ยง (Lot Multiplier) ตามความเหมาะสมระหว่างกลยุทธ์และสภาวะตลาด
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบเงื่อนไขวิกฤต (Risk-Off) หากตลาดอันตรายเกินไปจะคืนค่า 0.0 (ไม่เทรด)
 * 2. ตรวจสอบความสอดคล้องระหว่าง Engine (กลยุทธ์) กับ Regime (สภาวะตลาด):
 *    - TrendEngine: ให้ตัวคูณสูงในตลาดมีเทรนด์ (1.0) และลดลงในตลาดไซด์เวย์
 *    - MeanRevEngine: ให้ตัวคูณสูงในตลาดไซด์เวย์ (1.0) และลดลงในตลาดมีเทรนด์
 *    - BreakoutEngine: ให้ตัวคูณสูงเมื่อตลาดพร้อมเบรคเอาท์ (1.0)
 * 3. หากไม่ตรงเงื่อนไขใดๆ จะคืนค่า Default ที่ 0.5 (ลดความเสี่ยงครึ่งหนึ่ง)
 */
double GetEngineRegimeMultiplier(const string engine_name, const ENUM_REGIME_TYPE regime)
{
   // 1. ถ้าตลาดอยู่ในสถานะ Risk-Off (ห้ามเสี่ยง) ให้หยุดเทรดทันที
   if(regime == REGIME_RISK_OFF) return 0.0;

   // 2. ปรับตัวคูณตามความถนัดของแต่ละกลยุทธ์ (Engine)
   if(engine_name == "TrendEngine")
   {
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) return 1.0;
      if(regime == REGIME_TREND_VOLATILE) return 0.7; // ลดลอตเมื่อเจอเทรนด์ผันผวน
      if(regime == REGIME_RANGE) return 0.3;
      if(regime == REGIME_TRANSITION) return 0.4;
      if(regime == REGIME_UNKNOWN) return 0.5;
   }
   if(engine_name == "MeanRevEngine")
   {
      if(regime == REGIME_RANGE) return 1.0;
      if(regime == REGIME_RANGE_CHOPPY) return 0.8;
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) return 0.3;
      if(regime == REGIME_CHOPPY) return 0.5;
      if(regime == REGIME_UNKNOWN) return 0.6;
   }
   if(engine_name == "BreakoutEngine")
   {
      if(regime == REGIME_BREAKOUT_READY) return 1.0;
      if(regime == REGIME_BREAKOUT_PREP) return 0.9; 
      if(regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) return 0.8; 
      if(regime == REGIME_UNKNOWN) return 0.6; 
   }
   
   return 0.5; // ค่าเริ่มต้นหากไม่ระบุ
}

/**
 * GetRegimeRiskMultiplier: คำนวณตัวคูณความเสี่ยงตามความมั่นใจ (Confidence) ของโมเดล AI
 * อธิบายกระบวนการ:
 * - รับค่า Confidence (0.0 - 1.0) จากผลการทำนายของ AI
 * - แบ่งระดับการลดความเสี่ยงตามความเชื่อมั่น:
 *   - ต่ำกว่า 50%: ลดเหลือ 0.25 (ระวังมาก)
 *   - 50% - 65%: ลดเหลือ 0.50
 *   - 65% - 80%: ลดเหลือ 0.75
 *   - 80% ขึ้นไป: ใช้ความเสี่ยงเต็มที่ 1.0
 */
double GetRegimeRiskMultiplier(const double confidence)
{
   if(confidence < 0.50) return 0.25;
   if(confidence < 0.65) return 0.50;
   if(confidence < 0.80) return 0.75;
   return 1.0;
}

/**
 * GetPostPenaltyFloorByEngine: กำหนดเกณฑ์คะแนนขั้นต่ำ (Floor Score) หลังจากหักลบ Penalty แล้ว
 * อธิบายกระบวนการ:
 * - กำหนดคะแนนขั้นต่ำที่ยอมรับได้สำหรับแต่ละกลยุทธ์จากไฟล์ Config
 * - TrendEngine: มีการเช็คคุณภาพเทรนด์ (ADX และ Slope) ถ้าเทรนด์แรงจะยอมรับคะแนนที่ต่ำกว่าได้ (ยืดหยุ่นกว่า)
 */
double GetPostPenaltyFloorByEngine(const string engine_name, const MarketSnapshot &snap)
{
   if(engine_name == "BreakoutEngine") return MinPostPenaltyScoreBreakout;
   
   if(engine_name == "TrendEngine")
   {
      // ถ้า ADX สูง (เทรนด์ชัด) และ Slope ชัน (แรงส่งดี) ให้ใช้เกณฑ์ High Quality
      if(snap.adx >= 35.0 && MathAbs(snap.ema_slope) > 0.001) return MinPostPenaltyScoreTrendHighQual;
      return MinPostPenaltyScoreTrendBreakout;
   }
   
   if(engine_name == "MeanRevEngine") return MeanRevMinEntryScore;
   return MinEntryScore;
}

/**
 * ComputeEffectiveEntryThreshold: ปรับเกณฑ์คะแนนรวมขั้นต่ำแบบ Adaptive ตามสภาวะตลาดจริง
 * อธิบายกระบวนการ:
 * 1. ดึงค่า Floor Score พื้นฐานของแต่ละ Engine มาตั้งต้น
 * 2. กรณี Breakout: ตรวจสอบว่าสวนเทรนด์หลัก (HTF Trend) หรือไม่ 
 *    - ถ้าสวนเทรนด์ จะเพิ่มเกณฑ์คะแนนให้สูงขึ้น (เข้ายากขึ้น) เว้นแต่ Volume จะสูงมากจริงๆ
 * 3. กรณี Unknown Regime: เพิ่มเกณฑ์ความเข้มงวด เว้นแต่ AI จะมีความมั่นใจสูงมาก
 * 4. กรณี Volatility Storm: ตรวจสอบค่า ATR ล่าสุด เทียบกับค่าเฉลี่ย 50 แท่ง
 *    - ถ้าผันผวนสูงผิดปกติ (เกิน 1.5 เท่า) จะเพิ่มเกณฑ์คะแนน (thr) เพื่อป้องกันการเข้าเทรดในช่วงตลาดบ้าคลั่ง
 */
double ComputeEffectiveEntryThreshold(const SignalPack &sig, const MarketSnapshot &snap, ENUM_REGIME_TYPE reg)
{
   // 1. เริ่มต้นด้วยเกณฑ์คะแนนพื้นฐาน
   double thr = GetPostPenaltyFloorByEngine(sig.engine_name, snap);
   
   // 2. การปรับเกณฑ์สำหรับ Breakout ที่สวนเทรนด์หลัก (Counter-Trend Breakout)
   if(sig.engine_name == "BreakoutEngine")
   {
      bool aligned = (sig.direction == SIGNAL_BUY && snap.htf_trend > 0) ||
                     (sig.direction == SIGNAL_SELL && snap.htf_trend < 0);
      if(!aligned)
      {
         // ถ้าสวนเทรนด์ ต้องใช้ Volume มหาศาลในการยืนยัน (High Conviction)
         bool high_conviction = (double)snap.volume >= snap.vol_median * (UnknownBreakoutMinVolumeMult);
         if(!high_conviction) thr = 0.92; // ไม่ค่อยมั่นใจ ต้องได้คะแนนสูงมากถึงจะเข้า
         else thr = 0.88;
      }
   }

   // 3. การปรับเกณฑ์สำหรับสภาวะตลาดที่ไม่ชัดเจน (Unknown Regime)
   if(reg == REGIME_UNKNOWN)
   {
      // ถ้า AI มั่นใจเกินเกณฑ์ที่ตั้งไว้ ยอมให้ใช้เกณฑ์ปกติ แต่ถ้าไม่มั่นใจ ให้เพิ่มเกณฑ์ไปที่ 0.90
      if(sig.confidence >= UnknownRegimeMinAIConf) thr = UnknownRegimeMinScore;
      else thr = 0.90;
   }

   // 4. การปรับเกณฑ์ในช่วงที่มีความผันผวนสูง (Volatility Storm)
   double current_atr = 0;
   double median_atr = 0;
   int atr_h = HC_ATR(sig.symbol, MainTF, ATRPeriod);
   if(atr_h != INVALID_HANDLE) {
      double atr_buf[];
      if(CopyBuffer(atr_h, 0, 1, 50, atr_buf) >= 50) {
         current_atr = atr_buf[0];
         double atr_sum = 0;
         for(int k=0; k<50; k++) atr_sum += atr_buf[k];
         median_atr = atr_sum / 50.0;
      }
   }
   // ถ้าความผันผวนปัจจุบันสูงกว่าค่าเฉลี่ย 1.5 เท่า ให้เพิ่มความยากในการเข้าเทรด
   if(median_atr > 0 && current_atr > median_atr * 1.5) thr += VolStormScoreIncrease;

   return thr;
}

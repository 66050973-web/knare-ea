#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Regime Classifier Module - ระบบวิเคราะห์และจำแนกสภาวะตลาด            |
//| ทำหน้าที่ระบุว่าตลาดปัจจุบันอยู่ในสถานะใด (เช่น แนวโน้ม, ไซด์เวย์, หรือเสี่ยงสูง) |
//| เพื่อให้ระบบเลือกใช้กลยุทธ์ (Engine) ที่เหมาะสมกับสภาวะนั้นๆ             |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน DetectRegime: วิเคราะห์ข้อมูลตลาดปัจจุบันเพื่อระบุสภาวะตลาด (Market Regime)
 * @param features: ข้อมูล snapshot ของตลาด (ADX, RSI, ATR, EMA, etc.)
 * @return ENUM_REGIME_TYPE: ประเภทของสภาวะตลาดที่ตรวจพบ
 */
ENUM_REGIME_TYPE DetectRegime(const MarketSnapshot &features)
{
   // --- ขั้นตอนที่ 1: ตรวจสอบความเสี่ยง (Risk-Off Check) ---
   // ถ้าค่า Spread สูงเกินไป (สภาพคล่องต่ำ) ให้ถือเป็นสภาวะ RISK_OFF เพื่อความปลอดภัย
   // เนื่องจากในสภาวะที่ค่าสเปรดกว้าง การเข้าเทรดจะมีความเสี่ยงสูงและต้นทุนสูงเกินไป
   if(features.spread_points > RiskOffSpreadPoints) 
   {
      return REGIME_RISK_OFF;
   }

   // --- ขั้นตอนที่ 2: วิเคราะห์แนวโน้ม (Trend Analysis) ---
   // ใช้ ADX ในการวัดความแข็งแกร่งของเทรน และใช้ EMA ในการระบุทิศทาง
   bool is_trending = (features.adx >= ADXTrendThreshold); // ตรวจสอบว่าเทรนมีความแข็งแกร่งเพียงพอหรือไม่
   bool is_up = (features.ema_fast > features.ema_slow);    // ตรวจสอบทิศทางจากความสัมพันธ์ของเส้นค่าเฉลี่ย
   bool high_vol = (features.atr_percentile > 80.0);        // ตรวจสอบว่าความผันผวนอยู่ในระดับสูงมาก (80th percentile) หรือไม่
   
   if(is_trending)
   {
      // ถ้าเทรนแข็งแกร่งแต่ความผันผวนสูงมาก ให้ระวังการสะบัดของราคา (Volatile Trend)
      // สภาวะนี้อาจเกิดการแกว่งตัวแรงในทิศทางเทรน ทำให้ต้องระมัดระวังเป็นพิเศษ
      if(high_vol) return REGIME_TREND_VOLATILE;
      
      // คืนค่าสภาวะเทรนขาขึ้นหรือขาลงตามความสัมพันธ์ของ EMA
      if(is_up) return REGIME_TREND_UP;    // เทรนขาขึ้นชัดเจน
      else      return REGIME_TREND_DOWN;  // เทรนขาลงชัดเจน
   }

   // Phase 9: ตรวจจับสภาวะเปลี่ยนผ่าน (Transition / Possible Trend Reversal)
   // เมื่อ ADX ยังสูง (เคยมีเทรน) แต่ความชันของ EMA เริ่มนิ่ง (Slope ต่ำมาก) 
   // อาจเกิดการกลับตัวของเทรนหรือการพักตัวเพื่อสะสมพลังใหม่
   if(features.adx > 25.0 && MathAbs(features.ema_slope) < 0.0001)
   {
      return REGIME_TRANSITION;
   }

   // --- ขั้นตอนที่ 3: ตรวจสอบสภาวะบีบตัว (Breakout Preparation Analysis) ---
   // วิเคราะห์ช่วงราคา (Range Width) จาก Donchian Channel เทียบกับค่าความผันผวน (ATR)
   // เพื่อหาจุดที่ราคาวิ่งแคบลงและกำลังสะสมพลัง (Squeeze)
   double range_width = features.donchian_high - features.donchian_low;
   double range_atr_ratio = (features.atr > 0) ? range_width / features.atr : 10.0;
   
   if(range_atr_ratio < 2.5 && features.adx < 22.0)
   {
      // ถ้าความผันผวนต่ำมาก (ATR Percentile ต่ำกว่า 15) แสดงว่าราคาบีบตัวรุนแรง พร้อมที่จะเกิดการระเบิด (Breakout)
      if(features.atr_percentile < 15.0) return REGIME_BREAKOUT_PREP;
      // สภาวะทั่วไปที่พร้อมสำหรับการเบรคเอาท์
      return REGIME_BREAKOUT_READY;
   }

   // --- ขั้นตอนที่ 4: วิเคราะห์สภาวะไซด์เวย์ (Choppy / Range Analysis) ---
   // เมื่อค่า ADX ต่ำ (ต่ำกว่า 20) แสดงว่าตลาดไม่มีเทรนที่ชัดเจน
   if(features.adx < 20.0)
   {
      // หาก ADX ต่ำแต่ ATR สูง (ATR Percentile > 70) 
      // แสดงว่าราคาเหวี่ยงแรงแต่ไร้ทิศทาง ซึ่งเรียกว่าสภาวะ Choppy Market (ตลาดฟันปลา)
      if(features.atr_percentile > 70.0) return REGIME_CHOPPY;
      
      // หากความผันผวนปานกลางและราคามีการเหวี่ยงออกจากค่าเฉลี่ยอย่างชัดเจน (Z-Score สูง)
      // ในขณะที่ไม่มีเทรน แสดงว่าเป็นตลาดไซด์เวย์ที่มีการเหวี่ยงตัวแรง (Range Choppy)
      if(features.atr_percentile > 40.0 && MathAbs(features.zscore) > 1.5) return REGIME_RANGE_CHOPPY;
      
      // สภาวะตลาดไซด์เวย์ปกติ (Range) ราคาแกว่งในกรอบแคบ เหมาะกับกลยุทธ์ Mean Reversion
      return REGIME_RANGE;
   }

   // Phase 23: ระบบสำรอง (Default Fallbacks) 
   // หากไม่เข้าเงื่อนไขใดๆ ข้างต้น จะใช้ความชันของ EMA (EMA Slope) เป็นเกณฑ์สุดท้าย
   // เพื่อระบุทิศทางพื้นฐาน แทนการระบุว่าเป็น Unknown ทันที
   if(MathAbs(features.ema_slope) > 0.0005) 
      return (features.ema_slope > 0) ? REGIME_TREND_UP : REGIME_TREND_DOWN;

   // หากไม่สามารถระบุสภาวะที่ชัดเจนได้จริงๆ ให้คืนค่าเป็น Unknown
   return REGIME_UNKNOWN; 
}

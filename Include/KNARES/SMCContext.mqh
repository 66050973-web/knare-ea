#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#ifndef __KNARES_SMC_CONTEXT_MQH__
#define __KNARES_SMC_CONTEXT_MQH__

#include "Types.mqh"
#include "HandleCache.mqh"

//+------------------------------------------------------------------+
//| Smart Money Concepts Context Layer                               |
//| Purpose: ให้ข้อมูลบริบท SMC สำหรับคัดกรองสัญญาณ KNARES ที่มีอยู่          |
//| ไม่ได้เลียนแบบ LuxAlgo แต่ใช้หลักการ SMC ทั่วไป: โครงสร้างราคา (Structure), |
//| การเบรคโครงสร้าง (BOS/CHoCH), และโซนราคาสูง/ต่ำ (Premium/Discount)     |
//+------------------------------------------------------------------+

// ENUM_SMC_BIAS: กำหนดทิศทางแนวโน้มตามหลัก SMC
enum ENUM_SMC_BIAS
{
   SMC_BIAS_NEUTRAL = 0,   // เป็นกลาง (ไม่มีทิศทางชัดเจน)
   SMC_BIAS_BULLISH = 1,   // ขาขึ้น (โครงสร้างราคายกตัวขึ้น)
   SMC_BIAS_BEARISH = -1   // ขาลง (โครงสร้างราคาลดตัวลง)
};

// ENUM_SMC_ZONE: กำหนดโซนราคาตามหลัก SMC (Premium/Discount) อิงตาม Swing Range
enum ENUM_SMC_ZONE
{
   SMC_ZONE_UNKNOWN = 0,
   SMC_ZONE_DISCOUNT = 1,    // โซนราคาถูก (เหมาะสำหรับพิจารณาฝั่งซื้อ)
   SMC_ZONE_EQUILIBRIUM = 2, // โซนราคาสมดุล (ราคาอยู่แถวค่ากลางของกรอบ)
   SMC_ZONE_PREMIUM = 3      // โซนราคาแพง (เหมาะสำหรับพิจารณาฝั่งขาย)
};

// SMCContext: โครงสร้างข้อมูลสำหรับจัดเก็บสถานะ SMC ปัจจุบันเพื่อส่งต่อให้ระบบกรองสัญญาณ
struct SMCContext
{
   bool valid;
   ENUM_SMC_BIAS bias;           // แนวโน้มหลัก (ตัดสินใจร่วมกันจากหลายองค์ประกอบ)
   ENUM_SMC_BIAS internal_bias;  // แนวโน้มภายใน (Internal Structure - กรอบเล็ก)
   ENUM_SMC_BIAS higher_bias;    // แนวโน้มในไทม์เฟรมที่สูงกว่า (HTF Structure - กรอบใหญ่)
   ENUM_SMC_ZONE zone;           // โซนราคาปัจจุบัน (Premium/Discount/Equilibrium)
   double range_high;            // ราคาสูงสุดของกรอบ Swing ล่าสุด
   double range_low;             // ราคาต่ำสุดของกรอบ Swing ล่าสุด
   double range_mid;             // ราคากลางของกรอบ (50% Fibonacci level)
   double position_in_range;     // ตำแหน่งราคาปัจจุบันในกรอบ (0.0 = Low, 1.0 = High)
   bool bullish_bos;             // พบการเบรคโครงสร้างขาขึ้น (Break of Structure - Buy)
   bool bearish_bos;             // พบการเบรคโครงสร้างขาลง (Break of Structure - Sell)
   bool bullish_choch;           // พบการเปลี่ยนโครงสร้างขาขึ้น (Change of Character - Buy)
   bool bearish_choch;           // พบการเปลี่ยนโครงสร้างขาลง (Change of Character - Sell)
   bool htf_aligned_buy;         // สภาวะ HTF สอดคล้องกับการเล่นฝั่งซื้อ
   bool htf_aligned_sell;        // สภาวะ HTF สอดคล้องกับการเล่นฝั่งขาย
   
   // Phase 40: ข้อมูลการยืนยันเชิงลึก (Deep Confirmation)
   bool bullish_displacement;    // พบการเคลื่อนที่ของราคาอย่างรุนแรงในทิศทางขาขึ้น (Impulsive move)
   bool bearish_displacement;    // พบการเคลื่อนที่ของราคาอย่างรุนแรงในทิศทางขาลง
   bool bullish_retest;          // พบการทดสอบแนวราคาสำคัญ (เช่น EQ) แล้วเด้งขึ้น
   bool bearish_retest;          // พบการทดสอบแนวราคาสำคัญแล้วร่วงลง
   bool bullish_liquidity_sweep; // พบการกวาดสภาพคล่องด้านล่าง (ล่า SL) ก่อนจะดีดกลับ
   bool bearish_liquidity_sweep; // พบการกวาดสภาพคล่องด้านบนก่อนจะร่วงลง
   double buy_quality;           // คะแนนคุณภาพรวมสำหรับการเทรดฝั่งซื้อ (0.0 - 1.0)
   double sell_quality;          // คะแนนคุณภาพรวมสำหรับการเทรดฝั่งขาย (0.0 - 1.0)
   
   string reason;                // บันทึกเหตุผลหรือข้อผิดพลาด
};

/**
 * ฟังก์ชัน SMCBiasToString: แปลงสถานะ Bias เป็นข้อความ
 */
string SMCBiasToString(ENUM_SMC_BIAS bias)
{
   if(bias == SMC_BIAS_BULLISH) return "BULLISH";
   if(bias == SMC_BIAS_BEARISH) return "BEARISH";
   return "NEUTRAL";
}

/**
 * ฟังก์ชัน SMCZoneToString: แปลงสถานะ Zone เป็นข้อความ
 */
string SMCZoneToString(ENUM_SMC_ZONE zone)
{
   if(zone == SMC_ZONE_DISCOUNT) return "DISCOUNT";
   if(zone == SMC_ZONE_EQUILIBRIUM) return "EQUILIBRIUM";
   if(zone == SMC_ZONE_PREMIUM) return "PREMIUM";
   return "UNKNOWN";
}

/**
 * ฟังก์ชัน SMCGetRange: คำนวณหา High และ Low ล่าสุดจากจำนวนแท่งเทียนที่กำหนด (Swing Lookback)
 */
bool SMCGetRange(const string symbol, ENUM_TIMEFRAMES tf, int lookback, double &high, double &low)
{
   if(lookback < 5) lookback = 5;
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 1, lookback, rates);
   if(copied < 5) return false;

   high = rates[0].high;
   low  = rates[0].low;
   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > high) high = rates[i].high;
      if(rates[i].low  < low)  low  = rates[i].low;
   }
   return (high > low);
}

/**
 * ฟังก์ชัน SMCGetPreviousRange: คำนวณหา High/Low ของกรอบก่อนหน้า (ใช้สำหรับตรวจจับ BOS)
 */
bool SMCGetPreviousRange(const string symbol, ENUM_TIMEFRAMES tf, int lookback, double &high, double &low)
{
   if(lookback < 5) lookback = 5;
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 2, lookback, rates); // เริ่มต้นที่แท่งที่ 2
   if(copied < 5) return false;

   high = rates[0].high;
   low  = rates[0].low;
   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > high) high = rates[i].high;
      if(rates[i].low  < low)  low  = rates[i].low;
   }
   return (high > low);
}

/**
 * ฟังก์ชัน SMCComputeZone: คำนวณโซนราคา (Premium/Discount) ตามตำแหน่งปัจจุบันในกรอบ
 */
ENUM_SMC_ZONE SMCComputeZone(double pos)
{
   if(pos < 0.0 || pos > 1.0) return SMC_ZONE_UNKNOWN;
   if(pos <= SMCDiscountLevel) return SMC_ZONE_DISCOUNT;
   if(pos >= SMCPremiumLevel) return SMC_ZONE_PREMIUM;
   return SMC_ZONE_EQUILIBRIUM;
}

/**
 * ฟังก์ชัน SMCComputeSimpleBias: คำนวณทิศทางโครงสร้างราคาเบื้องต้น (BOS/CHoCH)
 */
ENUM_SMC_BIAS SMCComputeSimpleBias(const string symbol,
                                   ENUM_TIMEFRAMES tf,
                                   int lookback,
                                   double neutral_band,
                                   bool &bull_bos,
                                   bool &bear_bos,
                                   bool &bull_choch,
                                   bool &bear_choch)
{
   bull_bos = false;
   bear_bos = false;
   bull_choch = false;
   bear_choch = false;

   double rh, rl, prev_h, prev_l;
   if(!SMCGetRange(symbol, tf, lookback, rh, rl)) return SMC_BIAS_NEUTRAL;
   if(!SMCGetPreviousRange(symbol, tf, lookback, prev_h, prev_l)) return SMC_BIAS_NEUTRAL;

   double close1 = iClose(symbol, tf, 1);
   double close2 = iClose(symbol, tf, 2);
   if(close1 <= 0.0 || close2 <= 0.0) return SMC_BIAS_NEUTRAL;

   double mid = (rh + rl) * 0.5;

   // ตรวจจับ Break of Structure (BOS): ราคาปิดทะลุ High หรือ Low ของกรอบก่อนหน้า
   bull_bos = (close1 > prev_h);
   bear_bos = (close1 < prev_l);

   // ตรวจจับ Change of Character (CHoCH) เบื้องต้น: ราคาข้ามเส้นกึ่งกลางกรอบหลังมาจากฝั่งตรงข้าม
   bull_choch = (close2 < mid && close1 > mid);
   bear_choch = (close2 > mid && close1 < mid);

   // สรุปทิศทางโครงสร้างราคา
   if((bull_bos || bull_choch) && !(bear_bos || bear_choch)) return SMC_BIAS_BULLISH;
   if((bear_bos || bear_choch) && !(bull_bos || bull_choch)) return SMC_BIAS_BEARISH;
   if(bull_bos && !bear_bos) return SMC_BIAS_BULLISH;
   if(bear_bos && !bull_bos) return SMC_BIAS_BEARISH;
   return SMC_BIAS_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Phase 40: ระบบตรวจจับการยืนยันเชิงลึก (Deep SMC Confirmation)       |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน SMCDetectDisplacement: ตรวจหาการเคลื่อนที่ของราคาอย่างรุนแรง (Impulse)
 */
bool SMCDetectDisplacement(const string symbol, ENUM_TIMEFRAMES tf, bool bullish, double &displacement_score)
{
   displacement_score = 0.0;
   MqlRates rates[];
   if(CopyRates(symbol, tf, 1, 1, rates) < 1) return false;
   
   double atr = 0;
   int h = HC_ATR(symbol, tf, 14);
   if(h != INVALID_HANDLE)
   {
      double buf[];
      if(CopyBuffer(h, 0, 0, 1, buf) > 0) atr = buf[0];
   }
   if(atr <= 0) return false;
   
   double body = MathAbs(rates[0].close - rates[0].open);
   double range = rates[0].high - rates[0].low;
   if(range <= 0) return false;
   
   // เช็คว่าเนื้อเทียน (Body) ยาวกว่าค่า ATR ตามเกณฑ์ที่กำหนดหรือไม่
   bool is_impulse = (body > atr * SMCDisplacementBodyATR);
   
   if(bullish)
   {
      // ตรวจสอบว่าราคาปิดอยู่ใกล้จุดสูงสุดของแท่งเทียนหรือไม่
      bool close_near_top = (rates[0].close >= rates[0].low + range * SMCDisplacementCloseTopPct);
      if(is_impulse && rates[0].close > rates[0].open && close_near_top)
      {
         displacement_score = body / atr;
         return true;
      }
   }
   else
   {
      // สำหรับฝั่งขาลง
      bool close_near_bot = (rates[0].close <= rates[0].high - range * SMCDisplacementCloseTopPct);
      if(is_impulse && rates[0].close < rates[0].open && close_near_bot)
      {
         displacement_score = body / atr;
         return true;
      }
   }
   
   return false;
}

/**
 * ฟังก์ชัน SMCDetectRetest: ตรวจหาการย่อตัวเพื่อทดสอบแนวกึ่งกลาง (EQ)
 */
bool SMCDetectRetest(const string symbol, ENUM_TIMEFRAMES tf, bool bullish, double range_mid)
{
   MqlRates rates[];
   if(CopyRates(symbol, tf, 1, SMCRetestLookbackBars, rates) < SMCRetestLookbackBars) return false;
   
   double atr = 0;
   int h = HC_ATR(symbol, tf, 14);
   if(h != INVALID_HANDLE)
   {
      double buf[];
      if(CopyBuffer(h, 0, 0, 1, buf) > 0) atr = buf[0];
   }
   if(atr <= 0) return false;
   double tolerance = atr * SMCRetestToleranceATR;
   
   if(bullish)
   {
      // ตรวจสอบว่ามีแท่งเทียนใดที่ไส้ล่าง (Low) ลงไปแตะใกล้ EQ แล้วปิดยืนเหนือได้
      for(int i=0; i<SMCRetestLookbackBars; i++)
      {
         if(rates[i].low <= range_mid + tolerance && rates[i].close > range_mid)
            return true;
      }
   }
   else
   {
      for(int i=0; i<SMCRetestLookbackBars; i++)
      {
         if(rates[i].high >= range_mid - tolerance && rates[i].close < range_mid)
            return true;
      }
   }
   return false;
}

/**
 * ฟังก์ชัน SMCDetectLiquiditySweep: ตรวจหาการกวาดสภาพคล่อง (Liquidity Sweep)
 */
bool SMCDetectLiquiditySweep(const string symbol, ENUM_TIMEFRAMES tf, bool bullish)
{
   MqlRates rates[];
   int lookback = SMCLiquiditySweepLookback;
   if(CopyRates(symbol, tf, 1, lookback + 1, rates) < lookback + 1) return false;
   
   // แท่งปัจจุบันคือ rates[lookback]
   double cur_low = rates[lookback].low;
   double cur_high = rates[lookback].high;
   double cur_close = rates[lookback].close;
   
   if(bullish)
   {
      // หาจุดต่ำสุดของแท่งเทียนก่อนหน้า
      double min_low = rates[0].low;
      for(int i=1; i<lookback; i++) if(rates[i].low < min_low) min_low = rates[i].low;
      
      // Sweep: จุดต่ำสุดปัจจุบันทะลุแนวรับเดิมลงไป แต่ราคาปิดดึงกลับขึ้นมายืนเหนือแนวเดิมได้
      if(cur_low < min_low && cur_close > min_low) return true;
   }
   else
   {
      // หาจุดสูงสุดของแท่งเทียนก่อนหน้า
      double max_high = rates[0].high;
      for(int i=1; i<lookback; i++) if(rates[i].high > max_high) max_high = rates[i].high;
      
      if(cur_high > max_high && cur_close < max_high) return true;
   }
   
   return false;
}

/**
 * ฟังก์ชัน ComputeSMCBuyQuality: คำนวณคะแนนคุณภาพสำหรับการซื้อ (Buy Setup Quality)
 */
double ComputeSMCBuyQuality(const SMCContext &ctx, const MarketSnapshot &snap)
{
   double score = 0.50; // คะแนนเริ่มต้น
   
   // ปรับคะแนนตามองค์ประกอบ SMC
   if(ctx.bias == SMC_BIAS_BULLISH) score += 0.15;
   if(ctx.bullish_bos) score += 0.10;
   if(ctx.bullish_choch) score += 0.08;
   
   // เช็คตำแหน่งในกรอบ (Discount zone ให้คะแนนเพิ่ม)
   if(ctx.position_in_range >= 0.30 && ctx.position_in_range <= 0.85) score += 0.05;
   if(ctx.higher_bias != SMC_BIAS_BEARISH) score += 0.05;
   
   // เพิ่มคะแนนจากการยืนยันเชิงลึก
   if(ctx.bullish_displacement) score += 0.10;
   if(ctx.bullish_retest) score += 0.10;
   if(ctx.bullish_liquidity_sweep) score += 0.10;
   
   // บทลงโทษ (Penalties) สำหรับกรณีที่ขัดแย้งกับหลัก SMC
   if(ctx.bias == SMC_BIAS_NEUTRAL) score -= 0.15;
   if(ctx.bias == SMC_BIAS_BEARISH) score -= 0.25;
   if(ctx.position_in_range >= 0.96) score -= 0.15; // ราคาแพงเกินไป
   if(ctx.higher_bias == SMC_BIAS_BEARISH) score -= 0.20;
   if(ctx.bearish_choch) score -= 0.20;
   
   if(ctx.zone == SMC_ZONE_PREMIUM && !ctx.bullish_bos) score -= 0.15;
   if(!ctx.bullish_retest) score -= 0.10;
   
   return MathMax(0.0, MathMin(1.0, score));
}

/**
 * ฟังก์ชัน ComputeSMCSellQuality: คำนวณคะแนนคุณภาพสำหรับการขาย (Sell Setup Quality)
 */
double ComputeSMCSellQuality(const SMCContext &ctx, const MarketSnapshot &snap)
{
   double score = 0.50;
   
   if(ctx.bias == SMC_BIAS_BEARISH) score += 0.15;
   if(ctx.bearish_bos) score += 0.10;
   if(ctx.bearish_choch) score += 0.08;
   
   if(ctx.position_in_range >= 0.15 && ctx.position_in_range <= 0.70) score += 0.05;
   if(ctx.higher_bias != SMC_BIAS_BULLISH) score += 0.05;
   
   if(ctx.bearish_displacement) score += 0.10;
   if(ctx.bearish_retest) score += 0.10;
   if(ctx.bearish_liquidity_sweep) score += 0.10;
   
   // Penalties
   if(ctx.bias == SMC_BIAS_NEUTRAL) score -= 0.15;
   if(ctx.bias == SMC_BIAS_BULLISH) score -= 0.25;
   if(ctx.position_in_range <= 0.04) score -= 0.15; // ราคาถูกเกินไปที่จะขาย
   if(ctx.higher_bias == SMC_BIAS_BULLISH) score -= 0.20;
   if(ctx.bullish_choch) score -= 0.20;
   
   if(ctx.zone == SMC_ZONE_DISCOUNT && !ctx.bearish_bos) score -= 0.15;
   if(!ctx.bearish_retest) score -= 0.10;
   
   return MathMax(0.0, MathMin(1.0, score));
}

/**
 * ฟังก์ชัน BuildSMCContext: รวบรวมข้อมูลทั้งหมดเพื่อสร้าง SMC Context ปัจจุบัน
 */
bool BuildSMCContext(const string symbol, const MarketSnapshot &snap, SMCContext &ctx)
{
   // รีเซ็ตข้อมูล
   ctx.valid = false;
   ctx.bias = SMC_BIAS_NEUTRAL;
   ctx.internal_bias = SMC_BIAS_NEUTRAL;
   ctx.higher_bias = SMC_BIAS_NEUTRAL;
   ctx.zone = SMC_ZONE_UNKNOWN;
   ctx.range_high = 0.0;
   ctx.range_low = 0.0;
   ctx.range_mid = 0.0;
   ctx.position_in_range = 0.5;
   ctx.bullish_bos = false;
   ctx.bearish_bos = false;
   ctx.bullish_choch = false;
   ctx.bearish_choch = false;
   ctx.htf_aligned_buy = true;
   ctx.htf_aligned_sell = true;
   ctx.reason = "";

   double rh, rl;
   // คำนวณกรอบ Swing Range ในไทม์เฟรมหลักที่ใช้ดูโครงสร้าง
   if(!SMCGetRange(symbol, SMCStructureTF, SMCSwingLookbackBars, rh, rl))
   {
      ctx.reason = "smc_no_structure_range";
      return false;
   }

   ctx.range_high = rh;
   ctx.range_low = rl;
   ctx.range_mid = (rh + rl) * 0.5;
   // หาตำแหน่งราคาปัจจุบันในกรอบ
   double price = (snap.bid > 0.0 && snap.ask > 0.0) ? ((snap.bid + snap.ask) * 0.5) : iClose(symbol, SMCStructureTF, 1);
   double rng = MathMax(_Point, rh - rl);
   ctx.position_in_range = MathMax(0.0, MathMin(1.0, (price - rl) / rng));
   ctx.zone = SMCComputeZone(ctx.position_in_range);

   bool ibos_bull=false, ibos_bear=false, ichoch_bull=false, ichoch_bear=false;
   bool hbos_bull=false, hbos_bear=false, hchoch_bull=false, hchoch_bear=false;

   // คำนวณ Bias จากทั้งกรอบภายในและกรอบใหญ่ (HTF)
   ctx.internal_bias = SMCComputeSimpleBias(symbol, SMCStructureTF, SMCInternalLookbackBars,
                                            SMCNeutralBand, ibos_bull, ibos_bear, ichoch_bull, ichoch_bear);
   ctx.higher_bias = SMCComputeSimpleBias(symbol, SMCHigherTF, SMCSwingLookbackBars,
                                          SMCNeutralBand, hbos_bull, hbos_bear, hchoch_bull, hchoch_bear);

   ctx.bullish_bos = ibos_bull || hbos_bull;
   ctx.bearish_bos = ibos_bear || hbos_bear;
   ctx.bullish_choch = ichoch_bull || hchoch_bull;
   ctx.bearish_choch = ichoch_bear || hchoch_bear;

   // การตัดสินทิศทางแนวโน้มหลัก (Bias Resolution)
   // ถ้ากำหนดให้ต้องตาม HTF เป็นหลัก จะใช้ higher_bias
   if(SMCRequireHTFAlignment)
      ctx.bias = ctx.higher_bias;
   else if(ctx.higher_bias != SMC_BIAS_NEUTRAL)
      ctx.bias = ctx.higher_bias;
   else
      ctx.bias = ctx.internal_bias;

   if(ctx.bias == SMC_BIAS_NEUTRAL && ctx.internal_bias != SMC_BIAS_NEUTRAL && !SMCRequireHTFAlignment)
      ctx.bias = ctx.internal_bias;

   ctx.htf_aligned_buy = (ctx.higher_bias != SMC_BIAS_BEARISH);
   ctx.htf_aligned_sell = (ctx.higher_bias != SMC_BIAS_BULLISH);

   // Phase 40: เก็บข้อมูลการยืนยันเชิงลึกและคะแนนคุณภาพ
   double dscore = 0;
   ctx.bullish_displacement = SMCDetectDisplacement(symbol, SMCStructureTF, true, dscore);
   ctx.bearish_displacement = SMCDetectDisplacement(symbol, SMCStructureTF, false, dscore);
   ctx.bullish_retest = SMCDetectRetest(symbol, SMCStructureTF, true, ctx.range_mid);
   ctx.bearish_retest = SMCDetectRetest(symbol, SMCStructureTF, false, ctx.range_mid);
   ctx.bullish_liquidity_sweep = SMCDetectLiquiditySweep(symbol, SMCStructureTF, true);
   ctx.bearish_liquidity_sweep = SMCDetectLiquiditySweep(symbol, SMCStructureTF, false);
   
   ctx.buy_quality = ComputeSMCBuyQuality(ctx, snap);
   ctx.sell_quality = ComputeSMCSellQuality(ctx, snap);

   ctx.valid = true;
   return true;
}

/**
 * ฟังก์ชัน SMCContextSummary: สร้างข้อความสรุปสถานะ SMC สำหรับใช้ในการ Log ข้อมูล
 */
string SMCContextSummary(const string symbol, const SMCContext &ctx)
{
   if(!ctx.valid)
      return StringFormat("SMCContext[%s]: valid=false reason=%s", symbol, ctx.reason);

   return StringFormat(
      "SMCContext[%s]: bias=%s internal=%s htf=%s zone=%s pos=%.2f range=%.2f..%.2f bos(B/S)=%s/%s choch(B/S)=%s/%s quality(B/S)=%.2f/%.2f",
      symbol,
      SMCBiasToString(ctx.bias),
      SMCBiasToString(ctx.internal_bias),
      SMCBiasToString(ctx.higher_bias),
      SMCZoneToString(ctx.zone),
      ctx.position_in_range,
      ctx.range_low,
      ctx.range_high,
      ctx.bullish_bos ? "true" : "false",
      ctx.bearish_bos ? "true" : "false",
      ctx.bullish_choch ? "true" : "false",
      ctx.bearish_choch ? "true" : "false",
      ctx.buy_quality,
      ctx.sell_quality
   );
}

#endif // __KNARES_SMC_CONTEXT_MQH__

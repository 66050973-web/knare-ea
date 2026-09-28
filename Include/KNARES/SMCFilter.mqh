#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#ifndef __KNARES_SMC_FILTER_MQH__
#define __KNARES_SMC_FILTER_MQH__

#include "Types.mqh"
#include "SMCContext.mqh"

//+------------------------------------------------------------------+
//| SMC Filter Layer                                                 |
//| ทำหน้าที่เป็นชั้นกรอง (Filter) หรือปรับคะแนน (Score Adjustment)       |
//| โดยใช้บริบท SMC กับสัญญาณ KNARES ที่มีอยู่ SMC ในที่นี้จงใจ          |
//| ไม่ได้ออกแบบมาเพื่อเป็นเครื่องมือสร้างจุดเข้า (Entry Engine) โดยตรง     |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชัน SMCIsStrongAlignedTrend: ตรวจสอบความสอดคล้องของเทรนด์ที่แข็งแกร่งกับบริบท SMC
 */
bool SMCIsStrongAlignedTrend(const bool is_buy, const bool is_sell, const MarketSnapshot &snap, const SMCContext &ctx)
{
   // ถ้าค่า ADX ต่ำกว่าเกณฑ์ แสดงว่าเทรนด์ไม่แข็งแรงพอที่จะใช้ลอจิกนี้
   if(snap.adx < SMCZoneHybridADX)
      return false;

   // กรณีฝั่งซื้อ: เทรนด์ในไทม์เฟรมสูง (HTF) ต้องไม่เป็นขาลง และ Bias ของ SMC ต้องไม่เป็นขาลง
   if(is_buy)
      return (snap.htf_trend >= 0 && ctx.bias != SMC_BIAS_BEARISH);

   // กรณีฝั่งขาย: HTF ต้องไม่เป็นขาขึ้น และ SMC Bias ต้องเป็นขาลงชัดเจน
   if(is_sell)
      return (snap.htf_trend <= 0 && ctx.bias == SMC_BIAS_BEARISH);

   return false;
}

/**
 * ฟังก์ชัน SMCIsRuntimeTrendUp: ตรวจสอบว่าสภาวะตลาดปัจจุบัน (Runtime Regime) เป็นขาขึ้นหรือไม่
 */
bool SMCIsRuntimeTrendUp(const ENUM_REGIME_TYPE runtime_regime)
{
   return (runtime_regime == REGIME_TREND_UP);
}

/**
 * ฟังก์ชัน SMCIsRuntimeTrendDown: ตรวจสอบว่าสภาวะตลาดปัจจุบันเป็นขาลงหรือไม่
 */
bool SMCIsRuntimeTrendDown(const ENUM_REGIME_TYPE runtime_regime)
{
   return (runtime_regime == REGIME_TREND_DOWN);
}

/**
 * ฟังก์ชัน SMCIsRuntimeRangeLike: ตรวจสอบว่าตลาดมีลักษณะเป็น Sideway หรือไม่
 */
bool SMCIsRuntimeRangeLike(const ENUM_REGIME_TYPE runtime_regime)
{
   return (runtime_regime == REGIME_RANGE || runtime_regime == REGIME_RANGE_CHOPPY ||
           runtime_regime == REGIME_CHOPPY || runtime_regime == REGIME_TRANSITION);
}

/**
 * ฟังก์ชัน SMCIsRuntimeUnknownLike: ตรวจสอบว่าตลาดอยู่ในสภาวะที่ไม่ชัดเจนหรือมีความผันผวนผิดปกติหรือไม่
 */
bool SMCIsRuntimeUnknownLike(const ENUM_REGIME_TYPE runtime_regime)
{
   return (runtime_regime == REGIME_UNKNOWN || runtime_regime == REGIME_RISK_OFF ||
           runtime_regime == REGIME_VOLATILITY_SHOCK);
}

/**
 * ฟังก์ชัน SMCIsBuyPremiumContinuationAllowed: ตรวจสอบว่าอนุญาตให้ซื้อต่อเนื่องในโซน Premium หรือไม่
 * ใช้ในกรณีที่ตลาดเป็นเทรนด์ขาขึ้นที่แข็งแรงมาก แม้ราคาจะอยู่ในโซนที่ถือว่า "แพง" ตามหลัก SMC
 */
bool SMCIsBuyPremiumContinuationAllowed(const MarketSnapshot &snap,
                                        const ENUM_REGIME_TYPE runtime_regime,
                                        const SMCContext &ctx)
{
   if(!SMCBuyPremiumAllowTrendUpPenalty)
      return false;

   // ตรวจสอบเงื่อนไขประกอบ: เทรนด์ขาขึ้นชัดเจน, โครงสร้างไม่ขัดแย้ง, ความชันเป็นบวก และ ADX สูงพอ
   bool runtime_up = SMCIsRuntimeTrendUp(runtime_regime);
   bool structure_not_bearish = (ctx.bias != SMC_BIAS_BEARISH);
   bool slope_ok = (snap.ema_slope > 0.0);
   bool adx_ok = (snap.adx >= SMCBuyPremiumAllowADX);
   return (runtime_up && structure_not_bearish && slope_ok && adx_ok);
}

/**
 * ฟังก์ชัน SMCIsBullishBreakoutConfirmation: ตรวจสอบการยืนยันการทะลุโครงสร้างขาขึ้นจาก SMC
 */
bool SMCIsBullishBreakoutConfirmation(const SMCContext &ctx)
{
   // ยืนยันเมื่อพบ Bullish BOS, Bullish CHoCH หรือ Bias เป็นขาขึ้น
   return (ctx.bullish_bos || ctx.bullish_choch || ctx.bias == SMC_BIAS_BULLISH);
}

/**
 * ฟังก์ชัน SMCShouldBlockBuyPremiumExtreme: ตรวจสอบว่าควรบล็อกการซื้อในโซน Premium ที่ราคาสูงสุดโต่งหรือไม่
 */
bool SMCShouldBlockBuyPremiumExtreme(const MarketSnapshot &snap,
                                     const ENUM_REGIME_TYPE runtime_regime,
                                     const SMCContext &ctx,
                                     string &block_reason)
{
   // ทำงานเฉพาะเมื่อราคาอยู่ในโซน Premium
   if(ctx.zone != SMC_ZONE_PREMIUM)
      return false;

   // ตรวจสอบระดับความสูงของราคาในกรอบ (Position in Range)
   if(SMCBuyPremiumExtremePos > 0.0 && ctx.position_in_range >= SMCBuyPremiumExtremePos)
   {
      // บล็อกหากราคาอยู่ในระดับสูงมาก (Ultra Extreme) แต่ไม่มี Bullish Bias ยืนยัน
      if(SMCBuyUltraExtremeRequireBullishBias && ctx.position_in_range >= SMCBuyUltraExtremePos && ctx.bias != SMC_BIAS_BULLISH)
      {
         block_reason = StringFormat("block_smc_buy_ultra_extreme_not_bullish(pos=%.2f ultra=%.2f bias=%s)", ctx.position_in_range, SMCBuyUltraExtremePos, SMCBiasToString(ctx.bias));
         return true;
      }
      // บล็อกหากราคาอยู่ในระดับ Extreme และไม่มี Bullish Bias
      if(SMCBuyPremiumExtremeRequireBullishBias && ctx.bias != SMC_BIAS_BULLISH)
      {
         block_reason = StringFormat("block_smc_buy_extreme_premium_not_bullish(pos=%.2f bias=%s)", ctx.position_in_range, SMCBiasToString(ctx.bias));
         return true;
      }

      // บล็อกหากเทรนด์ HTF ขัดแย้ง (เป็นขาลง)
      if(SMCBuyPremiumExtremeBlockHTFBearish && snap.htf_trend < 0)
      {
         block_reason = StringFormat("block_smc_buy_extreme_premium_htf_conflict(pos=%.2f htf=%.0f)", ctx.position_in_range, snap.htf_trend);
         return true;
      }

      // บล็อกหากไม่มีการยืนยัน Breakout
      if(SMCBuyPremiumExtremeRequireBreakout && !SMCIsBullishBreakoutConfirmation(ctx))
      {
         block_reason = StringFormat("block_smc_buy_extreme_premium_no_breakout(pos=%.2f bias=%s)", ctx.position_in_range, SMCBiasToString(ctx.bias));
         return true;
      }
   }

   // ตรวจสอบเกณฑ์ราคาสูงสุดที่ยอมรับได้หากไม่มีการยืนยัน Breakout
   if(SMCBuyMaxPremiumPositionWithoutBreakout > 0.0 &&
      ctx.position_in_range > SMCBuyMaxPremiumPositionWithoutBreakout &&
      !SMCIsBullishBreakoutConfirmation(ctx))
   {
      bool can_continue = SMCIsBuyPremiumContinuationAllowed(snap, runtime_regime, ctx) &&
                          (SMCBuyPremiumExtremePos <= 0.0 || ctx.position_in_range < SMCBuyPremiumExtremePos);
      if(!can_continue)
      {
         block_reason = StringFormat("block_smc_buy_premium_above_max_no_breakout(pos=%.2f max=%.2f)", ctx.position_in_range, SMCBuyMaxPremiumPositionWithoutBreakout);
         return true;
      }
   }

   return false;
}

/**
 * ฟังก์ชัน SMCShouldPassGradedADX: ระบบคัดกรองสัญญาณตามระดับความแรงของ ADX (Graded Filter)
 * ใช้คัดกรองเฉพาะ Trend Engine เพื่อป้องกันสัญญาณหลอกในสภาวะที่ไม่มีเทรนด์
 */
bool SMCShouldPassGradedADX(const string symbol,
                            SignalPack &signal,
                            const MarketSnapshot &snap,
                            const ENUM_REGIME_TYPE runtime_regime,
                            const SMCContext &ctx,
                            const bool is_buy,
                            const bool is_sell,
                            string &block_reason)
{
   if(signal.engine_name != "TrendEngine" || SMCTrendMinADX <= 0.0)
      return true;

   // กรณีไม่ได้ใช้ Graded ADX: ใช้ค่าคงที่ในการตัดทิ้งทันที
   if(!SMCUseGradedADXFilter)
   {
      if(snap.adx < SMCTrendMinADX)
      {
         block_reason = StringFormat("block_smc_trend_adx_floor(adx=%.2f floor=%.2f)", snap.adx, SMCTrendMinADX);
         return false;
      }
      return true;
   }

   // ระดับการบล็อกแบบเด็ดขาด (Hard Block)
   if(snap.adx < SMCADXHardBlockBelow)
   {
      block_reason = StringFormat("block_smc_trend_adx_hard_floor(adx=%.2f floor=%.2f)", snap.adx, SMCADXHardBlockBelow);
      return false;
   }

   // ระดับที่ต้องตรวจสอบบริบทเพิ่มเติม (Context-based Penalty)
   if(snap.adx < SMCADXRequireContextBelow)
   {
      bool structure_ok = (is_buy && ctx.bias == SMC_BIAS_BULLISH) ||
                          (is_sell && ctx.bias == SMC_BIAS_BEARISH);
      bool htf_ok = (is_buy && snap.htf_trend >= 0) ||
                    (is_sell && snap.htf_trend < 0);
      bool slope_ok = (is_buy && snap.ema_slope > 0.0) ||
                      (is_sell && snap.ema_slope < -SMCStrictSellMinBearishSlope);
      bool regime_ok = (is_buy && SMCIsRuntimeTrendUp(runtime_regime)) ||
                       (is_sell && SMCIsRuntimeTrendDown(runtime_regime));

      // ปรับลดคะแนนแทนการบล็อกทันที เพื่อรักษาโอกาสในเทรนด์ที่กำลังตั้งตัว
      double penalty = SMCWeakADXPenalty;
      if(!(structure_ok && htf_ok && slope_ok && regime_ok))
         penalty += SMCWeakADXContextPenalty;

      signal.score = MathMax(0.0, signal.score - penalty);
      signal.confidence = MathMax(0.0, signal.confidence - (penalty * 0.5));
      signal.reason += StringFormat("|smc_graded_adx_penalty(adx=%.2f penalty=%.2f)", snap.adx, penalty);
   }

   return true;
}

/**
 * ฟังก์ชัน SMCShouldHardBlockSellZone: บล็อกการขายในโซนที่ไม่เหมาะสม (เช่น โซนราคาถูก)
 */
bool SMCShouldHardBlockSellZone(const SMCContext &ctx, string &block_reason)
{
   // บล็อกการขายในโซน Discount เสมอ เพราะถือว่าขายที่ปลายเทรนด์หรือจุดที่ราคาถูกเกินไป
   if(ctx.zone == SMC_ZONE_DISCOUNT)
   {
      block_reason = StringFormat("block_smc_sell_in_discount_hard(pos=%.2f)", ctx.position_in_range);
      return true;
   }

   // บล็อกหากราคาต่ำกว่าเกณฑ์การขายขั้นต่ำที่กำหนด
   if(SMCSellMinPositionInRange > 0.0 && ctx.position_in_range < SMCSellMinPositionInRange)
   {
      block_reason = StringFormat("block_smc_sell_below_allowed_zone(pos=%.2f min=%.2f)", ctx.position_in_range, SMCSellMinPositionInRange);
      return true;
   }

   // บล็อกหากกำหนดให้ขายเฉพาะในโซน Premium เท่านั้น
   if(SMCStrictSellPremiumOnly && ctx.zone != SMC_ZONE_PREMIUM)
   {
      block_reason = StringFormat("block_smc_sell_not_premium_only(zone=%s pos=%.2f)", SMCZoneToString(ctx.zone), ctx.position_in_range);
      return true;
   }

   return false;
}

/**
 * ฟังก์ชัน ApplySMCZonePolicy: ใช้มาตรการจัดการกับสัญญาณที่ขัดแย้งกับโซนราคา (Block/Penalty/Hybrid)
 */
bool ApplySMCZonePolicy(const string symbol,
                        SignalPack &signal,
                        const MarketSnapshot &snap,
                        const SMCContext &ctx,
                        const ENUM_REGIME_TYPE runtime_regime,
                        const bool is_buy,
                        const bool is_sell,
                        const bool zone_conflict,
                        const string hard_reason,
                        string &block_reason)
{
   if(!zone_conflict)
      return true;

   int mode = SMCZoneFilterMode;

   // 0 = BLOCK: บล็อกทันทีหากเกิดความขัดแย้งกับโซนราคา
   if(mode <= 0)
   {
      block_reason = hard_reason;
      return false;
   }

   // 1 = PENALTY: ไม่บล็อก แต่ลดคะแนนความเชื่อมั่นลง
   if(mode == 1)
   {
      signal.score = MathMax(0.0, signal.score - SMCZonePenalty);
      signal.confidence = MathMax(0.0, signal.confidence - (SMCZonePenalty * 0.5));
      signal.reason += "|smc_zone_penalty";
      return true;
   }

   // 2 = HYBRID: บล็อกกรณีที่บริบทอ่อนแอ และลดคะแนนกรณีเทรนด์แข็งแรง
   if(is_buy && SMCIsBuyPremiumContinuationAllowed(snap, runtime_regime, ctx))
   {
      signal.score = MathMax(0.0, signal.score - SMCZonePenalty);
      signal.confidence = MathMax(0.0, signal.confidence - (SMCZonePenalty * 0.5));
      signal.reason += "|smc_buy_premium_continuation_penalty";
      return true;
   }

   if(SMCIsStrongAlignedTrend(is_buy, is_sell, snap, ctx))
   {
      signal.score = MathMax(0.0, signal.score - SMCZonePenalty);
      signal.confidence = MathMax(0.0, signal.confidence - (SMCZonePenalty * 0.5));
      signal.reason += "|smc_zone_hybrid_penalty";
      return true;
   }

   // หากไม่เข้าเงื่อนไขยกเว้นในโหมด Hybrid ให้ทำการบล็อก
   block_reason = hard_reason + StringFormat(" mode=HYBRID adx=%.2f htf=%.0f bias=%s", snap.adx, snap.htf_trend, SMCBiasToString(ctx.bias));
   return false;
}

/**
 * ฟังก์ชันหลัก ApplySMCFilterToSignal: ประมวลผลและกรองสัญญาณเทรดด้วยบริบท SMC ทั้งหมด
 */
bool ApplySMCFilterToSignal(const string symbol,
                            SignalPack &signal,
                            const MarketSnapshot &snap,
                            const ENUM_REGIME_TYPE runtime_regime,
                            SMCContext &ctx,
                            string &block_reason)
{
   block_reason = "";

   if(!EnableSMCFilter)
      return true;

   if(EnableSMCAsEntryEngine)
   {
      // ป้องกันการใช้งานในโหมด Entry Engine หากยังไม่เสร็จสมบูรณ์
   }

   // สร้างบริบท SMC ปัจจุบัน
   if(!BuildSMCContext(symbol, snap, ctx))
   {
      if(SMCBlockWhenNoStructure)
      {
         block_reason = "block_smc_no_structure";
         return false;
      }
      return true;
   }

   bool is_buy = (signal.direction == SIGNAL_BUY);
   bool is_sell = (signal.direction == SIGNAL_SELL);

   // --- ส่วนของการกรองฝั่งซื้อ (Buy Filters) ---
   if(is_buy && SMCUsePremiumDiscountFilter && SMCShouldBlockBuyPremiumExtreme(snap, runtime_regime, ctx, block_reason))
      return false;

   // กรองกรณี SMC Bias เป็น Neutral (ไม่มีทิศทาง)
   if(is_buy && SMCBuyNeutralBiasStrengthFilter && ctx.bias == SMC_BIAS_NEUTRAL)
   {
      bool strong_neutral_buy = (snap.adx >= SMCBuyNeutralBiasMinADX &&
                                 snap.ema_slope >= SMCBuyNeutralBiasMinSlope &&
                                 SMCIsRuntimeTrendUp(runtime_regime));
      if(!strong_neutral_buy)
      {
         if(SMCBuyNeutralBiasUsePenalty && SMCIsRuntimeTrendUp(runtime_regime) && snap.ema_slope > 0.0 && ctx.position_in_range <= SMCBuyPremiumExtremePos)
         {
            double pen = MathMax(0.0, SMCBuyNeutralBiasPenalty);
            signal.score = MathMax(0.0, signal.score - pen);
            signal.confidence = MathMax(0.0, signal.confidence - pen * 0.50);
            signal.reason += "|smc_neutral_bias_penalty";
            if(EnableDebugLogs)
               PrintFormat("SMCFilterPenalty[%s]: neutral BUY weak context penalty=%.3f adx=%.2f slope=%.5f pos=%.2f", symbol, pen, snap.adx, snap.ema_slope, ctx.position_in_range);
         }
         else
         {
            block_reason = StringFormat("block_smc_buy_neutral_bias_weak_context(adx=%.2f slope=%.5f pos=%.2f)", snap.adx, snap.ema_slope, ctx.position_in_range);
            return false;
         }
      }
   }

   // ระบบคัดกรอง ADX เชิงบริบท
   if(!SMCShouldPassGradedADX(symbol, signal, snap, runtime_regime, ctx, is_buy, is_sell, block_reason))
      return false;

   // --- ส่วนของการกรองฝั่งขาย (Sell Filters) ---
   if(is_sell && SMCUsePremiumDiscountFilter && SMCBlockSellInDiscount)
   {
      if(SMCShouldHardBlockSellZone(ctx, block_reason))
         return false;
   }

   // ระบบการกรองการขายแบบเข้มงวด (Strict SELL Filter) เพื่อลดการลากของราคาฝั่งขาย
   if(is_sell && SMCStrictSellFilter)
   {
      if(SMCBlockSellInTrendUp && SMCIsRuntimeTrendUp(runtime_regime))
      {
         block_reason = "block_smc_sell_in_runtime_trend_up";
         return false;
      }

      if(SMCStrictSellRequireRuntimeTrendDown && !SMCIsRuntimeTrendDown(runtime_regime))
      {
         block_reason = StringFormat("block_smc_sell_runtime_not_bearish(regime=%s)", EnumToString(runtime_regime));
         return false;
      }

      if(SMCStrictSellBlockRange && SMCIsRuntimeRangeLike(runtime_regime))
      {
         block_reason = StringFormat("block_smc_sell_range_like(regime=%s)", EnumToString(runtime_regime));
         return false;
      }

      if(SMCStrictSellBlockUnknown && SMCIsRuntimeUnknownLike(runtime_regime))
      {
         block_reason = StringFormat("block_smc_sell_unknown_like(regime=%s)", EnumToString(runtime_regime));
         return false;
      }

      if(SMCStrictSellRequireBearishSlope && snap.ema_slope > -SMCStrictSellMinBearishSlope)
      {
         block_reason = StringFormat("block_smc_sell_slope_not_bearish(slope=%.5f need<-%.5f)", snap.ema_slope, SMCStrictSellMinBearishSlope);
         return false;
      }

      if(SMCStrictSellMinADX > 0.0 && snap.adx < SMCStrictSellMinADX)
      {
         block_reason = StringFormat("block_smc_sell_adx_low(adx=%.2f floor=%.2f)", snap.adx, SMCStrictSellMinADX);
         return false;
      }

      if(SMCStrictSellRequireBearishBias && ctx.bias != SMC_BIAS_BEARISH)
      {
         block_reason = StringFormat("block_smc_sell_not_confirmed(bias=%s)", SMCBiasToString(ctx.bias));
         return false;
      }

      if(SMCStrictSellRequireBearishHTF && snap.htf_trend >= 0)
      {
         block_reason = StringFormat("block_smc_sell_htf_not_bearish(htf=%.0f)", snap.htf_trend);
         return false;
      }
   }

   // --- การตรวจสอบความขัดแย้งเชิงโครงสร้าง (Structural Conflicts) ---
   if(SMCUseBOSFilter || SMCUseCHoCHFilter)
   {
      if(is_buy && ctx.bias == SMC_BIAS_BEARISH)
      {
         if(SMCBlockBiasConflict)
         {
            block_reason = StringFormat("block_smc_bias_conflict(signal=BUY bias=%s)", SMCBiasToString(ctx.bias));
            return false;
         }
         signal.score = MathMax(0.0, signal.score - SMCScorePenaltyConflict);
      }
      else if(is_sell && ctx.bias == SMC_BIAS_BULLISH)
      {
         if(SMCBlockBiasConflict)
         {
            block_reason = StringFormat("block_smc_bias_conflict(signal=SELL bias=%s)", SMCBiasToString(ctx.bias));
            return false;
         }
         signal.score = MathMax(0.0, signal.score - SMCScorePenaltyConflict);
      }
      else if((is_buy && ctx.bias == SMC_BIAS_BULLISH) || (is_sell && ctx.bias == SMC_BIAS_BEARISH))
      {
         // เพิ่มคะแนนหากโครงสร้างราคาสอดคล้องกับสัญญาณ
         signal.score = MathMin(1.0, signal.score + SMCScoreBoostAligned);
         signal.confidence = MathMin(1.0, signal.confidence + (SMCScoreBoostAligned * 0.5));
         signal.reason += "|smc_aligned";
      }
   }

   // การตรวจสอบความสอดคล้องกับแนวโน้ม HTF
   if(SMCRequireHTFAlignment)
   {
      if(is_buy && !ctx.htf_aligned_buy)
      {
         if(SMCIsBuyPremiumContinuationAllowed(snap, runtime_regime, ctx))
         {
            signal.score = MathMax(0.0, signal.score - SMCZonePenalty);
            signal.confidence = MathMax(0.0, signal.confidence - (SMCZonePenalty * 0.5));
            signal.reason += "|smc_buy_htf_lag_penalty";
         }
         else
         {
            block_reason = "block_smc_htf_conflict(signal=BUY)";
            return false;
         }
      }
      if(is_sell && !ctx.htf_aligned_sell)
      {
         block_reason = "block_smc_htf_conflict(signal=SELL)";
         return false;
      }
   }

   // การตรวจสอบความเหมาะสมของโซนราคา (Premium / Discount)
   if(SMCUsePremiumDiscountFilter)
   {
      bool buy_zone_conflict = (is_buy && SMCBlockBuyInPremium && ctx.zone == SMC_ZONE_PREMIUM);
      bool sell_zone_conflict = (is_sell && SMCBlockSellInDiscount && ctx.zone == SMC_ZONE_DISCOUNT);

      if(buy_zone_conflict)
      {
         string hard_reason = StringFormat("block_smc_buy_in_premium(pos=%.2f)", ctx.position_in_range);
         if(!ApplySMCZonePolicy(symbol, signal, snap, ctx, runtime_regime, is_buy, is_sell, true, hard_reason, block_reason))
            return false;
      }

      if(sell_zone_conflict)
      {
         block_reason = StringFormat("block_smc_sell_in_discount_hard(pos=%.2f)", ctx.position_in_range);
         return false;
      }
   }

   // บทลงโทษหากเกิดสัญญาณ CHoCH สวนทาง (CHoCH Warning)
   if(SMCUseCHoCHFilter)
   {
      if(is_buy && ctx.bearish_choch)
      {
         signal.score = MathMax(0.0, signal.score - (SMCScorePenaltyConflict * 0.5));
         signal.reason += "|smc_bearish_choch_penalty";
      }
      if(is_sell && ctx.bullish_choch)
      {
         signal.score = MathMax(0.0, signal.score - (SMCScorePenaltyConflict * 0.5));
         signal.reason += "|smc_bullish_choch_penalty";
      }
   }

   return true;
}

#endif // __KNARES_SMC_FILTER_MQH__

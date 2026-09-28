#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SMCContext.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "Metrics.mqh"
#include "DynamicThreshold.mqh"
#include "InternalHelpers.mqh"

//+------------------------------------------------------------------+
//| Signal Rescue Module - ระบบกู้คืนสัญญาณอัจฉริยะ                        |
//+------------------------------------------------------------------+

/**
 * IsBuyContinuationPipelineRescue: ลอจิกการกู้คืนสัญญาณขาขึ้นเมื่อคะแนนเกือบถึงเกณฑ์แต่คุณภาพ SMC สูง
 * @param ctx ข้อมูลบริบท SMC
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param runtime_regime สภาวะตลาดขณะรัน
 * @param signal สัญญาณเทรดที่อาจถูกกู้คืน
 * @return true หากตัดสินใจกู้คืนสัญญาณสำเร็จ
 */
bool IsBuyContinuationPipelineRescue(const SMCContext &ctx, const MarketSnapshot &snap, const ENUM_REGIME_TYPE runtime_regime, SignalPack &signal)
{
   if(!EnableBuyContinuationPipelineRescue) return false;
   if(signal.direction != SIGNAL_BUY) return false;
   if(signal.engine_name != "TrendEngine") return false;
   if(runtime_regime != REGIME_TREND_UP) return false;
   
   // 1. ตรวจสอบการหยุดทำงานชั่วคราวของระบบ Rescue
   if(EnableRescuePerformanceGuard && TimeCurrent() < g_rescue_pause_until)
      return false;

   // 2. ตรวจสอบ Cooldown จากการปิดไม้ด้วย Early Invalidation
   if(EnableContextExitRescueCooldown && TimeCurrent() < g_context_exit_pause_until)
      return false;
   
   // ตรวจสอบ Cooldown จากการชน Hard SL
   if(EnableHardSLCooldown && TimeCurrent() < g_hardsl_pause_until)
      return false;

   // 3. ตรวจสอบคุณภาพ SMC (SMC Quality Gate)
   double min_quality = RescueMinSMCQuality;
   double min_score_slack = BuyRescueMinScore;
   double max_range_pos = BuyRescueMaxSMCPos;

   // การปรับเกณฑ์คุณภาพตามขนาด Lot ที่ใหญ่ขึ้น
   if(FixedLotSize >= 0.03)
   {
      min_quality += 0.05;
      min_score_slack += 0.02;
      max_range_pos = MathMin(max_range_pos, 0.96);
   }
   if(FixedLotSize >= 0.05)
   {
      min_quality += 0.10;
      if(ctx.bias == SMC_BIAS_NEUTRAL) return false; // ต้องการเทรนด์ที่ชัดเจนสำหรับ Lot ใหญ่
   }
   
   bool is_soft = (ctx.buy_quality < RescueStrongQuality);
   
   // การบล็อกการ Rescue แบบ Soft ในกรณีที่ไม่สามารถลดขนาด Lot ได้
   double broker_min_lot = SymbolInfoDouble(snap.symbol, SYMBOL_VOLUME_MIN);
   if(is_soft && FixedLotSize <= broker_min_lot)
   {
      if(BlockSoftRescueWhenCannotReduceLot && ctx.buy_quality < SoftRescueMinQualityAtMinLot)
      {
         return false;
      }
   }

   if(EnableRescueSMCQualityGate && ctx.buy_quality < min_quality)
   {
      return false;
   }

   // 4. ตรวจสอบคะแนนและความมั่นใจที่เกือบจะถึงเกณฑ์ (Score/Confidence Slack)
   double min_s = MathMax(min_score_slack, GetPostPenaltyFloorByEngine(signal.engine_name, snap));
   double min_c = MinEntryConfidence;
   
   bool score_near = (signal.score + BuyRescueScoreSlack >= min_s);
   bool conf_near  = (signal.confidence + BuyRescueConfidenceSlack >= min_c);
   
   // เงื่อนไขพื้นฐานสำหรับการ Rescue
   bool structure_ok = (ctx.bias != SMC_BIAS_BEARISH);
   bool range_ok = (ctx.position_in_range <= max_range_pos);
   bool adx_ok = (snap.adx >= BuyRescueMinADX);
   bool slope_ok = (snap.ema_slope >= BuyRescueMinSlope);

   if(score_near && conf_near && structure_ok && range_ok && adx_ok && slope_ok)
   {
      g_pipeline_rescue_candidates++;
      signal.reason += "|PIPELINE_RESCUE";
      if(!is_soft)
         signal.reason += "(STRONG)";
      else
      {
         signal.reason += "(SOFT)";
         g_pipeline_rescue_soft_hits++;
      }
      
      return true;
   }

   return false;
}

/**
 * UpdateRescuePerformance: อัปเดตและติดตามประสิทธิภาพของระบบ Rescue
 */
void UpdateRescuePerformance(double pnl)
{
   g_rescue_trades_count++;
   if(pnl > 0) g_rescue_gross_profit += pnl;
   else g_rescue_gross_loss += MathAbs(pnl);
   
   LogInfo(StringFormat("PipelineRescueOutcome: pnl=%.2f result=%s", pnl, (pnl > 0 ? "WIN" : "LOSS")));

   if(EnableRescuePerformanceGuard && g_rescue_trades_count >= RescuePerfWindowTrades)
   {
      double pf = (g_rescue_gross_loss > 0) ? (g_rescue_gross_profit / g_rescue_gross_loss) : (g_rescue_gross_profit > 0 ? 99.0 : 1.0);
      if(pf < RescuePerfMinPF)
      {
         g_rescue_pause_until = TimeCurrent() + (RescuePauseMinutes * 60);
         LogWarning(StringFormat("RescuePerformanceGuard: Pausing rescue trades for %d min. PF %.2f < %.2f (trades=%d)",
                                 RescuePauseMinutes, pf, RescuePerfMinPF, g_rescue_trades_count));
      }
      // รีเซ็ตหน้าต่างการประเมิน
      g_rescue_trades_count = 0;
      g_rescue_gross_profit = 0;
      g_rescue_gross_loss = 0;
   }
}

/**
 * RecordContextExit: บันทึกการปิดไม้จากสภาวะตลาดเปลี่ยนเพื่อควบคุม Cooldown ระบบ Rescue
 */
void RecordContextExit()
{
   g_last_context_exit_times[g_context_exit_ptr] = TimeCurrent();
   g_context_exit_ptr = (g_context_exit_ptr + 1) % 5;

   if(!EnableContextExitRescueCooldown) return;

   int count = 0;
   datetime window_start = TimeCurrent() - (ContextExitCooldownWindowMinutes * 60);
   for(int i=0; i<5; i++)
   {
      if(g_last_context_exit_times[i] >= window_start)
         count++;
   }

   if(count >= ContextExitCooldownCount)
   {
      g_context_exit_pause_until = TimeCurrent() + (ContextExitRescuePauseMinutes * 60);
      LogWarning(StringFormat("ContextExitRescueCooldown: Pausing rescue trades for %d min. %d exits in %d min.",
                              ContextExitRescuePauseMinutes, count, ContextExitCooldownWindowMinutes));
   }
}

/**
 * LogPipelineRescueSummary: สรุปผลลัพธ์ของระบบกู้คืนสัญญาณ
 */
void LogPipelineRescueSummary()
{
   UpdateMetrics();
   LogInfo("--- PipelineRescueSummary ---");
   LogInfo(StringFormat("RescueCandidates: %d", g_pipeline_rescue_candidates));
   LogInfo(StringFormat("RescueSoftHits: %d", g_pipeline_rescue_soft_hits));
   LogInfo(StringFormat("RescueTradesExecuted: %d", g_rescue_trades_count));
   LogInfo(StringFormat("RescueNetProfit: %.2f", g_rescue_gross_profit - g_rescue_gross_loss));
   LogInfo("-----------------------------");
}

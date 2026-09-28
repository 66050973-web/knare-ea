#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "DynamicThreshold.mqh"
#include "SignalRescue.mqh"
#include "MarketPolicy.mqh"
#include "ReasonLogger.mqh"
#include "EngineController.mqh"

//+------------------------------------------------------------------+
//| Pipeline Controller Module - ระบบควบคุมลำดับขั้นตอนการตัดสินใจเทรด        |
//+------------------------------------------------------------------+

/**
 * ResetPipelineState: ล้างสถานะการวิเคราะห์ของ Pipeline ในแต่ละรอบ
 */
void ResetPipelineState()
{
   g_pipeline_trend = "-";
   g_pipeline_breakout = "-";
   g_pipeline_meanrev = "-";
   g_pipeline_score = "-";
   g_pipeline_conf = "-";
   g_pipeline_htf = "-";
   g_pipeline_dom = "-";
   g_pipeline_final = "-";
}

/**
 * ExecutePipeline: ดำเนินการคัดกรองสัญญาณและเลือกกลยุทธ์ที่ดีที่สุด
 * @param symbol ชื่อคู่เงิน
 * @param snapshot ข้อมูลตลาดปัจจุบัน
 * @param regime สภาวะตลาดปัจจุบัน
 * @param ctx ข้อมูลบริบท SMC
 * @param final_signal (Output) สัญญาณสุดท้ายที่เลือก
 * @return true หากพบสัญญาณที่พร้อมเทรด, false หากควรข้ามรอบนี้
 */
bool ExecutePipeline(const string symbol, const MarketSnapshot &snapshot, ENUM_REGIME_TYPE regime, const SMCContext &ctx, SignalPack &final_signal)
{
   ResetPipelineState();
   bool is_new_bar = IsNewBar(symbol, MainTF);

   // 1. วิเคราะห์สัญญาณจากทุก Engine (Pipeline Analysis)
   SignalPack signals[];
   SignalPack trend_sig, breakout_sig, meanrev_sig;
   
   if(EnableTrendEngine && !IsEngineDisabled("TrendEngine") && BuildTrendSignal(snapshot, regime, trend_sig))
   {
      trend_sig.smc_bias = (double)ctx.bias;
      trend_sig.smc_zone = (double)ctx.zone;
      trend_sig.smc_buy_quality = ctx.buy_quality;
      trend_sig.smc_sell_quality = ctx.sell_quality;
      ArrayResize(signals, ArraySize(signals) + 1);
      signals[ArraySize(signals)-1] = trend_sig;
      g_pipeline_trend = "PASS";
   }
   else if(EnableTrendEngine)
   {
      g_pipeline_trend = "FAIL";
      static datetime s_last_reject_bar = 0;
      datetime cur_bar = iTime(symbol, MainTF, 0);
      if(EnableDebugLogs && cur_bar != s_last_reject_bar)
      {
         s_last_reject_bar = cur_bar;
         LogInfo(StringFormat("TrendReject[%s]: regime=%s adx=%.1f slope=%.5f rsi=%.1f reason=%s",
                              symbol, EnumToString(regime), snapshot.adx, snapshot.ema_slope, snapshot.rsi, trend_sig.reason));
      }
   }
   
   if(EnableBreakoutEngine && !IsEngineDisabled("BreakoutEngine") && BuildBreakoutSignal(snapshot, regime, breakout_sig))
   {
      breakout_sig.smc_bias = (double)ctx.bias;
      breakout_sig.smc_zone = (double)ctx.zone;
      breakout_sig.smc_buy_quality = ctx.buy_quality;
      breakout_sig.smc_sell_quality = ctx.sell_quality;
      ArrayResize(signals, ArraySize(signals) + 1);
      signals[ArraySize(signals)-1] = breakout_sig;
      g_pipeline_breakout = "PASS";
   }
   else if(EnableBreakoutEngine) g_pipeline_breakout = "FAIL";
   
   if(EnableMeanRevEngine && !IsEngineDisabled("MeanRevEngine") && BuildMeanRevSignal(snapshot, regime, meanrev_sig))
   {
      meanrev_sig.smc_bias = (double)ctx.bias;
      meanrev_sig.smc_zone = (double)ctx.zone;
      meanrev_sig.smc_buy_quality = ctx.buy_quality;
      meanrev_sig.smc_sell_quality = ctx.sell_quality;
      ArrayResize(signals, ArraySize(signals) + 1);
      signals[ArraySize(signals)-1] = meanrev_sig;
      g_pipeline_meanrev = "PASS";
   }
   else if(EnableMeanRevEngine) g_pipeline_meanrev = "FAIL";

   // 2. รวมสัญญาณและเลือกสัญญาณที่ดีที่สุด
   bool has_any_signal = (ResolveSignals(signals, snapshot, final_signal) != SIGNAL_NONE);
   
   // Soft Entry ในสภาวะ Range
   if(!has_any_signal && EnableRangeSoftEntry && regime == REGIME_RANGE && ArraySize(signals) > 0)
   {
      int best_idx = -1; double best_rank = -1.0;
      for(int i = 0; i < ArraySize(signals); i++) {
         if(signals[i].direction == SIGNAL_NONE) continue;
         double rank = signals[i].score * signals[i].confidence;
         if(rank > best_rank) { best_rank = rank; best_idx = i; }
      }
      if(best_idx >= 0 && signals[best_idx].score >= RangeSoftEntryMinScore && signals[best_idx].confidence >= RangeSoftEntryMinConfidence) {
         final_signal = signals[best_idx]; has_any_signal = true;
      }
   }

   // วิเคราะห์สาเหตุการปฏิเสธสัญญาณ (Diagnostics)
   if(!has_any_signal) {
      AnalyzeSignalRejection(symbol, signals, snapshot);
      g_pipeline_final = "WAITING"; return false;
   }

   final_signal.symbol = symbol;

   // 3. ปรับคะแนนตามสภาวะตลาด (Regime Multiplier)
   double raw_signal_score = final_signal.score;
   double regime_mult = GetEngineRegimeMultiplier(final_signal.engine_name, regime);
   final_signal.score *= regime_mult;
   bool is_breakout = (final_signal.engine_name == "BreakoutEngine");

   if(regime_mult <= 0.0) {
      LogNoTradeReasonPerBar(symbol, MainTF, "block_regime_compatibility");
      g_pipeline_final = "BLOCK_REGIME"; return false;
   }

   // 4. คำนวณบทลงโทษ (Penalties)
   ApplyPipelinePenalties(final_signal, snapshot, regime);

   // 5. ตรวจสอบเกณฑ์พื้นฐาน (Confidence & Thresholds)
   double min_score_eff = ComputeEffectiveEntryThreshold(final_signal, snapshot, regime);
   double floor = GetPostPenaltyFloorByEngine(final_signal.engine_name, snapshot);
   
   bool post_penalty_floor_fail = (final_signal.score < MathMax(0.0, floor));
   bool conf_pass = (final_signal.confidence >= MinEntryConfidence);
   if(final_signal.score < LowScoreThreshold && final_signal.confidence < LowScoreMinConfidence) conf_pass = false;

   g_last_score = final_signal.score;
   g_last_confidence = final_signal.confidence;
   g_pipeline_score = ((final_signal.score + ScoreFloorEpsilon >= min_score_eff) && !post_penalty_floor_fail) ? "PASS" : "LOW";
   g_pipeline_conf  = conf_pass ? "PASS" : "LOW";

   // 6. ตรวจสอบความปลอดภัยเชิงลึก (DOM, HTF)
   bool dom_block = ShouldBlockByDOMSoftVeto(symbol, final_signal, snapshot);
   if(MQLInfoInteger(MQL_TESTER) && !EnableDOMHardBlockInTester) dom_block = false;
   g_pipeline_dom = dom_block ? "BLOCK" : "PASS";

   bool htf_mismatch = ((final_signal.direction == SIGNAL_BUY && snapshot.htf_trend < 0) ||
                        (final_signal.direction == SIGNAL_SELL && snapshot.htf_trend > 0));
   if(EnforceHTFAlignment) g_pipeline_htf = (!htf_mismatch || EnableHTFSoftPenalty) ? "PASS" : "FAIL";
   else g_pipeline_htf = "PASS";

   // 7. พยายามกู้คืนสัญญาณ (Rescue Logic)
   if(g_pipeline_score == "LOW" || g_pipeline_conf == "LOW" || g_pipeline_htf == "FAIL" || g_pipeline_dom == "BLOCK") {
      if(g_pipeline_htf == "PASS" && g_pipeline_dom == "PASS" && IsBuyContinuationPipelineRescue(ctx, snapshot, regime, final_signal)) {
         g_pipeline_score = "RESCUE"; g_pipeline_conf = "RESCUE";
      } else {
         LogNoTradeReasonPerBar(symbol, MainTF, "pipeline_reject");
         g_pipeline_final = "REJECT"; return false;
      }
   }

   return true;
}

/**
 * ApplyPipelinePenalties: คำนวณและหักลบจุดด้อยของสัญญาณ (Unknown Regime, HTF Mismatch)
 */
void ApplyPipelinePenalties(SignalPack &signal, const MarketSnapshot &snap, ENUM_REGIME_TYPE reg)
{
   bool htf_mismatch = ((signal.direction == SIGNAL_BUY && snap.htf_trend < 0) ||
                        (signal.direction == SIGNAL_SELL && snap.htf_trend > 0));
   
   double unk_score_pen = (EnableUnknownRegimePenalty && reg == REGIME_UNKNOWN) ? UnknownRegimeScorePenalty : 0;
   double unk_conf_pen = (EnableUnknownRegimePenalty && reg == REGIME_UNKNOWN) ? UnknownRegimeConfPenalty : 0;
   double htf_score_pen = (EnableHTFSoftPenalty && htf_mismatch) ? HTFScorePenalty : 0;
   double htf_conf_pen = (EnableHTFSoftPenalty && htf_mismatch) ? HTFConfidencePenalty : 0;

   double total_score_pen = unk_score_pen + htf_score_pen;
   if(MaxCombinedScorePenalty > 0 && total_score_pen > MaxCombinedScorePenalty)
   {
      double scale = MaxCombinedScorePenalty / total_score_pen;
      total_score_pen = MaxCombinedScorePenalty;
   }

   signal.score = MathMax(0.0, signal.score - total_score_pen);
   signal.confidence = MathMax(0.0, signal.confidence - (unk_conf_pen + htf_conf_pen));
}

/**
 * AnalyzeSignalRejection: วิเคราะห์เชิงลึกว่าทำไมสัญญาณถึงไม่ถูกยอมรับ
 */
void AnalyzeSignalRejection(const string symbol, SignalPack &signals[], const MarketSnapshot &snapshot)
{
   int best_idx = -1; double best_rank = -1.0;
   for(int i = 0; i < ArraySize(signals); i++) {
      if(signals[i].direction == SIGNAL_NONE) continue;
      double rank = signals[i].score * signals[i].confidence;
      if(rank > best_rank) { best_rank = rank; best_idx = i; }
   }

   double b_score = -1.0, b_conf = -1.0;
   bool s_low = true, c_low = true, h_fail = false, d_block = false;

   if(best_idx >= 0) {
      b_score = signals[best_idx].score; b_conf = signals[best_idx].confidence;
      double min_s = (signals[best_idx].engine_name == "MeanRevEngine") ? MeanRevMinEntryScore : MinEntryScore;
      s_low = (b_score < min_s); c_low = (b_conf < MinEntryConfidence);
      if(EnforceHTFAlignment) h_fail = !((signals[best_idx].direction == SIGNAL_BUY && snapshot.htf_trend >= 0) || (signals[best_idx].direction == SIGNAL_SELL && snapshot.htf_trend <= 0));
      d_block = ShouldBlockByDOMSoftVeto(symbol, signals[best_idx], snapshot);
   }

   LogNoTradeReasonPerBar(symbol, MainTF, StringFormat("no_final_signal(score_low=%s conf_low=%s htf_fail=%s dom_block=%s best_score=%.2f candidates=%d)",
                                                      s_low?"true":"false", c_low?"true":"false", h_fail?"true":"false", d_block?"true":"false", b_score, ArraySize(signals)));
}

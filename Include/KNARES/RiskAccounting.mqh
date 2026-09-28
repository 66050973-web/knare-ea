#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Logger.mqh"
#include "Metrics.mqh"
#include "RiskEngine.mqh"
#include "MarketData.mqh"
#include "FeatureEngine.mqh"
#include "RegimeClassifier.mqh"
#include "SharedGlobals.mqh"

//+------------------------------------------------------------------+
//| Risk Accounting Module - ระบบติดตามความเสี่ยงและสุขภาพพอร์ต             |
//+------------------------------------------------------------------+

/**
 * GetGlobalHeatUsed: คำนวณความเสี่ยงรวม (Heat) ที่ถูกใช้ไปในปัจจุบัน
 */
double GetGlobalHeatUsed()
{
   string gv_name = "KNARES_Total_Risk_Money";
   return GlobalVariableCheck(gv_name) ? GlobalVariableGet(gv_name) : 0.0;
}

/**
 * GetGlobalHeatMax: คำนวณขีดจำกัดความเสี่ยงรวมสูงสุดตาม Equity
 */
double GetGlobalHeatMax()
{
   return AccountInfoDouble(ACCOUNT_EQUITY) * PortfolioHeatCapPct;
}

/**
 * RunHealthChecks: ตรวจสอบสถานะการเชื่อมต่อและระดับ Margin
 */
void RunHealthChecks()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      LogWarning("Terminal is not connected to server!");

   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      LogWarning("Automated trading is disabled for this account!");

   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_level > 0 && margin_level < MinMarginLevelPct)
      LogError(StringFormat("CRITICAL: Low Margin Level (%.2f%%)", margin_level));
}

/**
 * LogPerformanceKPI: บันทึกตัวชี้วัดประสิทธิภาพของระบบในระดับพอร์ต
 */
void LogPerformanceKPI()
{
   UpdateMetrics(_Symbol);
   int fills = GetExecutionFillCount();
   
   int policy_blk = GetExecutionPolicyBlocks();
   int spread_blk = GetExecutionSpreadBlocks();
   int safety_blk = GetExecutionSafetyBlocks();
   int o_check_fail = GetExecutionOrderCheckFailed();
   int o_send_fail = GetExecutionOrderSendFailed();
   int b_rej = GetExecutionBrokerRejects();
   int mod_fail = GetExecutionModifyFailed();
   int part_fail = GetExecutionPartialFailed();
   
   int total_pipeline_rejects = policy_blk + spread_blk + safety_blk + o_check_fail + o_send_fail + b_rej + mod_fail + part_fail;
   int total_execution_rejects = o_send_fail + b_rej + mod_fail + part_fail;
   
   double pipeline_fill_rate = (fills + total_pipeline_rejects > 0) ? ((double)fills / (fills + total_pipeline_rejects)) * 100.0 : 0.0;
   double true_exec_fill_rate = (fills + total_execution_rejects > 0) ? ((double)fills / (fills + total_execution_rejects)) * 100.0 : 0.0;
   
   int total_trades = current_metrics.win_trades + current_metrics.loss_trades;
   double net_profit = current_metrics.total_profit - current_metrics.total_loss;

   LogInfo(StringFormat(
      "KPI[15m]: trades=%d winrate=%.2f%% pf=%.2f net=%.2f fills=%d | PL_FillRate=%.1f%% Exec_FillRate=%.1f%% | Breakdown(sprd=%d sfty=%d check=%d send=%d b_rej=%d mod=%d part=%d pol=%d)",
      total_trades,
      current_metrics.win_rate,
      current_metrics.profit_factor,
      net_profit,
      fills,
      pipeline_fill_rate,
      true_exec_fill_rate,
      spread_blk,
      safety_blk,
      o_check_fail,
      o_send_fail,
      b_rej,
      mod_fail,
      part_fail,
      policy_blk
   ));

   double global_risk = GetTotalReservedRisk();
   double open_pos_risk = GetOpenPositionsReservedRisk();
   int open_pos_count = 0;
   for(int i=0; i<PositionsTotal(); i++) if(PositionGetTicket(i)>0) open_pos_count++;
   
   LogInfo(StringFormat(
      "RiskAccountingCheck: global=%.2f openPosSum=%.2f residual=%.2f openPositions=%d",
      global_risk, open_pos_risk, global_risk - open_pos_risk, open_pos_count
   ));
}

/**
 * LogEngineKPI: บันทึกสถิติแยกตามรายกลยุทธ์ (Engine)
 */
void LogEngineKPI()
{
   for(int i = 0; i < 3; i++)
   {
      ENUM_ENGINE_STATUS status = GetEngineStatus(engine_metrics[i].name);
      engine_metrics[i].status = status;
      
      LogInfo(StringFormat("EngineKPI[%s]: trades=%d net=%.2f winrate=%.2f%% pf=%.2f expectancy=%.2f status=%s",
                           engine_metrics[i].name, engine_metrics[i].trades, engine_metrics[i].net_profit,
                           engine_metrics[i].win_rate, engine_metrics[i].pf, engine_metrics[i].expectancy,
                           EngineStatusToString(status)));
   }
   
   LogInfo(StringFormat("BreakoutStageSummary: TotalSignals=%d FloorPass=%d RegimePass=%d ThresholdPass=%d PipelinePass=%d GatePass=%d LimitPass=%d Sent=%d",
                        g_breakout_stage_total[0], g_breakout_stage_total[1], g_breakout_stage_total[2],
                        g_breakout_stage_total[3], g_breakout_stage_total[4], g_breakout_stage_total[5],
                        g_breakout_stage_total[6], g_breakout_stage_total[7]));

   LogInfo(StringFormat("LimitGateSummary: Portfolio=%d NoProfitScl=%d LowConfScl=%d StagedScl=%d MaxPos=%d Clust=%d ExpCap=%d HeatCap=%d | ManagePositionsCalled=%d",
                        g_limit_gate_counts[0], g_limit_gate_counts[1], g_limit_gate_counts[2],
                        g_limit_gate_counts[3], g_limit_gate_counts[4], g_limit_gate_counts[5],
                        g_limit_gate_counts[6], g_limit_gate_counts[7], g_manage_positions_called));

   LogInfo(StringFormat("CloseReasonKPI: HardSL=%d BE=%d ProfLock=%d Trail=%d AccelTrail=%d TP=%d Partial=%d RegimeExit=%d Timeout=%d VolShock=%d GlobProf=%d EarlyInv=%d Other=%d | VolShockDetects=%d",
                        g_close_reason_counts[0], g_close_reason_counts[1], g_close_reason_counts[2],
                        g_close_reason_counts[3], g_close_reason_counts[4], g_close_reason_counts[5],
                        g_close_reason_counts[6], g_close_reason_counts[7], g_close_reason_counts[8],
                        g_close_reason_counts[9], g_close_reason_counts[10], g_close_reason_counts[11],
                        g_close_reason_counts[12], GetVolShockDetections()));
   
   LogInfo(StringFormat("EarlyInvSummary: total=%d net=%.2f avg=%.2f", 
                        g_early_inv_count, g_early_inv_net, (g_early_inv_count > 0 ? g_early_inv_net/g_early_inv_count : 0.0)));
}

/**
 * RecordHardSL: บันทึกและตรวจจับการชน SL ต่อเนื่องเพื่อทำ Cooldown
 */
void RecordHardSL()
{
   g_last_hardsl_times[g_hardsl_ptr] = TimeCurrent();
   g_hardsl_ptr = (g_hardsl_ptr + 1) % 5;

   if(!EnableHardSLCooldown) return;

   int count = 0;
   datetime window_start = TimeCurrent() - (HardSLCooldownWindowMinutes * 60);
   for(int i=0; i<5; i++)
   {
      if(g_last_hardsl_times[i] >= window_start)
         count++;
   }

   if(count >= HardSLCooldownCount)
   {
      g_hardsl_pause_until = TimeCurrent() + (HardSLPauseMinutes * 60);
      LogWarning(StringFormat("HardSLCooldown: Pausing %s for %d min. %d HardSL in %d min.",
                              (HardSLCooldownPauseRescueOnly ? "rescue trades" : "all trades"),
                              HardSLPauseMinutes, count, HardSLCooldownWindowMinutes));
   }
}

/**
 * LogHardSLDetail: บันทึกรายละเอียดเชิงลึกของไม้ที่ชน SL
 */
void LogHardSLDetail(ulong ticket, double pnl, const string symbol)
{
   MarketSnapshot snap;
   if(GetMarketSnapshot(symbol, snap) && ComputeFeatures(symbol, snap))
   {
      string comment = "";
      if(PositionSelectByTicket(ticket))
      {
         comment = PositionGetString(POSITION_COMMENT);
         long dir = PositionGetInteger(POSITION_TYPE);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
         
         LogWarning(StringFormat("HardSLDetail[%I64u]: dir=%s pnl=%.2f open=%.2f sl=%.2f tp=%.2f age=%d bars rescue=%s comment=%s score=%.2f conf=%.2f regime=%s adx=%.2f htf=%.0f slope=%.6f z=%.2f",
                                 ticket, (dir == POSITION_TYPE_BUY ? "BUY" : "SELL"), pnl, open, sl, tp, 
                                 GetPositionAgeBars(symbol, MainTF, open_time),
                                 (StringFind(comment, "RESCUE") >= 0 ? "YES" : "NO"),
                                 comment, g_last_score, g_last_confidence, EnumToString(DetectRegime(snap)),
                                 snap.adx, snap.htf_trend, snap.ema_slope, snap.zscore));
      }
      else
      {
         LogInfo(StringFormat("HardSLDetail[%I64u]: pnl=%.2f dir=UNK score=%.2f conf=%.2f regime=%s adx=%.2f htf=%.0f slope=%.6f z=%.2f (Position data unavailable)",
                              ticket, pnl, g_last_score, g_last_confidence, EnumToString(DetectRegime(snap)),
                              snap.adx, snap.htf_trend, snap.ema_slope, snap.zscore));
      }
   }
}

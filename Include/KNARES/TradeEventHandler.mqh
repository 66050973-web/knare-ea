#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "FeatureEngine.mqh"
#include "RegimeClassifier.mqh"
#include "NeuralBridge.mqh"
#include "TradeTracking.mqh"
#include "RiskEngine.mqh"
#include "Metrics.mqh"
#include "SignalRescue.mqh"
#include "RiskAccounting.mqh"
#include "TradeJournal.mqh"
#include "TelegramWebhook.mqh"

//+------------------------------------------------------------------+
//| Trade Event Handler Module - ระบบจัดการเหตุการณ์ธุรกรรมการเทรด         |
//+------------------------------------------------------------------+

/**
 * HandleDealAddition: จัดการเมื่อมีการเพิ่ม Deal ใหม่ (การเปิดหรือปิดออเดอร์สำเร็จ)
 */
void HandleDealAddition(const MqlTradeTransaction &trans)
{
   // 1. อัปเดตข้อมูลพื้นฐานและ Dashboard
   UpdateMetrics(_Symbol);
   
   // 2. ติดตามการกระจายตัวของ Regime เมื่อมีการเทรด
   MarketSnapshot snap;
   if(GetMarketSnapshot(trans.symbol, snap))
   {
      ENUM_REGIME_TYPE r = DetectRegime(snap);
      // ครอบคลุม Regime ทั้ง  12 ประเภท (ENUM_REGIME_TYPE: UNKNOWN=0 ถึง REGIME_BREAKOUT_PREP=11)
      if(r >= 0 && r < 12) current_metrics.regime_dist[r]++;
   }

   // 4. วิเคราะห์รายละเอียดของ Deal เพื่อจัดการสถานะออเดอร์
   if(HistoryDealSelect(trans.deal))
   {
      long entry_kind = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      ulong pos_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int comment_idx = ResolveEngineIndexFromComment(comment);

      // กรณี: เปิดออเดอร์ใหม่ (ENTRY_IN)
      if(entry_kind == DEAL_ENTRY_IN || entry_kind == DEAL_ENTRY_INOUT)
      {
         if(comment_idx >= 0)
            BindPositionEngine(pos_id, comment_idx);
         
         LinkPendingRiskToTicket(trans.symbol, pos_id);
         double deal_vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         StorePositionInitialVolume(pos_id, deal_vol);
         
         SendTelegramWebhook(trans.symbol, "OPEN", StringFormat("Opened %.2f lots", deal_vol));
      }

      // กรณี: ปิดออเดอร์ (ENTRY_OUT / ENTRY_INOUT)
      if(entry_kind == DEAL_ENTRY_OUT || entry_kind == DEAL_ENTRY_OUT_BY || entry_kind == DEAL_ENTRY_INOUT)
      {
         double closed_vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         ReleasePositionRisk(pos_id, closed_vol);

         double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                      + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                      + HistoryDealGetDouble(trans.deal, DEAL_SWAP);
         
         int idx = FindPositionEngine(pos_id);
         if(idx < 0) idx = comment_idx;

         // อัปเดตสถิติราย Engine (KPI Update)
         if(idx >= 0 && idx < 3)
         {
            engine_metrics[idx].trades++;
            if(pnl > 0.0)
            {
               engine_metrics[idx].wins++;
               engine_metrics[idx].gross_profit += pnl;
            }
            else if(pnl < 0.0)
            {
               engine_metrics[idx].losses++;
               engine_metrics[idx].gross_loss += MathAbs(pnl);
            }
            
            engine_metrics[idx].net_profit += pnl;
            engine_metrics[idx].pf = CalcPF(engine_metrics[idx].gross_profit, engine_metrics[idx].gross_loss);
            engine_metrics[idx].win_rate = CalcWinRate(engine_metrics[idx].wins, engine_metrics[idx].trades);
            engine_metrics[idx].expectancy = CalcExpectancy(engine_metrics[idx].wins, engine_metrics[idx].losses, engine_metrics[idx].gross_profit, engine_metrics[idx].gross_loss);
         }

         // Online AI Learning: train ด้วย label ที่ถูกต้อง (pnl รวม commission+swap) เฝียงตอนปิดออเดอร์เท่านั้น
         if(ComputeFeatures(trans.symbol, snap))
         {
            int train_label = (pnl > 0) ? 1 : 0;
            // ดึงข้อมูล SMC จาก Trade Tracking ที่บันทึกไว้ตอนเปิดไม้มาใช้
            SignalPack train_signal;
            GetPositionSMC(pos_id, train_signal);
            NeuralBridgeTrain(snap, train_signal, train_label);
         }

         // วิเคราะห์และจัดหมวดหมู่สาเหตุการปิด
         long deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
         int reason_idx = ClassifyCloseReason(deal_reason, comment, pnl);
         
         if(reason_idx == CLOSE_EARLY_INVALIDATION)
         {
            g_early_inv_count++;
            g_early_inv_net += pnl;
            RecordContextExit();
         }
         if(reason_idx == CLOSE_REGIME_EXIT)
         {
            RecordContextExit();
         }
         if(reason_idx == CLOSE_HARD_SL_LOSS)
         {
            LogHardSLDetail(pos_id, pnl, trans.symbol);
            RecordHardSL();
         }
         
         if(StringFind(comment, "PIPELINE_RESCUE") >= 0)
         {
            UpdateRescuePerformance(pnl);
         }

         if(reason_idx >= 0 && reason_idx < 13)
            g_close_reason_counts[reason_idx]++;
         else
            g_close_reason_counts[12]++;
            
         SendTelegramWebhook(trans.symbol, "CLOSE", "Position Closed", StringFormat("%.2f", pnl));
      }
   }
}

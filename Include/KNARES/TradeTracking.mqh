#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "FeatureEngine.mqh"
#include "RegimeClassifier.mqh"
#include "RiskAccounting.mqh"

//+------------------------------------------------------------------+
//| Trade Tracking Module - ระบบจัดการสถานะออเดอร์เชิงลึกและการคัดกรอง       |
//+------------------------------------------------------------------+

/**
 * ResolveEngineIndexFromComment: ค้นหาดัชนีเครื่องมือเทรดจากคอมเมนต์ของออเดอร์
 */
int ResolveEngineIndexFromComment(const string comment)
{
   if(StringFind(comment, "TrendEngine") >= 0) return 0;
   if(StringFind(comment, "BreakoutEngine") >= 0) return 1;
   if(StringFind(comment, "MeanRevEngine") >= 0) return 2;
   return -1;
}

/**
 * BindPositionEngine: เชื่อมโยง ID ของไม้เทรดกับเครื่องมือเทรดที่เปิดไม้
 */
void BindPositionEngine(const ulong pos_id, const int engine_idx)
{
   if(pos_id == 0 || engine_idx < 0 || engine_idx > 2) return;
   for(int i = 0; i < ArraySize(g_pos_ids); i++)
   {
      if(g_pos_ids[i] == pos_id)
      {
         g_pos_engine_idx[i] = engine_idx;
         return;
      }
   }
   int n = ArraySize(g_pos_ids);
   ArrayResize(g_pos_ids, n + 1);
   ArrayResize(g_pos_engine_idx, n + 1);
   ArrayResize(g_pos_smc_bias, n + 1);
   ArrayResize(g_pos_smc_zone, n + 1);
   ArrayResize(g_pos_smc_buy_q, n + 1);
   ArrayResize(g_pos_smc_sell_q, n + 1);
   
   g_pos_ids[n] = pos_id;
   g_pos_engine_idx[n] = engine_idx;
   // กำหนดค่าเริ่มต้นให้กับ SMC fields
   g_pos_smc_bias[n] = 0.0;
   g_pos_smc_zone[n] = 0.0;
   g_pos_smc_buy_q[n] = 0.0;
   g_pos_smc_sell_q[n] = 0.0;
}

/**
 * BindPositionSMC: บันทึกข้อมูล SMC ของการตัดสินใจเปิดไม้เทรดนั้นๆ
 */
void BindPositionSMC(const ulong pos_id, const SignalPack &signal)
{
   if(pos_id == 0) return;
   for(int i = 0; i < ArraySize(g_pos_ids); i++)
   {
      if(g_pos_ids[i] == pos_id)
      {
         g_pos_smc_bias[i]   = signal.smc_bias;
         g_pos_smc_zone[i]   = signal.smc_zone;
         g_pos_smc_buy_q[i]  = signal.smc_buy_quality;
         g_pos_smc_sell_q[i] = signal.smc_sell_quality;
         return;
      }
   }
   // ถ้ายังไม่มีในระบบ ให้สร้างใหม่ (กรณี OrderSend ทำงานก่อน OnTradeTransaction)
   int n = ArraySize(g_pos_ids);
   ArrayResize(g_pos_ids, n + 1);
   ArrayResize(g_pos_engine_idx, n + 1);
   ArrayResize(g_pos_smc_bias, n + 1);
   ArrayResize(g_pos_smc_zone, n + 1);
   ArrayResize(g_pos_smc_buy_q, n + 1);
   ArrayResize(g_pos_smc_sell_q, n + 1);
   
   g_pos_ids[n] = pos_id;
   g_pos_engine_idx[n] = -1; // ยังไม่ระบุ Engine
   g_pos_smc_bias[n]   = signal.smc_bias;
   g_pos_smc_zone[n]   = signal.smc_zone;
   g_pos_smc_buy_q[n]  = signal.smc_buy_quality;
   g_pos_smc_sell_q[n] = signal.smc_sell_quality;
}

/**
 * GetPositionSMC: ดึงข้อมูล SMC ที่ผูกไว้กับไม้เทรด เพื่อนำไปใช้ Train AI ตอนปิดออเดอร์
 */
void GetPositionSMC(const ulong pos_id, SignalPack &out_signal)
{
   if(pos_id == 0) return;
   for(int i = 0; i < ArraySize(g_pos_ids); i++)
   {
      if(g_pos_ids[i] == pos_id)
      {
         out_signal.smc_bias         = g_pos_smc_bias[i];
         out_signal.smc_zone         = g_pos_smc_zone[i];
         out_signal.smc_buy_quality  = g_pos_smc_buy_q[i];
         out_signal.smc_sell_quality = g_pos_smc_sell_q[i];
         return;
      }
   }
}

/**
 * FindPositionEngine: ค้นหาดัชนีเครื่องมือเทรดที่รับผิดชอบไม้เทรดนั้นๆ
 */
int FindPositionEngine(const ulong pos_id)
{
   if(pos_id == 0) return -1;
   for(int i = 0; i < ArraySize(g_pos_ids); i++)
   {
      if(g_pos_ids[i] == pos_id)
         return g_pos_engine_idx[i];
   }
   return -1;
}

/**
 * ClassifyCloseReason: วิเคราะห์และจัดกลุ่มสาเหตุการปิดไม้ (TP, SL, Trailing, ฯลฯ)
 */
int ClassifyCloseReason(const long deal_reason, const string comment, double pnl)
{
   string c = comment;
   StringToLower(c);

   // 1. ตรวจสอบคำสำคัญในคอมเมนต์ (ลำดับความสำคัญสูงสุด)
   if(StringFind(c, "regime") >= 0) return CLOSE_REGIME_EXIT;
   if(StringFind(c, "timeout") >= 0) return CLOSE_TIMEOUT;
   if(StringFind(c, "volshock") >= 0) return CLOSE_VOL_SHOCK_EXIT;
   if(StringFind(c, "globalprofit") >= 0) return CLOSE_GLOBAL_PROFIT_EXIT;
   if(StringFind(c, "partial") >= 0) return CLOSE_PARTIAL_TP;
   if(StringFind(c, "earlyinvalidation") >= 0) return CLOSE_EARLY_INVALIDATION;

   // 2. ตรวจสอบสถานะการปิดด้วย Trailing Stop หรือการล็อคกำไร
   if(StringFind(c, "trailing-profit") >= 0) return CLOSE_SL_PROFIT_LOCK;
   if(StringFind(c, "accelerated-trailing") >= 0) return CLOSE_SL_ACCELERATED_TRAILING;
   if(StringFind(c, "trailing-atr") >= 0) return CLOSE_SL_TRAILING;
   if(StringFind(c, "breakeven") >= 0) return CLOSE_SL_BREAKEVEN;

   // 3. วิเคราะห์จากเหตุผลเริ่มต้นของคำสั่งซื้อขาย (Deal Reason)
   if(deal_reason == DEAL_REASON_SL)
   {
      if(pnl > 0.0) return CLOSE_SL_PROFIT_LOCK;
      return CLOSE_HARD_SL_LOSS;
   }
   if(deal_reason == DEAL_REASON_TP) return CLOSE_TP;

   return 12; // CLOSE_OTHER
}

/**
 * IsEntryCooldownOk: ตรวจสอบว่าพ้นช่วงเวลาหน่วงการเข้าเทรด (Cooldown) หรือยัง
 */
bool IsEntryCooldownOk(const string symbol, int seconds = 30)
{
   if(EnableOnlyNewBarEntry) return true;
   for(int i = 0; i < ArraySize(g_last_entry_symbol_per_symbol); i++)
   {
      if(g_last_entry_symbol_per_symbol[i] == symbol)
         return (TimeCurrent() - g_last_entry_time_per_symbol[i] >= seconds);
   }
   return true;
}

/**
 * UpdateEntryCooldown: บันทึกเวลาที่เข้าเทรดล่าสุดเพื่อใช้ในระบบ Cooldown
 */
void UpdateEntryCooldown(const string symbol)
{
   for(int i = 0; i < ArraySize(g_last_entry_symbol_per_symbol); i++)
   {
      if(g_last_entry_symbol_per_symbol[i] == symbol)
      {
         g_last_entry_time_per_symbol[i] = TimeCurrent();
         return;
      }
   }
   int n = ArraySize(g_last_entry_symbol_per_symbol);
   ArrayResize(g_last_entry_symbol_per_symbol, n + 1);
   ArrayResize(g_last_entry_time_per_symbol, n + 1);
   g_last_entry_symbol_per_symbol[n] = symbol;
   g_last_entry_time_per_symbol[n] = TimeCurrent();
}

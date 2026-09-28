#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Logger.mqh"
#include "Types.mqh"
#include "MarketDepth.mqh"
#include "AlgoExecution.mqh"
#include "SharedGlobals.mqh"

//+------------------------------------------------------------------+
//| Market Policy Module - ระบบวิเคราะห์ความสัมพันธ์และข้อจำกัด           |
//+------------------------------------------------------------------+

/**
 * IsHighlyCorrelated: ตรวจสอบความสัมพันธ์ระหว่างคู่เงิน
 * @param a ชื่อคู่เงินที่ 1
 * @param b ชื่อคู่เงินที่ 2
 * @return true หากมีความสัมพันธ์กันสูง
 */
bool IsHighlyCorrelated(const string a, const string b)
{
   if(a == b) return true;
   if((a == "EURUSD" && b == "GBPUSD") || (a == "GBPUSD" && b == "EURUSD"))
      return true;
   return false;
}

/**
 * HasCorrelatedActiveIceberg: เช็คว่ามีออเดอร์ประเภท Algo ทำงานอยู่ในคู่เงินที่สัมพันธ์กันหรือไม่
 * @param symbol ชื่อคู่เงินที่ต้องการตรวจสอบ
 */
bool HasCorrelatedActiveIceberg(const string symbol)
{
   if(!CorrelationBlockEnabled) return false;
   for(int i = 0; i < ArraySize(symbol_list); i++)
   {
      string s = symbol_list[i];
      if(s == "" || s == symbol) continue;
      if(!IsHighlyCorrelated(symbol, s)) continue;
      if(HasActiveAlgoOrder(s))
         return true;
   }
   return false;
}

/**
 * ShouldBlockByDOMSoftVeto: คัดกรองสัญญาณด้วยข้อมูลแรงซื้อขาย (Market Depth)
 * @param symbol ชื่อคู่เงิน
 * @param signal สัญญาณที่ได้รับ
 * @param snapshot ข้อมูลตลาดปัจจุบัน
 */
bool ShouldBlockByDOMSoftVeto(const string symbol, const SignalPack &signal, const MarketSnapshot &snapshot)
{
   if(!EnableDOMSoftVeto)
      return IsDOMPressureAgainst(signal, snapshot);

   double severe = MathMax(MathAbs(G_DOM_VETO_THRESHOLD), MathAbs(DOMVetoSevereThreshold));
   static string keys[];
   static int counts[];
   static datetime bars[];

   datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
   if(bar_time <= 0) bar_time = TimeCurrent();

   string key = symbol + "#" + IntegerToString((int)signal.direction);
   int idx = -1;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      if(keys[i] == key) { idx = i; break; }
   }
   if(idx < 0)
   {
      idx = ArraySize(keys);
      ArrayResize(keys, idx + 1);
      ArrayResize(counts, idx + 1);
      ArrayResize(bars, idx + 1);
      keys[idx] = key;
      counts[idx] = 0;
      bars[idx] = 0;
   }

    bool oppose = ((signal.direction == SIGNAL_BUY && snapshot.dom_imbalance <= -severe) ||
                   (signal.direction == SIGNAL_SELL && snapshot.dom_imbalance >= severe));
   if(!oppose)
   {
      counts[idx] = 0;
      bars[idx] = bar_time;
      return false;
   }

   if(bars[idx] != bar_time)
   {
      bars[idx] = bar_time;
      counts[idx]++;
   }

   int needed = MathMax(1, DOMVetoPersistentBars);
   if(counts[idx] >= needed)
   {
      static datetime last_dom_log_bar[];
      static string last_dom_log_key[];
      
      bool already_logged = false;
      for(int i=0; i<ArraySize(last_dom_log_key); i++)
      {
         if(last_dom_log_key[i] == key && last_dom_log_bar[i] == bar_time)
         {
            already_logged = true; break;
         }
      }
      
      if(!already_logged)
      {
         LogWarning(StringFormat("DOM SOFT-VETO BLOCK [%s]: dir=%d imbalance=%.2f severe=%.2f streak=%d/%d",
                                 symbol, (int)signal.direction, snapshot.dom_imbalance, severe, counts[idx], needed));
         
         int n = ArraySize(last_dom_log_key);
         bool found = false;
         for(int i=0; i<n; i++) { if(last_dom_log_key[i] == key) { last_dom_log_bar[i] = bar_time; found = true; break; } }
         if(!found) { ArrayResize(last_dom_log_key, n+1); ArrayResize(last_dom_log_bar, n+1); last_dom_log_key[n] = key; last_dom_log_bar[n] = bar_time; }
      }
      return true;
   }

   LogDebug(StringFormat("DOM SOFT-VETO HOLD [%s]: dir=%d imbalance=%.2f streak=%d/%d",
                         symbol, (int)signal.direction, snapshot.dom_imbalance, counts[idx], needed), EnableDebugLogs);
   return false;
}

/**
 * AllowRegimeUnknownBypass: อนุญาตให้เข้าเทรดในสภาวะ Unknown หากมีความมั่นใจสูงเป็นพิเศษ
 */
bool AllowRegimeUnknownBypass(const string symbol, double current_conf)
{
   if(!EnableRegimeUnknownCooldownBypass) return false;
   if(current_conf < UnknownRegimeMinConfidenceBypass) return false;

   int cooldown = MathMax(30, RegimeUnknownBypassCooldownSec);
   datetime now = TimeCurrent();

   int idx = -1;
   for(int i = 0; i < ArraySize(g_regime_bypass_keys); i++)
   {
      if(g_regime_bypass_keys[i] == symbol) { idx = i; break; }
   }
   if(idx < 0)
   {
      idx = ArraySize(g_regime_bypass_keys);
      ArrayResize(g_regime_bypass_keys, idx + 1);
      ArrayResize(g_regime_bypass_until, idx + 1);
      g_regime_bypass_keys[idx] = symbol;
      g_regime_bypass_until[idx] = 0;
   }

   if(now < g_regime_bypass_until[idx]) return false;

   g_regime_bypass_until[idx] = now + cooldown;
   return true;
}

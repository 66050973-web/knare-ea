#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Logger.mqh"
#include "SharedGlobals.mqh"

//+------------------------------------------------------------------+
//| Reason Logger Module - ระบบจัดการและบันทึกเหตุผลการไม่เข้าเทรด          |
//+------------------------------------------------------------------+

/**
 * CountSkipReason: นับจำนวนและประเภทของเหตุผลที่ไม่ได้เข้าเทรด
 * @param reason ข้อความระบุสาเหตุ
 */
void CountSkipReason(const string reason)
{
   if(!EnableDecisionTrace || reason == "") return;
   for(int i = 0; i < ArraySize(g_skip_reasons); i++)
   {
      if(g_skip_reasons[i] == reason)
      {
         g_skip_counts[i]++;
         return;
      }
   }
   int n = ArraySize(g_skip_reasons);
   ArrayResize(g_skip_reasons, n + 1);
   ArrayResize(g_skip_counts, n + 1);
   g_skip_reasons[n] = reason;
   g_skip_counts[n] = 1;
}

/**
 * LogDecisionTraceSummary: สรุปผลลัพธ์ของเหตุผลที่ไม่ได้เข้าเทรดในช่วงเวลาที่กำหนด
 */
void LogDecisionTraceSummary()
{
   if(!EnableDecisionTrace) return;
   int total = 0;
   string parts = "";
   for(int i = 0; i < ArraySize(g_skip_reasons); i++)
   {
      total += g_skip_counts[i];
      if(parts != "") parts += ", ";
      parts += g_skip_reasons[i] + "=" + IntegerToString(g_skip_counts[i]);
   }
   LogInfo(StringFormat("DecisionTrace[%ds]: total_skips=%d {%s}",
                        DecisionTraceIntervalSec, total, (parts == "" ? "none" : parts)));
   ArrayResize(g_skip_reasons, 0);
   ArrayResize(g_skip_counts, 0);
}

/**
 * GetDecisionReasonCount: คืนค่าจำนวนประเภทเหตุผลทั้งหมดที่บันทึกไว้
 */
int GetDecisionReasonCount() { return ArraySize(g_skip_reasons); }

/**
 * GetDecisionReasonName: คืนค่าชื่อเหตุผลตามลำดับดัชนี
 */
string GetDecisionReasonName(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_skip_reasons)) return "";
   return g_skip_reasons[idx];
}

/**
 * GetDecisionReasonValue: คืนค่าจำนวนครั้งที่พบเหตุผลตามลำดับดัชนี
 */
int GetDecisionReasonValue(const int idx)
{
   if(idx < 0 || idx >= ArraySize(g_skip_counts)) return 0;
   return g_skip_counts[idx];
}

/**
 * ResetSkipReasons: ล้างข้อมูลสถิติเหตุผลการไม่เข้าเทรดทั้งหมด
 */
void ResetSkipReasons()
{
   ArrayResize(g_skip_reasons, 0);
   ArrayResize(g_skip_counts, 0);
}

/**
 * LogNoTradeReasonPerBar: บันทึกเหตุผลที่ไม่ได้เข้าเทรดในแต่ละแท่งเทียน
 * ป้องกันการบันทึกซ้ำซ้อนในแท่งเทียนเดียวกันเพื่อลดปริมาณ Log
 */
void LogNoTradeReasonPerBar(const string symbol, ENUM_TIMEFRAMES tf, const string reason)
{
   static string keys[];
   static datetime last_bar_logged[];

   datetime bar_time = (datetime)SeriesInfoInteger(symbol, tf, SERIES_LASTBAR_DATE);
   if(bar_time <= 0) bar_time = TimeCurrent();
   string key = symbol + "#" + IntegerToString((int)tf) + "#" + reason;

   int idx = -1;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      if(keys[i] == key) { idx = i; break; }
   }
   if(idx < 0)
   {
      idx = ArraySize(keys);
      ArrayResize(keys, idx + 1);
      ArrayResize(last_bar_logged, idx + 1);
      keys[idx] = key;
      last_bar_logged[idx] = 0;
   }

   if(last_bar_logged[idx] == bar_time) return;
   last_bar_logged[idx] = bar_time;
   CountSkipReason(reason);
   LogInfo(StringFormat("NoTradeReason[%s]: %s", symbol, reason));
}

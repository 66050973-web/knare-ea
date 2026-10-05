#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "SharedGlobals.mqh"
#include "EngineController.mqh"
#include "SentimentFilter.mqh"
#include "TelegramWebhook.mqh"

//+------------------------------------------------------------------+
//| Daily Report - สรุปผลรายวันส่งเข้า Telegram (ส่งหลังเปลี่ยนวัน ตามเวลา Server)|
//+------------------------------------------------------------------+

// ปรับชื่อ symbol ในข้อความให้ไม่มีตัวอักษรที่ Telegram Markdown ตีความ (_ * ` [)
string DR_Clean(string s)
{
   StringReplace(s, "_", " ");
   StringReplace(s, "*", "");
   StringReplace(s, "`", "");
   StringReplace(s, "[", "(");
   return s;
}

/**
 * BuildDailyReport: สรุปเฉพาะดีลปิดของ EA นี้ (MagicNumber) ในช่วง [from, to)
 */
string BuildDailyReport(const datetime from, const datetime to)
{
   int wins = 0, losses = 0;
   double gross_profit = 0.0, gross_loss = 0.0;

   if(HistorySelect(from, to))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicNumber) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

         double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP);
         if(net > 0) { wins++; gross_profit += net; }
         else if(net < 0) { losses++; gross_loss += MathAbs(net); }
      }
   }

   int trades = wins + losses;
   double net_total = gross_profit - gross_loss;
   string pf = (gross_loss > 0.0) ? DoubleToString(gross_profit / gross_loss, 2) : (gross_profit > 0.0 ? "inf" : "-");
   string wr = (trades > 0) ? StringFormat("%.1f%%", 100.0 * wins / trades) : "-";

   int open_pos = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber) open_pos++;
   }

   string eng = "";
   string names[3] = {"TrendEngine", "BreakoutEngine", "MeanRevEngine"};
   for(int k = 0; k < 3; k++)
   {
      ENUM_ENGINE_STATUS st = GetEngineStatus(names[k]);
      if(st == ENGINE_DISABLED_BY_CONFIG) continue;
      eng += names[k] + "=" + EngineStatusToString(st) + " ";
   }
   if(eng == "") eng = "-";

   double sent_score = 0.0; int sent_age = 0;
   string sent_txt = "N/A";
   if(ReadSentimentCache(sent_score, sent_age))
      sent_txt = StringFormat("%.2f %s (%d min old)", sent_score, SentimentScoreToLabel(sent_score), sent_age);

   string news_txt = (g_minutes_to_next_news >= 999) ? "N/A" : StringFormat("%d min (%s)", g_minutes_to_next_news, g_next_news_name);

   string msg = StringFormat("Daily Report %s",  TimeToString(from, TIME_DATE));
   msg += "\\n" + StringFormat("Trades: %d (W %d / L %d) WinRate %s", trades, wins, losses, wr);
   msg += "\\n" + StringFormat("Net P/L: %.2f USD  PF: %s", net_total, pf);
   msg += "\\n" + StringFormat("Balance: %.2f  Equity: %.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   msg += "\\n" + StringFormat("Open positions: %d  Floating: %.2f", open_pos, AccountInfoDouble(ACCOUNT_PROFIT));
   msg += "\\n" + "Engines: " + DR_Clean(eng);
   msg += "\\n" + "Sentiment (USD): " + sent_txt;
   msg += "\\n" + "Next news: " + DR_Clean(news_txt);
   return msg;
}

/**
 * CheckDailyReport: เรียกจาก OnTimer — ส่งรายงานของ "เมื่อวาน" ครั้งเดียวหลังเปลี่ยนวัน (ตามเวลา Server)
 */
void CheckDailyReport()
{
   if(!EnableDailyReport) return;
   if(MQLInfoInteger(MQL_TESTER)) return;

   datetime now = TimeCurrent();
   datetime today = now - (now % 86400);

   static datetime s_last_day = 0;
   if(s_last_day == 0) { s_last_day = today; return; } // รอบแรกหลังเริ่ม EA แค่จดวันที่ ไม่ส่ง
   if(today <= s_last_day) return;

   datetime from = s_last_day;
   s_last_day = today;
   SendTelegramWebhook(_Symbol, "DAILY_REPORT", BuildDailyReport(from, today));
}

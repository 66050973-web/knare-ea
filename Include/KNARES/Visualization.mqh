#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Metrics.mqh"
#include "Config.mqh"
#include "ExecutionEngine.mqh"
#include "MarketData.mqh"
#include "SharedGlobals.mqh"
#include "SMCContext.mqh"
#include "SentimentFilter.mqh"
#include "EngineController.mqh"

//+------------------------------------------------------------------+
//| ฟังก์ชันนำเข้าข้อมูลจากโมดูลอื่นๆ เพื่อนำมาแสดงผลบน Dashboard            |
//+------------------------------------------------------------------+
int GetDecisionReasonCount();
string GetDecisionReasonName(const int idx);
int GetDecisionReasonValue(const int idx);
string GetSingleInstanceOwnerString();
int GetAutoGuardPauseRemainingSec();
int GetRegimePauseRemainingSec();
double GetGlobalHeatUsed();
double GetGlobalHeatMax();

//+------------------------------------------------------------------+
//| KNARES Advanced Dashboard - ระบบบัญชาการและแสดงผลข้อมูลเชิงลึก          |
//+------------------------------------------------------------------+

// --- การกำหนดชุดสี (Advanced Color Palette) ---
color UX_BG()       { return C'6,10,16'; }     // พื้นหลังหลัก (Deep Navy)
color UX_BORDER()   { return C'42,57,74'; }    // เส้นขอบ
color UX_TEXT()     { return C'238,244,250'; } // ตัวอักษรหลัก
color UX_MUTED()    { return C'150,166,184'; } // ตัวอักษรจาง
color UX_BLUE()     { return C'85,170,255'; }  // ข้อมูลทั่วไป
color UX_GREEN()    { return C'66,220,120'; }  // ค่าบวก
color UX_RED()      { return C'255,90,100'; }  // ค่าลบ/ความเสี่ยง
color UX_ORANGE()   { return C'255,160,60'; }  // คำเตือน
color UX_PURPLE()   { return C'180,120,255'; } // AI/Neural
color UX_CYAN()     { return C'0,230,255'; }   // SMC/Structure
color UX_DIM()      { return C'94,110,130'; }  // จางมาก

// --- ฟังก์ชันช่วยเหลือในการวาดกราฟิก (Graphic Helpers) ---

void UXCreateLabel(string name, string text, int x, int y, int anchor, int fontsize=9, color clr=CLR_NONE, string font="Verdana")
{
   if(clr == CLR_NONE) clr = UX_TEXT();
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontsize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void UXCreateRect(string name, int x1, int y1, int x2, int y2, color bg, color border, int border_width=1)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x1);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y1);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, x2 - x1);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, y2 - y1);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, border_width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

/**
 * ApplyCompactIndicatorPaneLayout: ปรับขนาดหน้าต่างให้ Main Window ใหญ่ที่สุด
 */
void ApplyCompactIndicatorPaneLayout()
{
   if(!CompactIndicatorPanes && !MQLInfoInteger(MQL_TESTER)) return;
   static datetime last_apply = 0;
   datetime now = TimeLocal();
   int interval = MQLInfoInteger(MQL_TESTER) ? 1 : CompactIndicatorLayoutUpdateSeconds;
   if(last_apply != 0 && now - last_apply < interval) return;
   last_apply = now;
   int windows_total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   if(windows_total <= 1) return;
   int sub_h = MQLInfoInteger(MQL_TESTER) ? 888 : CompactIndicatorPaneHeightPx;
   for(int pass = 0; pass < 3; pass++) {
      ChartSetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, 1000);
      for(int w = 1; w < windows_total; w++) ChartSetInteger(0, CHART_HEIGHT_IN_PIXELS, w, sub_h);
   }
   ChartRedraw(0);
}

/**
 * UpdateDashboard: อัปเดตข้อมูลระดับลึกทั้งหมดลงบน Dashboard
 */
void UpdateDashboard(ENUM_REGIME_TYPE regime, bool news_active, bool kill_switch)
{
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   // ข้าม Dashboard ทั้งหมดเมื่อรันใน Tester แบบไม่ Visual (ไม่มีใครดูอยู่แล้ว)
   // กันไม่ให้เสียเวลาคำนวณ GetMarketSnapshot/BuildSMCContext ซ้ำโดยไม่จำเป็นระหว่าง backtest
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   static datetime last_draw = 0;
   // บังคับหน่วงเวลาการอัปเดต (DashboardUpdateIntervalSec) ทั้งในโหมดปกติและ Tester 
   // เพื่อป้องกันอาการค้างจากการประมวลผลกราฟิกที่ถี่เกินไป
   if(TimeCurrent() - last_draw < DashboardUpdateIntervalSec)
      return;
   last_draw = TimeCurrent();

   ApplyCompactIndicatorPaneLayout();

   // ขยายความกว้างเป็นพิเศษ (Ultra-Wide) เป็น 480px เพื่อให้รองรับข้อมูลยาวๆ ได้เต็มที่
   int start_x = 10;
   int start_y = 30;
   int card_w = 480; 
   int section_h = 165;
   int gap = 5;

   // --- 1. [TOP] COMMAND CENTER & ACCOUNT PERFORMANCE ---
   UXCreateRect("DB_BG_SYS", start_x, start_y, start_x + card_w, start_y + section_h, UX_BG(), UX_BORDER(), 2);
   UXCreateLabel("LBL_T1", "KNARES APEX COMMAND CENTER", start_x + 10, start_y + 8, ANCHOR_LEFT_UPPER, 9, UX_PURPLE(), "Verdana Bold");
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl = eq - bal;
   double heat_max = GetGlobalHeatMax();
   double heat_pct = (heat_max > 0) ? (GetGlobalHeatUsed() / heat_max) * 100.0 : 0.0;
   string status_msg = news_active ? "NEWS PAUSE ACTIVE" : (kill_switch ? "EQUITY KILL SWITCH" : "SYSTEM READY");

   int cur_y = start_y + 35;
   UXCreateLabel("LBL_PNL_L", "Total Floating P/L:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_PNL_V", (pnl>=0?"+":"")+DoubleToString(pnl, 2)+" USD", start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (pnl>=0?UX_GREEN():UX_RED()), "Verdana Bold");
   
   cur_y += 18;
   UXCreateLabel("LBL_HEAT_L", "Global Portfolio Heat:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_HEAT_V", DoubleToString(heat_pct, 1) + "% Used", start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (heat_pct > 80 ? UX_RED() : UX_BLUE()));

   cur_y += 18;
   UXCreateLabel("LBL_STATUS_L", "Operational Status:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_STATUS_V", status_msg, start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (news_active?UX_ORANGE():(kill_switch?UX_RED():UX_GREEN())), "Verdana Bold");

   cur_y += 18;
   UXCreateLabel("LBL_RR_L", "WinRate / Avg RR:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_RR_V", StringFormat("%.1f%% / 1:%.2f", current_metrics.win_rate, current_metrics.avg_rr), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_BLUE());

   cur_y += 18;
   UXCreateLabel("LBL_REJ_L", "Execution Reject Streak:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   int streak = GetExecutionRejectStreak();
   UXCreateLabel("LBL_REJ_V", IntegerToString(streak) + " hits", start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (streak>0?UX_ORANGE():UX_TEXT()));

   // --- 2. [MIDDLE 1] SMC CONTEXT & MARKET ANALYTICS ---
   start_y += section_h + gap;
   int smc_section_h = section_h + 36; // ขยายสูงขึ้นเพื่อรองรับแถว News Countdown + Sentiment ที่เพิ่มมา
   UXCreateRect("DB_BG_SMC", start_x, start_y, start_x + card_w, start_y + smc_section_h, UX_BG(), UX_BORDER(), 1);
   UXCreateLabel("LBL_T2", "SMC & MARKET INTELLIGENCE", start_x + 10, start_y + 8, ANCHOR_LEFT_UPPER, 8, UX_CYAN(), "Verdana Bold");

   MarketSnapshot snap; SMCContext smc;
   if(GetMarketSnapshot(_Symbol, snap) && BuildSMCContext(_Symbol, snap, smc)) {
      cur_y = start_y + 35;
      UXCreateLabel("LBL_SMC_B_L", "Market Structure Bias:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      UXCreateLabel("LBL_SMC_B_V", SMCBiasToString(smc.bias), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (smc.bias==SMC_BIAS_BULLISH?UX_GREEN():(smc.bias==SMC_BIAS_BEARISH?UX_RED():UX_TEXT())));

      cur_y += 18;
      UXCreateLabel("LBL_SMC_Z_L", "Price Action Zone:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      UXCreateLabel("LBL_SMC_Z_V", SMCZoneToString(smc.zone), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (smc.zone==SMC_ZONE_DISCOUNT?UX_GREEN():(smc.zone==SMC_ZONE_PREMIUM?UX_RED():UX_BLUE())));

      cur_y += 18;
      UXCreateLabel("LBL_SMC_Q_L", "Buy/Sell Quality Score:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      UXCreateLabel("LBL_SMC_Q_V", StringFormat("%.2f Buy / %.2f Sell", smc.buy_quality, smc.sell_quality), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_BLUE());

      cur_y += 18;
      UXCreateLabel("LBL_AN_L", "Statistical Z / Vol%:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      UXCreateLabel("LBL_AN_V", StringFormat("%.2f Z | %.1f%% ATR", snap.zscore, snap.atr_percentile), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_TEXT());

      cur_y += 18;
      UXCreateLabel("LBL_HMM_L", "HMM Regime Shift Risk:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      double hmm = GlobalVariableCheck("KNARES_HMM_RISK") ? GlobalVariableGet("KNARES_HMM_RISK") : 0.0;
      UXCreateLabel("LBL_HMM_V", DoubleToString(hmm, 2), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (hmm>0.7?UX_RED():UX_TEXT()));

      cur_y += 18;
      UXCreateLabel("LBL_NEWS_L", "Next News In:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      string news_txt = (g_minutes_to_next_news >= 999) ? "N/A" : StringFormat("%dm (%s)", g_minutes_to_next_news, g_next_news_name);
      UXCreateLabel("LBL_NEWS_V", news_txt, start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (g_minutes_to_next_news <= 30 ? UX_ORANGE() : UX_TEXT()));

      cur_y += 18;
      UXCreateLabel("LBL_SENT_L", "News Sentiment (USD):", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      double sent_score = 0.0; int sent_age = 0;
      string sent_txt = "N/A";
      color sent_color = UX_TEXT();
      if(ReadSentimentCache(sent_score, sent_age))
      {
         sent_txt = StringFormat("%.2f (%s, %dm)", sent_score, SentimentScoreToLabel(sent_score), sent_age);
         sent_color = (sent_score > 0.15 ? UX_GREEN() : (sent_score < -0.15 ? UX_RED() : UX_TEXT()));
      }
      UXCreateLabel("LBL_SENT_V", sent_txt, start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, sent_color);
   }

   // --- 3. [MIDDLE 2] PERFORMANCE & SAFETY KPI ---
   start_y += smc_section_h + gap;
   UXCreateRect("DB_BG_PERF", start_x, start_y, start_x + card_w, start_y + section_h, UX_BG(), UX_BORDER(), 1);
   UXCreateLabel("LBL_T3", "SYSTEM PERFORMANCE & SAFETY", start_x + 10, start_y + 8, ANCHOR_LEFT_UPPER, 8, UX_GREEN(), "Verdana Bold");

   cur_y = start_y + 35;
   UXCreateLabel("LBL_T_L", "Trades / Profit Factor:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_T_V", StringFormat("%d TR | %.2f PF", current_metrics.win_trades+current_metrics.loss_trades, current_metrics.profit_factor), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_GREEN());
   
   cur_y += 18;
   UXCreateLabel("LBL_R_L", "Rescue (Wins / Net):", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_R_V", StringFormat("%d W | %.2f USD", g_rescue_trades_count, g_rescue_gross_profit-g_rescue_gross_loss), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_BLUE());
   
   cur_y += 18;
   UXCreateLabel("LBL_E_L", "Early Inv. Exits / Net:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_E_V", StringFormat("%d EX | %.2f USD", g_early_inv_count, g_early_inv_net), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_ORANGE());

   cur_y += 18;
   UXCreateLabel("LBL_DD_L", "Max Historical Drawdown:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   UXCreateLabel("LBL_DD_V", DoubleToString(current_metrics.max_drawdown_usd, 2) + " USD", start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_RED());

   cur_y += 18;
   UXCreateLabel("LBL_LG_L", "Limit Gate Blocked:", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
   int total_limit = 0; for(int i=0; i<8; i++) total_limit += g_limit_gate_counts[i];
   UXCreateLabel("LBL_LG_V", IntegerToString(total_limit) + " signals", start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, UX_DIM());

   // --- 4. [BOTTOM] ENGINE BREAKDOWN ---
   start_y += section_h + gap;
   UXCreateRect("DB_BG_ENG", start_x, start_y, start_x + card_w, start_y + 90, UX_BG(), UX_BORDER(), 1);
   UXCreateLabel("LBL_T4", "STRATEGY BREAKDOWN (TR | PF)", start_x + 10, start_y + 8, ANCHOR_LEFT_UPPER, 8, UX_BLUE(), "Verdana Bold");

   cur_y = start_y + 30;
   for(int i=0; i<3; i++) {
      string name = (i==0?"Trend Strategy":(i==1?"Breakout Engine":(i==2?"Mean Reversion":"Unknown")));
      UXCreateLabel("LBL_E_L_"+(string)i, name + ":", start_x + 15, cur_y, ANCHOR_LEFT_UPPER, 8, UX_TEXT());
      UXCreateLabel("LBL_E_V_"+(string)i, StringFormat("%d | %.2f", engine_metrics[i].trades, engine_metrics[i].pf), start_x + card_w - 15, cur_y, ANCHOR_RIGHT_UPPER, 8, (engine_metrics[i].pf>=1.0?UX_GREEN():UX_RED()));
      cur_y += 16;
   }

   // --- 5. [FOOTER] PIPELINE & INSTANCE ---
   cur_y = start_y + 95;
   UXCreateLabel("LBL_PL_V", StringFormat("Pipeline: %s|%s|%s | %s", g_pipeline_trend, g_pipeline_breakout, g_pipeline_meanrev, g_pipeline_final), start_x + 10, cur_y, ANCHOR_LEFT_UPPER, 7, UX_DIM());
   UXCreateLabel("LBL_INST", "Instance: " + GetSingleInstanceOwnerString(), start_x + card_w - 10, cur_y, ANCHOR_RIGHT_UPPER, 7, UX_DIM());
}

/**
 * ClearDashboard: ล้างข้อมูลบน Dashboard เมื่อหยุดการทำงาน
 */
void ClearDashboard()
{
   ObjectsDeleteAll(0, "DB_BG_");
   ObjectsDeleteAll(0, "LBL_");
}

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Logger.mqh"
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Metrics Module - ระบบคำนวณสถิติการเทรดที่ซิงค์ทั้ง Live & Backtest    |
//| ทำหน้าที่: ติดตามผลงาน (Performance), ความเสี่ยง (Risk), และประเมินคะแนนระบบ |
//+------------------------------------------------------------------+

// --- ตัวแปร Global สำหรับการวิเคราะห์และแสดงผลบน Dashboard ---
double last_ai_confidence = 0; // ความมั่นใจของ AI ล่าสุด (ใช้แสดงผลกราฟิก)
double last_dom_imbalance = 0; // ค่าความไม่สมดุลของ Order Book ล่าสุด
double g_last_score = 0;       // คะแนนรวมจากการวิเคราะห์ล่าสุด
double g_last_confidence = 0;  // ความมั่นใจของสัญญาณล่าสุด
double g_last_risk_money = 0;  // จำนวนเงินที่เสี่ยงในไม้ล่าสุด

//+------------------------------------------------------------------+
//| โครงสร้างข้อมูลสถิติแยกตาม Engine (Trend, Breakout, MeanReversion) |
//+------------------------------------------------------------------+
struct EngineStats
{
   string name;            // ชื่อ Engine
   int trades;             // จำนวนการเทรดทั้งหมด
   int wins;               // จำนวนครั้งที่ชนะ
   int losses;             // จำนวนครั้งที่แพ้
   double gross_profit;    // กำไรรวม
   double gross_loss;      // ขาดทุนรวม
   double net_profit;      // กำไรสุทธิ
   int sl_count;           // จำนวนที่ชน Stop Loss
   int tp_count;           // จำนวนที่ชน Take Profit
   int other_count;        // จำนวนที่ปิดด้วยเงื่อนไขอื่น
   double max_drawdown;    // Drawdown สูงสุดของ Engine นี้
   double pf;              // Profit Factor (กำไรหารด้วยขาดทุน)
   double win_rate;        // อัตราการชนะ (%)
   double expectancy;      // ค่าคาดหวังต่อการเทรด (Expectancy)
   ENUM_ENGINE_STATUS status; // สถานะปัจจุบันของ Engine
   double rolling_pf;      // Profit Factor แบบ Rolling Window (ไม้ล่าสุด N ไม้)
   double trade_share;     // สัดส่วนการเทรดเทียบกับทั้งหมด (%)
   double engine_rr;       // สัดส่วน Reward-to-Risk ราย Engine
};

//+------------------------------------------------------------------+
//| โครงสร้างข้อมูลสถิติรวมของกลยุทธ์ (Global Strategy Metrics)        |
//+------------------------------------------------------------------+
struct StrategyMetrics
{
   double total_profit;      // กำไรรวม (Gross Profit)
   double total_loss;        // ขาดทุนรวม (Gross Loss)
   double net_pnl;           // กำไรสุทธิ (Net P/L) ของคู่เงินปัจจุบัน
   double total_net_pnl;     // กำไรสุทธิรวมของ EA ทุกตัวในพอร์ต
   int win_trades;           // จำนวนไม้ที่ชนะ
   int loss_trades;          // จำนวนไม้ที่แพ้
   double max_drawdown_usd;  // Drawdown สูงสุด (หน่วยเงิน)
   double max_drawdown_pct;  // Drawdown สูงสุด (%)
   double profit_factor;     // Profit Factor รวม
   double win_rate;          // อัตราการชนะรวม (%)
   int consecutive_wins;     // จำนวนการชนะติดต่อกันปัจจุบัน
   int consecutive_losses;   // จำนวนการแพ้ติดต่อกันปัจจุบัน
   int max_consecutive_wins; // สถิติการชนะติดต่อกันสูงสุด
   int max_consecutive_losses; // สถิติการแพ้ติดต่อกันสูงสุด
   double sharpe_ratio;      // Sharpe Ratio (ประสิทธิภาพเทียบความเสี่ยง)
   double recovery_factor;   // Recovery Factor (ความสามารถในการฟื้นตัวจากจุดสูงสุดที่ติดลบ)
   
   // ตัวชี้วัดความเสี่ยงในระดับพอร์ต
   double portfolio_heat;    // ความเสี่ยงรวมที่กำลังถือครองในพอร์ต (Heat)
   double exposure;          // ระดับการถือครองสินทรัพย์เทียบกับ Equity (Exposure)
   double residual_risk;     // ความเสี่ยงที่เหลืออยู่หลังการป้องกันความเสี่ยง
   int regime_dist[12];      // การกระจายตัวของการเทรดในแต่ละสภาวะตลาด (12 Regimes ตาม ENUM_REGIME_TYPE)
   
   // โหมดความเสี่ยงปัจจุบัน (Phase 11 Risk Management)
   ENUM_RISK_MODE risk_mode;

   // การวิเคราะห์ขั้นสูงหลังการเทรด (Post-Trade Analytics)
   double unknown_ratio;      // % ของการเทรดที่เกิดขึ้นในสภาวะที่ไม่ชัดเจน (UNKNOWN)
   double rar;               // Risk-Adjusted Return (กำไรเทียบกับ MDD)
   double break_even_winrate; // อัตราการชนะขั้นต่ำที่ต้องมีเพื่อให้เท่าทุน (Break-even Winrate)
   double avg_rr;            // สัดส่วน Reward-to-Risk เฉลี่ย
   double misattrib_rate;    // ความแม่นยำของการระบุสาเหตุการปิดออเดอร์
   
   // สถิติที่ปรับจูนตามขนาด Lot (Lot-Aware Metrics เพื่อเปรียบเทียบข้ามพอร์ต)
   double lot_normalized_net;        // กำไรสุทธิที่ปรับฐานเป็น 0.01 lot
   double lot_normalized_expectancy; // ค่าคาดหวังที่ปรับฐานเป็น 0.01 lot
   double lot_normalized_drawdown;   // Drawdown ที่ปรับฐานเป็น 0.01 lot
   double lot_efficiency_score;      // คะแนนประสิทธิภาพการใช้ขนาด Lot
   int    exposure_cap_hits;         // จำนวนครั้งที่การเปิดออเดอร์ชนเพดาน Exposure
   int    heat_cap_hits;             // จำนวนครั้งที่การเปิดออเดอร์ชนเพดาน Heat
};

StrategyMetrics current_metrics;
EngineStats engine_metrics[3]; // อาร์เรย์เก็บสถิติแยกตาม Engine: 0=Trend, 1=Breakout, 2=MeanRev

//+------------------------------------------------------------------+
//| --- ฟังก์ชันช่วยคำนวณตัวชี้วัดหลัก (KPI Helpers) ---                |
//+------------------------------------------------------------------+

// คำนวณ Profit Factor
double CalcPF(double profit, double loss)
{
   double abs_loss = MathAbs(loss);
   if(abs_loss < 0.00001) return (profit > 0 ? 99.0 : 0.0);
   return profit / abs_loss;
}

// คำนวณ Win Rate
double CalcWinRate(int wins, int trades)
{
   if(trades <= 0) return 0.0;
   return (double)wins / (double)trades * 100.0;
}

// คำนวณ Expectancy (ค่าคาดหวังเฉลี่ยต่อหนึ่งการเทรด)
double CalcExpectancy(int wins, int losses, double profit, double loss)
{
   int trades = wins + losses;
   if(trades <= 0) return 0.0;
   double avg_win = profit / (double)MathMax(wins, 1);
   double avg_loss = MathAbs(loss) / (double)MathMax(losses, 1);
   double pw = (double)wins / (double)trades;
   double pl = (double)losses / (double)trades;
   return (pw * avg_win) - (pl * avg_loss);
}

//+------------------------------------------------------------------+
//| อัปเดตสถิติแบบ Rolling (ไม้ล่าสุด N ไม้) เพื่อประเมินผลงานปัจจุบัน      |
//| engine_idx: ลำดับของ Engine ในอาร์เรย์                             |
//+------------------------------------------------------------------+
void UpdateRollingMetrics(int engine_idx)
{
   if(engine_idx < 0 || engine_idx > 2 || !HistorySelect(0, TimeCurrent())) return;

   int total_deals = HistoryDealsTotal();
   string engine_name = engine_metrics[engine_idx].name;

   // ขั้นที่ 1: รวบรวม Position ID ของออเดอร์ที่ Engine นี้เป็นผู้เปิด (ชื่อ Engine อยู่ใน Comment ของดีลขาเข้าเท่านั้น
   // ดีลขาออกมี Comment เป็นเหตุผลการปิด เช่น RegimeExitProfit จึงต้องจับคู่ผ่าน Position ID)
   ulong eng_positions[];
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      if(StringFind(HistoryDealGetString(ticket, DEAL_COMMENT), engine_name) < 0) continue;
      int n = ArraySize(eng_positions);
      ArrayResize(eng_positions, n + 1);
      eng_positions[n] = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   }
   ArraySort(eng_positions);

   // ขั้นที่ 2: ถอยหลังจากดีลขาออกล่าสุด เลือก N ไม้ล่าสุดของ Engine นี้
   double g_profit = 0, g_loss = 0;
   int count = 0;
   for(int i = total_deals - 1; i >= 0 && count < RollingPFWindow; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;

      long entry_type = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;

      ulong pos_id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(ArraySize(eng_positions) == 0 || ArrayBsearch(eng_positions, pos_id) < 0 ||
         eng_positions[ArrayBsearch(eng_positions, pos_id)] != pos_id) continue;

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                   HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                   HistoryDealGetDouble(ticket, DEAL_SWAP);
      if(net > 0) g_profit += net;
      else if(net < 0) g_loss += MathAbs(net);
      count++;
   }

   // ไม่มีข้อมูลให้คำนวณ = ยังไม่ทราบผลงาน ให้ถือเป็นกลาง (ไม่ใช่ 0 ที่ทำให้ Engine ถูกหยุดโดยไม่มีเหตุผล)
   engine_metrics[engine_idx].rolling_pf = (count > 0) ? CalcPF(g_profit, g_loss) : 99.0;
}

//+------------------------------------------------------------------+
//| เริ่มต้นกำหนดค่าสถิติสำหรับทุก Engine (Initialization)               |
//+------------------------------------------------------------------+
void InitEngineMetrics()
{
   string names[3] = {"TrendEngine", "BreakoutEngine", "MeanRevEngine"};
   for(int i=0; i<3; i++)
   {
      engine_metrics[i].name = names[i];
      engine_metrics[i].trades = 0;
      engine_metrics[i].wins = 0;
      engine_metrics[i].losses = 0;
      engine_metrics[i].gross_profit = 0;
      engine_metrics[i].gross_loss = 0;
      engine_metrics[i].net_profit = 0;
      engine_metrics[i].sl_count = 0;
      engine_metrics[i].tp_count = 0;
      engine_metrics[i].other_count = 0;
      engine_metrics[i].max_drawdown = 0;
      engine_metrics[i].pf = 0;
      engine_metrics[i].win_rate = 0;
      engine_metrics[i].expectancy = 0;
      engine_metrics[i].status = ENGINE_ACTIVE;
      engine_metrics[i].rolling_pf = 0;
      engine_metrics[i].trade_share = 0;
      engine_metrics[i].engine_rr = 0;
   }
   
   // เริ่มต้นค่าตัวชี้วัดกลยุทธ์รวม
   current_metrics.unknown_ratio = 0;
   current_metrics.rar = 0;
   current_metrics.break_even_winrate = 0;
   current_metrics.avg_rr = 0;
   current_metrics.misattrib_rate = 0;
   for(int j=0; j<12; j++) current_metrics.regime_dist[j] = 0;
}

//+------------------------------------------------------------------+
//| อัปเดตสถิติรวมของระบบโดยการอ่านประวัติการเทรดจากโบรกเกอร์             |
//| symbol_filter: ชื่อคู่เงินที่ต้องการกรอง (ถ้าว่างจะคำนวณทั้งหมดภายใต้ Magic) |
//+------------------------------------------------------------------+
void UpdateMetrics(string symbol_filter = "")
{
   if(!HistorySelect(0, TimeCurrent())) return;

   double gross_profit = 0;
   double gross_loss = 0;
   double filtered_net = 0;
   double global_net = 0;
   int wins = 0, losses = 0;
   int c_wins = 0, c_losses = 0;
   int m_wins = 0, m_losses = 0;
   
   double max_balance = 0;
   double max_dd_usd = 0;

   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
      {
         // ตรองเฉพาะออเดอร์ของ EA ตัวนี้ (Magic Number)
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
         
         double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double s = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double deal_net = p + c + s;
         
         global_net += deal_net;

         // กรองสถิติตามคู่เงิน
         string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         if(symbol_filter != "" && deal_symbol != symbol_filter) continue;
         
         filtered_net += deal_net;

         // ตรวจสอบธุรกรรมที่เป็นการปิดสถานะ (Exit)
         long entry_type = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_INOUT)
         {
            // วิเคราะห์ Drawdown จากยอด Equity สะสม (Net P/L Curve)
            if(filtered_net > max_balance) max_balance = filtered_net;
            double dd = max_balance - filtered_net;
            if(dd > max_dd_usd) max_dd_usd = dd;

            if(deal_net > 0)
            {
               gross_profit += deal_net;
               wins++;
               c_wins++;
               c_losses = 0;
            }
            else if(deal_net < 0)
            {
               gross_loss += MathAbs(deal_net);
               losses++;
               c_losses++;
               c_wins = 0;
            }
            
            // เก็บสถิติการชนะและแพ้ติดต่อกันสูงสุด (Streak)
            if(c_wins > m_wins) m_wins = c_wins;
            if(c_losses > m_losses) m_losses = c_losses;
         }
      }
   }

   // เก็บข้อมูลลงในตัวแปรโครงสร้าง current_metrics
   current_metrics.total_profit = gross_profit;
   current_metrics.total_loss = gross_loss;
   current_metrics.net_pnl = filtered_net;
   current_metrics.total_net_pnl = global_net;
   current_metrics.win_trades = wins;
   current_metrics.loss_trades = losses;
   current_metrics.consecutive_wins = c_wins;
   current_metrics.consecutive_losses = c_losses;
   current_metrics.max_consecutive_wins = m_wins;
   current_metrics.max_consecutive_losses = m_losses;
   current_metrics.max_drawdown_usd = max_dd_usd;
   
   // ติดตามระดับความเสี่ยงรวม (Portfolio Heat) ผ่าน Global Variable
   current_metrics.portfolio_heat = 0;
   string gv_heat = "KNARES_Total_Risk_Money";
   if(GlobalVariableCheck(gv_heat)) current_metrics.portfolio_heat = GlobalVariableGet(gv_heat);
   
   // คำนวณค่า Exposure (มูลค่าสินทรัพย์รวมที่ถือครอง) เทียบกับเงินทุน
   current_metrics.exposure = 0;
   double total_notional = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         double pos_lots = PositionGetDouble(POSITION_VOLUME);
         double contract_size = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         double mid_price = 0.5 * (SymbolInfoDouble(pos_symbol, SYMBOL_BID) + SymbolInfoDouble(pos_symbol, SYMBOL_ASK));
         total_notional += pos_lots * (contract_size > 0 ? contract_size : 100000.0) * (mid_price > 0 ? mid_price : 1.0);
      }
   }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > 0) current_metrics.exposure = total_notional / eq;

   // คำนวณตัวชี้วัดพื้นฐาน
   current_metrics.profit_factor = CalcPF(gross_profit, gross_loss);
   int total_trades = wins + losses;
   current_metrics.win_rate = (total_trades > 0) ? (double)wins / (double)total_trades * 100.0 : 0.0;

   // คำนวณตัวชี้วัดขั้นสูง (Advanced Analysis)
   int total_regime_samples = 0;
   for(int k=0; k<12; k++) total_regime_samples += current_metrics.regime_dist[k];
   if(total_regime_samples > 0)
      current_metrics.unknown_ratio = (double)current_metrics.regime_dist[REGIME_UNKNOWN] / (double)total_regime_samples * 100.0;
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > 0 && max_dd_usd > 0)
      current_metrics.rar = (global_net / bal * 100.0) / (max_dd_usd / bal * 100.0);

   current_metrics.avg_rr = (losses > 0 && wins > 0) ? (gross_profit / (double)wins) / (gross_loss / (double)losses) : 0;
   if(current_metrics.avg_rr > 0)
      current_metrics.break_even_winrate = 100.0 / (1.0 + current_metrics.avg_rr);

   // สรุปสถิติย่อยราย Engine
   for(int i=0; i<3; i++)
   {
      if(total_trades > 0)
         engine_metrics[i].trade_share = (double)engine_metrics[i].trades / (double)total_trades * 100.0;
      
      if(engine_metrics[i].losses > 0 && engine_metrics[i].wins > 0)
         engine_metrics[i].engine_rr = (engine_metrics[i].gross_profit / (double)engine_metrics[i].wins) / (engine_metrics[i].gross_loss / (double)engine_metrics[i].losses);
   }

   // ตัวบ่งชี้ความสามารถในการฟื้นตัว (Recovery Factor)
   if(max_dd_usd > 0)
      current_metrics.recovery_factor = filtered_net / max_dd_usd;
   else
      current_metrics.recovery_factor = 0;

   // คำนวณ Sharpe Ratio แบบง่ายสำหรับการประเมินผลเบื้องต้น
   current_metrics.sharpe_ratio = (total_trades > 5) ? (filtered_net / (double)total_trades) / 10.0 : 0;
   
   // การปรับฐานข้อมูลตามขนาด Lot (Normalization) เพื่อให้เปรียบเทียบข้ามกลยุทธ์ได้
   double lot_scale = (FixedLotSize > 0) ? (FixedLotSize / 0.01) : 1.0;
   current_metrics.lot_normalized_net = filtered_net / lot_scale;
   current_metrics.lot_normalized_expectancy = CalcExpectancy(wins, losses, gross_profit, gross_loss) / lot_scale;
   current_metrics.lot_normalized_drawdown = max_dd_usd / lot_scale;
   
   // คำนวณคะแนนประสิทธิภาพการใช้ Lot
   current_metrics.lot_efficiency_score = (MathAbs(filtered_net) > 0) ? (current_metrics.lot_normalized_net / 15.02) : 1.0; 
}

//+------------------------------------------------------------------+
//| ฟังก์ชันสำหรับคำนวณคะแนนรวมในโหมด Strategy Tester (Custom Score) |
//| คืนค่า: คะแนนสุทธิที่ใช้ในการจัดอันดับผลการทดสอบ (Optimization)         |
//+------------------------------------------------------------------+
double ComputeCustomTesterScore()
{
   UpdateMetrics();

   int trades = current_metrics.win_trades + current_metrics.loss_trades;
   double net = current_metrics.lot_normalized_net; // ใช้กำไรที่ปรับฐานแล้วในการประเมิน
   double pf = current_metrics.profit_factor;
   double win_rate = current_metrics.win_rate / 100.0;
   double dd_usd = current_metrics.max_drawdown_usd;

   // หากไม่มีการเทรด ให้คะแนนติดลบสูงสุด
   if(trades <= 0)
   {
      Print("OnTesterGuard: trades=0 reason=no_trade score=-999999");
      return -999999.0;
   }

   if(pf <= 0.0)
      pf = 0.01;

   double dd_denom = MathMax(1.0, dd_usd);
   double score = 0.0;
   double low_trade_penalty = 0.0;

   int min_trades = MinTesterTrades;
   double per_trade_penalty = LowTradePenaltyPerTrade;

   // คำนวณคะแนนตามโหมดการทดสอบที่ตั้งไว้
   if(TesterScoreMode == TESTER_SCORE_QUICK)
   {
      // โหมด Quick: เน้นผลลัพธ์กำไรต่อความเสี่ยงพื้นฐาน ไม่เน้นความเข้มงวดของสถิติ
      min_trades = QuickTesterMinTrades;
      per_trade_penalty = QuickLowTradePenaltyPerTrade;

      double quick_quality = MathMax(0.10, pf) * MathMax(0.10, win_rate + 0.50);
      score = (net * quick_quality / dd_denom) * 100.0;
   }
   else if(TesterScoreMode == TESTER_SCORE_OPTIMIZE)
   {
      // โหมด Optimize: สร้างสมดุลที่เหมาะสมระหว่างกำไรสุทธิ, PF, Win Rate และ Drawdown
      min_trades = MinTesterTrades;
      per_trade_penalty = LowTradePenaltyPerTrade;

      double robustness_multiplier = MathMax(0.10, pf) * MathMax(0.10, win_rate + 0.50);
      score = (net * robustness_multiplier / dd_denom) * 100.0;
   }
   else // TESTER_SCORE_ROBUST
   {
      // โหมด Robust: เน้นความเสถียรสูงสุด (เหมาะสำหรับ OOS) ให้คะแนนยากและลงโทษรุนแรง
      min_trades = MathMax(MinTesterTrades, 50);
      per_trade_penalty = LowTradePenaltyPerTrade * 1.50;

      double pf_component = MathMax(0.01, pf - 1.0);
      double win_component = MathMax(0.10, win_rate);
      score = (net * pf_component * win_component / dd_denom) * 250.0;

      if(pf < 1.0)
         score -= 500.0; // บล็อกพารามิเตอร์ที่ไม่ทำกำไรสุทธิ
   }

   // ลงโทษหากจำนวนไม้ที่เทรดมีขนาดตัวอย่าง (Sample Size) น้อยเกินไป
   if(PenalizeLowTesterTrades && trades < min_trades)
      low_trade_penalty = (double)(min_trades - trades) * per_trade_penalty;

   score -= low_trade_penalty;

   // กรณีผลการทดสอบขาดทุนสุทธิ ให้สะท้อนคะแนนตามระดับความเสียหายจาก Drawdown
   if(net <= 0.0)
      score = net - low_trade_penalty - (dd_usd * 2.0);

   return score;
}

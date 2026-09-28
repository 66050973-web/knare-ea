#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes - ส่วนการนำเข้าไฟล์ไลบรารีและโมดูลต่างๆ ที่จำเป็นต่อระบบ EA     |
//+------------------------------------------------------------------+
#include <KNARES/Config.mqh>           // การตั้งค่าและพารามิเตอร์หลักของผู้ใช้
#include <KNARES/Types.mqh>            // การกำหนดโครงสร้างข้อมูลและ Enum ต่างๆ
#include <KNARES/SharedGlobals.mqh>    // ตัวแปรส่วนกลางที่ใช้ร่วมกันระหว่างโมดูล
#include <KNARES/Logger.mqh>           // ระบบบันทึกข้อมูลการทำงาน (Log)
#include <KNARES/ReasonLogger.mqh>     // ระบบบันทึกเหตุผลที่ไม่ได้เข้าเทรด
#include <KNARES/InstanceGuard.mqh>    // ป้องกันการเปิด EA ซ้ำซ้อนในหน้าต่างเดียวกัน
#include <KNARES/RiskAccounting.mqh>   // ระบบบัญชีและการคำนวณความเสี่ยง
#include <KNARES/MarketPolicy.mqh>     // นโยบายและกฎการเข้าตลาด
#include <KNARES/DynamicThreshold.mqh> // การปรับเกณฑ์การตัดสินใจแบบไดนามิก
#include <KNARES/InternalHelpers.mqh>  // ฟังก์ชันช่วยเหลือการทำงานภายใน
#include <KNARES/SignalRescue.mqh>     // ระบบกู้คืนสัญญาณเทรดที่เกือบผ่านเกณฑ์
#include <KNARES/TradeTracking.mqh>    // การติดตามสถานะออเดอร์และการเทรด
#include <KNARES/ApexAnalytics.mqh>    // ระบบวิเคราะห์ข้อมูลเชิงสถิติขั้นสูง Apex
#include <KNARES/TradeEventHandler.mqh> // ตัวจัดการเหตุการณ์ที่เกี่ยวกับการเทรด
#include <KNARES/LifecycleManager.mqh>  // ตัวจัดการวงจรการทำงาน (Init/Deinit)
#include <KNARES/InputManager.mqh>      // ตัวจัดการข้อมูลนำเข้าจากผู้ใช้
#include <KNARES/TesterEngine.mqh>     // ระบบสำหรับทำงานในโหมดทดสอบย้อนหลัง
#include <KNARES/EngineController.mqh>  // ตัวควบคุมการทำงานของกลยุทธ์ต่างๆ
#include <KNARES/PipelineController.mqh> // ตัวควบคุมลำดับขั้นตอนการตัดสินใจ Pipeline
#include <KNARES/DashboardController.mqh> // ตัวควบคุมการแสดงผลบน Dashboard
#include <KNARES/MarketData.mqh>       // ตัวจัดการข้อมูลราคาและค่า Spread
#include <KNARES/FeatureEngine.mqh>    // ตัวคำนวณคุณลักษณะทางเทคนิค (Features)
#include <KNARES/RegimeClassifier.mqh> // ตัวจำแนกสภาวะตลาด (Regime)
#include <KNARES/SignalTrend.mqh>      // กลยุทธ์การเทรดตามแนวโน้ม
#include <KNARES/SignalBreakout.mqh>   // กลยุทธ์การเทรดเมื่อราคาทะลุแนวรับแนวต้าน
#include <KNARES/SignalMeanReversion.mqh> // กลยุทธ์การเทรดแบบสวนกลับหาค่าเฉลี่ย
#include <KNARES/EnsembleScorer.mqh>   // ระบบรวมคะแนนจากหลายกลยุทธ์และใช้ AI
#include <KNARES/RiskEngine.mqh>       // ตัวคำนวณขนาดลอตและความเสี่ยงต่อไม้
#include <KNARES/PortfolioGovernor.mqh> // ตัวควบคุมความเสี่ยงรวมระดับพอร์ต
#include <KNARES/ExecutionEngine.mqh>   // ระบบส่งคำสั่งเทรดเข้าสู่ตลาดจริง
#include <KNARES/PositionManager.mqh>  // ตัวจัดการออเดอร์ที่เปิดอยู่ (SL/TP/Trailing)
#include <KNARES/Metrics.mqh>          // ตัวคำนวณสถิติและผลการดำเนินงาน
#include <KNARES/TradeJournal.mqh>     // ระบบบันทึกประวัติการเทรดลงไฟล์
#include <KNARES/Utils.mqh>            // ฟังก์ชันอรรถประโยชน์ทั่วไป
#include <KNARES/Visualization.mqh>    // ระบบการวาดภาพและกราฟิกบนหน้าจอ
#include <KNARES/OnnxOverlay.mqh>      // ระบบเชื่อมต่อโมดูล AI (ONNX)
#include <KNARES/FeatureExport.mqh>    // ระบบส่งออกข้อมูลเพื่อใช้สอน AI
#include <KNARES/NewsFilter.mqh>       // ตัวกรองข่าวสารเศรษฐกิจ
#include <KNARES/SentimentFilter.mqh>  // ตัวกรอง Sentiment ข่าวจากภายนอก (Alpha Vantage)
#include <KNARES/NewsConnector.mqh>    // ตัวเชื่อมต่อข้อมูลข่าวสารจากภายนอก
#include <KNARES/Diagnostics.mqh>      // ระบบตรวจสอบสุขภาพของ EA
#include <KNARES/ParameterManager.mqh> // ตัวจัดการการอัปเดตพารามิเตอร์ Real-time
#include <KNARES/MarketDepth.mqh>      // ตัววิเคราะห์ข้อมูลปริมาณคำสั่งซื้อขาย (DOM)
#include <KNARES/StatArbEngine.mqh>    // กลยุทธ์ Statistical Arbitrage
#include <KNARES/AlgoExecution.mqh>    // ระบบการส่งคำสั่งแบบอัลกอริทึม (เช่น Iceberg)
#include <KNARES/RegimeForecaster.mqh> // ตัวพยากรณ์สภาวะตลาดในอนาคต
#include <KNARES/MathLib.mqh>          // ไลบรารีฟังก์ชันคณิตศาสตร์
#include <KNARES/SMCContext.mqh>       // ตัววิเคราะห์โครงสร้างตลาดตามหลัก SMC
#include <KNARES/SMCFilter.mqh>        // ตัวกรองสัญญาณด้วยหลักการ SMC
#include <KNARES/SMCVisualizer.mqh>    // ตัวแสดงผลโครงสร้าง SMC บนกราฟ

//+------------------------------------------------------------------+
//| ฟังก์ชัน RunTradingCycle                                           |
//| ลอจิกหลักในการเทรด (Trading Cycle) จะถูกเรียกใช้งานทุกๆ Tick หรือรอบการรัน  |
//| ทำหน้าที่ประมวลผลข้อมูลตลาด, ตรวจสอบเงื่อนไข, หาจุดเข้าเทรด และจัดการออเดอร์ |
//+------------------------------------------------------------------+
void OnTickImpl();
void OnTimerImpl();
ulong g_prof_us[12];
string g_prof_names[12] = {"Features","SMCContext","DOM","Regime","ManagePos1","StatArb","HMM","ManagePos2","Pipeline","OnTickTotal","CycleTotal","OnTimerTotal"};

void RunTradingCycleImpl(string symbol);
void RunTradingCycle(string symbol)
{
   ulong __ct = GetMicrosecondCount();
   RunTradingCycleImpl(symbol);
   g_prof_us[10] += GetMicrosecondCount() - __ct;
}
void RunTradingCycleImpl(string symbol)
{
   g_last_symbol = symbol;
   
   // --- กำหนดค่าเริ่มต้นและตัวแปรควบคุมลำดับการทำงาน ---
   bool   pass_scale_in = true; // ตัวแปรสำหรับควบคุมการเปิดไม้เพิ่ม (Scale-in)
   bool   is_new_bar    = IsNewBar(symbol, MainTF); // ตรวจสอบว่าเป็นการเริ่มต้นแท่งเทียนใหม่หรือไม่

   // ตรวจสอบระบบป้องกันอัตโนมัติ (Auto-Guard)
   // หากระบบถูกสั่งให้พักการเทรดชั่วคราว (เช่น เกิดข้อผิดพลาดติดกัน) จะข้ามการทำงานในรอบนี้
   if(g_autoguard_pause_until > TimeCurrent())
   {
      int remain = (int)(g_autoguard_pause_until - TimeCurrent());
      LogNoTradeReasonPerBar(symbol, MainTF, "autoguard_pause");
      LogDebug(StringFormat("Cycle skip [%s]: Auto-Guard pause active (%ds)", symbol, remain), EnableDebugLogs);
      return;
   }

   // ตรวจสอบการหยุดฉุกเฉินจากการเปลี่ยนสภาวะตลาด
   // เช่น หากตรวจพบความผันผวนรุนแรงหรือตลาดเปลี่ยนทิศกะทันหัน
   if(IsRegimeExitPauseActive())
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "emergency_pause_active");
      LogDebug("Cycle skip [" + symbol + "]: emergency pause active", EnableDebugLogs);
      return;
   }

   // 1. ตรวจสอบความพร้อมของข้อมูล (Warmup Check)
   // ตรวจสอบว่ามีจำนวนแท่งเทียนย้อนหลังเพียงพอสำหรับการคำนวณอินดิเคเตอร์หรือไม่
   if(!IsDataReady(symbol, MainTF, REQUIRED_WARMUP_BARS))
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "data_not_ready");
      LogDebug("Cycle skip [" + symbol + "]: data not ready", EnableDebugLogs);
      return;
   }

   // 2. ดึง Snapshot ข้อมูลตลาดและคำนวณ Feature ต่างๆ
   MarketSnapshot snapshot;
   
   // ดึงข้อมูลราคาปัจจุบัน (Bid, Ask, Spread)
   if(!GetMarketSnapshot(symbol, snapshot))
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "snapshot_unavailable");
      LogDebug("Cycle skip [" + symbol + "]: market snapshot unavailable", EnableDebugLogs);
      return;
   }
   
   // ยืนยันการเลือกคู่เงินเข้าระบบ
   if(!SymbolSelect(symbol, true))
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "symbol_select_failed");
      LogDebug("Cycle skip [" + symbol + "]: SymbolSelect failed", EnableDebugLogs);
      return;
   }
   
   // คำนวณค่าอินดิเคเตอร์และข้อมูลเชิงสถิติ (ADX, RSI, EMA, ATR, Volume ฯลฯ)
   ulong __pt = GetMicrosecondCount();
   bool __feat_ok = ComputeFeatures(symbol, snapshot);
   g_prof_us[0] += GetMicrosecondCount() - __pt;
   if(!__feat_ok)
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "feature_failed");
      LogDebug("Cycle skip [" + symbol + "]: feature computation failed", EnableDebugLogs);
      return;
   }

   // Build SMC Context
   // รวบรวมและวิเคราะห์ข้อมูลตามแนวคิด Smart Money Concepts (โครงสร้างตลาด, BOS, CHoCH)
   SMCContext ctx;
   __pt = GetMicrosecondCount();
   BuildSMCContext(symbol, snapshot, ctx);
   g_prof_us[1] += GetMicrosecondCount() - __pt;
   
   // คำนวณความไม่สมดุลของปริมาณคำสั่งซื้อขายใน Order Book (Depth of Market)
   __pt = GetMicrosecondCount();
   ComputeDOMImbalance(symbol, snapshot);
   g_prof_us[2] += GetMicrosecondCount() - __pt;

   // Update Risk Mode
   // อัปเดตสถานะความเสี่ยงของพอร์ต (Normal, Defensive, หรือ Recovery) ตาม Drawdown ปัจจุบัน
   UpdateRiskMode();

   // 3. วิเคราะห์สภาวะตลาด (Regime Detection)
   // จำแนกสภาวะตลาด (เช่น เทรนด์ขาขึ้น, ขาลง, ไซด์เวย์, ตลาดผันผวน)
   __pt = GetMicrosecondCount();
   ENUM_REGIME_TYPE regime = DetectRegime(snapshot);
   g_prof_us[3] += GetMicrosecondCount() - __pt;

   // Phase 23 P0-5: Always manage existing positions first
   // จัดการออเดอร์ที่เปิดอยู่ก่อนเสมอ (เช่น เลื่อน SL, แบ่งปิดกำไร, หรือปิดออเดอร์ที่สัญญาณเสีย)
   __pt = GetMicrosecondCount();
   ManagePositions(snapshot, regime);
   g_prof_us[4] += GetMicrosecondCount() - __pt;
   g_manage_positions_called++;

   // Early return if Volatility Shock pause is active
   // หากระบบตรวจพบภาวะช็อกของตลาด (Volatility Shock) จะหยุดการเปิดออเดอร์ใหม่
   string shock_key = "KNARES_Vol_Shock_Until";
   if(GlobalVariableCheck(shock_key))
   {
      datetime until = (datetime)GlobalVariableGet(shock_key);
      if(TimeCurrent() < until)
      {
         if(is_new_bar) LogNoTradeReasonPerBar(symbol, MainTF, "block_portfolio_vol_shock_pause");
         g_pipeline_final = "BLOCK_VOL";
         return;
      }
      else GlobalVariableDel(shock_key);
   }

   // --- Aggregate Profit Exit ---
   // ตรวจสอบและปิดออเดอร์ทั้งหมดหากกำไรรวมถึงเป้าหมายที่กำหนด (ในหน่วย R)
   if(EnableAggregateProfitExit)
   {
      double total_pnl_r = 0;
      int pos_count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double risk_dist = MathAbs(open_price - sl);
            if(risk_dist > 0)
            {
               double profit_dist = (type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price);
               total_pnl_r += (profit_dist / risk_dist);
            }
            pos_count++;
         }
      }
      // หากจำนวนออเดอร์และกำไรรวมถึงเกณฑ์ ให้ปิดทั้งหมดทันที
      if(pos_count > 1 && total_pnl_r >= AggregateProfitExitR)
      {
         LogInfo(StringFormat("Aggregate Profit Exit triggered for %s: pos_count=%d total_r=%.2f", symbol, pos_count, total_pnl_r));
         for(int j = PositionsTotal() - 1; j >= 0; j--)
         {
            ulong ticket = PositionGetTicket(j);
            if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
               pos_manager.PositionClose(ticket);
         }
         return;
      }
   }

   // --- Smart Recovery ---
   // ระบบแก้พอร์ตอัจฉริยะ: หากออเดอร์เก่าขาดทุนถึงระดับที่กำหนด จะพยายามหาจังหวะสวนเทรนด์ (Reversal) ด้วยความมั่นใจสูงเพื่อกู้คืน
   if(EnableSmartRecovery)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_sl = PositionGetDouble(POSITION_SL);
            double pos_lots = PositionGetDouble(POSITION_VOLUME);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double risk_dist = MathAbs(pos_open - pos_sl);
            
            if(risk_dist > 0)
            {
               // คำนวณ PnL ในหน่วยความเสี่ยง (R)
               double current_pnl_r = ((type == POSITION_TYPE_BUY ? snapshot.bid : snapshot.ask) - pos_open) / risk_dist;
               if(type == POSITION_TYPE_SELL) current_pnl_r = (pos_open - (type == POSITION_TYPE_BUY ? snapshot.bid : snapshot.ask)) / risk_dist;
               
               // หากขาดทุนถึงเกณฑ์ที่เริ่มกู้คืนได้
               if(current_pnl_r <= -RecoveryDrawdownR)
               {
                  int total_pos = 0;
                  for(int k=0; k<PositionsTotal(); k++) {
                     if(PositionSelectByTicket(PositionGetTicket(k)) && PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
                        total_pos++;
                  }
                  
                  // ถอนจำนวนไม้แก้ที่เปิดอยู่ยังไม่เกินขีดจำกัด
                  if(total_pos <= RecoveryMaxAttempts)
                  {
                     SignalPack recovery_signal;
                     // ตรวจสอบสัญญาณเทรนด์สำหรับการกู้คืน
                     if(BuildTrendSignal(snapshot, regime, recovery_signal))
                     {
                        // หากมีสัญญาณตรงข้ามที่ความมั่นใจสูงพอ ให้เปิดออเดอร์สวน
                        if(recovery_signal.direction == (type == POSITION_TYPE_BUY ? SIGNAL_BUY : SIGNAL_SELL) && recovery_signal.confidence >= RecoveryMinConfidence)
                        {
                           LogInfo(StringFormat("SMART RECOVERY: High Confidence reversal suspected for %s (Drawdown %.2fR, Confidence %.2f)", symbol, current_pnl_r, recovery_signal.confidence));
                           recovery_signal.stop_price = pos_sl;
                           RiskDecision rec_risk;
                           if(EvaluateRisk(recovery_signal, snapshot, rec_risk))
                           {
                              if(SendOrderWithRetry(recovery_signal, rec_risk))
                              {
                                 ReserveGlobalRisk(rec_risk.risk_money);
                                 StorePendingRisk(symbol, rec_risk.risk_money);
                                 UpdateEntryCooldown(symbol);
                                 return; // ส่งคำสั่งสำเร็จ จบรอบนี้
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }

   // ตรวจสอบสถานะและจำนวนออเดอร์ปัจจุบันในคู่เงินนี้
   int current_pos_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
         current_pos_count++;
   }
   
   // หากปิดฟีเจอร์การเปิดไม้เพิ่ม (ScaleIn) และมีออเดอร์อยู่แล้ว จะข้ามการพิจารณาออเดอร์ใหม่
   if(!EnableScaleIn && current_pos_count > 0)
   {
      if(is_new_bar) {
         LogNoTradeReasonPerBar(symbol, MainTF, "block_scale_in(disabled_has_pos)");
         LogDebug(StringFormat("Cycle skip [%s]: Scale-in disabled and position exists.", symbol), EnableDebugLogs);
      }
      return;
   }

   // ตรวจสอบแท่งใหม่อีกครั้งเพื่อความแม่นยำ
   is_new_bar = IsNewBar(symbol, MainTF);

   // --- Apex Analytics ---
   // รันการประเมิน Statistical Arbitrage เชิงลึก
   __pt = GetMicrosecondCount();
   RunStatArbApexCycle(symbol, is_new_bar, snapshot);
   g_prof_us[5] += GetMicrosecondCount() - __pt;
   __pt = GetMicrosecondCount();
   bool __hmm_ok = EvaluateHMMApexRisk(symbol, snapshot);
   g_prof_us[6] += GetMicrosecondCount() - __pt;
   if(!__hmm_ok) return; // หยุดถ้าระบบ Apex บอกว่าเสี่ยงสูง

   // 3. วิเคราะห์สภาวะตลาด (Regime) เชิงลึกเมื่อเริ่มแท่งใหม่
   if(is_new_bar && EnableRegimeDiagnostics)
   {
      double range_width = snapshot.donchian_high - snapshot.donchian_low;
      LogInfo(StringFormat(
         "RegimeDiag[%s]: regime=%s adx=%.2f ema_fast=%.5f ema_slow=%.5f ema_slope=%.5f z=%.2f atr=%.5f atr_pct=%.2f spread=%.1f range=%.5f",
         symbol, EnumToString(regime),
         snapshot.adx, snapshot.ema_fast, snapshot.ema_slow, snapshot.ema_slope,
         snapshot.zscore, snapshot.atr, snapshot.atr_percentile, snapshot.spread_points, range_width));
   }

   // 4. จัดการออเดอร์เก่า (เรียกซ้ำเผื่อมีความเปลี่ยนแปลงหลังอัปเดตสภาวะตลาด)
   __pt = GetMicrosecondCount();
   ManagePositions(snapshot, regime);
   g_prof_us[7] += GetMicrosecondCount() - __pt;

   // 5. ตรวจสอบ News Filter และ Kill Switch
   // เช็คว่ามีข่าวแรงหรือไม่ และเช็ค Drawdown ของพอร์ต
   bool news_active = IsNewsActive(symbol);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   bool kill_switch = (balance > 0 && (1.0 - (equity / balance)) * 100.0 >= EquityKillSwitchPct * 100.0);

   // หาก Equity หายไปจนถึงระดับที่กำหนด จะสั่งปิดทุกไม้ทันที (Hard Close)
   if(kill_switch)
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "kill_switch");
      LogError("EQUITY KILL SWITCH ACTIVE. Initiating Hard Close...");
      HardCloseAllPositions();
      return; 
   }

   // 6. อัปเดต Dashboard
   // แสดงผลสภาวะตลาดและสถานะการกรองบนหน้าจอหลัก
   if(symbol == _Symbol) UpdateDashboard(regime, news_active, kill_switch);

   // 7. ตรวจสอบความปลอดภัยเบื้องต้น (Execution Safe)
   // ตรวจสอบค่า Spread ว่ากว้างเกินเกณฑ์รับได้หรือไม่
   bool execution_safe = IsExecutionSafe(symbol);
   if(!execution_safe || kill_switch || news_active)
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "execution_or_news_block");
      LogDebug("Cycle skip [" + symbol + "]: execution/news/kill-switch block", EnableDebugLogs);
      return;
   }

   // 0. Recovery Exit (Global Profit Exit)
   // ตรวจสอบว่ากำไรรวมทั้งพอร์ตถึงเป้าหมายหรือยัง หากถึงเป้าแล้วให้ปิดทุกคู่เงิน
   if(GlobalProfitExitUSD > 0 && AccountInfoDouble(ACCOUNT_PROFIT) >= GlobalProfitExitUSD)
   {
      LogInfo(StringFormat("Recovery Exit Triggered: Total Profit %.2f >= Target %.2f. Closing all positions.", 
                           AccountInfoDouble(ACCOUNT_PROFIT), GlobalProfitExitUSD));
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
               pos_manager.PositionClose(ticket);
         }
      }
      return;
   }

   // --- 8. ดำเนินการ Pipeline (Signal Analysis & Selection) ---
   // ให้ PipelineController ประเมินสัญญาณจากทุก Engine และเลือกสัญญาณที่ดีที่สุด
   SignalPack final_signal;
   __pt = GetMicrosecondCount();
   bool __pipe_ok = ExecutePipeline(symbol, snapshot, regime, ctx, final_signal);
   g_prof_us[8] += GetMicrosecondCount() - __pt;
   if(!__pipe_ok) return;

   // --- 9. ตัวกรองการเปิดออเดอร์ (Execution Gate) ---
   // กรองตามการตั้งค่า เช่น อนุญาตเทรดเฉพาะตอนเปิดแท่งเทียน, หรือติด Cooldown
   if(EnableOnlyNewBarEntry && !is_new_bar) {
      LogNoTradeReasonPerBar(symbol, MainTF, "waiting_new_bar");
      g_pipeline_final = "WAIT_BAR"; return;
   }
   if(!EnableOnlyNewBarEntry && !IsEntryCooldownOk(symbol, 0)) {
      LogNoTradeReasonPerBar(symbol, MainTF, "entry_cooldown");
      g_pipeline_final = "COOLDOWN"; return;
   }
   // ห้ามเข้าเทรดหากสภาวะตลาดเสี่ยงสูงมาก (RISK_OFF)
   if(regime == REGIME_RISK_OFF) {
     LogNoTradeReasonPerBar(symbol, MainTF, "block_regime(risk_off)");
     g_pipeline_final = "BLOCK_REGIME"; return;
   }

   // --- 9B. ตัวกรอง News Sentiment (ถ้าเปิดใช้งาน EnableSentimentFilter) ---
   // ถ้า sentiment ข่าวสวนทางกับทิศทางสัญญาณแรงพอ ให้ข้ามรอบนี้ (skip); ปิดค่า default ไว้ = เทรดตามปกติ
   if(IsSentimentConflicting(final_signal.direction)) {
      LogNoTradeReasonPerBar(symbol, MainTF, "sentiment_conflict");
      g_pipeline_final = "BLOCK_SENTIMENT"; return;
   }

   // --- 10. ส่งคำสั่งเทรด (Trade Execution) ---
   // บังคับจุด Stop Loss ขั้นต่ำตามการตั้งค่าแต่ละ Engine
   ApplyEngineStopFloor(final_signal);

   // ประเมินความเสี่ยงและคำนวณขนาด Lot
   RiskDecision risk;
   if(!EvaluateRisk(final_signal, snapshot, risk)) {
      LogNoTradeReasonPerBar(symbol, MainTF, "block_risk");
      g_pipeline_final = "BLOCK_RISK"; return;
   }
   
   // ปรับความเสี่ยงย่อยตาม Regime, Drawdown, และจังหวะฟื้นฟู (Risk Restoring)
   double risk_mult = GetRegimeRiskMultiplier(final_signal.confidence);
   risk_mult *= GetDrawdownRiskMultiplier();
   risk_mult *= GetRiskRestoreMultiplier();
   
   // ลดความเสี่ยงสำหรับสัญญาณ Rescue แบบประนีประนอม (Soft Rescue)
   if(StringFind(final_signal.reason, "(SOFT)") >= 0)
   {
      risk_mult *= RescueSoftRiskFactor;
      LogInfo(StringFormat("PipelineRescue[%s]: Applying Soft Quality risk factor %.2f", symbol, RescueSoftRiskFactor));
   }
   
   // ตรวจสอบสถิติย้อนหลังของ Engine นั้นๆ ว่าผลงานดรอปลงหรือไม่ (Auto Pause/Reduce)
   double staged_mult = 1.0;
   int e_idx = EngineIndexByName(final_signal.engine_name);
   string staged_pause_reason = "";
   if(e_idx >= 0 && EnableEngineAutoPause && engine_metrics[e_idx].trades >= RollingPFWindow)
   {
      double r_pf = engine_metrics[e_idx].rolling_pf;
      if(r_pf < 0.90) { staged_mult = 0.50; if(is_new_bar) LogWarning(StringFormat("AutoPause Stage 1 [%s]: Rolling PF (%.2f) < 0.90. Reducing lot size by 50%%.", final_signal.engine_name, r_pf)); }
      // บล็อกเฉพาะการเพิ่มไม้ (scale-in) เมื่อมีออเดอร์ค้างอยู่ ถ้าบล็อกการเข้าไม้แรกด้วย EA จะไม่มีเทรดใหม่มาฟื้น Rolling PF อีกเลย (deadlock)
      if(r_pf < 0.75 && current_pos_count > 0) { pass_scale_in = false; staged_pause_reason = "staged_pause"; if(is_new_bar) LogWarning(StringFormat("AutoPause Stage 2 [%s]: Rolling PF (%.2f) < 0.75. Blocking scale-in.", final_signal.engine_name, r_pf)); }
   }
   
   // ปรับปรุงขนาด Lot สุดท้ายหลังหักลบตัวคูณต่างๆ
   risk.lots = NormalizeLot(symbol, risk.lots * risk_mult * staged_mult);
   risk.risk_money *= (risk_mult * staged_mult);
   
   // หาก Lot ที่คำนวณได้เป็น 0 หรือติดลบ ให้ยกเลิกการเข้าเทรด
   if(risk.lots <= 0) {
      LogNoTradeReasonPerBar(symbol, MainTF, "block_risk_mult_low");
      g_pipeline_final = "BLOCK_RISK"; return;
   }
   
   g_last_risk_money = risk.risk_money;

   // การควบคุมการสะสมไม้ (Scale-in Check)
   // จะเปิดไม้เพิ่มได้เมื่อไม้เดิมมีกำไรระดับหนึ่งเท่านั้น
   bool has_profitable_pos = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol) {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double risk_dist = MathAbs(open_price - sl);
         if(risk_dist > 0) {
            double profit_dist = (type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price);
            if(profit_dist >= risk_dist * ScaleInMinProfitR) has_profitable_pos = true;
         }
      }
   }
   
   // พิจารณาเงื่อนไขการอนุญาตให้ Scale-in
   string scale_in_reason = "";
   if(current_pos_count > 0) {
      if(!has_profitable_pos && final_signal.score < ScaleInSuperSignalScore) { scale_in_reason = "no_profit"; pass_scale_in = false; }
      else if(final_signal.score < ScaleInMinScore) { scale_in_reason = "low_conviction"; pass_scale_in = false; }
      else if(staged_pause_reason != "") { scale_in_reason = staged_pause_reason; pass_scale_in = false; }
   }
   
   if(!pass_scale_in && current_pos_count > 0) LogNoTradeReasonPerBar(symbol, MainTF, "block_scale_in(" + scale_in_reason + ")");

   // ทดสอบเพดานความเสี่ยงรวม (Limit Gate) เช่น Exposure, Portfolio Heat, Price Clustering
   LimitGateResult limit_res;
   EvaluateLimitGate(symbol, final_signal.direction, risk.lots, risk.risk_money, snapshot, limit_res);
   
   // ข้อยกเว้นพิเศษ (Ultimate Bypass): หากความมั่นใจสูงมากๆ จะยอมให้พอร์ตรับความเสี่ยง(Heat)เกินกำหนดเล็กน้อยได้
   if(final_signal.confidence > 0.95 && limit_res.portfolio_pass && pass_scale_in && limit_res.exposure_cap_pass && limit_res.price_clustering_pass && limit_res.max_positions_pass)
   {
      limit_res.heat_cap_pass = true;
      LogInfo(StringFormat("ULTIMATE BYPASS: Portfolio Heat check ignored due to ultra-high confidence (%.2f)", final_signal.confidence));
   }

   // ตรวจสอบผลรวมของ Limit Gate ทั้งหมดว่าผ่านหรือไม่
   if(limit_res.portfolio_pass && pass_scale_in && limit_res.exposure_cap_pass && limit_res.price_clustering_pass && limit_res.max_positions_pass && limit_res.heat_cap_pass)
   {
      LogInfo(StringFormat("AttemptEntry[%s]: dir=%d score=%.2f conf=%.2f lots=%.2f regime=%s",
                           symbol, (int)final_signal.direction, final_signal.score, final_signal.confidence,
                           risk.lots, EnumToString(regime)));
      
      // ส่งคำสั่งพร้อมระบบลองใหม่หากผิดพลาดหน้างานเล็กน้อย
      if(SendOrderWithRetry(final_signal, risk)) {
         if(StringFind(final_signal.reason, "PIPELINE_RESCUE") >= 0)
            LogInfo(StringFormat("PipelineRescueOrderSent[%s]: dir=%s score=%.2f conf=%.2f quality=%.2f engine=%s",
                                 symbol, (final_signal.direction == SIGNAL_BUY ? "BUY" : "SELL"),
                                 final_signal.score, final_signal.confidence, ctx.buy_quality, final_signal.engine_name));
         
         g_pipeline_final = "SENT"; 
         // ทำการจองความเสี่ยงล่วงหน้าและอัปเดตเวลาเข้าเพื่อเข้าคูลดาวน์
         ReserveGlobalRisk(risk.risk_money);
         StorePendingRisk(symbol, risk.risk_money);
         UpdateEntryCooldown(symbol);
      } else {
         LogNoTradeReasonPerBar(symbol, MainTF, "reject_execution");
         g_pipeline_final = "REJ_EXEC";
      }
   } else {
      // ระบุเหตุผลว่าบล็อกในขั้นตอนใดเพื่อเก็บ Log
      string limit_reason = "block_limit";
      if(!limit_res.portfolio_pass) limit_reason = "block_portfolio_" + limit_res.exp_fail_reason; 
      else if(!pass_scale_in) limit_reason = "block_scale_in(" + scale_in_reason + ")";
      else if(!limit_res.max_positions_pass) limit_reason = "block_max_positions";
      else if(!limit_res.price_clustering_pass) limit_reason = "block_price_clustering";
      else if(!limit_res.exposure_cap_pass) limit_reason = "block_exposure_cap";
      else if(!limit_res.heat_cap_pass) limit_reason = "block_heat_cap";
      
      LogNoTradeReasonPerBar(symbol, MainTF, limit_reason);
      g_pipeline_final = "BLOCK_LIMIT";
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันเริ่มต้นทำงานของ Expert Advisor (Initialization)            |
//| ทำงานครั้งเดียวเมื่อลาก EA ลงกราฟ ใช้สำหรับตรวจสอบและเตรียมระบบ       |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo("Initializing KNARES MT5 (Knowledge-Navigator)...");
   LoadSymbolParameters(); // โหลดการตั้งค่าพารามิเตอร์ของคู่เงิน
   InitEngineMetrics(); // เริ่มต้นการติดตาม KPI ของแต่ละ Engine (กลยุทธ์)
   DiagnosticResults diag;
   // ตรวจสอบความถูกต้องเบื้องต้น (PreFlight Check) เช่น พารามิเตอร์ขัดแย้งกันหรือไม่
   if(!RunPreFlightCheck(diag))
   {
      LogError("Startup Blocked: " + diag.error_msg);
      return INIT_FAILED;
   }
   FetchRealNews(); // โหลดข้อมูลข่าวเศรษฐกิจเพื่อกรองข่าว
   g_test_force_once_consumed = false;
   g_last_decision_trace_log = TimeCurrent();
   ResetSkipReasons();
   if(!ValidateInputs()) return INIT_FAILED; // ตรวจสอบความถูกต้องของการตั้งค่า (Input)
   
   // ตรวจสอบโหมดการทำงานของการปิดทำกำไรบางส่วน (Partial Close Runtime Diagnostic)
   // ตรวจสอบว่าลอตขั้นต่ำของโบรกเกอร์สัมพันธ์กับการตั้งค่าการปิดกำไรบางส่วนหรือไม่
   double broker_min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   bool partial_possible = (FixedLotSize * PartialCloseSizePct) >= MathMax(PartialCloseMinLots, broker_min_lot);
   LogInfo(StringFormat("PartialCloseRuntimeMode: actual_partial=%s fixedLot=%.2f minLot=%.2f pct=%.2f mode=%s",
                        partial_possible ? "TRUE" : "FALSE", FixedLotSize, broker_min_lot, PartialCloseSizePct,
                        partial_possible ? "REAL_CLOSE" : "FALLBACK_ONLY"));
   
   LogRuntimeConfig(); // แสดงผลการตั้งค่าหลักใน Log
   LogInfo(StringFormat("Liveness Check: EarlyInvMinLossR=%.2f TrailTriggerR=%.2f TrendStopFloor=%d",
                        TrendEarlyInvMinLossR, TrailingProfitTriggerR, TrendMinStopDistancePoints));
   
   // เริ่มต้นโมดูลต่างๆ
   InitializeSymbolList();
   NormalizeSymbolList();
   
   if(ArraySize(symbol_list) == 0)
   {
      LogError("No valid symbols after normalization.");
      return INIT_FAILED;
   }
   if(!MarketDataInit()) return INIT_FAILED;      // เริ่มต้นระบบข้อมูลตลาด
   if(!FeatureEngineInit()) return INIT_FAILED;   // เริ่มต้นระบบอินดิเคเตอร์
   if(!OnnxOverlayInit()) return INIT_FAILED;     // เริ่มต้นระบบ AI (ONNX)
   if(!NeuralBridgeInit()) return INIT_FAILED;    // เริ่มต้นระบบ Neural Network ภายนอก
   if(!NewsFilterInit()) return INIT_FAILED;      // เริ่มต้นระบบกรองข่าว
   
   // โหลดแบบจำลองพยากรณ์สภาวะตลาดขั้นสูง (Apex HMM)
   LoadApexHMM();

   MarketDepthInit(_Symbol); // เริ่มอ่าน Depth of Market (Order Book)
   if(!ExecutionInit()) return INIT_FAILED; // เริ่มต้นระบบส่งคำสั่งเทรด
   if(!AcquireSingleInstanceGuard()) return INIT_FAILED; // ป้องกันการเปิดหน้าต่างกราฟซ้ำซ้อนกัน
   ResetGlobalRiskTracker(); // ล้างประวัติการจองความเสี่ยง
   
   // ควบคุมการเขียน Log ในตอน Init ไม่ให้รกเกินไปถ้ารีสตาร์ทถี่
   bool verbose_init_log = (TimeCurrent() - g_last_init_log >= 30);
   g_last_init_log = TimeCurrent();
   if(verbose_init_log)
   {
      LogInfo(StringFormat("BuildStamp=%s date=%s mqlbuild=%d",
                           KNARES_BUILD_TAG, __DATE__, __MQLBUILD__));
      LogInfo(StringFormat("Config Confirm: EnableTestForceEntry=%s DisableIcebergTemporarily=%s TradeOnlyChartSymbol=%s MinScore=%.2f MinConf=%.2f HTFAlign=%s MaxSpreadXAU=%.1f RegimeConfirmBars=%d RegimeCooldown=%ds RegimeLock=%ds PauseThreshold=%d/%ds PauseDuration=%ds MainTF=%d RiskPerTradePct=%.6f",
                           EnableTestForceEntry ? "true" : "false",
                           DisableIcebergTemporarily ? "true" : "false",
                           TradeOnlyChartSymbol ? "true" : "false",
                           MinEntryScore, MinEntryConfidence, EnforceHTFAlignment ? "true" : "false", MaxSpreadPointsXAU,
                           RegimeExitConfirmBars, RegimeExitEntryCooldownSec,
                           RegimeExitSymbolLockSec, RegimeExitStormThreshold, RegimeExitStormWindowSec, RegimeExitStormPauseSec,
                           (int)MainTF, RiskPerTradePct));
      LogInfo(StringFormat("PerformanceMaxSafe=%s AutoGuard=%s RejectStreakLimit=%d PauseSec=%d KpiLogIntervalSec=%d MaxLotsXAU=%.2f MinStopPoints=%d UnknownBypass(ADX>=%.1f ATR>=%.2f Z_BO>=%.2f Z_MR>=%.2f)",
                           EnablePerformanceMaxSafe ? "true" : "false",
                           EnableAutoGuard ? "true" : "false",
                           AutoGuardRejectStreak, AutoGuardPauseSec, KpiLogIntervalSec,
                           MaxLotsPerTradeXAU, MinStopDistancePoints,
                           UnknownRegimeMinADX, UnknownRegimeMinATR,
                           UnknownBreakoutMinAbsZ, UnknownMeanRevMinAbsZ));
      LogInfo(StringFormat("DecisionTrace=%s interval=%ds DOMSoftVeto=%s severe=%.2f persistentBars=%d SingleInstance=%s ExposureCap(FX=%.1f,XAU=%.1f)",
                           EnableDecisionTrace ? "true" : "false",
                           DecisionTraceIntervalSec,
                           EnableDOMSoftVeto ? "true" : "false",
                           DOMVetoSevereThreshold, DOMVetoPersistentBars,
                           EnableSingleInstanceGuard ? "true" : "false",
                           ExposureCapEquityMultipleFX, ExposureCapEquityMultipleXAU));
   }
   else
   {
      LogInfo("Config Confirm (throttled): re-init detected within 30s, using previous profile.");
   }
   
   JournalInit(); // เริ่มต้นระบบจดบันทึกประวัติการเทรด
   EventSetTimer(5); // ตั้งเวลาให้ OnTimer() ทำงานทุกๆ 5 วินาที
   LogInfo("KNARES MT5 initialization successful.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ฟังก์ชันที่ทำงานเมื่อปิด Expert Advisor (Deinitialization)           |
//| ใช้เคลียร์หน่วยความจำและตัวแปรต่างๆ คืนสู่ระบบ                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ตรวจสอบการรีสตาร์ทซ้ำๆ เพื่อไม่ให้เกิด Log มากเกินไป
   bool repeat_deinit = (reason == g_last_deinit_reason && (TimeCurrent() - g_last_deinit_log) < 20);
   g_last_deinit_reason = reason;
   g_last_deinit_log = TimeCurrent();
   if(repeat_deinit)
      LogInfo(StringFormat("Deinit throttled: reason=%d chart=%I64d symbol=%s tf=%d", reason, ChartID(), _Symbol, (int)Period()));
   else
      LogInfo(StringFormat("Deinit reason=%d chart=%I64d symbol=%s tf=%d", reason, ChartID(), _Symbol, (int)Period()));
   
   // ถ้าอยู่ในโหมด Tester ให้สรุปผลลัพธ์ประสิทธิภาพเชิงลึกเพื่อการวิเคราะห์
   if(MQLInfoInteger(MQL_TESTER))
   {
      {
         string ps = "PROFILE(ms total):";
         for(int pi = 0; pi < 12; pi++) ps += StringFormat(" %s=%.0f", g_prof_names[pi], g_prof_us[pi] / 1000.0);
         LogInfo(ps);
      }
      LogLotAwareSummary();
      LogPipelineRescueSummary();
      LogDailyLossClusterSummary();
      LogHardSLSummary();
   }

   GenerateWeeklySummary(); // สร้างรายงานสรุปประจำสัปดาห์
   MarketDepthDeinit(_Symbol);
   EventKillTimer(); // ปิดการใช้งานฟังก์ชัน Timer
   ClearDashboard(); // ลบหน้าต่าง Dashboard ออกจากหน้าจอ
   
   // คืนทรัพยากรทุกโมดูล
   NeuralBridgeDeinit();
   OnnxOverlayDeinit();
   FeatureEngineDeinit();
   MarketDataDeinit();
   ReleaseSingleInstanceGuard(); // ปลดล็อกการเช็คหน้าต่าง
   LogInfo("KNARES MT5 deinitialized.");
}

//+------------------------------------------------------------------+
//| ฟังก์ชันประมวลผลเหตุการณ์ใน Order Book (Market Depth BookEvent)      |
//| ทำงานเมื่อข้อมูลของใบสั่งซื้อขายแบบ Depth มีการเปลี่ยนแปลง              |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
{
   HandleBookEvent(symbol); // ดึงลอจิกจัดการ DOM
}

//+------------------------------------------------------------------+
//| ฟังก์ชันที่ทำงานในทุกๆ Tick ของราคา (Expert tick function)          |
//| เป็นจังหวะที่รับรู้การเคลื่อนไหวของตลาดและสั่งประมวลผลระบบ                |
//+------------------------------------------------------------------+
void OnTick()
{
   ulong __ot = GetMicrosecondCount();
   OnTickImpl();
   g_prof_us[9] += GetMicrosecondCount() - __ot;
}
void OnTickImpl()
{
   // ตรวจสอบว่าบัญชีอนุญาตให้เทรดแบบ Expert หรือไม่
   // หากไม่อนุญาตจะหยุดการทำงานเพื่อไม่ให้เกิดข้อผิดพลาด
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      if(TimeCurrent() - g_last_autotrade_disabled_log >= 30)
      {
         g_last_autotrade_disabled_log = TimeCurrent();
         LogWarning("OnTick: AutoTrading disabled by terminal/account. Trading cycle paused.");
      }
      return;
   }

   // รายงานสถานะชีพจรการทำงานของโปรแกรม (Heartbeat) แบบ Debug
   if(EnableDebugLogs && TimeCurrent() - g_last_heartbeat >= 30)
   {
      g_last_heartbeat = TimeCurrent();
      LogInfo(StringFormat("OnTick heartbeat: symbol=%s ticks processing, active_algo_orders=%d", _Symbol, ArraySize(g_active_algo_orders)));
   }

   ProcessAlgoOrders(); // จัดการคำสั่งเทรดที่รอดำเนินการแบบกระจายส่ง (เช่น Iceberg)
   
   // โหมดทำงานเฉพาะคู่เงินหน้ากราฟเดียว เพื่อลดการกินทรัพยากร
   if(TradeOnlyChartSymbol)
   {
      RunTradingCycle(_Symbol);
      return;
   }

   // โหมดวนลูปทำงานในทุก Symbol ที่กำหนดไว้ในรายการ (Multi-Symbol mode)
   for(int i = 0; i < ArraySize(symbol_list); i++)
   {
      string sym = symbol_list[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      RunTradingCycle(sym); // สั่งเดินกระบวนการตัดสินใจ
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันที่ทำงานตามคาบเวลา (Timer function)                       |
//| ทำงานตามที่ตั้งเวลาไว้ (ตอนนี้ตั้งเป็นทุก 5 วินาที) สำหรับอัปเดตงานรอง     |
//+------------------------------------------------------------------+
void OnTimer()
{
   ulong __tt = GetMicrosecondCount();
   OnTimerImpl();
   g_prof_us[11] += GetMicrosecondCount() - __tt;
}
void OnTimerImpl()
{
   // ใน Strategy Tester Timer ถูกยิงทุก 5 วินาทีจำลอง (~60 ครั้งต่อแท่ง M5) ทำให้ backtest ช้ามาก
   // จึงจำกัดให้ทำงานไม่ถี่กว่า 1 ครั้งต่อ 60 วินาทีจำลอง และข้าม Heartbeat/Dashboard ถ้าไม่ใช่ Visual Mode
   const bool tester_mode = (bool)MQLInfoInteger(MQL_TESTER);
   const bool tester_fast = (tester_mode && !MQLInfoInteger(MQL_VISUAL_MODE));
   if(tester_mode)
   {
      static datetime s_last_timer = 0;
      if(TimeCurrent() - s_last_timer < 60) return;
      s_last_timer = TimeCurrent();
   }
   // ระบบตรวจสอบ Heartbeat เพื่อยืนยันว่าโปรแกรมยังทำงานอยู่ (Local Diagnostic)
   // บันทึกสถานะการมีชีวิตลงในไฟล์
   int heartbeat_h = tester_mode ? INVALID_HANDLE : FileOpen("KNARES_Heartbeat.txt", FILE_WRITE | FILE_TXT);
   if(heartbeat_h != INVALID_HANDLE)
   {
      FileWrite(heartbeat_h, "Alive at: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      FileClose(heartbeat_h);
   }

   RefreshSingleInstanceHeartbeat(); // ส่งสัญญาณบอกว่าหน้าต่างนี้ยังทำงานอยู่ ไม่ต้องเรียกหน้าต่างซ้อน

   // ระบบ Auto-Guard: หยุดเทรดชั่วคราวหากมีการปฏิเสธคำสั่งเทรดต่อเนื่อง
   // ป้องกัน EA ส่งคำสั่งรัวๆ เข้าโบรกเกอร์จนอาจจะโดนแบน
   if(EnableAutoGuard && AutoGuardRejectStreak > 0 && g_autoguard_pause_until <= TimeCurrent() &&
      GetExecutionRejectStreak() >= AutoGuardRejectStreak)
   {
      g_autoguard_pause_until = TimeCurrent() + AutoGuardPauseSec;
      LogWarning(StringFormat("Auto-Guard: reject streak reached (%d). Pausing new entries for %d sec. LastRetcode=%u",
                              GetExecutionRejectStreak(), AutoGuardPauseSec, GetExecutionLastRetcode()));
      ResetExecutionStats();
   }

   // บันทึก Performance KPI ตามช่วงเวลา
   if(KpiLogIntervalSec > 0 && (TimeCurrent() - g_last_kpi_log) >= KpiLogIntervalSec)
   {
      g_last_kpi_log = TimeCurrent();
      LogPerformanceKPI();
      LogEngineKPI();
   }

   // บันทึกสรุปการตัดสินใจ (Decision Trace Summary) เพื่อสืบย้อนลอจิกพฤติกรรมของ EA
   if(EnableDecisionTrace && DecisionTraceIntervalSec > 0 &&
      (TimeCurrent() - g_last_decision_trace_log) >= DecisionTraceIntervalSec)
   {
      g_last_decision_trace_log = TimeCurrent();
      LogDecisionTraceSummary();
   }

   RunHealthChecks(); // ตรวจสอบความสมบูรณ์ของระบบโดยรวม
   UpdateNewsStatus(_Symbol); // อัปเดตสถานะข่าวสารปัจจุบัน
   MonitorParameterUpdate(); // ตรวจสอบว่ามีการเปลี่ยนแปลงการตั้งค่าขณะโปรแกรมรันอยู่หรือไม่
   UpdateMetrics(_Symbol); // อัปเดตสถิติระบบและยอดการถือครอง
   if(!tester_fast) TriggerDashboardUpdate(); // บังคับอัปเดตหน้าจอทุกรอบ Timer (5 วินาที)
}

//+------------------------------------------------------------------+
//| ฟังก์ชันจัดการธุรกรรมการเทรด (TradeTransaction function)           |
//| ถูกกระตุ้นเมื่อมีการทำธุรกรรมใดๆ (เปิดออเดอร์, ปิดออเดอร์, เลื่อน SL ฯลฯ) |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   JournalTrade(trans, request, result); // บันทึกปูมการเทรดแบบละเอียดเพื่อทำบัญชีและประเมินผล
   
   // หากมีการทำธุรกรรมการเพิ่มดีล (Deal Addition) เช่น จับคู่ราคาเปิด/ปิดออเดอร์
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      HandleDealAddition(trans); // นำข้อมูลดีลไปประมวลผลต่อในโมดูลวิเคราะห์
   }
}
#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "HandleCache.mqh"

//+------------------------------------------------------------------+
//| Portfolio Governor - ตัวควบคุมความเสี่ยงในระดับพอร์ต (Portfolio Risk Management) |
//| ทำหน้าที่: ตรวจสอบความปลอดภัยระดับพอร์ต, จำกัดความเสี่ยงรวม, ป้องกันสภาวะวิกฤต |
//+------------------------------------------------------------------+

// ตัวแปรส่วนกลางสำหรับติดตามสถิติการควบคุมความเสี่ยง
int g_vol_shock_detections = 0;         // จำนวนครั้งที่ตรวจพบความผันผวนรุนแรงจนต้องหยุดพัก (Volatility Shock)
int g_daily_loss_cluster_triggers = 0;  // จำนวนครั้งที่ระบบป้องกันการขาดทุนสะสม (Daily Loss Cluster) ทำงาน

/**
 * บันทึกสรุปการทำงานของระบบ Daily Loss Cluster Guard
 * ใช้เพื่อตรวจสอบย้อนหลังว่าระบบได้ทำการบล็อกการเทรดที่เสี่ยงเกินไปกี่ครั้ง
 */
void LogDailyLossClusterSummary()
{
   LogInfo("--- DailyLossClusterSummary ---");
   LogInfo(StringFormat("TotalClusterTriggers: %d", g_daily_loss_cluster_triggers));
   LogInfo("--------------------------------");
}

/**
 * ตรวจสอบขีดจำกัดการเทรดรายวันและรายสัปดาห์ (Daily/Weekly Limits)
 * ป้องกันการเทรดเกินพอดีและการคืนกำไรให้ตลาดในช่วงที่สภาวะตลาดไม่เป็นใจ
 * 
 * @param fail_reason ข้อความระบุสาเหตุหากไม่ผ่านการตรวจสอบ (Output)
 * @return true หากผ่านเกณฑ์, false หากต้องหยุดเทรด
 */
bool IsDailyLimitOk(string &fail_reason)
{
   datetime now = TimeCurrent();
   fail_reason = "";
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   // --- 1. Weekly Profit Lock: ล็อกกำไรรายสัปดาห์ ---
   // หากทำกำไรถึงเป้าหมาย % ต่อสัปดาห์ที่ตั้งไว้ ระบบจะหยุดเทรดทันทีเพื่อรักษาผลกำไรนั้น
   if(EnableWeeklyLock)
   {
      double weekly_pnl = 0;
      // คำนวณวันเริ่มต้นของสัปดาห์ (เริ่มนับจากวันอาทิตย์/จันทร์)
      datetime start_of_week = now - ((dt.day_of_week > 0 ? dt.day_of_week : 7) * 86400); 
      HistorySelect(start_of_week, now);
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         {
            // รวมผลกำไร, ค่าคอมมิชชัน และค่า Swap ของออเดอร์ทั้งหมดในสัปดาห์นี้
            weekly_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            weekly_pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            weekly_pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         }
      }
      // เป้าหมายกำไรคิดเป็นเงินจริงตาม % ของยอดเงินฝาก
      double weekly_target = AccountInfoDouble(ACCOUNT_BALANCE) * (WeeklyProfitTargetPct / 100.0);
      if(weekly_pnl >= weekly_target && weekly_target > 0)
      {
         fail_reason = "weekly_profit_lock";
         LogInfo(StringFormat("Weekly Profit Lock: %.2f >= Target %.2f. Trading paused.", weekly_pnl, weekly_target));
         return false;
      }
   }

   // --- 2. Volatility Fatigue: ระบบพักการเทรดหลังเจอภาวะช็อก ---
   // ตรวจสอบค่า Global Variable ว่ามีการสั่งระงับการเทรดชั่วคราวจากส่วนอื่นของระบบหรือไม่
   string shock_key = "KNARES_Vol_Shock_Until";
   if(GlobalVariableCheck(shock_key))
   {
      datetime until = (datetime)GlobalVariableGet(shock_key);
      if(now < until)
      {
         fail_reason = "vol_shock_pause";
         LogInfo(StringFormat("Volatility Fatigue: Trading paused due to shock until %s", TimeToString(until)));
         return false;
      }
   }

   // --- 3. Daily Hard Loss: ตรวจสอบการขาดทุนสูงสุดที่ยอมรับได้ในหนึ่งวัน ---
   // หากยอดขาดทุนรวมของวันถึงจุดตัดระบบจะหยุดการเทรดทั้งหมดเพื่อป้องกันการล้างพอร์ต
   datetime today_start = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(today_start, now)) return true;

   double daily_pnl = 0;
   int total_deals = HistoryDealsTotal();

   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         {
            daily_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            daily_pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            daily_pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         }
      }
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double limit_money = balance * DailyHardLossPct;

   if(daily_pnl <= -limit_money)
   {
      fail_reason = "daily_hard_loss";
      LogError(StringFormat("Daily Hard Loss Reached: %.2f (Limit: %.2f)", daily_pnl, -limit_money));
      return false;
   }

   return true;
}

/**
 * ตรวจสอบความเสี่ยงรวมของคู่เงินและการกระจุกตัวของราคา (Exposure & Clustering Limits)
 * ทำหน้าที่ควบคุมไม่ให้ถือครองออเดอร์ในคู่เงินเดียวมากเกินไป และป้องกันการเปิดไม้ซ้อนกันในราคาใกล้ๆ กัน
 * 
 * @param symbol สัญลักษณ์ที่ต้องการตรวจสอบ
 * @param dir ทิศทางของสัญญาณ (Buy/Sell)
 * @param lots ขนาดลอตที่ต้องการเปิดเพิ่ม
 * @param fail_reason สาเหตุที่ไม่ผ่านเกณฑ์ (Output)
 * @return true หากผ่านเกณฑ์การตรวจสอบ
 */
bool CheckExposureLimits(string symbol, ENUM_SIGNAL_DIRECTION dir, double lots, string &fail_reason)
{
   double total_notional = 0; // มูลค่ารวมของออเดอร์ที่ถืออยู่ (Notional Value)
   int symbol_count = 0;      // จำนวนออเดอร์ปัจจุบันในคู่เงินนี้
   int total_positions = 0;   // จำนวนออเดอร์รวมทุกคู่เงินในพอร์ต
   fail_reason = "";

   // 1. คำนวณมูลค่ารวมของการถือครอง (Notional Exposure) ในปัจจุบัน
   // วนลูปตรวจสอบออเดอร์ที่เปิดค้างไว้ทั้งหมดในระบบ
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            string pos_symbol = PositionGetString(POSITION_SYMBOL);
            double pos_lots = PositionGetDouble(POSITION_VOLUME);
            double contract_size = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            double mid_price = 0.5 * (SymbolInfoDouble(pos_symbol, SYMBOL_BID) + SymbolInfoDouble(pos_symbol, SYMBOL_ASK));
            if(contract_size <= 0) contract_size = 100000.0;
            if(mid_price <= 0) mid_price = 1.0;
            // คำนวณมูลค่าการถือครองจริง: Lots * ขนาดสัญญา * ราคาปัจจุบัน
            total_notional += pos_lots * contract_size * mid_price; 
            total_positions++;
            
            if(pos_symbol == symbol) symbol_count++;
         }
      }
   }

   // 2. จำกัดจำนวนออเดอร์สูงสุดต่อหนึ่งคู่เงิน (Max Positions per Symbol)
   // ป้องกันการทุ่มเงินเทรดในคู่เงินเดียวจนเกินความเสี่ยงที่กำหนด
   int max_pos_per_symbol = MathMax(1, MaxPositionsPerSymbol);
   if(symbol_count >= max_pos_per_symbol) 
   {
      fail_reason = StringFormat("max_pos_reached(%d/%d)", symbol_count, max_pos_per_symbol);
      LogWarning(StringFormat("Exposure limit: Max positions for %s reached (%d/%d).",
                 symbol, symbol_count, max_pos_per_symbol));
      return false;
   }

   // --- 3. Price Clustering Guard: ป้องกันการกระจุกตัวของราคา ---
   // ระบบจะห้ามเปิดออเดอร์ใหม่หากราคาปัจจุบันอยู่ใกล้กับราคาที่เปิดออเดอร์เดิมไว้เกินไป
   double current_atr = 0;
   int atr_handle = HC_ATR(symbol, MainTF, ATRPeriod);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buf[];
      if(CopyBuffer(atr_handle, 0, 1, 1, atr_buf) > 0)
         current_atr = atr_buf[0];
   }

   // ใช้ค่า ATR เพื่อกำหนดระยะห่างขั้นต่ำที่เหมาะสมตามความผันผวนของตลาด
   if(current_atr > 0 && MinPositionDistanceATR > 0)
   {
      double min_dist = current_atr * MinPositionDistanceATR;
      double current_price = (dir == SIGNAL_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
            {
               double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
               // ตรวจสอบว่าราคาออเดอร์ใหม่ ห่างจากราคาออเดอร์เก่าพอหรือไม่
               if(MathAbs(current_price - pos_open) < min_dist)
               {
                  fail_reason = StringFormat("price_clustering(dist=%.1f pts < min=%.1f)", 
                                             MathAbs(current_price - pos_open) / SymbolInfoDouble(symbol, SYMBOL_POINT), 
                                             min_dist / SymbolInfoDouble(symbol, SYMBOL_POINT));
                  LogInfo(StringFormat("Price Clustering Guard: New entry too close to position open (%s)", fail_reason));
                  return false;
               }
            }
         }
      }
   }

   // 4. จำกัดมูลค่ารวมที่ถือครองต่อทุน (Exposure Cap)
   // บล็อกไม่ให้เปิดออเดอร์ใหม่หากมูลค่ารวมของพอร์ตจะเกินเพดานที่กำหนด (Leverage Limit)
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double mid_price = 0.5 * (SymbolInfoDouble(symbol, SYMBOL_BID) + SymbolInfoDouble(symbol, SYMBOL_ASK));
   if(contract_size <= 0) contract_size = 100000.0;
   if(mid_price <= 0) mid_price = 1.0;
   double new_notional = lots * contract_size * mid_price;

   bool is_xau = (StringFind(symbol, "XAU") >= 0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   // แยกเพดานความเสี่ยงระหว่างทองคำและคู่เงินปกติ
   double cap_mult = is_xau ? ExposureCapEquityMultipleXAU : ExposureCapEquityMultipleFX;
   
   // ระบบเพดานแบบไดนามิก: ยิ่งมีออเดอร์มาก ยิ่งค่อยๆ ขยับเพดานความเสี่ยงขึ้นเล็กน้อยตามกฎ Scaling
   if(EnableOpenMarketIncrementalCaps)
   {
      double add = MathMin(IncrementalExposureMaxAdd,
                           MathMax(0.0, IncrementalExposureStepPerPos) * (double)total_positions);
      cap_mult += MathMax(0.0, add);
   }
   double max_allowed_exposure = MathMax(1.0, eq * cap_mult);
   double projected = total_notional + new_notional;
   if(projected > max_allowed_exposure)
   {
      fail_reason = StringFormat("exposure_cap(proj=%.1f > max=%.1f)", projected, max_allowed_exposure);
      LogWarning(StringFormat("Exposure blocked [%s]: %s", symbol, fail_reason));
      return false;
   }

   return true;
}

/**
 * บันทึกเหตุการณ์การปิดออเดอร์จำนวนมาก (Regime Exit Storm Protection)
 * ทำหน้าที่ตรวจจับภาวะที่ออเดอร์โดนปิดพร้อมกันหลายไม้ (เช่น ตลาดเปลี่ยนทิศรุนแรง)
 * เพื่อสั่งให้ระบบหยุดพักการทำงานฉุกเฉิน
 */
void RecordRegimeExitEvent(string symbol)
{
   if(!EnableEmergencyGuards || RegimeExitStormPauseSec <= 0) return;

   datetime now = TimeCurrent();

   // บันทึกเวลาที่ปิดออเดอร์ล่าสุดของแต่ละสัญลักษณ์
   string last_exit_key = "KNARES_RegimeExit_Last_" + symbol;
   GlobalVariableSet(last_exit_key, (double)now);

   string win_start_key = "KNARES_RegimeExit_WindowStart";
   string win_count_key = "KNARES_RegimeExit_WindowCount";
   string pause_until_key = "KNARES_RegimeExit_PauseUntil";

   double win_start = GlobalVariableCheck(win_start_key) ? GlobalVariableGet(win_start_key) : (double)now;
   double win_count = GlobalVariableCheck(win_count_key) ? GlobalVariableGet(win_count_key) : 0.0;
   
   // ตรวจสอบว่าจำนวนการปิดออเดอร์เกิดขึ้นภายในหน้าต่างเวลาที่กำหนดหรือไม่
   if((now - (datetime)win_start) > RegimeExitStormWindowSec)
   {
      win_start = (double)now;
      win_count = 0.0;
   }
   win_count += 1.0;
   GlobalVariableSet(win_start_key, win_start);
   GlobalVariableSet(win_count_key, win_count);

   // หากมีการปิดออเดอร์ถี่เกินไป (Burst) สั่งระงับการเทรดทั้งพอร์ตทันที
   if((int)win_count >= RegimeExitStormThreshold)
   {
      datetime pause_until = now + RegimeExitStormPauseSec;
      double current_pause = GlobalVariableCheck(pause_until_key) ? GlobalVariableGet(pause_until_key) : 0.0;
      if((double)pause_until > current_pause)
         GlobalVariableSet(pause_until_key, (double)pause_until);
      LogError(StringFormat("Emergency Pause armed: RegimeExit burst=%d in %ds, pause=%ds",
               (int)win_count, RegimeExitStormWindowSec, RegimeExitStormPauseSec));
      GlobalVariableSet(win_start_key, (double)now);
      GlobalVariableSet(win_count_key, 0.0);
   }
}

/**
 * ตรวจสอบว่าคู่เงินนี้อยู่ในช่วงเวลาล็อกห้ามเทรดซ้ำ (Symbol Lock) หลังจากเพิ่งปิดออเดอร์แบบ Regime Exit หรือไม่
 */
bool IsRegimeExitLockActive(const string symbol)
{
   if(!EnableEmergencyGuards) return false;
   string last_exit_key = "KNARES_RegimeExit_Last_" + symbol;
   if(!GlobalVariableCheck(last_exit_key)) return false;
   datetime last_exit = (datetime)GlobalVariableGet(last_exit_key);
   // หากเวลาที่ปิดออเดอร์ล่าสุดยังไม่พ้นระยะห่างที่กำหนด จะบล็อกการเข้าใหม่
   if(TimeCurrent() - last_exit < RegimeExitSymbolLockSec)
   {
      LogWarning(StringFormat("RegimeExit Lock active for %s (%ds)", symbol, RegimeExitSymbolLockSec));
      return true;
   }
   return false;
}

/**
 * ตรวจสอบสถานะการระงับการเทรดฉุกเฉินระดับพอร์ต (Emergency Pause Status)
 */
bool IsRegimeExitPauseActive()
{
   if(!EnableEmergencyGuards) return false;
   string pause_until_key = "KNARES_RegimeExit_PauseUntil";
   if(!GlobalVariableCheck(pause_until_key)) return false;
   datetime pause_until = (datetime)GlobalVariableGet(pause_until_key);
   if(TimeCurrent() < pause_until)
   {
      LogError(StringFormat("Emergency Pause active until %s", TimeToString(pause_until, TIME_SECONDS)));
      return true;
   }
   return false;
}

/**
 * ตรวจสอบล่วงหน้าว่าการถือครอง (Exposure) กำลังเข้าใกล้ขีดจำกัดสูงสุดหรือไม่ (Soft Limit)
 * ใช้เพื่อเตือนหรือชะลอการส่งคำสั่งก่อนที่จะถูกบล็อกจริงโดย Hard Limit
 */
bool IsExposureNearLimit(string symbol, double lots, double soft_ratio = 0.90)
{
   double total_notional = 0;
   int symbol_count = 0;
   int total_positions = 0;

   // คำนวณสถานะพอร์ตปัจจุบัน
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            string pos_symbol = PositionGetString(POSITION_SYMBOL);
            double pos_lots = PositionGetDouble(POSITION_VOLUME);
            double contract_size = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            double mid_price = 0.5 * (SymbolInfoDouble(pos_symbol, SYMBOL_BID) + SymbolInfoDouble(pos_symbol, SYMBOL_ASK));
            if(contract_size <= 0) contract_size = 100000.0;
            if(mid_price <= 0) mid_price = 1.0;
            total_notional += pos_lots * contract_size * mid_price;
            if(pos_symbol == symbol) symbol_count++;
            total_positions++;
         }
      }
   }

   // คำนวณมูลค่าที่จะเพิ่มเข้ามาหากเปิดไม้ใหม่
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double mid_price = 0.5 * (SymbolInfoDouble(symbol, SYMBOL_BID) + SymbolInfoDouble(symbol, SYMBOL_ASK));
   if(contract_size <= 0) contract_size = 100000.0;
   if(mid_price <= 0) mid_price = 1.0;
   double new_notional = lots * contract_size * mid_price;
   bool is_xau = (StringFind(symbol, "XAU") >= 0);
   double cap_mult = is_xau ? ExposureCapEquityMultipleXAU : ExposureCapEquityMultipleFX;
   if(EnableOpenMarketIncrementalCaps)
   {
      double add = MathMin(IncrementalExposureMaxAdd,
                           MathMax(0.0, IncrementalExposureStepPerPos) * (double)total_positions);
      cap_mult += MathMax(0.0, add);
   }
   double max_allowed_exposure = MathMax(1.0, AccountInfoDouble(ACCOUNT_EQUITY) * cap_mult);
   double projected = total_notional + new_notional;
   
   // แจ้งเตือนหากมูลค่ารวมเกินสัดส่วนที่กำหนด (เช่น 90% ของขีดจำกัดสูงสุด)
   if(projected >= (max_allowed_exposure * soft_ratio))
   {
      LogWarning(StringFormat("Soft Exposure Block: projected_notional=%.2f near cap=%.2f (ratio=%.2f)",
                 projected, max_allowed_exposure, soft_ratio));
      return true;
   }
   return false;
}

/**
 * ตรวจสอบช่วงเวลาที่อนุญาตให้เทรด และการป้องกันความเสี่ยงช่วงตลาดปิด (Session Guard)
 * @return true หากอยู่ในช่วงเวลาเทรดปกติ
 */
bool IsTradingSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // 1. ตรวจสอบชั่วโมงการทำงานรายวัน (Start - End Hour)
   if(dt.hour < StartHour || dt.hour >= EndHour)
   {
      LogInfo(StringFormat("Session blocked: server hour=%d outside [%d,%d)", dt.hour, StartHour, EndHour));
      return false;
   }
   
   // 2. ป้องกันการถือออเดอร์ข้ามคืนวันศุกร์ (Weekend Gap Prevention)
   // บล็อกการเข้าเทรดใหม่ตั้งแต่ช่วงเย็นวันศุกร์ เพื่อเลี่ยงความเสี่ยงที่ราคาจะกระโดดในเช้าวันจันทร์
   if(!TradeOnFridayClose && dt.day_of_week == 5 && dt.hour >= 18)
   {
      LogInfo("Friday night session closed. Preventing weekend gaps.");
      return false;
   }
   
   return true;
}

/**
 * Daily Loss Cluster Guard: ระบบตรวจสอบพฤติกรรมการขาดทุนสะสมในหน้าต่างเวลาสั้นๆ
 * ทำหน้าที่หยุดการทำงานของพอร์ตหากพบว่ามีการแพ้ถี่เกินไป เพื่อเลี่ยงสภาวะตลาดที่ EA ไม่ถนัด
 * 
 * @param fail_reason สาเหตุหากถูกสั่งระงับ (Output)
 * @return true หากผ่านเกณฑ์
 */
bool IsDailyLossClusterOk(string &fail_reason)
{
   if(!EnableDailyLossClusterGuard) return true;
   
   string pause_key = "KNARES_DailyLossCluster_Until";
   datetime now = TimeCurrent();
   
   // 1. ตรวจสอบสถานะการหยุดเทรดปัจจุบันที่บันทึกไว้ใน Global Variable
   if(GlobalVariableCheck(pause_key))
   {
      datetime until = (datetime)GlobalVariableGet(pause_key);
      if(now < until)
      {
         fail_reason = "daily_loss_cluster_pause";
         return false;
      }
      else GlobalVariableDel(pause_key);
   }

   // 2. วิเคราะห์ประวัติการเทรดล่าสุดภายในหน้าต่างเวลาที่กำหนด (Cluster Window)
   datetime window_start = now - (DailyLossClusterWindowMinutes * 60);
   if(!HistorySelect(window_start, now)) return true;
   
   int bad_exits = 0;
   double cluster_loss = 0;
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealSelect(ticket))
      {
         // ตรวจสอบเฉพาะออเดอร์ที่ถูกเปิดโดย EA ตัวนี้เท่านั้น (Magic Number)
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
         
         // วิเคราะห์เฉพาะการปิดออเดอร์ (Entry Out)
         long entry_type = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_INOUT)
         {
            double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double s = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double net = p + c + s;
            
            if(net < 0) cluster_loss += MathAbs(net);
            
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            StringToLower(comment);
            
            // คัดกรองประเภทการปิดออเดอร์ที่เป็นสัญญาณอันตราย (Bad Exits)
            bool is_bad = false;
            // นับออเดอร์ที่โดน Stop Loss เต็ม
            if(DailyLossClusterCountHardSL && HistoryDealGetInteger(ticket, DEAL_REASON) == DEAL_REASON_SL && net < 0) is_bad = true;
            // นับออเดอร์ที่ถูกระบบแก้ไม้ย่อยปิดไปแบบขาดทุน (Micro Exit)
            if(DailyLossClusterCountMicro && StringFind(comment, "micro") >= 0) is_bad = true;
            // นับออเดอร์ที่ปิดเพราะสภาวะตลาดเปลี่ยน (Regime Exit)
            if(DailyLossClusterCountContext && (StringFind(comment, "regime") >= 0 || StringFind(comment, "contextexit") >= 0)) is_bad = true;
            
            if(is_bad) bad_exits++;
         }
      }
   }
   
   // 3. ตรวจสอบเงื่อนไขการสั่งระงับเทรด (Trigger)
   // หากจำนวนไม้เสียถึงเกณฑ์ หรือยอดเงินขาดทุนรวมถึงเกณฑ์ ระบบจะสั่งพักทันที
   bool cluster_hit = (bad_exits >= DailyLossClusterBadExitCount) || (cluster_loss >= DailyLossClusterNetLossUSD && DailyLossClusterNetLossUSD > 0);
   
   if(cluster_hit)
   {
      datetime until = now + (DailyLossClusterPauseMinutes * 60);
      GlobalVariableSet(pause_key, (double)until);
      g_daily_loss_cluster_triggers++;
         
      fail_reason = StringFormat("daily_loss_cluster(%d_bad_exits, %.2f_loss)", bad_exits, cluster_loss);
      LogWarning(StringFormat("DailyLossClusterGuard: %s. Trading paused for %d min.", fail_reason, DailyLossClusterPauseMinutes));
      return false;
   }
   
   return true;
}

/**
 * ฟังก์ชันรวมศูนย์การตรวจสอบความปลอดภัยของพอร์ตทั้งหมด (Unified Security Gate)
 * ตรวจสอบกฎเหล็กทุกลำดับชั้นก่อนตัดสินใจอนุญาตให้ดำเนินการเทรดต่อ
 */
bool CheckPortfolioLimits(string &fail_reason)
{
   fail_reason = "";
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   // คำนวณ Drawdown ของพอร์ต ณ ปัจจุบัน
   double drawdown_pct = (balance > 0) ? (1.0 - (equity / balance)) * 100.0 : 0;

   // 1. Equity Kill Switch: กฎข้อสุดท้าย ตัดขาดการทำงานทันทีหากพอร์ตเสียหายเกินขีดจำกัดวิกฤต
   if(drawdown_pct >= EquityKillSwitchPct * 100.0)
   {
      fail_reason = "equity_kill_switch";
      LogError(StringFormat("EQUITY KILL SWITCH TRIGGERED! Drawdown: %.2f%%", drawdown_pct));
      return false;
   }

   // 2. Max Total Drawdown: บล็อกการเทรดใหม่หากพอร์ตอยู่ในสภาวะติดลบรวมเกินค่าที่ตั้งไว้
   if(drawdown_pct >= MaxTotalDrawdownPercent)
   {
      fail_reason = "max_total_drawdown";
      LogError(StringFormat("TOTAL DRAWDOWN GUARD TRIGGERED! %.2f%% >= %.2f%%", drawdown_pct, MaxTotalDrawdownPercent));
      return false;
   }

   // 3. ตรวจสอบขีดจำกัดย่อย: รายวัน, รายสัปดาห์ และคลัสเตอร์การขาดทุน
   if(!IsDailyLimitOk(fail_reason)) return false;
   if(!IsDailyLossClusterOk(fail_reason)) return false;

   // 4. ตรวจสอบเวลาปฏิบัติการ
   if(!IsTradingSession())
   {
      fail_reason = "session_closed";
      return false;
   }
   
   return true;
}

/**
 * CheckGlobalPortfolioHeat: ตรวจสอบความเสี่ยงรวมของเงินทุนทั้งหมด (Cross-Instance Risk)
 * ใช้ Global Variable เพื่อให้ EA หลายหน้าต่างแชร์ข้อมูลความเสี่ยงร่วมกัน เพื่อไม่ให้เปิดออเดอร์รวมกันจนเกินกำลังพอร์ต
 */
bool CheckGlobalPortfolioHeat(double new_risk_money, string &fail_reason)
{
   string gv_name = "KNARES_Total_Risk_Money";
   double current_total_risk = 0;
   fail_reason = "";

   if(GlobalVariableCheck(gv_name))
      current_total_risk = GlobalVariableGet(gv_name);

   // คำนวณเพดานความเสี่ยงรวม (Heat Cap) ที่ยอมรับได้
   double max_heat = AccountInfoDouble(ACCOUNT_EQUITY) * PortfolioHeatCapPct;
   if(EnableOpenMarketIncrementalCaps)
   {
      int total_positions = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)) &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            total_positions++;
      }
      // เพิ่มขยายเพดานความเสี่ยงเล็กน้อยเมื่อมีออเดอร์ในตลาดมากขึ้น (Incremental Heat)
      double heat_add_ratio = MathMin(MathMax(0.0, IncrementalHeatMaxAdd),
                                      MathMax(0.0, IncrementalHeatStepPerPos) * (double)total_positions);
      max_heat *= (1.0 + heat_add_ratio);
   }

   // ตรวจสอบว่าหากเพิ่มความเสี่ยงของออเดอร์ใหม่เข้าไป จะเกินเพดานหรือไม่
   if(current_total_risk + new_risk_money > max_heat)
   {
      fail_reason = StringFormat("heat_cap(proj=%.2f > max=%.2f)", current_total_risk + new_risk_money, max_heat);
      LogWarning(StringFormat("Global Heat Cap reached: %s", fail_reason));
      return false;
   }
   return true;
}

/**
 * EvaluateLimitGate: ฟังก์ชันรวมขั้นตอนการประเมินกฎเหล็กก่อนส่งคำสั่งจริง
 * ทำการตรวจสอบทั้งในระดับพอร์ต, ระดับคู่เงิน และความเสี่ยงรวม เพื่อยืนยันความปลอดภัยขั้นสูงสุด
 */
void EvaluateLimitGate(string symbol, ENUM_SIGNAL_DIRECTION dir, double lots, double risk_money, const MarketSnapshot &snap, LimitGateResult &res)
{
   // เริ่มต้นค่าพารามิเตอร์ผลลัพธ์
   res.exp_fail_reason = "";
   res.heat_fail_reason = "";
   // ขั้นที่ 1: ตรวจสอบกฎพอร์ตพื้นฐาน
   res.portfolio_pass = CheckPortfolioLimits(res.exp_fail_reason);
   
   res.exposure_cap_pass = true;
   res.price_clustering_pass = true;
   res.max_positions_pass = true;
   res.heat_cap_pass = true;
   
   // --- ส่วนที่ 1: ตรวจสอบ Exposure และ Clustering รายสัญลักษณ์ ---
   double total_notional = 0;
   int symbol_count = 0;
   int total_positions = 0;

   // สแกนออเดอร์ปัจจุบันเพื่อคำนวณมูลค่าถือครอง
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         double pos_lots = PositionGetDouble(POSITION_VOLUME);
         double contract_size = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         double mid_price = 0.5 * (SymbolInfoDouble(pos_symbol, SYMBOL_BID) + SymbolInfoDouble(pos_symbol, SYMBOL_ASK));
         total_notional += pos_lots * (contract_size > 0 ? contract_size : 100000.0) * (mid_price > 0 ? mid_price : 1.0);
         total_positions++;
         if(pos_symbol == symbol) symbol_count++;
      }
   }

   res.exposure_actual = total_notional;
   int max_pos = MathMax(1, MaxPositionsPerSymbol);
   if(symbol_count >= max_pos)
   {
      res.max_positions_pass = false;
      res.exp_fail_reason = StringFormat("max_pos_reached(%d/%d)", symbol_count, max_pos);
   }

   // ตรวจสอบความกระจุกตัวของราคา (Price clustering) อ้างอิง ATR ปัจจุบัน
   double current_atr = snap.atr;
   if(current_atr > 0 && MinPositionDistanceATR > 0)
   {
      double min_dist = current_atr * MinPositionDistanceATR;
      double current_price = (dir == SIGNAL_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            if(MathAbs(current_price - PositionGetDouble(POSITION_PRICE_OPEN)) < min_dist)
            {
               res.price_clustering_pass = false;
               if(res.exp_fail_reason == "") 
                  res.exp_fail_reason = StringFormat("price_clustering(dist=%.1f < min=%.1f)", 
                                                     MathAbs(current_price - PositionGetDouble(POSITION_PRICE_OPEN))/SymbolInfoDouble(symbol, SYMBOL_POINT),
                                                     min_dist/SymbolInfoDouble(symbol, SYMBOL_POINT));
            }
         }
      }
   }

   // ตรวจสอบขีดจำกัดเพดาน Exposure ของคู่เงิน
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double mid_price = 0.5 * (SymbolInfoDouble(symbol, SYMBOL_BID) + SymbolInfoDouble(symbol, SYMBOL_ASK));
   double new_notional = lots * (contract_size > 0 ? contract_size : 100000.0) * (mid_price > 0 ? mid_price : 1.0);
   
   bool is_xau = (StringFind(symbol, "XAU") >= 0);
   double cap_mult = is_xau ? ExposureCapEquityMultipleXAU : ExposureCapEquityMultipleFX;
   if(EnableOpenMarketIncrementalCaps)
   {
      double add = MathMin(IncrementalExposureMaxAdd, MathMax(0.0, IncrementalExposureStepPerPos) * (double)total_positions);
      cap_mult += MathMax(0.0, add);
   }
   res.exposure_max = MathMax(1.0, AccountInfoDouble(ACCOUNT_EQUITY) * cap_mult);
   if(total_notional + new_notional > res.exposure_max)
   {
      res.exposure_cap_pass = false;
      current_metrics.exposure_cap_hits++;
      if(res.exp_fail_reason == "")
         res.exp_fail_reason = StringFormat("exposure_cap(proj=%.1f > max=%.1f)", total_notional + new_notional, res.exposure_max);
      
      LogInfo(StringFormat("ExposureCapDetail: symbol=%s lot=%.2f price=%.2f notional=%.1f equity=%.1f mult=%.1f cap=%.1f result=BLOCK",
                           symbol, lots, snap.bid, new_notional, AccountInfoDouble(ACCOUNT_EQUITY), (total_notional+new_notional)/AccountInfoDouble(ACCOUNT_EQUITY), cap_mult));
   }

   // --- ส่วนที่ 2: ตรวจสอบ Heat cap (ความเสี่ยงรวมพอร์ต) ---
   res.heat_actual = GetTotalReservedRisk();
   res.heat_max = AccountInfoDouble(ACCOUNT_EQUITY) * PortfolioHeatCapPct;
   if(EnableOpenMarketIncrementalCaps)
   {
      double heat_add = MathMin(MathMax(0.0, IncrementalHeatMaxAdd), MathMax(0.0, IncrementalHeatStepPerPos) * (double)total_positions);
      res.heat_max *= (1.0 + heat_add);
   }
   if(res.heat_actual + risk_money > res.heat_max)
   {
      res.heat_cap_pass = false;
      current_metrics.heat_cap_hits++;
      res.heat_fail_reason = StringFormat("heat_cap(proj=%.2f > max=%.2f)", res.heat_actual + risk_money, res.heat_max);
   }
}

// --- ฟังก์ชันจัดการการจองและคืนค่าความเสี่ยง (Risk Reservation System) ---
// ระบบนี้ใช้เพื่อจัดการยอดเงินเสี่ยงที่ "จอง" ไว้ตั้งแต่ตอนส่งออเดอร์ เพื่อให้ข้อมูล Real-time แม้ออเดอร์ยังไม่ถูกเติม

/**
 * จองความเสี่ยงในระบบ Global เพื่อให้ EA ตัวอื่นรับรู้
 */
void ReserveGlobalRisk(double risk_money)
{
   string gv_name = "KNARES_Total_Risk_Money";
   double current_total_risk = 0;
   if(GlobalVariableCheck(gv_name))
      current_total_risk = GlobalVariableGet(gv_name);
   GlobalVariableSet(gv_name, current_total_risk + MathMax(0.0, risk_money));
}

/**
 * บันทึกยอดความเสี่ยงที่รอการเปิด (Pending) ของคู่เงินนั้นๆ
 */
void StorePendingRisk(string symbol, double risk_money)
{
   string gv_name = "KNARES_PENDING_RISK_" + symbol;
   GlobalVariableSet(gv_name, risk_money);
   LogInfo(StringFormat("RiskPendingStored: symbol=%s risk=%.2f", symbol, risk_money));
}

/**
 * เชื่อมโยงยอดความเสี่ยงจากสถานะ Pending เข้ากับออเดอร์ที่ถูกเปิดสำเร็จ (Ticket)
 */
void LinkPendingRiskToTicket(string symbol, ulong ticket)
{
   string pending_gv = "KNARES_PENDING_RISK_" + symbol;
   if(GlobalVariableCheck(pending_gv))
   {
      double risk = GlobalVariableGet(pending_gv);
      StorePositionRisk(ticket, risk);
      GlobalVariableDel(pending_gv);
      LogInfo(StringFormat("RiskLinkedToPosition: ticket=%I64u symbol=%s risk=%.2f", ticket, symbol, risk));
   }
   else
   {
      LogWarning(StringFormat("RiskLinkMissing: ticket=%I64u symbol=%s (no pending risk found)", ticket, symbol));
   }
}

/**
 * บันทึกข้อมูลความเสี่ยงลงใน Global Variable โดยใช้เลข Ticket เป็นกุญแจหลัก
 */
void StorePositionRisk(ulong ticket, double risk_money)
{
   if(ticket <= 0) return;
   string gv_name = "KNARES_POS_RISK_" + (string)ticket;
   GlobalVariableSet(gv_name, risk_money);
}

/**
 * บันทึกขนาด Lot เริ่มต้นของออเดอร์เพื่อใช้คำนวณการคืนความเสี่ยงตามสัดส่วน
 */
void StorePositionInitialVolume(ulong ticket, double volume)
{
   if(ticket <= 0) return;
   string gv_name = "KNARES_POS_VOL_" + (string)ticket;
   GlobalVariableSet(gv_name, volume);
}

/**
 * คืนค่าความเสี่ยงเมื่อมีการปิดออเดอร์ (รองรับทั้งการปิดทั้งหมดและการปิดบางส่วน)
 */
void ReleasePositionRisk(ulong ticket, double closed_volume = 0.0)
{
   if(ticket <= 0) return;
   string gv_risk = "KNARES_POS_RISK_" + (string)ticket;
   string gv_vol  = "KNARES_POS_VOL_" + (string)ticket;

   if(!GlobalVariableCheck(gv_risk))
   {
      LogWarning(StringFormat("RiskReleaseMissing: ticket=%I64u (no stored risk found)", ticket));
      return;
   }

   double total_risk = GlobalVariableGet(gv_risk);
   double release_amt = 0.0;
   double stored_vol = GlobalVariableCheck(gv_vol) ? GlobalVariableGet(gv_vol) : 0.0;
   
   // ตรวจสอบว่าเป็นการปิดออเดอร์ทั้งหมดหรือไม่
   if(closed_volume <= 0.0 || stored_vol <= 0.0 || closed_volume >= (stored_vol - 0.0001))
   {
      release_amt = total_risk;
      GlobalVariableDel(gv_risk);
      GlobalVariableDel(gv_vol);
      LogInfo(StringFormat("RiskReleased(Full): ticket=%I64u risk=%.2f", ticket, release_amt));
   }
   else
   {
      // คืนความเสี่ยงตามสัดส่วน (สำหรับการแบ่งปิดกำไร - Partial Close)
      release_amt = total_risk * (closed_volume / stored_vol);
      double remaining_risk = MathMax(0.0, total_risk - release_amt);
      double remaining_vol  = MathMax(0.0, stored_vol - closed_volume);
      
      GlobalVariableSet(gv_risk, remaining_risk);
      GlobalVariableSet(gv_vol, remaining_vol);
      LogInfo(StringFormat("RiskReleased(Partial): ticket=%I64u released=%.2f remaining=%.2f (vol: closed=%.2f remain=%.2f)", 
                           ticket, release_amt, remaining_risk, closed_volume, remaining_vol));
   }

   if(release_amt > 0)
      ReleaseGlobalRisk(release_amt);
}

/**
 * คืนความเสี่ยงให้กับระบบ Global เพื่อเพิ่มพื้นที่ให้กับออเดอร์ใหม่
 */
void ReleaseGlobalRisk(double risk_money)
{
   string gv_name = "KNARES_Total_Risk_Money";
   if(GlobalVariableCheck(gv_name))
   {
      double current = GlobalVariableGet(gv_name);
      GlobalVariableSet(gv_name, MathMax(0, current - risk_money));
   }
}

/**
 * ล้างข้อมูลการจองความเสี่ยงทั้งหมด (ใช้เมื่อเริ่มระบบใหม่หรือล้างสถานะผิดพลาด)
 */
void ResetGlobalRiskTracker()
{
   string gv_name = "KNARES_Total_Risk_Money";
   GlobalVariableSet(gv_name, 0.0);
   LogInfo("Global risk tracker reset to 0.");
}

/**
 * ดึงค่าความเสี่ยงรวมที่มีการจองไว้ในปัจจุบัน
 */
double GetTotalReservedRisk()
{
   string gv_name = "KNARES_Total_Risk_Money";
   return GlobalVariableCheck(gv_name) ? GlobalVariableGet(gv_name) : 0.0;
}

/**
 * คำนวณความเสี่ยงรวมของออเดอร์ที่ถืออยู่จริงเท่านั้น โดยสแกนจากข้อมูล Ticket
 */
double GetOpenPositionsReservedRisk()
{
   double sum = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string gv_name = "KNARES_POS_RISK_" + (string)ticket;
         if(GlobalVariableCheck(gv_name))
            sum += GlobalVariableGet(gv_name);
      }
   }
   return sum;
}

// --- ฟังก์ชันดึงข้อมูลสรุปสำหรับการแสดงผล (Dashboard Helpers) ---

/**
 * ดึงข้อมูลสรุปสถานะการถือครอง (Exposure) ของคู่เงิน
 */
ExposureInfo GetExposureInfo(string symbol, double new_lots)
{
   ExposureInfo info = {0, 0, 0};
   double total_notional = 0;
   int total_positions = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         double pos_lots = PositionGetDouble(POSITION_VOLUME);
         double contract_size = SymbolInfoDouble(pos_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         double mid_price = 0.5 * (SymbolInfoDouble(pos_symbol, SYMBOL_BID) + SymbolInfoDouble(pos_symbol, SYMBOL_ASK));
         total_notional += pos_lots * (contract_size > 0 ? contract_size : 100000.0) * (mid_price > 0 ? mid_price : 1.0);
         total_positions++;
      }
   }
   
   info.actual = total_notional;
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double mid_price = 0.5 * (SymbolInfoDouble(symbol, SYMBOL_BID) + SymbolInfoDouble(symbol, SYMBOL_ASK));
   double new_notional = new_lots * (contract_size > 0 ? contract_size : 100000.0) * (mid_price > 0 ? mid_price : 1.0);
   info.projected = total_notional + new_notional;

   bool is_xau = (StringFind(symbol, "XAU") >= 0);
   double cap_mult = is_xau ? ExposureCapEquityMultipleXAU : ExposureCapEquityMultipleFX;
   if(EnableOpenMarketIncrementalCaps)
   {
      double add = MathMin(IncrementalExposureMaxAdd,
                           MathMax(0.0, IncrementalExposureStepPerPos) * (double)total_positions);
      cap_mult += MathMax(0.0, add);
   }
   info.max = MathMax(1.0, AccountInfoDouble(ACCOUNT_EQUITY) * cap_mult);
   
   return info;
}

/**
 * ดึงข้อมูลสรุปสถานะความเสี่ยงรวม (Heat) ของพอร์ต
 */
HeatInfo GetHeatInfo(double new_risk_money)
{
   HeatInfo info = {0, 0, 0};
   info.actual = GetTotalReservedRisk();
   info.projected = info.actual + new_risk_money;

   double base_max = AccountInfoDouble(ACCOUNT_EQUITY) * PortfolioHeatCapPct;
   if(EnableOpenMarketIncrementalCaps)
   {
      int total_positions = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            total_positions++;
      }
      double heat_add_ratio = MathMin(MathMax(0.0, IncrementalHeatMaxAdd),
                                      MathMax(0.0, IncrementalHeatStepPerPos) * (double)total_positions);
      base_max *= (1.0 + heat_add_ratio);
   }
   info.max = base_max;
   return info;
}


int GetVolShockDetections() { return g_vol_shock_detections; }
void IncrementVolShockDetections() { g_vol_shock_detections++; }

/**
 * GetDrawdownRiskMultiplier: ระบบลดความเสี่ยงแบบแปรผันตามระดับ Drawdown ของพอร์ต (Dynamic De-leveraging)
 * ทำหน้าที่ลดขนาด Lot ทันทีเมื่อพอร์ตเสียหายถึงจุดที่กำหนด เพื่อรักษาชีวิตของพอร์ต (Survival Mode)
 */
double GetDrawdownRiskMultiplier()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_pct = (balance > 0) ? (1.0 - (equity / balance)) * 100.0 : 0;

   // ยิ่ง Drawdown สูง ตัวคูณความเสี่ยงยิ่งลดลง
   if(dd_pct < 5.0) return 1.00;   // ปกติ
   if(dd_pct < 10.0) return 0.75;  // ลดลง 25%
   if(dd_pct < 15.0) return 0.50;  // ลดลง 50%
   if(dd_pct < 20.0) return 0.25;  // ลดลง 75%
   return 0.10; // โหมดวิกฤต: เหลือความเสี่ยงเพียง 10% เพื่อประคองพอร์ต
}

/**
 * UpdateRiskMode: ระบบจัดการสภาวะการเทรด (Risk State Machine)
 * ปรับเปลี่ยนพฤติกรรมของ EA ระหว่างโหมดปกติ, โหมดป้องกัน และโหมดฟื้นฟู ตามสุขภาพของพอร์ต
 */
ENUM_RISK_MODE UpdateRiskMode()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_pct = (balance > 0) ? (1.0 - (equity / balance)) * 100.0 : 0;

   // 1. เข้าสู่โหมด Defensive: เมื่อ DD เกิน 10% หรือแพ้สะสมเยอะ
   if(dd_pct >= 10.0 || current_metrics.consecutive_losses >= LossStreakLimit)
   {
      current_metrics.risk_mode = RISK_MODE_DEFENSIVE;
      return RISK_MODE_DEFENSIVE;
   }

   // 2. เข้าสู่โหมด Recovery: เมื่อพอร์ตเริ่มดีขึ้น (DD ต่ำกว่า 5%) และมีกำไรคาดหวังเริ่มกลับมา (PF > 1.05)
   if(current_metrics.risk_mode == RISK_MODE_DEFENSIVE && dd_pct < 5.0 && current_metrics.profit_factor > 1.05)
   {
      current_metrics.risk_mode = RISK_MODE_RECOVERY;
      LogInfo("Phase 11: Entering RECOVERY mode. Progressively restoring risk.");
      return RISK_MODE_RECOVERY;
   }

   // 3. กลับสู่โหมด Normal: เมื่อพอร์ตกลับสู่สภาวะแข็งแกร่ง (DD < 2%)
   if(current_metrics.risk_mode == RISK_MODE_RECOVERY && dd_pct < 2.0)
   {
      current_metrics.risk_mode = RISK_MODE_NORMAL;
      LogInfo("Phase 11: Risk restored to NORMAL.");
   }

   return current_metrics.risk_mode;
}

/**
 * GetRiskRestoreMultiplier: คำนวณตัวคูณเพื่อค่อยๆ เพิ่มความเสี่ยงกลับมาในโหมดฟื้นฟู (Progressive Restoration)
 */
double GetRiskRestoreMultiplier()
{
   if(current_metrics.risk_mode == RISK_MODE_DEFENSIVE) return RiskReductionFactor;
   
   if(current_metrics.risk_mode == RISK_MODE_RECOVERY)
   {
      // ค่อยๆ เพิ่มความเสี่ยงกลับมาตามจำนวนไม้ที่ชนะติดต่อกันในโหมด Recovery
      double base = RiskReductionFactor;
      double step = RiskRestoreStep * (double)current_metrics.consecutive_wins;
      return MathMin(1.0, base + step);
   }
   
   return 1.0;
}

/**
 * IsExecutionSafe: การตรวจสอบความปลอดภัยขั้นสุดท้าย ณ จังหวะส่งคำสั่ง (Pre-execution Safety)
 * ตรวจสอบค่า Spread และสภาวะตลาดเพื่อให้มั่นใจว่าจะไม่เสียเปรียบจากการส่งคำสั่ง
 */
bool IsExecutionSafe(string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(symbol, SYMBOL_POINT);

   // Adaptive Spread: ปรับเพดาน Spread ที่ยอมรับได้ตามค่ากลาง (Median) ล่าสุด เพื่อให้ยืดหยุ่นตามสภาวะตลาดจริง
   double median_spread = GetLastMedianSpreadPoints();
   bool is_xau = (StringFind(symbol, "XAU", 0) >= 0);
   double base_cap = is_xau ? MathMax(MaxSpreadPointsXAU, XAUAdaptiveSpreadFloor) : 50.0;
   double spread_mult = is_xau ? XAUAdaptiveSpreadMedianMult : 1.8;
   double adaptive_cap = (median_spread > 0.0) ? MathMax(base_cap, median_spread * spread_mult) : base_cap;

   // บล็อกหาก Spread กว้างเกินไป (เช่น ช่วงข่าวแรง หรือช่วงเปิด/ปิดตลาด)
   if(spread > adaptive_cap)
   {
      LogWarning(StringFormat("Execution unsafe: High Spread (%.1f points > cap %.1f, median %.1f)",
                              spread, adaptive_cap, median_spread));
      return false;
   }

   return true;
}

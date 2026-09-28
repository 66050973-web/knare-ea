#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "PortfolioGovernor.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Position Manager Module - โมดูลจัดการออเดอร์หลังการเปิดเทรด (Trade Management) |
//| ทำหน้าที่: ดูแลออเดอร์ที่เปิดอยู่, ปรับ SL/TP อัตโนมัติ, จัดการการปิดออเดอร์ตามเงื่อนไข |
//+------------------------------------------------------------------+

CTrade pos_manager; // ออบเจกต์สำหรับการจัดการและแก้ไขออเดอร์ที่เปิดอยู่

// --- ระบบการจัดการสถานะภายในออเดอร์ (Internal Position State Management) ---
// ใช้ Global Variables เพื่อติดตามสถานะและการตัดสินใจที่เคยเกิดขึ้นกับแต่ละ Ticket

/**
 * HasPositionFlag: ตรวจสอบสถานะพิเศษของออเดอร์
 * @param ticket หมายเลขตั๋วออเดอร์
 * @param flag ชื่อสถานะที่ต้องการตรวจสอบ
 * @return คืนค่า true หากพบ Flag นี้ในระบบ
 */
bool HasPositionFlag(const ulong ticket, const string flag)
{
   string key = "KNARES_FLAG_" + (string)ticket + "_" + flag;
   return GlobalVariableCheck(key);
}

/**
 * SetPositionFlag: บันทึกสถานะพิเศษให้กับออเดอร์
 * @param ticket หมายเลขตั๋วออเดอร์
 * @param flag ชื่อสถานะที่ต้องการบันทึก
 * ใช้เพื่อป้องกันไม่ให้ระบบทำคำสั่งเดิมซ้ำ (เช่น การแบ่งปิดกำไรไปแล้ว)
 */
void SetPositionFlag(const ulong ticket, const string flag)
{
   string key = "KNARES_FLAG_" + (string)ticket + "_" + flag;
   GlobalVariableSet(key, 1.0);
}

/**
 * SetPositionCooldown: กำหนดเวลาพักการทำงานของฟังก์ชันเฉพาะ
 * @param ticket หมายเลขตั๋วออเดอร์
 * @param action ชื่อการดำเนินการ
 * @param seconds จำนวนวินาทีที่ต้องการให้พัก
 */
void SetPositionCooldown(const ulong ticket, const string action, int seconds)
{
   string key = "KNARES_COOL_" + (string)ticket + "_" + action;
   GlobalVariableSet(key, (double)(TimeCurrent() + seconds));
}

/**
 * IsPositionCooldownActive: ตรวจสอบว่าฟังก์ชันยังอยู่ในช่วงพักหรือไม่
 * @param ticket หมายเลขตั๋วออเดอร์
 * @param action ชื่อการดำเนินการ
 * @return คืนค่า true หากยังไม่ครบกำหนดเวลาพัก
 */
bool IsPositionCooldownActive(const ulong ticket, const string action)
{
   string key = "KNARES_COOL_" + (string)ticket + "_" + action;
   if(!GlobalVariableCheck(key)) return false;
   datetime until = (datetime)GlobalVariableGet(key);
   if(TimeCurrent() < until) return true;
   GlobalVariableDel(key); 
   return false;
}

/**
 * ClearPositionFlags: ล้างข้อมูลชั่วคราวทั้งหมดของออเดอร์
 * @param ticket หมายเลขตั๋วออเดอร์
 * เรียกใช้เมื่อออเดอร์ถูกปิด เพื่อไม่ให้มีข้อมูลขยะค้างในระบบ Global Variables
 */
void ClearPositionFlags(const ulong ticket)
{
   GlobalVariableDel("KNARES_FLAG_" + (string)ticket + "_PARTIAL_FALLBACK_DONE");
   GlobalVariableDel("KNARES_FLAG_" + (string)ticket + "_TRAILING_DONE");
   GlobalVariableDel("KNARES_FLAG_" + (string)ticket + "_ACCEL_DONE");
   GlobalVariableDel("KNARES_COOL_" + (string)ticket + "_PARTIAL_FALLBACK");
   GlobalVariableDel("KNARES_COOL_" + (string)ticket + "_TRAILING");
   GlobalVariableDel("KNARES_COOL_" + (string)ticket + "_ACCEL");
   
   GlobalVariableDel("KNARES_CONFIRM_" + (string)ticket + "_EARLYINV");
   GlobalVariableDel("KNARES_CONFBAR_" + (string)ticket + "_EARLYINV");
   GlobalVariableDel("KNARES_CONFIRM_" + (string)ticket + "_REGIME_LOSS_CUT");
   GlobalVariableDel("KNARES_CONFBAR_" + (string)ticket + "_REGIME_LOSS_CUT");
   
   GlobalVariableDel("KNARES_Modify_Last_" + (string)ticket);
   GlobalVariableDel("KNARES_Modify_Bar_" + (string)ticket);
   GlobalVariableDel("KNARES_RegimeExit_Count_" + (string)ticket);
   GlobalVariableDel("KNARES_RegimeExit_Bar_" + (string)ticket);
}

// ฟังก์ชันภายในสำหรับสร้างชื่อตัวแปร Global
string RegimeExitCountKey(const ulong ticket) { return "KNARES_RegimeExit_Count_" + (string)ticket; }
string RegimeExitBarKey(const ulong ticket) { return "KNARES_RegimeExit_Bar_" + (string)ticket; }
string ModifyThrottleKey(const ulong ticket) { return "KNARES_Modify_Last_" + (string)ticket; }
string ModifyThrottleBarKey(const ulong ticket) { return "KNARES_Modify_Bar_" + (string)ticket; }

/**
 * ShouldThrottleModify: ระบบป้องกันการส่งคำสั่งแก้ไขออเดอร์ถี่เกินไป (Anti-spam)
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param old_sl ราคา SL เดิม
 * @param old_tp ราคา TP เดิม
 * @param new_sl ราคา SL ใหม่
 * @param new_tp ราคา TP ใหม่
 * @return คืนค่า true หากควร "ระงับ" การส่งคำสั่งแก้ไขในรอบนี้
 */
bool ShouldThrottleModify(const ulong ticket,
                          const string symbol,
                          const double old_sl,
                          const double old_tp,
                          const double new_sl,
                          const double new_tp)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.00001;
   
   // 1. ตรวจสอบระยะห่างขั้นต่ำ (Min Delta): จะไม่แก้ไขถ้าการเปลี่ยนแปลงราคาน้อยเกินไป
   double min_delta = MathMax(0, ModifyMinDeltaPoints) * point;
   bool sl_small = (new_sl == 0.0 || old_sl == 0.0) ? false : (MathAbs(new_sl - old_sl) < min_delta);
   bool tp_small = (new_tp == 0.0 || old_tp == 0.0) ? false : (MathAbs(new_tp - old_tp) < min_delta);

   if((new_sl != 0.0 || new_tp != 0.0) && (sl_small && tp_small))
      return true;

   // 2. ตรวจสอบการหน่วงเวลาเป็นวินาที (Time Throttling) ตามค่าที่ตั้งไว้ใน ModifyThrottleSeconds
   datetime now = TimeCurrent();
   int cool = MathMax(0, ModifyThrottleSeconds);
   string tkey = ModifyThrottleKey(ticket);
   if(cool > 0 && GlobalVariableCheck(tkey))
   {
      datetime last_ts = (datetime)GlobalVariableGet(tkey);
      if((now - last_ts) < cool)
         return true;
   }

   // 3. จำกัดการแก้ไขเพียง 1 ครั้งต่อ 1 แท่งเทียน (Once Per Bar Throttling)
   if(ModifyOncePerBar)
   {
      datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
      if(bar_time > 0)
      {
         string bkey = ModifyThrottleBarKey(ticket);
         if(GlobalVariableCheck(bkey))
         {
            datetime last_bar = (datetime)GlobalVariableGet(bkey);
            if(last_bar == bar_time)
               return true;
         }
      }
   }

   return false;
}

/**
 * MarkModifySent: บันทึกว่ามีการส่งคำสั่งแก้ไขออเดอร์ไปแล้ว
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 */
void MarkModifySent(const ulong ticket, const string symbol)
{
   GlobalVariableSet(ModifyThrottleKey(ticket), (double)TimeCurrent());
   if(ModifyOncePerBar)
   {
      datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
      if(bar_time > 0)
         GlobalVariableSet(ModifyThrottleBarKey(ticket), (double)bar_time);
   }
}

/**
 * GetPositionAgeBars: คำนวณอายุของออเดอร์เป็นจำนวนแท่งเทียน
 * @param symbol คู่เงิน
 * @param tf ไทม์เฟรม
 * @param open_time เวลาที่เปิดออเดอร์
 * @return จำนวนแท่งเทียนที่ผ่านไปแล้ว
 */
int GetPositionAgeBars(string symbol, ENUM_TIMEFRAMES tf, datetime open_time)
{
   int shift = iBarShift(symbol, tf, open_time, false);
   if(shift < 0) return 0;
   return shift;
}

/**
 * ConfirmConditionBars: ตรวจสอบการยืนยันเงื่อนไขต่อเนื่องตามจำนวนแท่งเทียน
 * @param ticket ตั๋วออเดอร์
 * @param key_suffix ชื่อระบุเงื่อนไข
 * @param symbol คู่เงิน
 * @param required_bars จำนวนแท่งที่ต้องการยืนยัน
 * @return คืนค่า true หากเงื่อนไขเกิดขึ้นครบตามจำนวนแท่งที่กำหนด
 */
bool ConfirmConditionBars(const ulong ticket, const string key_suffix, string symbol, int required_bars)
{
   if(required_bars <= 1) return true;
   
   string key = "KNARES_CONFIRM_" + (string)ticket + "_" + key_suffix;
   string bar_key = "KNARES_CONFBAR_" + (string)ticket + "_" + key_suffix;
   
   datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
   if(bar_time <= 0) return false;

   int count = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
   datetime last_bar = GlobalVariableCheck(bar_key) ? (datetime)GlobalVariableGet(bar_key) : 0;

   // อัปเดตตัวนับเฉพาะเมื่อเริ่มแท่งเทียนใหม่
   if(last_bar != bar_time)
   {
      count++;
      GlobalVariableSet(key, (double)count);
      GlobalVariableSet(bar_key, (double)bar_time);
   }

   return (count >= required_bars);
}

/**
 * ResetConditionConfirm: รีเซ็ตสถานะการยืนยันเงื่อนไข
 * @param ticket ตั๋วออเดอร์
 * @param key_suffix ชื่อระบุเงื่อนไข
 */
void ResetConditionConfirm(const ulong ticket, const string key_suffix)
{
   GlobalVariableDel("KNARES_CONFIRM_" + (string)ticket + "_" + key_suffix);
   GlobalVariableDel("KNARES_CONFBAR_" + (string)ticket + "_" + key_suffix);
}

/**
 * ResetRegimeExitConfirmState: รีเซ็ตสถานะการยืนยันการปิดตามสภาวะตลาด
 * @param ticket ตั๋วออเดอร์
 */
void ResetRegimeExitConfirmState(const ulong ticket)
{
   string count_key = RegimeExitCountKey(ticket);
   string bar_key = RegimeExitBarKey(ticket);
   if(GlobalVariableCheck(count_key)) GlobalVariableDel(count_key);
   if(GlobalVariableCheck(bar_key)) GlobalVariableDel(bar_key);
}

/**
 * ShouldCloseByRegimeWithHysteresis: ตรวจสอบว่าควรปิดออเดอร์เนื่องจากสภาวะตลาดเปลี่ยนหรือไม่
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์ (Buy/Sell)
 * @param current_regime สภาวะตลาดปัจจุบัน
 * @param open_time เวลาเปิดออเดอร์
 * @return คืนค่า true หากสภาวะตลาดตรงข้ามกับออเดอร์และได้รับการยืนยันครบถ้วน
 */
bool ShouldCloseByRegimeWithHysteresis(
   const ulong ticket,
   const string symbol,
   const ENUM_POSITION_TYPE type,
   const ENUM_REGIME_TYPE current_regime,
   const datetime open_time)
{
   // ตรวจสอบว่าสภาวะปัจจุบันขัดแย้งกับออเดอร์ที่ถืออยู่หรือไม่
   bool opposing_regime =
      (type == POSITION_TYPE_BUY && current_regime == REGIME_TREND_DOWN) ||
      (type == POSITION_TYPE_SELL && current_regime == REGIME_TREND_UP);

   if(!opposing_regime)
   {
      ResetRegimeExitConfirmState(ticket);
      return false;
   }

   // ระบบหน่วงเวลาเริ่มต้น (Entry Cooldown) เพื่อไม่ให้ปิดไวเกินไปหลังเปิดไม้
   int cooldown_sec = MathMax(0, RegimeExitEntryCooldownSec);
   if(cooldown_sec > 0 && (TimeCurrent() - open_time) < cooldown_sec)
   {
      LogDebug(StringFormat("Regime Exit cooldown [%s]: ticket=%I64u age=%ds/%ds",
               symbol, ticket, (int)(TimeCurrent() - open_time), cooldown_sec), EnableDebugLogs);
      return false;
   }

   datetime bar_time = (datetime)SeriesInfoInteger(symbol, MainTF, SERIES_LASTBAR_DATE);
   if(bar_time <= 0) return false;

   string count_key = RegimeExitCountKey(ticket);
   string bar_key = RegimeExitBarKey(ticket);
   int confirm_count = GlobalVariableCheck(count_key) ? (int)GlobalVariableGet(count_key) : 0;
   datetime last_bar = GlobalVariableCheck(bar_key) ? (datetime)GlobalVariableGet(bar_key) : 0;

   // ต้องพบสภาวะขัดแย้งติดต่อกันเป็นจำนวนแท่งเทียนที่กำหนด (RegimeExitConfirmBars)
   if(last_bar != bar_time)
   {
      confirm_count++;
      GlobalVariableSet(count_key, (double)confirm_count);
      GlobalVariableSet(bar_key, (double)bar_time);
   }

   int required_bars = MathMax(2, RegimeExitConfirmBars);
   if(confirm_count < required_bars)
   {
      static datetime last_log_bar = 0;
      static ulong last_log_ticket = 0;
      if(last_log_bar != bar_time || last_log_ticket != ticket)
      {
         LogInfo(StringFormat("Regime Exit pending [%s]: ticket=%I64u confirm=%d/%d",
                  symbol, ticket, confirm_count, required_bars));
         last_log_bar = bar_time;
         last_log_ticket = ticket;
      }
      return false;
   }

   return true;
}

/**
 * PositionCloseWithComment: ปิดออเดอร์พร้อมระบุคอมเมนต์เพื่อบันทึกสถิติ
 * @param ticket ตั๋วออเดอร์
 * @param comment ข้อความระบุเหตุผลการปิด
 * @return คืนค่า true หากส่งคำสั่งปิดสำเร็จ
 */
bool PositionCloseWithComment(const ulong ticket, const string comment)
{
   if(!PositionSelectByTicket(ticket)) return false;
   string symbol = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   
   request.action       = TRADE_ACTION_DEAL;
   request.position     = ticket;
   request.symbol       = symbol;
   request.volume       = volume;
   request.magic        = MagicNumber;
   request.comment      = comment;
   request.price        = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   request.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   
   // เลือกโหมด Filling ให้ตรงกับที่โบรกเกอร์กำหนด
   long fill_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fill_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) request.type_filling = ORDER_FILLING_IOC;
   else if((fill_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) request.type_filling = ORDER_FILLING_FOK;
   else request.type_filling = ORDER_FILLING_RETURN;

   if(!OrderSend(request, result))
   {
      LogError(StringFormat("CloseWithComment failed for ticket %I64u: %u", ticket, GetLastError()));
      IncrementPartialFailed();
      return false;
   }
   return (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED);
}

/**
 * SafeModifyPosition: แก้ไข SL/TP อย่างปลอดภัย พร้อมตรวจสอบกฎข้อบังคับของโบรกเกอร์
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param side ทิศทางออเดอร์
 * @param old_sl ราคา SL เดิม
 * @param old_tp ราคา TP เดิม
 * @param new_sl ราคา SL ใหม่
 * @param new_tp ราคา TP ใหม่
 * @param reason เหตุผลการแก้ไข
 * @return คืนค่า true หากส่งคำสั่งแก้ไขสำเร็จและผ่านการตรวจสอบกฎ Stops Level
 */
bool SafeModifyPosition(
   const ulong ticket,
   const string symbol,
   const ENUM_POSITION_TYPE side,
   const double old_sl,
   const double old_tp,
   double new_sl,
   double new_tp,
   const string reason)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   long stops_level_pts = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level_pts = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double stops_level = stops_level_pts * point;
   double freeze_level = freeze_level_pts * point;
   double ref_price = (side == POSITION_TYPE_BUY) ? bid : ask;

   new_sl = (new_sl == 0.0) ? 0.0 : NormalizePrice(symbol, new_sl);
   new_tp = (new_tp == 0.0) ? 0.0 : NormalizePrice(symbol, new_tp);

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = SymbolInfoDouble(symbol, SYMBOL_POINT);

   // ตรวจสอบว่าราคาใหม่มีความแตกต่างจากราคาเดิมอย่างมีนัยสำคัญหรือไม่
   bool sl_unchanged = (new_sl == 0.0 && old_sl == 0.0) || (new_sl != 0.0 && old_sl != 0.0 && MathAbs(new_sl - old_sl) < tick_size * 0.5);
   bool tp_unchanged = (new_tp == 0.0 && old_tp == 0.0) || (new_tp != 0.0 && old_tp != 0.0 && MathAbs(new_tp - old_tp) < tick_size * 0.5);
   if(sl_unchanged && tp_unchanged)
      return false;

   // ระบบป้องกันการส่งคำสั่งแก้ไขถี่เกินไป
   if(ShouldThrottleModify(ticket, symbol, old_sl, old_tp, new_sl, new_tp))
   {
      if(!EnableSilentThrottling)
         LogDebug(StringFormat("Modify throttled [%s]: ticket=%I64u reason=%s", symbol, ticket, reason), EnableDebugLogs);
      return false;
   }

   // ตรวจสอบระยะห่างขั้นต่ำจากราคาปัจจุบัน (Stops Level และ Freeze Level)
   if(new_sl != 0.0)
   {
      if(MathAbs(ref_price - new_sl) < stops_level || MathAbs(ref_price - new_sl) < freeze_level)
      {
         LogWarning(StringFormat(
            "Modify blocked [%s][%s]: oldSL=%.*f oldTP=%.*f newSL=%.*f newTP=%.*f bid=%.*f ask=%.*f stopsLevel=%ld freezeLevel=%ld reason=%s",
            symbol, (side == POSITION_TYPE_BUY ? "BUY" : "SELL"), digits, old_sl, digits, old_tp, digits, new_sl, digits, new_tp,
            digits, bid, digits, ask, stops_level_pts, freeze_level_pts, reason));
         return false;
      }
   }

   if(new_tp != 0.0)
   {
      if(MathAbs(ref_price - new_tp) < stops_level || MathAbs(ref_price - new_tp) < freeze_level)
      {
         LogWarning(StringFormat(
            "Modify blocked [%s][%s]: oldSL=%.*f oldTP=%.*f newSL=%.*f newTP=%.*f bid=%.*f ask=%.*f stopsLevel=%ld freezeLevel=%ld reason=%s",
            symbol, (side == POSITION_TYPE_BUY ? "BUY" : "SELL"), digits, old_sl, digits, old_tp, digits, new_sl, digits, new_tp,
            digits, bid, digits, ask, stops_level_pts, freeze_level_pts, reason));
         return false;
      }
   }

   // ดำเนินการส่งคำสั่งแก้ไขออเดอร์
   bool ok = pos_manager.PositionModify(ticket, new_sl, new_tp);
   uint retcode = pos_manager.ResultRetcode();
   string rettext = pos_manager.ResultRetcodeDescription();

   if(ok)
   {
      MarkModifySent(ticket, symbol);
      LogInfo(StringFormat("Modify success [%s][%s]: newSL=%.*f newTP=%.*f reason=%s", symbol, (side == POSITION_TYPE_BUY ? "BUY" : "SELL"), digits, new_sl, digits, new_tp, reason));
      return true;
   }

   LogWarning(StringFormat("Modify failed [%s][%s]: retcode=%u comment=%s reason=%s", symbol, (side == POSITION_TYPE_BUY ? "BUY" : "SELL"), retcode, rettext, reason));
   IncrementModifyFailed();
   return false;
}

/**
 * ShouldTimeoutExit: ตรวจสอบการปิดออเดอร์เนื่องจากถือครองนานเกินเวลาที่กำหนด
 * @param ticket ตั๋วออเดอร์
 * @param current_profit กำไรปัจจุบัน
 * @return คืนค่า true หากถือครองนานเกิน MaxHoldingMinutes และกำไรไม่ถึงเกณฑ์ที่จะถือต่อ
 */
bool ShouldTimeoutExit(const ulong ticket, const double current_profit)
{
   if(!PositionSelectByTicket(ticket)) return false;
   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
   int minutes_open = (int)((TimeCurrent() - open_time) / 60);

   if(minutes_open >= MaxHoldingMinutes && current_profit <= MinProfitForHold)
      return true;
   return false;
}

/**
 * ShouldVolatilityShockExit: ตรวจสอบความผันผวนของราคาที่รุนแรงผิดปกติ
 * @param symbol คู่เงิน
 * @param current_atr ค่า ATR ปัจจุบัน
 * @param median_atr ค่ากลางของ ATR ย้อนหลัง
 * @return คืนค่า true หากความผันผวนปัจจุบันพุ่งสูงเกินกว่าค่ากลางมาก (ตลาดเจอ Shock)
 */
bool ShouldVolatilityShockExit(const string symbol, const double current_atr, const double median_atr)
{
   if(median_atr > 0 && current_atr >= median_atr * VolatilityShockExitMult)
      return true;
   return false;
}

/**
 * EvaluateForcedExits: ประเมินเงื่อนไขการปิดออเดอร์แบบบังคับฉุกเฉิน
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param current_pnl กำไร/ขาดทุนปัจจุบัน
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluateForcedExits(ulong ticket, string symbol, const MarketSnapshot &snap, double current_pnl, ExitIntent &intent)
{
   // ตรวจสอบสภาวะ Shock ของตลาด
   if(ShouldVolatilityShockExit(symbol, snap.atr, snap.atr_median))
   {
      intent.action = EXIT_ACTION_CLOSE_FORCED;
      intent.priority = 100;
      intent.reason = "vol_shock_exit";
      intent.comment = "KNARES_VolShockExit";
      return;
   }
   // ตรวจสอบการถือครองนานเกินกำหนด
   if(ShouldTimeoutExit(ticket, current_pnl))
   {
      intent.action = EXIT_ACTION_CLOSE_FORCED;
      intent.priority = 95;
      intent.reason = "timeout_exit";
      intent.comment = "KNARES_TimeoutExit";
      return;
   }
}

/**
 * EvaluateRegimeExit: ประเมินการปิดออเดอร์เมื่อสภาวะตลาดเปลี่ยนทิศทาง
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์
 * @param regime สภาวะตลาดปัจจุบัน
 * @param open_time เวลาที่เปิดออเดอร์
 * @param profit_r กำไรปัจจุบันในหน่วย R
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluateRegimeExit(ulong ticket, string symbol, ENUM_POSITION_TYPE type, ENUM_REGIME_TYPE regime, datetime open_time, double profit_r, ExitIntent &intent)
{
   // ตรวจสอบสภาวะขัดแย้ง (เช่น ถือ Buy แต่ตลาดเป็น Trend Down)
   bool opposing_regime =
      (type == POSITION_TYPE_BUY && (regime == REGIME_TREND_DOWN || regime == REGIME_TRANSITION)) ||
      (type == POSITION_TYPE_SELL && (regime == REGIME_TREND_UP || regime == REGIME_TRANSITION));

   if(!opposing_regime)
   {
      ResetRegimeExitConfirmState(ticket);
      ResetConditionConfirm(ticket, "REGIME_LOSS_CUT");
      return;
   }

   // กรณีมีกำไร: ปิดเพื่อรักษากำไรทันทีที่ตลาดเปลี่ยนทิศทาง
   if(profit_r >= RegimeExitMinProfitR)
   {
      if(ShouldCloseByRegimeWithHysteresis(ticket, symbol, type, regime, open_time))
      {
         intent.action = EXIT_ACTION_CLOSE_REGIME;
         intent.priority = 90;
         intent.reason = "regime_exit_profit_protect";
         intent.comment = "KNARES_RegimeExitProfit";
         return;
      }
   }

   // กรณีขาดทุน: รอการยืนยันสัญญาณขัดแย้งหลายแท่งก่อนตัดสินใจตัดขาดทุน
   if(profit_r <= -RegimeExitLossCutR)
   {
      if(ConfirmConditionBars(ticket, "REGIME_LOSS_CUT", symbol, RegimeExitLossConfirmBars))
      {
         intent.action = EXIT_ACTION_CLOSE_REGIME;
         intent.priority = 80;
         intent.reason = "regime_exit_loss_cut";
         intent.comment = "KNARES_RegimeExitLoss";
         return;
      }
   }
}

/**
 * EvaluateEarlyInvalidation: ประเมินการปิดออเดอร์เมื่อสัญญาณเริ่มอ่อนแรง (เสียทรง)
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param regime สภาวะตลาดปัจจุบัน
 * @param profit_r กำไรปัจจุบันในหน่วย R
 * @param open_time เวลาที่เปิดออเดอร์
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluateEarlyInvalidation(ulong ticket, string symbol, ENUM_POSITION_TYPE type, const MarketSnapshot &snap, ENUM_REGIME_TYPE regime, double profit_r, datetime open_time, ExitIntent &intent)
{
   // ต้องถือออเดอร์มานานกว่าเกณฑ์ขั้นต่ำก่อนเริ่มตรวจจับ
   if(GetPositionAgeBars(symbol, MainTF, open_time) < TrendEarlyInvMinBarsOpen) return;
   
   // จะใช้เงื่อนไขนี้เฉพาะตอนออเดอร์ขาดทุน (เพื่อหนีออกจากไม้ที่สัญญาณเสียแล้ว)
   if(profit_r > -TrendEarlyInvMinLossR) {
      ResetConditionConfirm(ticket, "EARLYINV");
      return;
   }

   // ตรวจสอบความชันของ EMA (EMA Slope Reversal)
   bool slope_reversed = (type == POSITION_TYPE_BUY && snap.ema_slope <= -TrendEarlyInvSlopeThreshold) ||
                        (type == POSITION_TYPE_SELL && snap.ema_slope >= TrendEarlyInvSlopeThreshold);
   if(!slope_reversed) {
      ResetConditionConfirm(ticket, "EARLYINV");
      return;
   }

   // หากตั้งค่าให้ตรวจสอบ Regime ขัดแย้งด้วย
   if(TrendEarlyInvRequireOpposingRegime)
   {
      bool opposing = (type == POSITION_TYPE_BUY && (regime == REGIME_TREND_DOWN || regime == REGIME_TRANSITION)) ||
                      (type == POSITION_TYPE_SELL && (regime == REGIME_TREND_UP || regime == REGIME_TRANSITION));
      if(!opposing) {
         ResetConditionConfirm(ticket, "EARLYINV");
         return;
      }
   }

   // ยืนยันสัญญาณเสียทรงติดต่อกันตามจำนวนแท่งที่กำหนด
   if(ConfirmConditionBars(ticket, "EARLYINV", symbol, TrendEarlyInvConfirmBars))
   {
      intent.action = EXIT_ACTION_CLOSE_EARLYINV;
      intent.priority = 85;
      intent.reason = "early_invalidation";
      intent.comment = "KNARES_EarlyInvalidation";
   }
}

/**
 * EvaluateProfitLock: ระบบเลื่อน SL เพื่อล็อกกำไรแบบไดนามิก (Profit Locking)
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param pos_open ราคาเปิด
 * @param pos_sl ราคา SL ปัจจุบัน
 * @param pos_tp ราคา TP ปัจจุบัน
 * @param risk_dist ระยะความเสี่ยงเริ่มต้น
 * @param current_profit_dist ระยะกำไรปัจจุบัน
 * @param profit_r กำไรในหน่วย R
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluateProfitLock(ulong ticket, string symbol, ENUM_POSITION_TYPE type, const MarketSnapshot &snap, 
                        double pos_open, double pos_sl, double pos_tp, double risk_dist, double current_profit_dist, double profit_r,
                        ExitIntent &intent)
{
   if(risk_dist <= 0) return;
   if(IsPositionCooldownActive(ticket, "TRAILING")) return;

   double comm_buffer = CommissionBufferPoints * SymbolInfoDouble(symbol, SYMBOL_POINT);

   // เริ่มขยับ SL เมื่อกำไรถึงจุด Trigger (เช่น 1.25R)
   if(profit_r >= TrailingProfitTriggerR)
   {
      double target_lock_r = profit_r - TrailingProfitGapR;
      string trail_reason = "profit_lock";
      
      // Accelerated Trailing: เร่งการเลื่อน SL ให้แคบลงเมื่อกำไรพุ่งสูงขึ้นมากๆ
      if(EnableAcceleratedTrailing && profit_r >= AcceleratedTrailingProfitR)
      {
         target_lock_r = MathMax(target_lock_r, profit_r - AcceleratedTrailingGapR);
         trail_reason = "accel_trailing";
      }
      
      // ขยับเป็นขั้นๆ ตาม TrailingProfitLockStepR เพื่อไม่ให้ส่งคำสั่งถี่เกินไป
      if(TrailingProfitLockStepR > 0)
         target_lock_r = MathFloor(target_lock_r / TrailingProfitLockStepR) * TrailingProfitLockStepR;
      
      target_lock_r = MathMax(TrailingProfitLockMinR, MathMin(TrailingProfitLockMaxR, target_lock_r));

      double lock_level = (type == POSITION_TYPE_BUY) ? pos_open + (risk_dist * target_lock_r) + comm_buffer 
                                                      : pos_open - (risk_dist * target_lock_r) - comm_buffer;
      lock_level = NormalizePrice(symbol, lock_level);
      
      // เลื่อน SL ตามไปข้างหน้าเพื่อล็อกกำไรมากขึ้นเท่านั้น ไม่มีการเลื่อนถอยหลัง
      if((type == POSITION_TYPE_BUY && lock_level > pos_sl) || (type == POSITION_TYPE_SELL && (lock_level < pos_sl || pos_sl == 0)))
      {
         if(CheckLevels(symbol, (type == POSITION_TYPE_BUY ? snap.bid : snap.ask), lock_level, pos_tp))
         {
            if(intent.priority < 70) 
            {
               intent.action = EXIT_ACTION_MOD_PROFITLOCK;
               intent.priority = 70;
               intent.new_sl = lock_level;
               intent.new_tp = pos_tp;
               intent.reason = trail_reason;
            }
         }
      }
   }
}

/**
 * EvaluatePartialFallback: ระบบจัดการการแบ่งปิดกำไรหรือบังทุน
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param pos_open ราคาเปิด
 * @param pos_sl ราคา SL ปัจจุบัน
 * @param pos_tp ราคา TP ปัจจุบัน
 * @param risk_dist ระยะความเสี่ยงเริ่มต้น
 * @param current_profit_dist ระยะกำไรปัจจุบัน
 * @param pos_lots ขนาดลอตปัจจุบัน
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluatePartialFallback(ulong ticket, string symbol, ENUM_POSITION_TYPE type, const MarketSnapshot &snap,
                             double pos_open, double pos_sl, double pos_tp, double risk_dist, double current_profit_dist, double pos_lots,
                             ExitIntent &intent)
{
   if(!EnablePartialClose || HasPositionFlag(ticket, "PARTIAL_FALLBACK_DONE")) return;
   if(IsPositionCooldownActive(ticket, "PARTIAL_FALLBACK")) return;
   
   // ต้องมีกำไรถึงระดับที่กำหนด (PartialCloseLevelR)
   if(risk_dist <= 0 || current_profit_dist < risk_dist * PartialCloseLevelR) return;

   double close_lots = pos_lots * PartialCloseSizePct;
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   close_lots = MathFloor(close_lots / lot_step) * lot_step;
   
   // หากขนาดลอตที่คำนวณได้ ต่ำกว่าขั้นต่ำที่จะแบ่งปิดได้ ให้ใช้การ "ขยับ SL มาบังทุน (Breakeven)" แทน
   if(close_lots < PartialCloseMinLots || close_lots <= 0)
   {
      double lock_r = PartialFallbackLockR;
      if(EnableLotAwarePartialFallback)
      {
         if(pos_lots <= SmallLotThreshold) lock_r = SmallLotFallbackLockR;
         else lock_r = LargeLotFallbackLockR;
      }
      
      double comm_buffer = CommissionBufferPoints * SymbolInfoDouble(symbol, SYMBOL_POINT);
      double lock_sl = (type == POSITION_TYPE_BUY) ? (pos_open + (risk_dist * lock_r) + comm_buffer) : (pos_open - (risk_dist * lock_r) - comm_buffer);
      lock_sl = NormalizePrice(symbol, lock_sl);
      
      if(intent.priority < 60)
      {
         intent.action = EXIT_ACTION_MOD_PARTIAL;
         intent.priority = 60;
         intent.new_sl = lock_sl;
         intent.new_tp = pos_tp;
         intent.reason = "partial_fallback_lock";
         intent.comment = "FALLBACK";
      }
   }
   else
   {
      // มีขนาดลอตใหญ่พอที่จะแบ่งปิดได้จริง
      if(intent.priority < 80)
      {
         intent.action = EXIT_ACTION_MOD_PARTIAL;
         intent.priority = 80;
         intent.reason = "partial_close";
         intent.new_sl = pos_open; 
         intent.new_tp = pos_tp;
         intent.comment = "PARTIAL";
      }
   }
}

/**
 * EvaluateATRTrailing: ระบบเลื่อน SL ตามความผันผวนของราคา (ATR Trailing Stop)
 * @param ticket ตั๋วออเดอร์
 * @param symbol คู่เงิน
 * @param type ประเภทออเดอร์
 * @param snap ข้อมูลตลาดปัจจุบัน
 * @param pos_open ราคาเปิด
 * @param pos_sl ราคา SL ปัจจุบัน
 * @param pos_tp ราคา TP ปัจจุบัน
 * @param intent โครงสร้างผลการตัดสินใจ
 */
void EvaluateATRTrailing(ulong ticket, string symbol, ENUM_POSITION_TYPE type, const MarketSnapshot &snap,
                         double pos_open, double pos_sl, double pos_tp, ExitIntent &intent)
{
   if(!EnableTrailingStop || IsPositionCooldownActive(ticket, "TRAILING") || snap.atr <= 0) return;

   double trail_dist = snap.atr * ATRStopMultiple;
   double ts_sl = (type == POSITION_TYPE_BUY) ? NormalizePrice(symbol, snap.bid - trail_dist) 
                                              : NormalizePrice(symbol, snap.ask + trail_dist);
   
   // เริ่มใช้ระบบนี้เมื่อราคาวิ่งเข้าทางกำไรอย่างน้อย 1 ATR
   bool eligible = (type == POSITION_TYPE_BUY) ? (snap.bid > pos_open + snap.atr) : (snap.ask < pos_open - snap.atr);
   if(!eligible) return;

   // เลื่อน SL ตามราคาไปในทิศทางล็อกกำไรเท่านั้น
   if((type == POSITION_TYPE_BUY && ts_sl > pos_sl) || (type == POSITION_TYPE_SELL && (ts_sl < pos_sl || pos_sl == 0)))
   {
      if(intent.priority < 50)
      {
         intent.action = EXIT_ACTION_MOD_ATR_TRAIL;
         intent.priority = 50;
         intent.new_sl = ts_sl;
         intent.new_tp = pos_tp;
         intent.reason = "trailing_atr";
      }
   }
}

/**
 * ManagePositions: ฟังก์ชันศูนย์กลางในการดูแลและบริหารจัดการออเดอร์ทั้งหมด
 * @param features ข้อมูลตลาดปัจจุบัน
 * @param current_regime สภาวะตลาดปัจจุบัน
 * ทำการวนลูปตรวจสอบออเดอร์ที่มี Magic Number ของระบบ และประเมินเงื่อนไขการจัดการต่างๆ
 */
void ManagePositions(const MarketSnapshot &features, ENUM_REGIME_TYPE current_regime)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         // ตรวจสอบว่าเป็นออเดอร์ที่เปิดโดย EA ตัวนี้หรือไม่
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         double pos_sl = PositionGetDouble(POSITION_SL);
         double pos_tp = PositionGetDouble(POSITION_TP);
         double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double pos_lots = PositionGetDouble(POSITION_VOLUME);

         MarketSnapshot pos_snap;
         if(!GetMarketSnapshot(symbol, pos_snap) || !ComputeFeatures(symbol, pos_snap)) continue;

         double current_atr = pos_snap.atr;
         double risk_dist = MathAbs(pos_open - pos_sl);
         if(pos_sl == 0.0) risk_dist = current_atr * ATRStopMultiple;
         double current_profit_dist = (type == POSITION_TYPE_BUY) ? (pos_snap.bid - pos_open) : (pos_open - pos_snap.ask);
         double profit_r = (risk_dist > 0) ? (current_profit_dist / risk_dist) : 0;

         // --- ขั้นตอนการประเมินเหตุผลขาออก (Exit Arbitration) ---
         ExitIntent intent;
         intent.action = EXIT_ACTION_NONE;
         intent.priority = 0;
         
         // รวบรวมและคัดเลือกเหตุผลที่ความสำคัญสูงสุด (Winner Takes All)
         EvaluateForcedExits(ticket, symbol, pos_snap, PositionGetDouble(POSITION_PROFIT), intent);
         EvaluateRegimeExit(ticket, symbol, type, current_regime, (datetime)PositionGetInteger(POSITION_TIME), profit_r, intent);
         EvaluateEarlyInvalidation(ticket, symbol, type, pos_snap, current_regime, profit_r, (datetime)PositionGetInteger(POSITION_TIME), intent);
         EvaluatePartialFallback(ticket, symbol, type, pos_snap, pos_open, pos_sl, pos_tp, risk_dist, current_profit_dist, pos_lots, intent);
         EvaluateProfitLock(ticket, symbol, type, pos_snap, pos_open, pos_sl, pos_tp, risk_dist, current_profit_dist, profit_r, intent);
         EvaluateATRTrailing(ticket, symbol, type, pos_snap, pos_open, pos_sl, pos_tp, intent);

         if(intent.action != EXIT_ACTION_NONE && EnableDebugLogs)
         {
            LogInfo(StringFormat("ExitArbiter[%I64u]: winner=%s priority=%d reason=%s", 
                                 ticket, EnumToString(intent.action), intent.priority, intent.reason));
         }

         // --- ดำเนินการตามความตั้งใจที่ได้รับเลือก (Execution of Chosen Intent) ---
         bool processed = false;
         switch(intent.action)
         {
            case EXIT_ACTION_CLOSE_FORCED:
            case EXIT_ACTION_CLOSE_REGIME:
            case EXIT_ACTION_CLOSE_EARLYINV:
               // ดำเนินการปิดออเดอร์
               if(PositionCloseWithComment(ticket, intent.comment))
               {
                  if(intent.action == EXIT_ACTION_CLOSE_REGIME) { ResetRegimeExitConfirmState(ticket); RecordRegimeExitEvent(symbol); }
                  if(intent.action == EXIT_ACTION_CLOSE_EARLYINV) ResetConditionConfirm(ticket, "EARLYINV");
                  processed = true;
               }
               break;

            case EXIT_ACTION_MOD_PARTIAL:
               // ดำเนินการแบ่งปิดกำไรหรือขยับมาบังทุน
               if(intent.comment == "PARTIAL")
               {
                  double p_vol = pos_lots * PartialCloseSizePct;
                  double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
                  p_vol = MathFloor(p_vol / lot_step) * lot_step;
                  LogInfo(StringFormat("Partial Close triggered for %s: Closing %.2f of %.2f lots", symbol, p_vol, pos_lots));
                  if(pos_manager.PositionClosePartial(ticket, p_vol))
                  {
                     SafeModifyPosition(ticket, symbol, type, pos_sl, pos_tp, pos_open, pos_tp, "partial-close-breakeven");
                     processed = true;
                  }
                  else IncrementPartialFailed();
               }
               else // Fallback Lock (บวกคุ้มทุน)
               {
                  bool ok = SafeModifyPosition(ticket, symbol, type, pos_sl, pos_tp, intent.new_sl, intent.new_tp, intent.reason);
                  if(ok) SetPositionFlag(ticket, "PARTIAL_FALLBACK_DONE");
                  else SetPositionCooldown(ticket, "PARTIAL_FALLBACK", 60);
                  processed = ok;
               }
               break;

            case EXIT_ACTION_MOD_PROFITLOCK:
            case EXIT_ACTION_MOD_ATR_TRAIL:
               // ดำเนินการเลื่อน SL เพื่อล็อกกำไรหรือ Trailing Stop
            {
               bool ok = SafeModifyPosition(ticket, symbol, type, pos_sl, pos_tp, intent.new_sl, intent.new_tp, intent.reason);
               if(!ok) SetPositionCooldown(ticket, "TRAILING", 60);
               processed = ok;
               break;
            }
         }
         
         if(processed) continue;
      }
   }
}

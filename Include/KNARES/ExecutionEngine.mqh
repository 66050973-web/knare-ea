#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "Utils.mqh"
#include "AlgoExecution.mqh"
#include "PortfolioGovernor.mqh"
#include "TradeTracking.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Execution Engine - โมดูลหลักสำหรับการส่งคำสั่งซื้อขาย (Trade Execution) |
//| ทำหน้าที่: จัดการการส่งคำสั่งไปยังโบรกเกอร์, ควบคุม Slippage, แก้ไขปัญหา Retcode, |
//| และรองรับการแบ่งส่งออเดอร์ขนาดใหญ่ (Iceberg)                        |
//+------------------------------------------------------------------+
CTrade trade_manager; // ออบเจกต์หลักของ MQL5 Library สำหรับจัดการการเทรด (ส่งคำสั่ง, แก้ไข, ปิด)

// --- ตัวแปรสำหรับเก็บสถิติการทำงานของระบบส่งคำสั่ง (Execution Metrics) ---
int g_exec_fill_count = 0;           // จำนวนออเดอร์ที่เปิดสำเร็จ (Matched/Filled)
int g_exec_reject_count = 0;         // จำนวนออเดอร์ที่ไม่สำเร็จ (Rejected/Error)
int g_exec_policy_blocks = 0;        // ถูกระงับโดยนโยบายภายใน (เช่น Risk Engine สั่งห้ามเทรด)
int g_exec_spread_blocks = 0;        // ถูกระงับเพราะ Spread กว้างเกินกว่าที่รับได้ ณ ขณะนั้น
int g_exec_news_blocks = 0;          // ถูกระงับเพราะอยู่ในช่วงเวลาที่มีข่าวสำคัญ
int g_exec_safety_blocks = 0;        // ถูกระงับโดยระบบความปลอดภัย (เช่น Margin ไม่พอ หรือ Netting Account ห้ามสวนทาง)
int g_exec_ordercheck_failed = 0;    // ตรวจสอบคำสั่ง (OrderCheck) ไม่ผ่านก่อนส่งจริง
int g_exec_ordersend_failed = 0;     // ส่งคำสั่ง (OrderSend) ไปยังเซิร์ฟเวอร์แล้วล้มเหลว
int g_exec_broker_rejects = 0;       // โบรกเกอร์ปฏิเสธคำสั่ง (เช่น Invalid Volume, Market Closed)
int g_exec_modify_failed = 0;        // แก้ไขออเดอร์ (SL/TP) ไม่สำเร็จ
int g_exec_partial_failed = 0;       // ปิดออเดอร์บางส่วนไม่สำเร็จ

int g_exec_consecutive_rejects = 0;  // จำนวนครั้งที่ถูกปฏิเสธต่อเนื่องกัน
uint g_exec_last_retcode = 0;        // รหัสตอบกลับ (Return Code) ล่าสุดจากเซิร์ฟเวอร์โบรกเกอร์
double g_exec_slippage_points_sum = 0.0; // ผลรวมของ Slippage ทั้งหมดที่เกิดขึ้น (หน่วยเป็นจุด)
int g_exec_slippage_samples = 0;     // จำนวนครั้งที่นำมาคำนวณ Slippage

/**
 * ResetExecutionStats: ล้างค่าสถิติการส่งคำสั่งทั้งหมด
 * อธิบายกระบวนการ:
 * - รีเซ็ตตัวแปรนับจำนวน (Counter) ทั้งหมดให้เป็น 0
 * - ใช้เมื่อต้องการเริ่มนับสถิติใหม่ (เช่น เมื่อเริ่มวันใหม่ หรือรีสตาร์ท EA)
 */
void ResetExecutionStats()
{
   g_exec_fill_count = 0;
   g_exec_reject_count = 0;
   g_exec_policy_blocks = 0;
   g_exec_spread_blocks = 0;
   g_exec_news_blocks = 0;
   g_exec_safety_blocks = 0;
   g_exec_ordercheck_failed = 0;
   g_exec_ordersend_failed = 0;
   g_exec_broker_rejects = 0;
   g_exec_modify_failed = 0;
   g_exec_partial_failed = 0;
   g_exec_consecutive_rejects = 0;
   g_exec_last_retcode = 0;
   g_exec_slippage_points_sum = 0.0;
   g_exec_slippage_samples = 0;
}

// ฟังก์ชันกลุ่ม Getter สำหรับดึงค่าสถิติไปใช้ในการแสดงผลบนหน้าจอ Dashboard หรือรายงานผล
int GetExecutionFillCount() { return g_exec_fill_count; }
int GetExecutionRejectCount() { return g_exec_reject_count; }
int GetExecutionPolicyBlocks() { return g_exec_policy_blocks; }
int GetExecutionSpreadBlocks() { return g_exec_spread_blocks; }
int GetExecutionNewsBlocks() { return g_exec_news_blocks; }
int GetExecutionSafetyBlocks() { return g_exec_safety_blocks; }
int GetExecutionOrderCheckFailed() { return g_exec_ordercheck_failed; }
int GetExecutionOrderSendFailed() { return g_exec_ordersend_failed; }
int GetExecutionBrokerRejects() { return g_exec_broker_rejects; }
int GetExecutionModifyFailed() { return g_exec_modify_failed; }
int GetExecutionPartialFailed() { return g_exec_partial_failed; }
int GetExecutionRejectStreak() { return g_exec_consecutive_rejects; }
uint GetExecutionLastRetcode() { return g_exec_last_retcode; }

// ฟังก์ชันเพิ่มจำนวนครั้งที่เกิดความผิดพลาด (ใช้จากโมดูลอื่นๆ)
void IncrementModifyFailed() { g_exec_modify_failed++; }
void IncrementPartialFailed() { g_exec_partial_failed++; }

/**
 * GetExecutionAvgSlippagePoints: คำนวณค่า Slippage เฉลี่ย
 * อธิบายกระบวนการ:
 * - นำผลรวม Slippage หารด้วยจำนวนครั้งที่ส่งคำสั่งสำเร็จ
 * - คืนค่าเป็นจุด (Points) เพื่อให้ทราบว่าโบรกเกอร์ส่งคำสั่งได้ตรงตามราคาที่ขอหรือไม่
 */
double GetExecutionAvgSlippagePoints()
{
   return (g_exec_slippage_samples > 0) ? (g_exec_slippage_points_sum / g_exec_slippage_samples) : 0.0;
}

/**
 * IsHedgingAccount: ตรวจสอบโหมดบัญชี
 * อธิบายกระบวนการ:
 * - เช็คจาก Account Information ของ MQL5
 * - หากเป็น Retail Hedging จะสามารถเปิด Buy และ Sell ในคู่เงินเดียวกันพร้อมกันได้
 */
bool IsHedgingAccount()
{
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

/**
 * ExecutionInit: เริ่มต้นตั้งค่าระบบส่งคำสั่ง
 * อธิบายกระบวนการ:
 * 1. กำหนด Magic Number ให้กับ Trade Manager เพื่อแยกแยะออเดอร์ของ EA ตัวนี้
 * 2. ตั้งค่าโหมดการเติมออเดอร์ (Type Filling) ตามที่โบรกเกอร์กำหนด
 * 3. ตั้งค่า Deviation (ส่วนเบี่ยงเบนราคาที่ยอมรับได้) เริ่มต้นที่ 10 จุด
 * 4. ตรวจสอบโหมดบัญชี (Hedging/Netting) และบันทึกลง Log
 */
bool ExecutionInit()
{
   trade_manager.SetExpertMagicNumber(MagicNumber);
   trade_manager.SetTypeFillingBySymbol(_Symbol);
   // กำหนด Slippage ที่ยอมรับได้เบื้องต้น
   trade_manager.SetDeviationInPoints(100); 
   ResetExecutionStats();

   if(IsHedgingAccount())
      LogInfo("Execution Engine: Hedging account detected.");
   else
      LogInfo("Execution Engine: Netting account detected.");

   return true;
}

// --- ค่าคงที่ที่ใช้ในระบบการส่งคำสั่ง (Hard-coded Safety Guards) ---
const int MAX_RETRIES = 2;              // จำนวนครั้งที่อนุญาตให้ส่งซ้ำเมื่อเกิด Requote
const int RETRY_DELAY_MS = 1000;         // ระยะเวลารอระหว่างการส่งซ้ำ
#define MAX_EXEC_SPREAD_POINTS (RiskOffSpreadPoints) // Spread สูงสุดที่ยอมให้ส่งคำสั่งได้ (Points) ผูกกับ input RiskOffSpreadPoints
const int SYMBOL_SYNC_MAX_WAIT_MS = 2000;  // เวลารอสูงสุดในการ Sync ข้อมูลคู่เงิน
const int SYMBOL_SYNC_POLL_MS = 100;     // ความถี่ในการเช็คสถานะ Sync

/**
 * NormalizeVolumeBySymbol: ปรับขนาด Lot ให้ถูกต้องตามกฎของโบรกเกอร์
 * อธิบายกระบวนการ:
 * 1. ดึงข้อมูล Volume Min, Max และ Step จากเซิร์ฟเวอร์
 * 2. ตรวจสอบไม่ให้ต่ำกว่าขั้นต่ำ หรือสูงกว่าขั้นสูงสุด
 * 3. ปัดเศษ (MathFloor) ให้ลงตัวตาม Step (เช่น ทุกๆ 0.01)
 * 4. ทำ NormalizeDouble เพื่อป้องกันความผิดพลาดของเลขทศนิยม (Precision Error)
 */
double NormalizeVolumeBySymbol(const string symbol, const double requested_lots)
{
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0) vstep = 0.01;
   double lots = requested_lots;
   
   if(lots < vmin) lots = vmin;
   if(lots > vmax) lots = vmax;
   
   lots = MathFloor(lots / vstep) * vstep;
   int vol_digits = 2;
   if(vstep < 0.1) vol_digits = 3;
   if(vstep < 0.01) vol_digits = 4;
   lots = NormalizeDouble(lots, vol_digits);
   return lots;
}

/**
 * ResolveFillingMode: หาโหมดการเติมคำสั่งที่โบรกเกอร์รองรับ
 * อธิบายกระบวนการ:
 * - โบรกเกอร์แต่ละเจ้ามีกฎต่างกัน (IOC, FOK, RETURN)
 * - ฟังก์ชันนี้จะเช็ค Bitmask ของโบรกเกอร์และเลือกโหมดที่ดีที่สุดที่ใช้ได้
 */
ENUM_ORDER_TYPE_FILLING ResolveFillingMode(const string symbol)
{
   long fill_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fill_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((fill_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

/**
 * LogOrderCheckDetails: บันทึกข้อมูลการตรวจสอบคำสั่งอย่างละเอียด
 * อธิบายกระบวนการ:
 * - รวบรวมค่าปัจจุบัน (Bid, Ask, StopsLevel) และค่าที่ขอส่ง (Price, SL, TP)
 * - บันทึกลง Log เพื่อให้ Dev สามารถวิเคราะห์ได้ว่าทำไม OrderCheck ถึงล้มเหลว
 */
void LogOrderCheckDetails(const string stage,
                          const MqlTradeRequest &request,
                          const MqlTradeCheckResult &check_result,
                          const bool ok)
{
   int digits = (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS);
   if(digits < 0) digits = 5;
   double point = SymbolInfoDouble(request.symbol, SYMBOL_POINT);
   if(point <= 0.0) point = 0.00001;
   MqlTick tick;
   SymbolInfoTick(request.symbol, tick);
   int stops_level = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   string side = (request.type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   LogInfo(StringFormat(
      "OrderCheck %s: ok=%s symbol=%s side=%s type=%d filling=%d volume=%.3f price=%.*f sl=%.*f tp=%.*f bid=%.*f ask=%.*f stopsLevel=%d freezeLevel=%d retcode=%u comment=%s",
      stage,
      ok ? "true" : "false",
      request.symbol,
      side,
      (int)request.type,
      (int)request.type_filling,
      request.volume,
      digits, request.price,
      digits, request.sl,
      digits, request.tp,
      digits, tick.bid,
      digits, tick.ask,
      stops_level,
      freeze_level,
      check_result.retcode,
      check_result.comment
   ));
}

/**
 * SanitizeOrderRequest: "ทำความสะอาด" และเตรียมข้อมูลคำสั่งเทรด
 * อธิบายกระบวนการ:
 * 1. ปรับ Volume (Lot) ให้ถูกต้องตามกฎโบรกเกอร์
 * 2. ตรวจสอบและตั้งค่า Filling Mode
 * 3. ปรับราคา (Price) ให้ตรงกับราคาตลาดปัจจุบัน (Real-time Price Sync)
 * 4. ตรวจสอบกฎ SL/TP (Stops Level): หากตั้งใกล้ราคาปัจจุบันเกินไป จะขยับออกให้อัตโนมัติเพื่อป้องกัน "Invalid Stops"
 */
bool SanitizeOrderRequest(MqlTradeRequest &request)
{
   if(request.symbol == "") return false;

   MqlTick tick;
   if(!SymbolInfoTick(request.symbol, tick)) return false;

   int digits = (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS);
   if(digits < 0) digits = 5;
   double point = SymbolInfoDouble(request.symbol, SYMBOL_POINT);
   if(point <= 0.0) return false;

   // 1. ปรับขนาด Lot
   request.volume = NormalizeVolumeBySymbol(request.symbol, request.volume);
   if(request.volume <= 0.0) return false;

   // 2. หา Filling Mode
   request.type_filling = ResolveFillingMode(request.symbol);

   // 3. ปรับราคาเข้า
   const bool is_buy = (request.type == ORDER_TYPE_BUY);
   const double ref_price = is_buy ? tick.ask : tick.bid;
   request.price = NormalizeDouble(ref_price, digits);

   // 4. ตรวจสอบความปลอดภัยของ SL/TP (Stops Level Check)
   const int stops_level = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int freeze_level = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const int min_points = MathMax(stops_level, freeze_level);
   const double min_dist = (double)min_points * point;

   if(request.sl > 0.0)
   {
      double sl = request.sl;
      if(is_buy && (request.price - sl) < min_dist) sl = request.price - min_dist;
      if(!is_buy && (sl - request.price) < min_dist) sl = request.price + min_dist;
      request.sl = NormalizeDouble(sl, digits);
   }
   if(request.tp > 0.0)
   {
      double tp = request.tp;
      if(is_buy && (tp - request.price) < min_dist) tp = request.price + min_dist;
      if(!is_buy && (request.price - tp) < min_dist) tp = request.price - min_dist;
      request.tp = NormalizeDouble(tp, digits);
   }

   return true;
}

/**
 * WaitForSymbolReady: รอความพร้อมของข้อมูลคู่เงิน
 * อธิบายกระบวนการ:
 * - ในบางกรณี Terminal ยังเชื่อมต่อข้อมูลคู่เงินไม่เสร็จ (เช่น หลังเปิดเครื่องใหม่)
 * - ฟังก์ชันจะวนลูปเช็คสถานะ Synchronized จนกว่าจะพร้อม หรือจนกว่าจะหมดเวลา
 */
bool WaitForSymbolReady(const string symbol, const int timeout_ms = 2000)
{
   if(symbol == "") return false;
   if(!SymbolSelect(symbol, true)) return false;

   int waited = 0;
   while(waited <= timeout_ms)
   {
      if(SymbolIsSynchronized(symbol))
         return true;
      Sleep(SYMBOL_SYNC_POLL_MS);
      waited += SYMBOL_SYNC_POLL_MS;
   }

   LogWarning(StringFormat("Symbol sync timeout: %s waited=%dms", symbol, timeout_ms));
   return false;
}

/**
 * TryOrderCheckWithFillingFallback: ตรวจสอบความพร้อมของออเดอร์พร้อมระบบแก้ปัญหา Filling Mode
 * อธิบายกระบวนการ:
 * - พยายามทำ OrderCheck (จำลองการส่งคำสั่งเพื่อเช็ค Margin และ Error)
 * - หากโหมดปัจจุบันไม่ผ่าน ระบบจะลองวนโหมดอื่นๆ (IOC, FOK, RETURN) ให้โดยอัตโนมัติ
 * - ช่วยลดปัญหา EA ไม่เทรดเพราะตั้ง Filling Mode ผิด
 */
bool TryOrderCheckWithFillingFallback(MqlTradeRequest &request, MqlTradeCheckResult &check_result)
{
   ENUM_ORDER_TYPE_FILLING fill_candidates[4];
   fill_candidates[0] = request.type_filling;
   fill_candidates[1] = ORDER_FILLING_IOC;
   fill_candidates[2] = ORDER_FILLING_FOK;
   fill_candidates[3] = ORDER_FILLING_RETURN;

   for(int i = 0; i < 4; i++)
   {
      ENUM_ORDER_TYPE_FILLING f = fill_candidates[i];

      bool seen = false;
      for(int j = 0; j < i; j++)
      {
         if(fill_candidates[j] == f)
         {
            seen = true;
            break;
         }
      }
      if(seen) continue;

      request.type_filling = f;
      bool ok = OrderCheck(request, check_result);
      if(ok)
      {
         LogInfo(StringFormat("OrderCheck fallback passed with filling=%d", (int)f));
         return true;
      }
   }
   return false;
}

/**
 * IsRetriableRetcode: ตรวจสอบรหัสข้อผิดพลาดที่สามารถลองใหม่ได้
 * อธิบายกระบวนการ:
 * - คัดเลือก Retcode เช่น Requote, Price Changed, หรือ Too Many Requests
 * - คืนค่า true เพื่อบอกให้ระบบวน Loop ส่งคำสั่งใหม่อีกครั้ง
 */
bool IsRetriableRetcode(const uint retcode)
{
   return (retcode == TRADE_RETCODE_REQUOTE ||
           retcode == TRADE_RETCODE_PRICE_CHANGED ||
           retcode == TRADE_RETCODE_TOO_MANY_REQUESTS ||
           retcode == TRADE_RETCODE_LOCKED ||
           retcode == TRADE_RETCODE_CONNECTION);
}

/**
 * SendOrderWithRetry: ส่งคำสั่งเทรดพร้อมระบบวนส่งซ้ำเมื่อเกิดข้อผิดพลาดชั่วคราว
 * อธิบายกระบวนการ:
 * 1. วนลูปการส่งคำสั่งสูงสุดตามค่า MAX_RETRIES (2 ครั้ง)
 * 2. ตรวจสอบความพร้อมของราคา (Tick) และ Spread ก่อนการส่งแต่ละครั้ง
 * 3. หากส่งไม่สำเร็จและเป็นความผิดพลาดที่ "ลองใหม่ได้" (Retriable) จะหน่วงเวลา 1 วินาทีแล้วลองใหม่
 * 4. บันทึกผลลัพธ์และสถิติหลังจบกระบวนการ
 */
bool SendOrderWithRetry(const SignalPack &signal, const RiskDecision &risk)
{
   if(signal.symbol == "")
   {
      LogError("Execution blocked: empty symbol.");
      g_exec_last_retcode = 0;
      g_exec_reject_count++;
      g_exec_consecutive_rejects++;
      return false;
   }

   int attempt = 0;
   bool success = false;

   while(attempt <= MAX_RETRIES && !success)
   {
      MqlTick tick;
      if(!SymbolInfoTick(signal.symbol, tick))
      {
         LogWarning("Retry blocked: SymbolInfoTick unavailable for " + signal.symbol);
         break;
      }
      double point = SymbolInfoDouble(signal.symbol, SYMBOL_POINT);
      if(point <= 0) break;
      
      double current_spread = (tick.ask - tick.bid) / point;

      // ตรวจสอบ Spread หน้างานอีกครั้ง (Last-second spread guard)
      if(current_spread > MAX_EXEC_SPREAD_POINTS)
      {
         LogWarning(StringFormat("Retry blocked: Spread spike detected (%.1f points)", current_spread));
         g_exec_spread_blocks++;
         break;
      }

      success = SendOrder(signal, risk);
      if(success) break;

      uint retcode = trade_manager.ResultRetcode();
      g_exec_last_retcode = retcode;
      
      if(IsRetriableRetcode(retcode))
      {
         attempt++;
         if(attempt <= MAX_RETRIES)
         {
            LogWarning(StringFormat("Execution failed (Retcode %u). Retrying... Attempt %d/%d", retcode, attempt, MAX_RETRIES));
            Sleep(RETRY_DELAY_MS);
         }
         else g_exec_ordersend_failed++;
      }
      else
      {
         LogError(StringFormat("Critical Execution Retcode (%u). Aborting retries.", retcode));
         g_exec_ordersend_failed++;
         break;
      }
   }
   
   if(success)
   {
      g_exec_fill_count++;
      g_exec_consecutive_rejects = 0;
   }
   else
   {
      g_exec_reject_count++;
      g_exec_consecutive_rejects++;
   }
   return success;
}

/**
 * HardCloseAllPositions: คำสั่งปิดออเดอร์ทั้งหมด "ทันที"
 * อธิบายกระบวนการ:
 * - วนลูปปิดทุกออเดอร์ที่ถืออยู่ (เฉพาะ Magic Number ของ EA ตัวนี้)
 * - ใช้ในกรณีพอร์ตวิกฤต หรือเมื่อระบบสั่ง Shutdown
 */
void HardCloseAllPositions()
{
   LogWarning("HARD CLOSE ALL POSITIONS TRIGGERED!");
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            if(!trade_manager.PositionClose(ticket))
               LogError("Emergency close failed for ticket " + (string)ticket);
         }
      }
   }
}

/**
 * SendOrder: ฟังก์ชันแกนกลางสำหรับการเตรียมข้อมูลและส่งคำสั่ง
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบความปลอดภัยเบื้องต้น: Risk Allowed?, Lot > 0?, Symbol Ready?
 * 2. Iceberg Detection: หาก Lot ใหญ่เกิน (>= 2.0) จะส่งเข้าสู่ระบบ Iceberg Splitter แทนการเปิดไม้เดียว
 * 3. ตรวจสอบกฎบัญชีประเภท Netting: ห้ามเปิดสวนทางกับออเดอร์ที่มีอยู่
 * 4. เตรียม Request: ตั้งค่า Magic, Type, Price, SL, TP และ Filling Mode
 * 5. Sanitize & OrderCheck: ปรับแต่งค่าให้เป๊ะตามกฎเซิร์ฟเวอร์และเช็ค Margin
 * 6. ส่งคำสั่งจริง (Final Execution):
 *    - หากสำเร็จ: คำนวณ Slippage และ Latency บันทึกลงสถิติ
 *    - หากล้มเหลวเพราะ "Invalid Stops": จะสลับไปเปิดแบบ "Naked Entry" (ไม่มี SL/TP) แล้วตามไปแก้ SL/TP ภายหลังทันที
 */
bool SendOrder(const SignalPack &signal, const RiskDecision &risk)
{
   // --- ขั้นตอนที่ 1: การตรวจสอบเบื้องต้น (Pre-flight Execution Check) ---
   if(!risk.allowed) 
   {
      g_exec_policy_blocks++;
      return false;
   }
   if(signal.symbol == "" || !MathIsValidNumber(risk.lots) || risk.lots <= 0)
   {
      g_exec_policy_blocks++;
      return false;
   }
   if(!WaitForSymbolReady(signal.symbol))
   {
      g_exec_policy_blocks++;
      return false;
   }

   // --- ขั้นตอนที่ 2: ระบบจัดการออเดอร์ขนาดใหญ่ (Iceberg / Algo Trading) ---
   if(risk.lots >= 2.0 && DisableIcebergTemporarily)
   {
      LogWarning(StringFormat("Iceberg disabled: sending single parent order %.2f lots.", risk.lots));
   }
   else if(risk.lots >= 2.0)
   {
      // ป้องกันไม่ให้การเปิด Iceberg ทำให้ Exposure รวมเกินขีดจำกัด
      if(IsExposureNearLimit(signal.symbol, risk.lots, 0.85))
      {
         LogWarning("Iceberg soft-blocked: exposure too close to cap.");
         g_exec_safety_blocks++;
         return false;
      }
      LogInfo(StringFormat("High Volume Protection: Splitting %.2f lots into Iceberg slices.", risk.lots));
      // เรียกใช้โมดูล AlgoExecution เพื่อแบ่งออเดอร์เป็น 10 ไม้ย่อย
      bool created = CreateAlgoOrder(signal, risk, ALGO_ICEBERG, 10);
      return created;
   }

   // --- ขั้นตอนที่ 3: เตรียมราคาและตรวจสอบโหมดบัญชี ---
   ENUM_ORDER_TYPE order_type = (signal.direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   MqlTick tick;
   if(!SymbolInfoTick(signal.symbol, tick)) return false;
   double live_entry_price = (order_type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;

   // เตรียมระดับ SL/TP ตามทิศทางและราคาล่าสุด
   double prepared_sl = 0.0;
   double prepared_tp = 0.0;
   if(!PrepareStopsForEntry(signal.symbol, order_type, live_entry_price, signal.stop_price, signal.take_profit_price, prepared_sl, prepared_tp))
   {
      g_exec_policy_blocks++;
      return false;
   }
   
   // ซ่อน SL จากโบรกเกอร์ (Stealth Mode) หากตั้งค่าไว้
   if(!EnableStopLoss) prepared_sl = 0.0; 

   // ตรวจสอบกฎ Netting Account (ห้ามเทรดสองทาง)
   if(!IsHedgingAccount())
   {
      if(PositionSelect(signal.symbol))
      {
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if((signal.direction == SIGNAL_BUY && pos_type == POSITION_TYPE_SELL) ||
            (signal.direction == SIGNAL_SELL && pos_type == POSITION_TYPE_BUY))
         {
            LogWarning("Netting account: Opposite position exists. Blocking new order.");
            g_exec_safety_blocks++;
            return false;
         }
      }
   }

   // --- ขั้นตอนที่ 4: จัดเตรียมโครงสร้าง MqlTradeRequest ---
   MqlTradeRequest request = {};
   MqlTradeCheckResult check_result = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = signal.symbol;
   request.volume = risk.lots;
   request.type   = order_type;
   request.price  = live_entry_price;
   request.sl     = prepared_sl;
   request.tp     = prepared_tp;
   request.magic  = MagicNumber;
   request.deviation = 100;
   request.type_filling = ResolveFillingMode(signal.symbol);

   // ปรับปรุงราคาและขนาด Lot ให้เป็นมาตรฐาน
   if(!SanitizeOrderRequest(request)) return false;
   
   // ตรวจสอบ Margin ครั้งสุดท้ายก่อนส่ง
   uint start_tick = GetTickCount(); // เริ่มจับเวลา Latency
   bool check_ok = TryOrderCheckWithFillingFallback(request, check_result);
   if(!check_ok || check_result.margin_free < 0)
   {
      g_exec_ordercheck_failed++;
      return false;
   }

   // --- ขั้นตอนที่ 5: การส่งคำสั่งจริง (Final Order Send) ---
   bool res = false;
   string comment = "KNARES_" + signal.engine_name;
   trade_manager.SetTypeFilling(request.type_filling);
   
   if(signal.direction == SIGNAL_BUY)
      res = trade_manager.Buy(request.volume, signal.symbol, 0.0, request.sl, request.tp, comment);
   else if(signal.direction == SIGNAL_SELL)
      res = trade_manager.Sell(request.volume, signal.symbol, 0.0, request.sl, request.tp, comment);

   if(!res)
   {
      uint ret = trade_manager.ResultRetcode();
      g_exec_last_retcode = ret;
      
      // กรณีพิเศษ: โบรกเกอร์ไม่ยอมรับ SL/TP ในคำสั่งแรก (Invalid Stops)
      if(ret == TRADE_RETCODE_INVALID_STOPS)
      {
         LogWarning(StringFormat("OrderSend invalid stops [%s]: retrying naked entry then modify", signal.symbol));
         bool naked_ok = false;
         if(signal.direction == SIGNAL_BUY)
            naked_ok = trade_manager.Buy(request.volume, signal.symbol, 0.0, 0.0, 0.0, comment + "_NO_STOPS");
         else if(signal.direction == SIGNAL_SELL)
            naked_ok = trade_manager.Sell(request.volume, signal.symbol, 0.0, 0.0, 0.0, comment + "_NO_STOPS");

         if(naked_ok)
         {
            // แก้ไขออเดอร์ทันทีที่เปิดสำเร็จเพื่อใส่ SL/TP
            trade_manager.PositionModify(signal.symbol, prepared_sl, prepared_tp);
            ulong tkt = trade_manager.ResultOrder();
            if(tkt > 0) BindPositionSMC(tkt, signal);
            return true;
         }
         else g_exec_ordersend_failed++;
      }
      else
      {
         g_exec_broker_rejects++;
      }
   }
   else
   {
      // สำเร็จ: บันทึก Slippage และ Latency
      uint latency = GetTickCount() - start_tick;
      double result_price = trade_manager.ResultPrice();
      double point = SymbolInfoDouble(signal.symbol, SYMBOL_POINT);
      if(point > 0 && result_price > 0)
      {
         double slip_pts = MathAbs(result_price - live_entry_price) / point;
         g_exec_slippage_points_sum += slip_pts;
         g_exec_slippage_samples++;
      }
      ulong tkt = trade_manager.ResultOrder();
      if(tkt > 0) BindPositionSMC(tkt, signal);
      LogTrade(signal.symbol, "OPEN", true, StringFormat("Order filled. Latency: %d ms", latency));
   }
   return res;
}

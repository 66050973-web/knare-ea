#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Logger.mqh"
#include "Config.mqh"
#include "Utils.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Algo Execution Module - ประสิทธิภาพสูงสุด (Apex Stealth Logic)        |
//| ทำหน้าที่: ระบบส่งคำสั่งอัจฉริยะแบบพรางตัวเพื่อลดผลกระทบต่อตลาด (Iceberg/Stealth) |
//| ช่วยจัดการไม้ขนาดใหญ่โดยการแบ่งส่ง เพื่อเลี่ยงการตรวจจับและลด Slippage |
//+------------------------------------------------------------------+

// --- ตัวแปรส่วนกลางสำหรับระบบ Algo Execution ---
AlgoOrderState g_active_algo_orders[]; // อาเรย์เก็บสถานะของออเดอร์อัลกอรึทึมที่กำลังทำงานอยู่
CTrade g_algo_trade;                   // ออบเจกต์สำหรับการส่งคำสั่งเทรดภายในโมดูล

/**
 * FindLatestPositionTicket: ค้นหา Ticket ของออเดอร์ล่าสุดที่เปิดสำเร็จ
 * @param symbol ชื่อคู่เงินที่ต้องการค้นหา
 * @return คืนค่า ticket ล่าสุดที่พบ หรือ 0 หากไม่พบ
 * 
 * ฟังก์ชันนี้มีไว้เพื่อติดตามออเดอร์ย่อยที่เพิ่งถูกส่งเข้าไปในตลาด 
 * เพื่อนำมาแก้ไข SL/TP ในกรณีที่ระบบปกติส่งไม่ได้ (เช่น กรณีที่ส่งแบบไม่มี Stop เข้าไปก่อน)
 */
ulong FindLatestPositionTicket(const string symbol)
{
   ulong best_ticket = 0;
   long best_time = -1;
   
   // วนลูปหาออเดอร์ที่เปิดอยู่ทั้งหมดเพื่อหาอันล่าสุด
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
         
      // ตรวจสอบ Magic Number เพื่อให้แน่ใจว่าเป็นออเดอร์จาก EA ตัวนี้
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;
         
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
         
      // เปรียบเทียบเวลาที่เปิดออเดอร์ (หน่วยมิลลิวินาที) เพื่อหาไม้ล่าสุด
      long t = PositionGetInteger(POSITION_TIME_MSC);
      if(t > best_time)
      {
         best_time = t;
         best_ticket = ticket;
      }
   }
   return best_ticket;
}

/**
 * HasActiveAlgoOrder: ตรวจสอบสถานะการทำงานของอัลกอริทึม
 * @param symbol คู่เงินที่ต้องการตรวจสอบ
 * @return คืนค่า true หากมีแผนการส่งคำสั่งพรางตัวที่ยังทำงานไม่จบสำหรับคู่เงินนี้
 * 
 * ใช้เพื่อป้องกันไม่ให้มีการสร้างแผนส่งคำสั่งซ้ำซ้อนกันในคู่เงินเดียว
 */
bool HasActiveAlgoOrder(const string symbol)
{
   for(int i = 0; i < ArraySize(g_active_algo_orders); i++)
   {
      // ตรวจสอบว่ามีออเดอร์ที่ยัง IsActive อยู่และเป็นคู่เงินที่ระบุหรือไม่
      if(g_active_algo_orders[i].is_active && g_active_algo_orders[i].symbol == symbol)
         return true;
   }
   return false;
}

/**
 * CreateAlgoOrder: เริ่มต้นสร้างแผนการส่งออเดอร์อัจฉริยะ (Iceberg/Stealth)
 * @param signal ข้อมูลสัญญาณเทรดที่ได้จากระบบวิเคราะห์
 * @param risk ข้อมูลขนาดลอตรวมและความเสี่ยงที่คำนวณมาแล้ว
 * @param type ประเภทอัลกอริทึมที่จะใช้ (เช่น Iceberg)
 * @param slices จำนวนไม้ย่อยที่จะทำการแบ่ง (เพื่อพรางขนาดจริง)
 * @return คืนค่า true หากสร้างแผนสำเร็จ
 * 
 * ฟังก์ชันนี้จะรับสัญญาณและขนาดลอตมา แล้วทำการคำนวณแบ่งเป็นไม้ย่อยๆ 
 * เพื่อทยอยส่งเข้าตลาดแทนการส่งไม้เดียวขนาดใหญ่
 */
bool CreateAlgoOrder(const SignalPack &signal, const RiskDecision &risk, ENUM_ALGO_TYPE type, int slices)
{
   // ตรวจสอบเงื่อนไขเบื้องต้น: ต้องแบ่งอย่างน้อย 2 ไม้ขึ้นไป
   if(slices <= 1) return false; 
   if(signal.symbol == "")
   {
      LogWarning("Apex Algo skipped: empty symbol.");
      return false;
   }
   
   // ป้องกันการสร้างออเดอร์อัลกอริทึมซ้ำซ้อนในคู่เงินเดียวกัน
   if(HasActiveAlgoOrder(signal.symbol))
   {
      LogInfo("Apex Algo skipped: active iceberg already exists for " + signal.symbol);
      return false;
   }

   // ขยายอาเรย์เพื่อเก็บสถานะออเดอร์ใหม่
   int size = ArraySize(g_active_algo_orders);
   ArrayResize(g_active_algo_orders, size + 1);
   
   // บันทึกรายละเอียดแผนการส่งคำสั่งแบบพรางตัว (Stealth Execution Plan)
   g_active_algo_orders[size].symbol = signal.symbol;
   g_active_algo_orders[size].direction = signal.direction;
   g_active_algo_orders[size].type = type;
   g_active_algo_orders[size].total_lots = risk.lots;
   g_active_algo_orders[size].remaining_lots = risk.lots;
   g_active_algo_orders[size].filled_lots = 0;
   
   // คำนวณขนาดลอตต่อหนึ่งไม้ย่อย (จะมีการสุ่มเพิ่ม/ลดในภายหลังเพื่อให้ไม่เท่ากันเป๊ะ)
   g_active_algo_orders[size].slice_lots = risk.lots / slices; 
   
   g_active_algo_orders[size].sl = signal.stop_price;
   g_active_algo_orders[size].tp = signal.take_profit_price;
   
   // บันทึกระยะห่างของ SL/TP จากราคาเข้า
   g_active_algo_orders[size].stop_distance = MathAbs(signal.entry_price - signal.stop_price);
   g_active_algo_orders[size].tp_distance = MathAbs(signal.take_profit_price - signal.entry_price);
   
   g_active_algo_orders[size].limit_price = signal.entry_price;
   g_active_algo_orders[size].max_slippage_points = 2.0; 
   g_active_algo_orders[size].total_slices = slices;
   g_active_algo_orders[size].filled_slices = 0;
   g_active_algo_orders[size].is_active = true;
   
   // กำหนดเวลาเริ่มทำงานทันที
   g_active_algo_orders[size].next_execution = TimeCurrent();
   g_active_algo_orders[size].random_seed = (int)GetTickCount();
   g_active_algo_orders[size].invalid_stops_streak = 0;
   g_active_algo_orders[size].cooldown_until = 0;

   LogInfo(StringFormat("Apex Algo Created [%s][%s]: Stealth mode activated for %.2f lots.",
                        EnumToString(type), signal.symbol, risk.lots));
   return true;
}

/**
 * ProcessAlgoOrders: ลอจิกหลักในการประมวลผลและทยอยส่งไม้ย่อยเข้าสู่ตลาด
 * 
 * ฟังก์ชันนี้ควรถูกเรียกใช้งานสม่ำเสมอใน OnTick
 * มีระบบสุ่มขนาดและสุ่มเวลาเพื่อพรางพฤติกรรมการเทรดจากการตรวจจับ (Anti-Pattern Matching)
 */
void ProcessAlgoOrders()
{
   for(int i = ArraySize(g_active_algo_orders) - 1; i >= 0; i--)
   {
      // ข้ามออเดอร์ที่ทำงานจบไปแล้ว
      if(!g_active_algo_orders[i].is_active) continue;
      
      // ตรวจสอบ Cooldown หากโบรกเกอร์ปฏิเสธคำสั่งบ่อยเกินไป (ป้องกันการย้ำส่งที่ผิดพลาดจนโดนแบน)
      if(TimeCurrent() < g_active_algo_orders[i].cooldown_until) continue;

      // 1. ตรวจสอบเงื่อนไขเวลาในการส่งไม้ถัดไป (ระบบหน่วงเวลาแบบสุ่ม)
      if(TimeCurrent() < g_active_algo_orders[i].next_execution) continue;

      // 2. Slippage Guard: ตรวจสอบราคาปัจจุบันว่ายังอยู่ในโซนราคาที่ยอมรับได้หรือไม่
      double current_price = SymbolInfoDouble(g_active_algo_orders[i].symbol, 
         (g_active_algo_orders[i].direction == SIGNAL_BUY) ? SYMBOL_ASK : SYMBOL_BID);
      
      // คำนวณส่วนต่างราคาปัจจุบันกับราคาที่ต้องการ (หน่วย Point)
      double deviation = MathAbs(current_price - g_active_algo_orders[i].limit_price) / SymbolInfoDouble(g_active_algo_orders[i].symbol, SYMBOL_POINT);
      
      // หากราคาเคลื่อนที่ห่างจากจุดเข้าเกินไป (Slip เกินเกณฑ์) จะพักการส่งไม้ย่อยนั้นไว้ก่อน
      if(deviation > 10.0) 
      {
         g_active_algo_orders[i].next_execution = TimeCurrent() + 5; 
         continue;
      }

      // 3. Randomized Slicing: สุ่มขนาดของไม้ย่อย (80% - 120%) 
      // เพื่อให้ขนาดไม้ดูเหมือนการเทรดโดยมนุษย์ ไม่ให้มีขนาดที่เท่ากันเป๊ะทุกไม้จนเป็นจุดสังเกต
      MathSrand(g_active_algo_orders[i].random_seed + i);
      double noise = 0.8 + ((double)MathRand() / 32767.0) * 0.4; 
      double lots_to_trade = NormalizeLot(g_active_algo_orders[i].symbol, g_active_algo_orders[i].slice_lots * noise);
      
      // ตรวจสอบไม่ให้เทรดเกินกว่าจำนวนลอตที่เหลืออยู่ทั้งหมด
      lots_to_trade = MathMin(lots_to_trade, g_active_algo_orders[i].remaining_lots);

      // หากคำนวณแล้วไม่มีลอตเหลือพอจะเทรด ให้จบงาน
      if(lots_to_trade <= 0) 
      {
         g_active_algo_orders[i].is_active = false;
         continue;
      }

      // 4. จัดเตรียม MqlTradeRequest สำหรับส่งไม้ย่อยเข้าตลาด
      MqlTradeRequest request = {};
      MqlTradeResult  result = {};
      request.action = TRADE_ACTION_DEAL;
      request.symbol = g_active_algo_orders[i].symbol;
      request.volume = lots_to_trade;
      request.type   = (g_active_algo_orders[i].direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.magic  = MagicNumber;
      request.price  = current_price;
      
      // คำนวณราคา Stop Loss และ Take Profit โดยอ้างอิงจากระยะห่างที่จดบันทึกไว้
      double raw_sl = 0.0;
      double raw_tp = 0.0;
      if(request.type == ORDER_TYPE_BUY)
      {
         raw_sl = request.price - g_active_algo_orders[i].stop_distance;
         raw_tp = request.price + g_active_algo_orders[i].tp_distance;
      }
      else
      {
         raw_sl = request.price + g_active_algo_orders[i].stop_distance;
         raw_tp = request.price - g_active_algo_orders[i].tp_distance;
      }

      double prepared_sl = 0.0;
      double prepared_tp = 0.0;
      
      // ตรวจสอบกฎการวางจุด Stop ของโบรกเกอร์ (Stops Level) เพื่อไม่ให้คำสั่งถูกปฏิเสธ
      if(!PrepareStopsForEntry(request.symbol, request.type, request.price, raw_sl, raw_tp, prepared_sl, prepared_tp))
      {
         LogWarning(StringFormat("Stealth Slice blocked by stop-distance guard: Symbol=%s Lots=%.2f Entry=%.5f",
                    request.symbol, lots_to_trade, request.price));
         // หากติดกฎเรื่องระยะหยุด ให้หน่วงเวลารอกระบวนการตัดสินใจรอบหน้า
         g_active_algo_orders[i].next_execution = TimeCurrent() + 5;
         continue;
      }
      
      // หากมีการปิดระบบ Stop Loss ใน Config ให้เซตเป็น 0
      if(!EnableStopLoss) prepared_sl = 0.0; 

      request.sl     = prepared_sl;
      request.tp     = prepared_tp;
      request.comment = "KNARES_STEALTH_" + IntegerToString(i);

      // 5. ดำเนินการส่งคำสั่งไม้ย่อยไปยังตลาดจริง
      bool sent = OrderSend(request, result);
      
      // ตรวจสอบผลการส่งว่าสำเร็จหรือไม่ (Done / Partial Done / Placed)
      bool filled = sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED);

      // Fallback Strategy: กรณีโบรกเกอร์ปฏิเสธเพราะจุด SL/TP ไม่ถูกต้อง (เช่น ราคาเคลื่อนที่กะทันหันขณะส่ง)
      // กลยุทธ์คือส่งไม้แบบ "ไม่มี SL/TP" เข้าไปก่อน เพื่อให้จับคู่ราคาได้ทันที แล้วค่อยตามไปแก้ (Modify) SL/TP ทีหลัง
      if(!filled && result.retcode == TRADE_RETCODE_INVALID_STOPS)
      {
         MqlTradeRequest fallback = request;
         MqlTradeResult fallback_result = {};
         fallback.sl = 0.0;
         fallback.tp = 0.0;
         bool fallback_sent = OrderSend(fallback, fallback_result);
         bool fallback_filled = fallback_sent && (fallback_result.retcode == TRADE_RETCODE_DONE || fallback_result.retcode == TRADE_RETCODE_DONE_PARTIAL || fallback_result.retcode == TRADE_RETCODE_PLACED);
         if(fallback_filled)
         {
            // หา Ticket ของไม้ที่เพิ่งเปิดสำเร็จ แล้วส่งคำสั่งแก้ไข SL/TP ตามไป
            ulong ticket = FindLatestPositionTicket(request.symbol);
            if(ticket > 0)
            {
               g_algo_trade.PositionModify(ticket, prepared_sl, prepared_tp);
            }
            result = fallback_result;
            filled = true;
            LogInfo(StringFormat("Stealth Slice fallback filled (no SL/TP first): Symbol=%s Lots=%.2f Retcode=%u",
                                 request.symbol, lots_to_trade, fallback_result.retcode));
         }
      }
      
      if(filled)
      {
         // อัปเดตสถิติและความคืบหน้าของออเดอร์เมื่อส่งสำเร็จ
         g_active_algo_orders[i].filled_lots += lots_to_trade;
         g_active_algo_orders[i].remaining_lots -= lots_to_trade;
         g_active_algo_orders[i].filled_slices++;
         g_active_algo_orders[i].invalid_stops_streak = 0;
         
         // สุ่มหน่วงเวลาระหว่างไม้ (5-25 วินาที) เพื่อทำลายรูปแบบเวลาที่สม่ำเสมอเกินไป 
         // ป้องกันการถูกอัลกอริทึมฝั่งตรงข้ามตรวจจับพฤติกรรม (Anti-Detection)
         int delay = 5 + (MathRand() % 20); 
         g_active_algo_orders[i].next_execution = TimeCurrent() + delay; 
         
         LogInfo(StringFormat("Stealth Slice Filled: %.2f lots. Remaining: %.2f (Delay: %ds, Retcode=%u)", 
            lots_to_trade, g_active_algo_orders[i].remaining_lots, delay, result.retcode));
      }
      else
      {
         // กรณีส่งไม่สำเร็จ (Rejected)
         LogWarning(StringFormat("Stealth Slice Rejected: Symbol=%s Lots=%.2f Retcode=%u Comment=%s",
                    request.symbol, lots_to_trade, result.retcode, result.comment));
         
         // หากโดนปฏิเสธเรื่อง SL/TP ซ้ำๆ ติดกัน 3 ครั้ง (เช่น ตลาดผันผวนรุนแรงจนตั้งจุดไม่ได้) 
         // ให้สั่งออเดอร์นี้เข้าโหมดพักรอดูสถานการณ์ 1 นาที (Cooldown)
         if(result.retcode == TRADE_RETCODE_INVALID_STOPS)
         {
            g_active_algo_orders[i].invalid_stops_streak++;
            if(g_active_algo_orders[i].invalid_stops_streak >= 3)
            {
               int cool_sec = 60 + (MathRand() % 61);
               g_active_algo_orders[i].cooldown_until = TimeCurrent() + cool_sec;
               g_active_algo_orders[i].invalid_stops_streak = 0;
               LogWarning(StringFormat("Stealth Slice cooldown: Symbol=%s paused %ds after repeated invalid stops",
                                        request.symbol, cool_sec));
            }
         }
         // หน่วงเวลารอจังหวะราคาใหม่ 5 วินาที
         g_active_algo_orders[i].next_execution = TimeCurrent() + 5;
      }

      // ตรวจสอบว่าจำนวนลอตรวมทั้งหมดถูกส่งเข้าตลาดจนครบถ้วนตามแผนแล้วหรือไม่
      if(g_active_algo_orders[i].remaining_lots <= 0)
      {
         g_active_algo_orders[i].is_active = false;
         LogInfo("Apex Stealth Execution Completed Successfully.");
      }
   }
}

/**
 * NormalizeLot: ปรับขนาด Lot ให้ถูกต้องตามกฎระเบียบของแต่ละโบรกเกอร์
 * @param symbol คู่เงิน
 * @param lots ขนาดลอตที่ต้องการส่ง
 * @return ขนาดลอตที่ผ่านการปัดเศษและตรวจสอบขั้นต่ำตามที่โบรกเกอร์ยอมรับ
 * 
 * ใช้เพื่อป้องกัน Error "Invalid Volume" โดยการปัดเศษตามค่า Volume Step 
 * และตรวจสอบว่าต้องไม่ต่ำกว่า Volume Minimum
 */
double NormalizeLot(string symbol, double lots)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   
   // ปัดเศษลงตามขั้นของปริมาณที่โบรกเกอร์กำหนด
   double res = MathFloor(lots / step) * step;
   
   // บังคับให้ไม่ต่ำกว่าค่าลอตขั้นต่ำสุด
   return MathMax(res, min_lot);
}

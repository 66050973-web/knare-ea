#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Risk Engine - โมดูลคำนวณความเสี่ยงและขนาดลอต (Risk Management)      |
//| ทำหน้าที่: ประเมินความเสี่ยงต่อไม้, คำนวณ Lot Size ตามกฎ Money Management |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชันหลักในการประเมินความเสี่ยงและคำนวณขนาดลอตสำหรับการเทรด
 * ทำหน้าที่ตรวจสอบความถูกต้องของสัญลักษณ์, คำนวณระยะ Stop Loss, ปรับความเสี่ยงตามสถิติการเทรด,
 * และตรวจสอบข้อจำกัดของโบรกเกอร์เพื่อให้ได้ขนาดลอตที่ปลอดภัยที่สุด
 * 
 * @param signal ข้อมูลสัญญาณเทรดที่ได้รับจาก Signal Engine
 * @param features ข้อมูลสแนปช็อตตลาดปัจจุบัน
 * @param decision โครงสร้างข้อมูลสำหรับเก็บผลการตัดสินใจด้านความเสี่ยง (Output)
 * @return true หากคำนวณสำเร็จและอนุญาตให้เทรด, false หากผิดพลาดหรือไม่อนุญาต
 */
bool EvaluateRisk(const SignalPack &signal, const MarketSnapshot &features, RiskDecision &decision)
{
   // กำหนดค่าเริ่มต้นให้กับโครงสร้างการตัดสินใจ เพื่อความปลอดภัยหากฟังก์ชันจบการทำงานก่อนกำหนด
   decision.allowed = false;
   decision.lots = 0.0;
   decision.risk_money = 0.0;
   decision.expected_loss = 0.0;
   decision.reason = "init";

   // 1. ตรวจสอบความถูกต้องของสัญลักษณ์ (Symbol Verification)
   // หากไม่มีการระบุชื่อคู่เงิน จะไม่อนุญาตให้เปิดเทรด
   if(signal.symbol == "")
   {
      decision.reason = "Empty symbol";
      return false;
   }

   // ตรวจสอบว่าสัญลักษณ์นี้พร้อมใช้งานในระบบ และทำการเลือกเข้า Market Watch อัตโนมัติ
   if(!SymbolSelect(signal.symbol, true))
   {
      decision.reason = "SymbolSelect failed";
      return false;
   }
   
   // 2. คำนวณระยะห่างของจุดหยุดขาดทุน (Stop Loss Distance Calculation)
   // คำนวณระยะห่างระหว่างราคาเข้าและจุด SL เพื่อหาความเสี่ยงในเชิงราคา
   double stop_distance = MathAbs(signal.entry_price - signal.stop_price);
   if(stop_distance <= 0 || !MathIsValidNumber(stop_distance))
   {
      decision.reason = "Invalid stop distance";
      return false;
   }
   // ดึงค่า Point ของสัญลักษณ์ (เช่น 0.00001 สำหรับคู่เงิน 5 ตำแหน่ง)
   double point = SymbolInfoDouble(signal.symbol, SYMBOL_POINT);
   
   // Phase 23: การควบคุมระยะ Stop ขั้นต่ำแยกตามกลยุทธ์ (Engine-specific Stop Floor)
   // ป้องกันการตั้ง SL แคบเกินไปซึ่งมักเกิดจากความผันผวนชั่วคราว (Noise)
   int engine_min_points = MinStopDistancePoints;
   if(signal.engine_name == "BreakoutEngine") engine_min_points = BreakoutMinStopDistancePoints;
   else if(signal.engine_name == "TrendEngine") engine_min_points = TrendMinStopDistancePoints;
   else if(signal.engine_name == "MeanRevEngine") engine_min_points = MeanRevMinStopDistancePoints;

   // คำนวณระยะหยุดขั้นต่ำในเชิงราคา
   double min_stop_distance = MathMax(0, engine_min_points) * point;
   if(point > 0 && min_stop_distance > 0 && stop_distance < min_stop_distance)
   {
      // หากระยะ SL ที่คำนวณได้แคบกว่าเกณฑ์ความปลอดภัย ให้ปรับเพิ่มเป็นเกณฑ์ขั้นต่ำ
      stop_distance = min_stop_distance;
      LogWarning(StringFormat("Risk clamp [%s][%s]: stop_distance raised to min floor %.1f points",
                              signal.symbol, signal.engine_name, (double)engine_min_points));
   }

   // 3. คำนวณความเสี่ยงพื้นฐาน (Base Risk Calculation)
   // ใช้มูลค่า Equity ของพอร์ตเป็นฐาน (คำนึงถึงออเดอร์ที่ค้างอยู่ด้วย)
   double balance = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0 || !MathIsValidNumber(balance))
   {
      decision.reason = "Invalid account equity";
      return false;
   }

   // ดึงค่าเปอร์เซ็นต์ความเสี่ยงต่อไม้จากไฟล์ตั้งค่า
   double risk_pct = RiskPerTradePct;
   if(!MathIsValidNumber(risk_pct) || risk_pct <= 0)
   {
      decision.reason = "Invalid RiskPerTradePct";
      return false;
   }
   // กฎเหล็กความปลอดภัย: จำกัดความเสี่ยงสูงสุดไม่ให้เกิน 2% ของพอร์ตต่อหนึ่งออเดอร์
   risk_pct = MathMin(risk_pct, 0.02);

   // 4. ระบบปรับความเสี่ยงอัตโนมัติ (Dynamic Risk Scaling)
   // ตรวจสอบว่าระบบเปิดใช้งานการลดความเสี่ยงเมื่อเกิดการแพ้ต่อเนื่องหรือไม่
   if(EnableDynamicRisk)
   {
      // หากสถิติปัจจุบันพบว่ามีการแพ้เกินขีดจำกัด ให้ทำการลดความเสี่ยงลงตามสัดส่วนที่กำหนด
      if(current_metrics.loss_trades > LossStreakLimit) 
      {
         risk_pct *= RiskReductionFactor; // ตัวคูณลดความเสี่ยง (เช่น 0.5 คือลดลงครึ่งหนึ่ง)
         LogWarning(StringFormat("Dynamic Risk: High loss streak detected. Reducing risk to %.2f%%", risk_pct * 100.0));
      }
   }

   // คำนวณจำนวนเงินจริงที่จะใช้เสี่ยงในไม้นี้
   double risk_money = balance * risk_pct; 
   if(!MathIsValidNumber(risk_money) || risk_money <= 0)
   {
      decision.reason = "Invalid risk money";
      return false;
   }
   
   // 5. ดึงข้อมูลคุณสมบัติสัญญาของสัญลักษณ์ (Symbol Contract Specifications)
   // ตรวจสอบมูลค่าต่อหนึ่ง Tick เพื่อแปลงเป็นจำนวนเงินได้อย่างถูกต้อง
   double tick_value = SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_value <= 0 || tick_size <= 0)
   {
      decision.reason = "Invalid tick value/size";
      return false;
   }

   // ตรวจสอบกฎการวาง Lot ของสัญลักษณ์นั้นๆ (Step, Min, Max)
   double lot_step = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MAX);
   if(lot_step <= 0 || min_lot <= 0 || max_lot <= 0)
   {
      decision.reason = "Invalid symbol volume constraints";
      return false;
   }

   // 6. การคำนวณขนาดลอตจริง (Lot Size Determination)
   // ประเมินว่าหากถือ 1 ลอตแล้วโดน SL จะเสียเงินเท่าไหร่
   double loss_per_lot = stop_distance * tick_value / tick_size;
   if(loss_per_lot <= 0 || !MathIsValidNumber(loss_per_lot))
   {
      decision.reason = "Invalid loss-per-lot";
      return false;
   }

   double lots = 0;
   // เลือกระหว่างการใช้ Lot คงที่ หรือคำนวณตามความเสี่ยงที่ตั้งไว้
   if(LotMode == LOT_FIXED)
   {
      lots = FixedLotSize; 
      risk_money = FixedLotSize * loss_per_lot; // อัปเดตมูลค่าเงินเสี่ยงตาม Lot คงที่
   }
   else
   {
      // สูตรคำนวณ Lot: จำนวนเงินที่ยอมเสียได้ หารด้วย มูลค่าความเสียหายต่อ 1 ลอต
      lots = risk_money / loss_per_lot; 
   }

   if(!MathIsValidNumber(lots) || lots <= 0)
   {
      decision.reason = "Invalid calculated lot size";
      return false;
   }

   // 7. ข้อจำกัดความปลอดภัยเพิ่มเติม (Safety Overrides)
   // บังคับจำกัดขนาด Lot สำหรับทองคำเป็นพิเศษ เนื่องจากมีความผันผวนสูงกว่าคู่เงินปกติ
   if(StringFind(signal.symbol, "XAU") >= 0 && MaxLotsPerTradeXAU > 0)
      lots = MathMin(lots, MaxLotsPerTradeXAU);
   
   // ปรับขนาด Lot ให้สอดคล้องกับ Volume Step ของโบรกเกอร์ (เช่น ปัดให้เป็นทศนิยม 2 ตำแหน่ง)
   lots = MathFloor(lots / lot_step) * lot_step;
   // ตรวจสอบไม่ให้เกิน Max Lot และไม่ให้น้อยกว่า Min Lot
   if(lots > max_lot) lots = max_lot;
   if(lots < min_lot) lots = 0; // หาก Lot ต่ำเกินกว่าที่โบรกเกอร์รับได้ ให้ยกเลิกการเทรดนี้

   if(lots <= 0)
   {
      decision.reason = "Calculated lots <= 0";
      return false;
   }

   // 8. สรุปผลการตัดสินใจ (Final Decision)
   // บันทึกผลลัพธ์ลงในโครงสร้าง RiskDecision เพื่อส่งต่อให้ Execution Engine
   decision.allowed = true;
   decision.lots = lots;
   decision.risk_money = risk_money;
   decision.expected_loss = lots * loss_per_lot;
   decision.reason = "Risk and Dynamic Scaling evaluated successfully";

   return true;
}

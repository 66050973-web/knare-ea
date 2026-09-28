#ifndef __KNARES_INPUT_MANAGER_MQH__
#define __KNARES_INPUT_MANAGER_MQH__

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "SMCInputs.mqh"
#include "Logger.mqh"
#include "SharedGlobals.mqh"

//+------------------------------------------------------------------+
//| Input Manager Module - ระบบจัดการและตรวจสอบความถูกต้องของพารามิเตอร์      |
//| ทำหน้าที่: ตรวจสอบความสมเหตุสมผลของค่าที่ผู้ใช้ตั้งค่า (Inputs) และเตรียมรายชื่อ |
//| คู่เงิน (Symbols) ให้พร้อมสำหรับการทำงานของระบบ Portfolio Governor      |
//+------------------------------------------------------------------+

/**
 * ValidateInputs: ฟังก์ชันตรวจสอบความถูกต้องของค่าที่ผู้ใช้ตั้งค่าไว้ (Input Validation)
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบความปลอดภัย (Safety Check): จำกัดความเสี่ยงไม่ให้สูงเกินไป (เช่น Risk per Trade ไม่ควรเกิน 2%)
 * 2. ตรวจสอบรายชื่อคู่เงิน: ต้องมีการระบุคู่เงินอย่างน้อยหนึ่งตัวในช่อง Symbols
 * 3. ตรวจสอบการเปิดใช้งานระบบ: ต้องมีอย่างน้อย 1 กลยุทธ์ (Engine) ที่ถูกเปิดใช้งาน
 * 4. ตรวจสอบเป้าหมายกำไร/ขาดทุน (SL/TP): แจ้งเตือนหากตั้งค่าที่อาจส่งผลเสียต่อประสิทธิภาพ (เช่น TP แคบเกินไป)
 * 5. ตรวจสอบ SMC (Smart Money Concepts): เช็คระดับ Premium/Discount และความเหมาะสมของไทม์เฟรม
 * 6. ตรวจสอบระบบกู้คืน (Smart Recovery): แจ้งเตือนหากตั้งจำนวนครั้งในการแก้พอร์ตสูงเกินไป
 * @return true หากผ่านการตรวจสอบเบื้องต้นทั้งหมด, false หากพบค่าที่ไม่ปลอดภัยร้ายแรง
 */
bool ValidateInputs()
{
   bool success = true;

   // 1. ตรวจสอบความปลอดภัยพื้นฐาน (Basic Safety)
   // ป้องกันผู้ใช้ตั้งความเสี่ยงต่อไม้สูงเกินไป ซึ่งอาจทำให้พอร์ตเสียหายรวดเร็ว
   if(RiskPerTradePct > 0.02) 
   {
      LogError("ValidateInputs: RiskPerTradePct is too high (max recommended 2%). Set to " + DoubleToString(RiskPerTradePct * 100, 2) + "%");
      success = false;
   }

   // แจ้งเตือนหากตั้งค่าการยอมรับการติดลบ (Drawdown) ไว้สูงมาก
   if(MaxTotalDrawdownPercent > 50.0)
   {
      LogWarning("ValidateInputs: MaxTotalDrawdownPercent is very high (> 50%). Portfolios are at significant risk.");
   }

   // 2. ตรวจสอบความพร้อมของคู่เงิน (Symbols)
   // ต้องระบุชื่อคู่เงินใน Input (คั่นด้วยเครื่องหมายจุลภาค)
   if(StringLen(Symbols) == 0)
   {
      LogError("ValidateInputs: No symbols defined in input.");
      success = false;
   }

   // 3. ตรวจสอบการเปิดใช้งานกลยุทธ์ (Trading Engine Validation)
   // หากไม่มี Engine ใดถูกเปิดเลย EA จะไม่ทำงาน
   if(!EnableTrendEngine && !EnableBreakoutEngine && !EnableMeanRevEngine && !EnableSmartRecovery)
   {
      LogError("ValidateInputs: No trading engines are enabled. EA will not take any trades.");
      success = false;
   }

   // 4. ตรวจสอบเป้าหมายกำไรและจุดตัดขาดทุน (SL/TP Validation)
   // หาก Take Profit ต่ำเกินไป กำไรอาจจะไม่คุ้มกับค่า Spread และ Commission
   if(TakeProfitR <= 0.5)
   {
      LogWarning("ValidateInputs: TakeProfitR is very low. System might suffer from high commission/spread impact.");
   }

   // ป้องกันการตั้ง SL แคบเกินไปจนโบรกเกอร์ไม่สามารถส่งคำสั่งได้
   if(MinStopDistancePoints < 10)
   {
      LogWarning("ValidateInputs: MinStopDistancePoints is extremely low. Stop Loss might be too tight for broker execution.");
   }

   // 5. ตรวจสอบการตั้งค่า SMC (SMC Parameter Validation)
   if(EnableSMCFilter)
   {
      // แจ้งเตือนหากใช้ไทม์เฟรมปัจจุบันในการวิเคราะห์โครงสร้าง ซึ่งอาจทำให้ผลลัพธ์ไม่เสถียรเมื่อเปลี่ยนกราฟ
      if(SMCStructureTF == PERIOD_CURRENT)
      {
         LogWarning("ValidateInputs: SMCStructureTF set to CURRENT. This may lead to inconsistent structure analysis on different charts.");
      }
      
      // ระดับราคา Premium ต้องอยู่สูงกว่า Discount เสมอตามตรรกะ Fibonacci
      if(SMCPremiumLevel <= SMCDiscountLevel)
      {
         LogError("ValidateInputs: SMCPremiumLevel must be higher than SMCDiscountLevel.");
         success = false;
      }
   }

   // 6. ตรวจสอบระบบกู้คืนพอร์ต (Rescue & Recovery)
   // หากตั้งจำนวนไม้แก้พอร์ตมากเกินไป จะมีความเสี่ยงเรื่องการเทรดเกินตัว (Over-trading)
   if(EnableSmartRecovery && RecoveryMaxAttempts > 5)
   {
      LogWarning("ValidateInputs: RecoveryMaxAttempts is high. Over-trading risk detected.");
   }

   // สรุปผลการตรวจสอบลงใน Log
   if(success)
   {
      LogInfo("ValidateInputs: All parameters validated successfully.");
   }
   else
   {
      LogError("ValidateInputs: Parameter validation failed. Please check your settings.");
   }

   return success;
}

/**
 * InitializeSymbolList: จัดการเตรียมรายชื่อคู่เงินจาก Input ให้พร้อมใช้งาน
 * อธิบายกระบวนการ:
 * 1. นำข้อความจากช่อง Symbols มาแยก (Split) ด้วยเครื่องหมายจุลภาค (,)
 * 2. ล้างช่องว่าง (Space) ส่วนเกินออกจากชื่อคู่เงินแต่ละตัว
 * 3. ตรวจสอบว่าคู่เงินของกราฟปัจจุบัน (Chart Symbol) อยู่ในรายการหรือไม่ 
 *    - หากไม่อยู่ จะถูกเพิ่มเข้าไปโดยอัตโนมัติเพื่อความสะดวก
 * 4. บันทึกรายชื่อคู่เงินที่ผ่านการจัดระเบียบแล้วลงในอาเรย์ symbol_list (Global Variable)
 */
void InitializeSymbolList()
{
   ushort sep = StringGetCharacter(",", 0);
   string raw_list[];
   // แยกรายชื่อคู่เงินจาก String เป็น Array
   StringSplit(Symbols, sep, raw_list);
   
   string clean_list[];
   int count = 0;
   bool chart_symbol_found = false;

   // 1. วนลูปเพื่อจัดการความสะอาดข้อมูล (Data Cleaning)
   for(int i = 0; i < ArraySize(raw_list); i++)
   {
      string sym = raw_list[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "") continue; // ข้ามช่องว่าง
      
      // ตรวจสอบว่ามีชื่อคู่เงินตรงกับกราฟปัจจุบันหรือไม่
      if(sym == _Symbol) chart_symbol_found = true;
      
      ArrayResize(clean_list, count + 1);
      clean_list[count] = sym;
      count++;
   }

   // 2. บังคับเพิ่มคู่เงินของกราฟปัจจุบันเข้าไปในรายการ (ถ้ายังไม่มี)
   if(!chart_symbol_found)
   {
      ArrayResize(clean_list, count + 1);
      clean_list[count] = _Symbol;
      count++;
   }

   // 3. ย้ายข้อมูลเข้าสู่ symbol_list เพื่อให้โมดูลอื่นๆ เรียกใช้งานได้
   ArrayResize(symbol_list, ArraySize(clean_list));
   ArrayCopy(symbol_list, clean_list);
}

#endif // __KNARES_INPUT_MANAGER_MQH__

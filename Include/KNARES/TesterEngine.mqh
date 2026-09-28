#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Metrics.mqh"

//+------------------------------------------------------------------+
//| Tester Engine Module - ระบบทดสอบและประเมินผลประสิทธิภาพเชิงลึก          |
//| ทำหน้าที่: จัดการลอจิกเฉพาะที่ทำงานในโหมด Strategy Tester เท่านั้น         |
//+------------------------------------------------------------------+

/**
 * OnTester: ฟังก์ชันคำนวณคะแนนสำหรับการทดสอบใน Strategy Tester (Custom Score)
 * ถูกเรียกโดย MetaTrader 5 เมื่อจบการ Backtest เพื่อใช้ในขั้นตอนการ Optimization
 */
double OnTester()
{
   // เรียกใช้งานลอจิกการคำนวณคะแนนมาตรฐานที่ออกแบบไว้ใน Metrics Module
   return ComputeCustomTesterScore();
}

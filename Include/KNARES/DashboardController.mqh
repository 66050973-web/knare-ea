#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "RegimeClassifier.mqh"
#include "NewsFilter.mqh"
#include "Metrics.mqh"
#include "Visualization.mqh"
#include "EngineController.mqh"

//+------------------------------------------------------------------+
//| Dashboard Controller Module - ระบบจัดการหน้าจอและอินเตอร์เฟส            |
//+------------------------------------------------------------------+

/**
 * TriggerDashboardUpdate: ฟังก์ชันสำหรับสั่งอัปเดตข้อมูลบนหน้าจอ Dashboard
 * อธิบายกระบวนการ:
 * 1. ดึงข้อมูล Snapshot ล่าสุดของตลาด (ราคา, สภาพคล่อง)
 * 2. ตรวจสอบสภาวะตลาดปัจจุบัน (Regime) เช่น เทรนด์ หรือ ไซด์เวย์
 * 3. เช็คสถานะข่าวสารว่ามีข่าวรุนแรงที่ส่งผลกระทบหรือไม่
 * 4. คำนวณความเสี่ยง (Kill Switch) โดยเทียบ Equity กับ Balance
 * 5. สั่งอัปเดตตัวเลขทางสถิติ (Metrics) และส่งข้อมูลทั้งหมดไปแสดงผลบนกราฟ
 */
void TriggerDashboardUpdate()
{
   // 1. ดึงข้อมูลภาพรวมตลาดปัจจุบัน ถ้าดึงไม่ได้ให้หยุดทำงาน
   MarketSnapshot snapshot;
   if(!GetMarketSnapshot(_Symbol, snapshot)) return;
   
   // 2. วิเคราะห์สภาวะตลาด (Market Regime) จากข้อมูล Snapshot
   ENUM_REGIME_TYPE regime = DetectRegime(snapshot);
   
   // 3. ตรวจสอบว่าปัจจุบันอยู่ในช่วงเวลาที่มีข่าวสำคัญหรือไม่
   bool news_active = IsNewsActive(_Symbol);
   
   // 4. ตรวจสอบเงื่อนไขการตัดขาดทุนฉุกเฉิน (Equity Kill Switch)
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // คำนวณเปอร์เซ็นต์ Drawdown ณ ปัจจุบัน เทียบกับค่าที่ตั้งไว้ใน Config
   bool kill_switch = (balance > 0 && (1.0 - (equity / balance)) * 100.0 >= EquityKillSwitchPct * 100.0);
   
   // 5. อัปเดตข้อมูลสถิติการเทรด (Win Rate, Profit, etc.)
   UpdateMetrics(_Symbol);
   
   // 6. ส่งข้อมูลทั้งหมดไปยังโมดูล Visualization เพื่อวาดลงบนหน้าจอ
   UpdateDashboard(regime, news_active, kill_switch);
}

/**
 * HandleBookEvent: จัดการเหตุการณ์การเปลี่ยนแปลงของ Order Book (Depth of Market)
 * อธิบายกระบวนการ:
 * 1. คัดกรองเฉพาะสัญลักษณ์ (Symbol) ที่ EA กำลังทำงานอยู่
 * 2. คำนวณความไม่สมดุลของแรงซื้อและแรงขาย (DOM Imbalance) จาก Order Book
 * 3. บันทึกค่า Imbalance ล่าสุดลงในตัวแปร Global
 * 4. สั่งอัปเดตหน้าจอทันทีเพื่อให้เห็นการไหลของคำสั่งซื้อขายแบบ Real-time
 */
void HandleBookEvent(const string &symbol)
{
   // 1. ตรวจสอบว่าเหตุการณ์ที่เกิดขึ้นเป็นของ Symbol ที่เราสนใจหรือไม่
   if(symbol != _Symbol) return;
   
   // 2. คำนวณค่าความไม่สมดุลระหว่างฝั่ง Bid และ Ask (Order Flow)
   MarketSnapshot snapshot;
   if(ComputeDOMImbalance(symbol, snapshot))
   {
      // 3. เก็บค่า Imbalance ที่คำนวณได้ไว้ใช้งานในโมดูลอื่นๆ
      last_dom_imbalance = snapshot.dom_imbalance;
      
      // 4. อัปเดตการแสดงผลบนหน้าจอทันที (เน้นความไวในการตอบสนอง)
      bool news_active = IsNewsActive(symbol);
      UpdateDashboard(DetectRegime(snapshot), news_active, false);
   }
}

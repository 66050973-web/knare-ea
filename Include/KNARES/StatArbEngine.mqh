#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Logger.mqh"
#include "Config.mqh"
#include "MathLib.mqh"

//+------------------------------------------------------------------+
//| StatArb Engine - ประสิทธิภาพสูงสุด (Apex Dynamic Co-integration)     |
//+------------------------------------------------------------------+

/**
 * วิเคราะห์และสร้างสัญญาณการเทรดแบบส่วนต่างราคาสองสินทรัพย์ (Pair Trading)
 * โดยใช้หลักการทางสถิติเพื่อหาความเบี่ยงเบนจากสมดุล (Divergence)
 * 
 * @param sym_a ชื่อสินทรัพย์แรก
 * @param sym_b ชื่อสินทรัพย์ที่สอง
 * @param snap โครงสร้างข้อมูลสำหรับบันทึกค่า Snapshot ของคู่เทรด
 * @param sig_a ตัวแปรรับสัญญาณของสินทรัพย์แรก
 * @param sig_b ตัวแปรรับสัญญาณของสินทรัพย์ที่สอง
 * @return true หากพบโอกาสในการเทรด (Z-Score เกินเพดาน), false หากยังไม่มีสัญญาณ
 */
bool BuildPairSignal(string sym_a, string sym_b, PairSnapshot &snap, SignalPack &sig_a, SignalPack &sig_b)
{
   double close_a[], close_b[];
   // ตั้งค่าอาร์เรย์ให้เรียงลำดับจากปัจจุบันไปอดีต
   ArraySetAsSeries(close_a, true);
   ArraySetAsSeries(close_b, true);
   
   int bars = 100; // ใช้ข้อมูลย้อนหลัง 100 แท่งเพื่อการวิเคราะห์
   if(CopyClose(sym_a, MainTF, 0, bars, close_a) != bars) return false;
   if(CopyClose(sym_b, MainTF, 0, bars, close_b) != bars) return false;

   // 1. คำนวณความสัมพันธ์เชิงพลวัต (Dynamic Hedge Ratio หรือ Beta) ผ่านวิธี OLS
   double beta, alpha;
   if(!CalculateBeta(close_a, close_b, beta, alpha)) return false;

   // 2. คำนวณค่าส่วนต่าง (Spread) ในแต่ละช่วงเวลา: Spread = Price_A - (Beta * Price_B + Alpha)
   double spread_buffer[];
   ArrayResize(spread_buffer, bars);
   for(int i=0; i<bars; i++) spread_buffer[i] = close_a[i] - (beta * close_b[i] + alpha);

   // 3. ตรวจสอบความรวดเร็วในการกลับเข้าหาค่าเฉลี่ย (Half-life of Mean Reversion)
   double hl = CalculateHalfLife(spread_buffer);
   if(hl > 25.0) // หากต้องรอนานเกิน 25 แท่งเทียนเพื่อให้ Spread กลับมาที่เดิม ให้ข้ามคู่นี้ไปก่อน
   {
      return false;
   }

   // 4. คำนวณค่าสถิติ Z-score เพื่อระบุความรุนแรงของการเบี่ยงเบนจากราคาปกติ
   double current_spread = close_a[0] - (beta * close_b[0] + alpha);
   double mean = 0, std = 0;
   CalculateStats(spread_buffer, mean, std);

   // ป้องกันการหารด้วยศูนย์และคำนวณ Z-score
   double zscore = (current_spread - mean) / (std + 1e-9);
   
   // บันทึกข้อมูลวิเคราะห์ลงใน Snapshot
   snap.symbol_a = sym_a;
   snap.symbol_b = sym_b;
   snap.price_a = close_a[0];
   snap.price_b = close_b[0];
   snap.ratio = beta; 
   snap.ratio_zscore = zscore;

   // 5. เงื่อนไขการเข้าเทรด (ระดับนัยสำคัญทางสถิติที่ 2.2 Standard Deviations)
   const double ENTRY_Z_THRESHOLD = 2.2;
   
   // หาก Z-score สูงเกินไป: สินทรัพย์ A แพงไป (Sell) และสินทรัพย์ B ถูกไปเมื่อเทียบกัน (Buy)
   if(zscore > ENTRY_Z_THRESHOLD)
   {
      sig_a.direction = SIGNAL_SELL; sig_a.symbol = sym_a;
      sig_b.direction = SIGNAL_BUY;  sig_b.symbol = sym_b;
      // ส่งค่า Beta เพื่อให้ Risk Engine ใช้คำนวณขนาด Lot ที่สัมพันธ์กัน
      sig_b.score = beta; 
      return true;
   }
   
   // หาก Z-score ต่ำเกินไป: สินทรัพย์ A ถูกไป (Buy) และสินทรัพย์ B แพงไปเมื่อเทียบกัน (Sell)
   if(zscore < -ENTRY_Z_THRESHOLD)
   {
      sig_a.direction = SIGNAL_BUY;  sig_a.symbol = sym_a;
      sig_b.direction = SIGNAL_SELL; sig_b.symbol = sym_b;
      sig_b.score = beta;
      return true;
   }

   return false;
}

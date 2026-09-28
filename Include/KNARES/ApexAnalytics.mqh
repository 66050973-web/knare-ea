#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "StatArbEngine.mqh"
#include "RegimeForecaster.mqh"
#include "RiskEngine.mqh"
#include "ExecutionEngine.mqh"
#include "TradeTracking.mqh"
#include "ReasonLogger.mqh"

//+------------------------------------------------------------------+
//| Apex Analytics Module - ระบบวิเคราะห์คู่เงินสัมพันธ์และพยากรณ์ขั้นสูง      |
//| ทำหน้าที่: จัดการลอจิกการเทรดแบบคู่ (Arbitrage) และประเมินความเสี่ยงเชิงสถิติ |
//+------------------------------------------------------------------+

/**
 * RunStatArbApexCycle: วิเคราะห์และเทรดแบบคู่ (Statistical Arbitrage)
 * ทำหน้าที่ประเมินความสัมพันธ์ระหว่าง 2 คู่เงิน (เช่น EURUSD และ GBPUSD) 
 * หากราคาเบี่ยงเบนจากค่าสถิติที่ควรจะเป็น ระบบจะทำการเปิดออเดอร์สวนทางกัน (Hedge)
 * 
 * @param symbol สัญลักษณ์ปัจจุบัน
 * @param is_new_bar ตรวจสอบว่าเป็นแท่งเทียนใหม่หรือไม่
 * @param snapshot ข้อมูลตลาดปัจจุบัน
 */
void RunStatArbApexCycle(const string symbol, bool is_new_bar, const MarketSnapshot &snapshot)
{
   // จำกัดให้ประเมินเฉพาะตอนเกิดแท่งใหม่ของ symbol หลัก (ในตัวอย่างคือ EURUSD) เพื่อลดภาระการประมวลผล
   if(!TradeOnlyChartSymbol && is_new_bar && symbol == "EURUSD")
   {
      PairSnapshot p_snap;
      SignalPack sig_a, sig_b;
      
      // 1. สร้างสัญญาณเทรดแบบคู่ (Pair Trading) โดยคำนวณ Z-Score และ Beta ของความสัมพันธ์
      if(BuildPairSignal("EURUSD", "GBPUSD", p_snap, sig_a, sig_b))
      {
         RiskDecision r_a, r_b;
         
         // 2. ประเมินความเสี่ยงสำหรับคู่เงินแรก (Symbol A)
         if(EvaluateRisk(sig_a, snapshot, r_a))
         {
            // 3. กำหนดรายละเอียดสำหรับคู่เงินที่สอง (Symbol B) เพื่อทำการ Hedge
            sig_b.entry_price = SymbolInfoDouble(sig_b.symbol, SYMBOL_BID);
            r_b.allowed = true;
            
            // คำนวณขนาดลอตของคู่ที่สองให้สัมพันธ์กับคู่แรกตามค่า Beta (Ratio)
            r_b.lots = NormalizeLot(sig_b.symbol, r_a.lots * p_snap.ratio); 
            
            // 4. หากขนาดลอตถูกต้อง ให้ส่งคำสั่งเข้าตลาดพร้อมกันทั้งสองคู่เงิน
            if(r_b.lots > 0)
            {
               LogInfo(StringFormat("StatArb Apex: Z-Score %.2f, Beta %.2f. Executing Dynamic Hedge.", p_snap.ratio_zscore, p_snap.ratio));
               SendOrderWithRetry(sig_a, r_a); // เปิดออเดอร์ไม้แรก
               SendOrderWithRetry(sig_b, r_b); // เปิดออเดอร์ไม้ที่สอง (Hedge)
               UpdateEntryCooldown(symbol);    // เข้าสู่โหมดพักการเทรดชั่วคราว
            }
         }
      }
   }
}

/**
 * EvaluateHMMApexRisk: วิเคราะห์การพยากรณ์ราคา (HMM Inference) เพื่อคัดกรองความเสี่ยง
 * ใช้โมเดล Hidden Markov Model เพื่อประเมินความน่าจะเป็นที่ตลาดจะเปลี่ยนสภาวะ (Regime Shift)
 * 
 * @param symbol สัญลักษณ์ที่ต้องการตรวจสอบ
 * @param snapshot ข้อมูลตลาดปัจจุบัน
 * @return true หากผ่านการตรวจสอบความปลอดภัย, false หากตรวจพบความเสี่ยงเปลี่ยนสภาวะสูง
 */
bool EvaluateHMMApexRisk(const string symbol, const MarketSnapshot &snapshot)
{
   // 1. คำนวณ Log Return ของราคาปัจจุบันเทียบกับราคาปิดแท่งที่แล้ว
   double log_ret = MathLog(snapshot.ask / iClose(symbol, MainTF, 1));
   
   // 2. ระบุสภาวะตลาดปัจจุบัน (Market State) โดยใช้โมเดล HMM และค่าความผันผวน (ATR)
   int hmm_state = IdentifyCurrentState(log_ret, snapshot.atr);
   
   // 3. คำนวณค่าความเสี่ยงที่จะเกิดการเปลี่ยนสภาวะตลาด (Regime Shift Risk)
   double shift_risk = GetRegimeShiftRisk(hmm_state);

   // 4. ตรวจสอบเกณฑ์ความเสี่ยง (HMM Transition Risk)
   // หากความเสี่ยงที่จะเกิดการเปลี่ยนเทรนด์กะทันหันสูงเกินไป จะทำการระงับการเข้าเทรด
   if(shift_risk > HMMShiftRiskBlockThreshold)
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "hmm_shift_risk");
      LogWarning(StringFormat("HMM Apex Alert: Transition Risk too high (%.2f > %.2f). Blocking entry.", shift_risk, HMMShiftRiskBlockThreshold));
      return false; // ไม่อนุญาตให้เข้าเทรด
   }
   
   return true; // ผ่านการตรวจสอบ
}

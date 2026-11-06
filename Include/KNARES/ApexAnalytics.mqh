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
      if(BuildPairSignal("EURUSD", G_STATARB_PAIR_B, p_snap, sig_a, sig_b))
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

// TR/close ของแท่ง shift (ใช้เป็นฐานความผันผวนระยะยาวของ HMM)
double HMMTRClose(const string symbol, int shift)
{
   double hi = iHigh(symbol, MainTF, shift), lo = iLow(symbol, MainTF, shift), pc = iClose(symbol, MainTF, shift + 1);
   double cl = iClose(symbol, MainTF, shift);
   if(cl <= 0) return 0;
   return MathMax(hi - lo, MathMax(MathAbs(hi - pc), MathAbs(lo - pc))) / cl;
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
   // ตัวกรองปิดอยู่ หรือไม่มีไฟล์พารามิเตอร์ที่ฝึกแล้ว -> ไม่กรอง (ดู LoadApexHMM)
   if(!UseHMMFilter || !g_hmm_loaded) return true;

   // คำนวณครั้งเดียวต่อแท่งเทียนที่ปิดแล้ว ให้ตรงกับ Features ตอนฝึก (scripts/train_hmm.py)
   static datetime s_bar_time = 0;
   static bool     s_pass     = true;
   static double   s_trc_sum  = 0;      // ผลรวม TR/close ของ HMM_REL_BARS แท่งล่าสุด (แท่งปิด)
   static datetime s_sum_bar  = 0;      // เวลาแท่ง [1] ที่ผลรวมนี้ถูกคำนวณถึง
   datetime bar_time = iTime(symbol, MainTF, 0);
   if(bar_time == s_bar_time) return s_pass;
   s_bar_time = bar_time;

   const int HMM_REL_BARS = 2000;
   if(iBars(symbol, MainTF) < HMM_REL_BARS + ATRPeriod + 5) { s_pass = true; return s_pass; }

   // ผลรวม TR/close แบบเลื่อนต่อแท่ง (ถ้าข้ามแท่งให้คำนวณใหม่ทั้งหมด)
   if(s_sum_bar != 0 && iBarShift(symbol, MainTF, s_sum_bar, true) == 2)
      s_trc_sum += HMMTRClose(symbol, 1) - HMMTRClose(symbol, HMM_REL_BARS + 1);
   else
   {
      s_trc_sum = 0;
      for(int k = 1; k <= HMM_REL_BARS; k++) s_trc_sum += HMMTRClose(symbol, k);
   }
   s_sum_bar = iTime(symbol, MainTF, 1);

   double c1 = iClose(symbol, MainTF, 1);
   double c2 = iClose(symbol, MainTF, 2);
   if(c1 <= 0 || c2 <= 0) { s_pass = true; return s_pass; }

   // ATR% = SMA(TR, ATRPeriod) / close[1]
   double tr_sum = 0;
   for(int k = 1; k <= ATRPeriod; k++)
   {
      double hi = iHigh(symbol, MainTF, k), lo = iLow(symbol, MainTF, k), pc = iClose(symbol, MainTF, k + 1);
      tr_sum += MathMax(hi - lo, MathMax(MathAbs(hi - pc), MathAbs(lo - pc)));
   }
   double atr_pct = (tr_sum / ATRPeriod) / c1;
   double base    = s_trc_sum / HMM_REL_BARS;
   if(atr_pct <= 0 || base <= 0) { s_pass = true; return s_pass; }

   // Feature 1: log return หน่วย ATR ; Feature 2: ความผันผวนสัมพัทธ์ = ATR% / ค่าเฉลี่ยระยะยาว
   // (แบบสัมพัทธ์ทำให้ไม่ขึ้นกับระดับราคา/ความผันผวนของยุคที่ฝึก)
   double log_ret = MathLog(c1 / c2) / atr_pct;
   double vol_rel = atr_pct / base;

   // 2. ระบุสภาวะตลาดปัจจุบัน (Market State) ด้วย HMM (0=ผันผวนต่ำ ... 2=ผันผวนสูง)
   int hmm_state = IdentifyCurrentState(log_ret, vol_rel);

   // 3. ค่าความเสี่ยงที่ตลาดจะอยู่/เปลี่ยนไปสู่สภาวะผันผวนสูง (Regime Shift Risk)
   double shift_risk = GetRegimeShiftRisk(hmm_state);
   GlobalVariableSet("KNARES_HMM_RISK", shift_risk);   // ให้ Dashboard แสดงผล

   // 4. ตรวจสอบเกณฑ์ความเสี่ยง (HMM Transition Risk) หากสูงเกินไปจะระงับการเข้าเทรด
   s_pass = (shift_risk <= HMMShiftRiskBlockThreshold);
   if(s_pass && shift_risk > G_HMM_RISK_TOLERANCE)
      LogNoTradeReasonPerBar(symbol, MainTF, StringFormat("hmm_risk_elevated(%.2f>%.2f)", shift_risk, G_HMM_RISK_TOLERANCE)); // เตือนเท่านั้น ยังไม่บล็อก
   if(!s_pass)
   {
      LogNoTradeReasonPerBar(symbol, MainTF, "hmm_shift_risk");
      LogWarning(StringFormat("HMM Apex Alert: state=%d transition risk %.2f > %.2f. Blocking entry.", hmm_state, shift_risk, HMMShiftRiskBlockThreshold));
   }
   return s_pass;
}

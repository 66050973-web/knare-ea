#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

#include "OnnxOverlay.mqh"
#include "NeuralBridge.mqh"

//+------------------------------------------------------------------+
//| Ensemble Scorer - ระบบให้คะแนนถ่วงน้ำหนักและตัดสินใจขั้นสุดท้าย         |
//| ทำหน้าที่รวบรวมสัญญาณจากหลาย Engine และใช้ AI ในการตัดสินใจเข้าเทรด    |
//+------------------------------------------------------------------+

/**
 * PredictSignalQuality: ฟังก์ชันสำหรับประเมินคุณภาพของสัญญาณเทรดด้วย AI
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบระบบ Neural Bridge (Online Learning):
 *    - ถ้าเปิดใช้งาน จะส่งข้อมูล Snapshot + SMC fields ไปให้ AI ที่เรียนรู้แบบ Real-time วิเคราะห์
 *    - หากสำเร็จ (คืนค่า >= 0) จะใช้ค่าความเชื่อมั่นนั้นทันที
 * 2. กรณีสำรอง (Fallback) ไปที่ ONNX (Static Model):
 *    - ถ้า Neural Bridge ทำงานไม่ได้ จะใช้ Model AI ที่ถูกเทรนมาล่วงหน้า (Pre-trained)
 *    - Input 8 ค่า: [0]ADX, [1]RSI, [2]ATR%, [3]EMA_diff, [4]smc_bias, [5]smc_zone, [6]smc_buy_quality, [7]smc_sell_quality
 *    - รันการทำนายเพื่อหาค่า Probability ของความสำเร็จ
 * 3. กรณี AI ขัดข้องทั้งคู่:
 *    - คืนค่ากลาง 0.5 (Neutral) เพื่อไม่เสริมน้ำหนักสัญญาณเกินจริง การตัดสินใจไปใช้ rule-based score เป็นหลัก
 */
double PredictSignalQuality(const MarketSnapshot &features, const SignalPack &signal)
{
   // 1. ลองใช้ระบบ Online Learning (Neural Bridge) ที่เรียนรู้จากพฤติกรรมตลาดล่าสุด
   if(EnableNeuralBridge)
   {
      double prob = NeuralBridgeInfer(features, signal);
      if(prob >= 0) return prob;
      LogWarning("NeuralBridge inference failed. Falling back to Local ONNX.");
   }

   // 2. ถ้า Neural Bridge ไม่พร้อม ให้สลับมาใช้ไฟล์โมเดล AI (.onnx) ในเครื่อง
   if(EnableOnnxOverlay && onnx_handle != INVALID_HANDLE)
   {
      // จัดเตรียมข้อมูลทางเทคนิค (Features) 8 ตัว เพื่อป้อนเข้าสู่ Model
      float input_data[8];
      // --- Technical Features (เดิม) ---
      input_data[0] = (float)features.adx;
      input_data[1] = (float)features.rsi;
      input_data[2] = (float)(features.ask > 0 ? (features.atr / features.ask * 1000.0) : 0);
      input_data[3] = (float)(features.ema_fast - features.ema_slow);
      // --- SMC Features (ใหม่) --- ดึงจาก SignalPack ที่ถูก populate จาก SMCContext แล้ว
      input_data[4] = (float)signal.smc_bias;         // BEARISH=-1, NEUTRAL=0, BULLISH=1
      input_data[5] = (float)signal.smc_zone;         // UNKNOWN=0, DISCOUNT=1, EQUILIBRIUM=2, PREMIUM=3
      input_data[6] = (float)signal.smc_buy_quality;  // 0.0 – 1.0
      input_data[7] = (float)signal.smc_sell_quality; // 0.0 – 1.0

      float output_data[1];
      // รันการประมวลผลผ่าน ONNX Runtime
      if(OnnxRun(onnx_handle, ONNX_NO_CONVERSION, input_data, output_data))
      {
         double prob = (double)output_data[0];
         // ควบคุมค่าให้อยู่ในช่วง 0.0 - 1.0
         return MathMax(0.0, MathMin(1.0, prob));
      }
   }

   // 3. AI ปิดหรือใช้ไม่ได้: ใช้คะแนน rule-based ของ Engine เป็นค่าความมั่นใจ เพื่อให้ rule-based ตัดสินใจได้เอง
   // (ค่ากลาง 0.5 ต่ำกว่า MinEntryConfidence ทำให้ไม่มีสัญญาณไหนผ่านเลย)
   if(UseRuleScoreWhenAIOff)
      return MathMax(0.0, MathMin(1.0, signal.score));

   if(EnableNeuralBridge || EnableOnnxOverlay)
      LogWarning("PredictSignalQuality: All AI paths failed. Returning neutral confidence 0.5.");
   return 0.5;
}

/**
 * ResolveSignals: ฟังก์ชันตัดสินใจเลือกสัญญาณที่ดีที่สุด (Decision Making Engine)
 * อธิบายกระบวนการ:
 * 1. ระบบ Double Engine Bonus:
 *    - ตรวจสอบว่ามีสัญญาณจาก TrendEngine และ BreakoutEngine ไปในทิศทางเดียวกันหรือไม่
 *    - ถ้าใช่ จะบวกคะแนนพิเศษ (Bonus) เพื่อเพิ่มน้ำหนักให้สัญญาณนั้น
 * 2. การคำนวณน้ำหนัก (Weighting Process):
 *    - วนลูปทุกสัญญาณที่ได้รับมา
 *    - เรียกใช้ PredictSignalQuality เพื่อหาค่าความมั่นใจจาก AI (Confidence)
 *    - กรองสัญญาณทิ้งหาก AI มั่นใจน้อยกว่าเกณฑ์ (AI Confidence Filter)
 *    - กรองสัญญาณตามสภาวะตลาด (Smart Filtering) เช่น Volume ต่ำ หรือ ATR ต่ำผิดปกติ
 *    - คำนวณน้ำหนักรวม: Weight = Score (จาก Engine) * Confidence (จาก AI)
 * 3. การจัดการความขัดแย้ง (Conflict Resolution):
 *    - หากมีสัญญาณทั้ง Buy และ Sell พร้อมกัน จะต้องเปรียบเทียบน้ำหนัก
 *    - เลือกฝั่งที่ชนะขาดลอย (Dominant Majority) โดยใช้อัตราส่วน 1.5 เท่าขึ้นไป
 *    - หากก้ำกึ่งกัน (Conflicting) จะยกเลิกการเทรดเพื่อความปลอดภัย
 * 4. การตัดสินใจขั้นสุดท้าย (Final Selection):
 *    - ตรวจสอบน้ำหนักสุทธิว่าถึงเกณฑ์ (Threshold 0.42) หรือไม่
 *    - คืนค่าทิศทาง (BUY/SELL) และบันทึกข้อมูลสัญญาณลงใน final_signal
 */
ENUM_SIGNAL_DIRECTION ResolveSignals(SignalPack &signals[], const MarketSnapshot &features, SignalPack &final_signal)
{
   int signal_count = ArraySize(signals);
   if(signal_count == 0) return SIGNAL_NONE;

   double buy_weight = 0;
   double sell_weight = 0;
   
   // --- ขั้นตอนที่ 1: ตรวจสอบการยืนยันร่วมกัน (Double Engine Confirmation) ---
   bool trend_buy = false, trend_sell = false;
   bool breakout_buy = false, breakout_sell = false;
   for(int i=0; i<signal_count; i++)
   {
      if(signals[i].engine_name == "TrendEngine")
      {
         if(signals[i].direction == SIGNAL_BUY) trend_buy = true;
         if(signals[i].direction == SIGNAL_SELL) trend_sell = true;
      }
      if(signals[i].engine_name == "BreakoutEngine")
      {
         if(signals[i].direction == SIGNAL_BUY) breakout_buy = true;
         if(signals[i].direction == SIGNAL_SELL) breakout_sell = true;
      }
   }
   // หากมองตรงกันทั้งสองระบบ ให้เพิ่มคะแนนพิเศษเพื่อความแม่นยำ
   if((trend_buy && breakout_buy) || (trend_sell && breakout_sell))
   {
      for(int i=0; i<signal_count; i++)
      {
         if(signals[i].engine_name == "TrendEngine" || signals[i].engine_name == "BreakoutEngine")
         {
            signals[i].score += DoubleEngineBonusScore;
         }
      }
   }

   // --- ขั้นตอนที่ 2: วิเคราะห์คุณภาพและคำนวณน้ำหนักโดย AI ---
   for(int i=0; i<signal_count; i++)
   {
      // ให้ AI ประเมินความน่าจะเป็นของความสำเร็จ
      double confidence = PredictSignalQuality(features, signals[i]);
      if(!MathIsValidNumber(confidence))
      {
         LogWarning("AI confidence invalid. Fallback to 0.");
         confidence = 0.0;
      }
      confidence = MathMax(0.0, MathMin(1.0, confidence));
      signals[i].confidence = confidence;
      
      // เก็บค่าความมั่นใจล่าสุดไว้แสดงบน Dashboard
      if(signals[i].symbol == _Symbol) last_ai_confidence = confidence;

      // กรองสัญญาณที่ AI มองว่ามีความเสี่ยงสูง (Confidence ไม่ถึงเกณฑ์)
      if(EnableOnnxOverlay && confidence < AIConfidenceThreshold)
      {
         LogInfo(StringFormat("AI blocked %s: Confidence Gap %.2f (%.2f < %.2f)", signals[i].engine_name, AIConfidenceThreshold - confidence, confidence, AIConfidenceThreshold));
         signals[i].direction = SIGNAL_NONE;
         continue;
      }

      double score = signals[i].score;
      
      // กรองสัญญาณตามปริมาณการซื้อขาย (Volume Filter)
      long prev_vol = iTickVolume(features.symbol, MainTF, 1);
      if(EnableVolumeFilter && (double)prev_vol < features.vol_median * (MinVolumePercentile / 100.0))
      {
         LogInfo(StringFormat("SmartFilter Blocked [%s]: Volume too low", signals[i].engine_name));
         signals[i].direction = SIGNAL_NONE; continue;
      }

      // กรองสัญญาณตามความผันผวน (Volatility Filter)
      if(EnableVolatilityFilter && features.atr < features.atr_median * 0.3)
      {
         LogInfo(StringFormat("SmartFilter Blocked [%s]: Volatility extremely low", signals[i].engine_name));
         signals[i].direction = SIGNAL_NONE; continue;
      }

      // คำนวณน้ำหนักสุทธิ: คะแนนกลยุทธ์ x ความมั่นใจ AI
      double weight = score * confidence; 
      
      if(signals[i].direction == SIGNAL_BUY)  buy_weight += weight;
      if(signals[i].direction == SIGNAL_SELL) sell_weight += weight;
   }

   // --- ขั้นตอนที่ 3: จัดการกรณีสัญญาณขัดแย้งกัน (Conflict Resolution) ---
   if(buy_weight > 0 && sell_weight > 0)
   {
      double ratio = (buy_weight > sell_weight) ? (buy_weight / sell_weight) : (sell_weight / buy_weight);
      // ถ้าฝ่ายหนึ่งมีน้ำหนักมากกว่า 1.5 เท่า และมีคะแนนสูงพอ ให้เลือกฝ่ายที่ชนะ
      if(ratio >= 1.5 && (buy_weight >= 0.42 || sell_weight >= 0.42)) 
      {
         bool winner_ok = (buy_weight > sell_weight) ? (buy_weight >= 0.82) : (sell_weight >= 0.82);
         if(winner_ok)
         {
            LogInfo(StringFormat("Conflict Resolved: Active Majority selected (Ratio: %.2f)", ratio));
            if(buy_weight > sell_weight) sell_weight = 0; else buy_weight = 0;
         }
      }
      
      // หากน้ำหนักก้ำกึ่งกัน ให้ยกเลิกการเทรดเพื่อลดความเสี่ยง
      if(buy_weight > 0 && sell_weight > 0)
      {
         LogWarning(StringFormat("Weight Conflict Unresolved: Buy=%.2f Sell=%.2f Ratio=%.2f. Blocking entry.", buy_weight, sell_weight, ratio));
         return SIGNAL_NONE;
      }
   }

   // --- ขั้นตอนที่ 4: สรุปผลการตัดสินใจ ---
   double threshold = 0.42; // เกณฑ์น้ำหนักรวมขั้นต่ำในการเปิดออเดอร์
   
   if(buy_weight >= threshold)
   {
      // เลือกโครงสร้างสัญญาณฝั่ง Buy ที่มีคะแนนสูงสุดมาใช้งาน
      for(int i=0; i<signal_count; i++)
      {
         if(signals[i].direction == SIGNAL_BUY) { final_signal = signals[i]; break; }
      }
      return SIGNAL_BUY;
   }
   
   if(sell_weight >= threshold)
   {
      // เลือกโครงสร้างสัญญาณฝั่ง Sell ที่มีคะแนนสูงสุดมาใช้งาน
      for(int i=0; i<signal_count; i++)
      {
         if(signals[i].direction == SIGNAL_SELL) { final_signal = signals[i]; break; }
      }
      return SIGNAL_SELL;
   }

   return SIGNAL_NONE; // ไม่มีสัญญาณใดผ่านเกณฑ์
}

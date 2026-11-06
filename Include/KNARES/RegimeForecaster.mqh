#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Logger.mqh"
#include "MathLib.mqh"

//+------------------------------------------------------------------+
//| Regime Forecaster - ประสิทธิภาพสูงสุด (Apex HMM Inference)           |
//+------------------------------------------------------------------+

// ตัวแปรเก็บค่าตารางความน่าจะเป็นของการเปลี่ยนสภาวะ (Transition Matrix)
double g_trans_matrix[3][3];
// ค่าเฉลี่ยของ Features ในแต่ละสภาวะ (Means)
double g_means[3][2];
// ค่าความแปรปรวนของ Features ในแต่ละสภาวะ (Variances)
double g_vars[3][2];

/**
 * โหลดพารามิเตอร์ของโมเดล HMM (Hidden Markov Model) จากไฟล์ CSV
 * โมเดลนี้ใช้สำหรับพยากรณ์และระบุสภาวะตลาด (Regime)
 * @return true หากโหลดข้อมูลครบถ้วน, false หากขาดหายไป
 */
bool g_hmm_loaded = false;   // true เมื่อโหลดพารามิเตอร์ HMM ครบ (ถ้า false ตัวกรอง HMM จะไม่ทำงาน)

bool LoadApexHMM()
{
   g_hmm_loaded = false;
   // พารามิเตอร์ฝึกแยกตามไทม์เฟรม เพราะ Features (Return, ATR%) ขึ้นกับขนาดแท่งเทียน
   string tf = StringSubstr(EnumToString(MainTF), 7);   // PERIOD_M5 -> "M5"
   string f_trans = "KNARES_HMM_Trans_" + tf + ".csv";
   string f_means = "KNARES_HMM_Means_" + tf + ".csv";
   string f_vars  = "KNARES_HMM_Vars_"  + tf + ".csv";

   if(!FileIsExist(f_trans, FILE_COMMON) || !FileIsExist(f_means, FILE_COMMON) || !FileIsExist(f_vars, FILE_COMMON))
   {
      LogWarning("Apex HMM Engine: parameter files for " + tf + " not found. HMM filter DISABLED (run scripts/train_hmm.py " + tf + ").");
      return false;
   }

   // 1. โหลดตารางความน่าจะเป็นในการเปลี่ยนสถานะ (Transition Matrix)
   int h = FileOpen(f_trans, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(h == INVALID_HANDLE) return false;
   for(int i=0; i<3; i++) for(int j=0; j<3; j++) g_trans_matrix[i][j] = FileReadNumber(h);
   FileClose(h);

   // 2. โหลดค่าเฉลี่ยของ Features (Return และ ATR%) ของทั้ง 3 สภาวะ
   h = FileOpen(f_means, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(h == INVALID_HANDLE) return false;
   for(int i=0; i<3; i++) for(int j=0; j<2; j++) g_means[i][j] = FileReadNumber(h);
   FileClose(h);

   // 3. โหลดค่าความแปรปรวน (Variances) ของทั้ง 3 สภาวะ
   h = FileOpen(f_vars, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   if(h == INVALID_HANDLE) return false;
   for(int i=0; i<3; i++) for(int j=0; j<2; j++) g_vars[i][j] = FileReadNumber(h);
   FileClose(h);

   // ตรวจความสมเหตุสมผล: แต่ละแถวของ Transition Matrix ต้องรวมได้ ~1 และ Variance ต้องเป็นบวก
   for(int i=0; i<3; i++)
   {
      double s = g_trans_matrix[i][0] + g_trans_matrix[i][1] + g_trans_matrix[i][2];
      if(MathAbs(s - 1.0) > 0.01 || g_vars[i][0] <= 0 || g_vars[i][1] <= 0)
      {
         LogWarning("Apex HMM Engine: parameter files invalid. HMM filter DISABLED.");
         return false;
      }
   }

   g_hmm_loaded = true;
   LogInfo("Apex HMM Engine: All state parameters loaded (" + tf + ").");
   return true;
}

/**
 * ระบุสภาวะตลาดปัจจุบัน (Current State) โดยใช้หลักการ Maximum Likelihood
 * @param ret ผลตอบแทนของราคา (Return)
 * @param vol ความผันผวนของราคา (Volatility)
 * @return ดัชนีของสภาวะตลาดที่มีความเป็นไปได้สูงสุด (0, 1 หรือ 2)
 */
int IdentifyCurrentState(double ret, double vol)
{
   double max_lh = -1.0;
   int best_state = 0;

   // ตรวจสอบความเป็นไปได้ (Likelihood) ในแต่ละสภาวะ (State)
   for(int i=0; i<3; i++)
   {
      // คำนวณ Joint Likelihood โดยใช้ Gaussian PDF จาก MathLib
      double lh = GaussianPDF(ret, g_means[i][0], g_vars[i][0]) * 
                  GaussianPDF(vol, g_means[i][1], g_vars[i][1]);
      
      // เลือกสภาวะที่ให้ค่า Likelihood สูงที่สุด
      if(lh > max_lh)
      {
         max_lh = lh;
         best_state = i;
      }
   }
   return best_state;
}

/**
 * คำนวณความเสี่ยงที่ตลาดจะเปลี่ยนไปสู่สภาวะความผันผวนสูง
 * @param current_state สภาวะตลาดในปัจจุบัน
 * @return ค่าความน่าจะเป็นที่จะเปลี่ยนไปสู่สภาวะ High Volatility (State 2)
 */
double GetRegimeShiftRisk(int current_state)
{
   // อ้างอิงจากตาราง Transition Matrix เพื่อหาโอกาสในการเปลี่ยนจากสถานะปัจจุบันไปยังสถานะที่ 2
   return g_trans_matrix[current_state][2];
}

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
bool LoadApexHMM()
{
   string f_trans = "KNARES_HMM_Trans.csv";
   string f_means = "KNARES_HMM_Means.csv";
   string f_vars  = "KNARES_HMM_Vars.csv";

   if(!FileIsExist(f_trans, FILE_COMMON)) return false;

   // 1. โหลดตารางความน่าจะเป็นในการเปลี่ยนสถานะ (Transition Matrix)
   int h = FileOpen(f_trans, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   for(int i=0; i<3; i++) for(int j=0; j<3; j++) g_trans_matrix[i][j] = FileReadNumber(h);
   FileClose(h);

   // 2. โหลดค่าเฉลี่ยของ Features (Return และ Volatility) ของทั้ง 3 สภาวะ
   h = FileOpen(f_means, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   for(int i=0; i<3; i++) for(int j=0; j<2; j++) g_means[i][j] = FileReadNumber(h);
   FileClose(h);

   // 3. โหลดค่าความแปรปรวน (Variances) ของทั้ง 3 สภาวะ
   h = FileOpen(f_vars, FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
   for(int i=0; i<3; i++) for(int j=0; j<2; j++) g_vars[i][j] = FileReadNumber(h);
   FileClose(h);

   LogInfo("Apex HMM Engine: All state parameters loaded.");
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

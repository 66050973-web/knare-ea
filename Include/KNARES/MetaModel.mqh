#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "MarketData.mqh"
#include "FeatureEngine.mqh"

//+------------------------------------------------------------------+
//| Meta-label Model - ตัวกรองสัญญาณด้วยโมเดล ML (Logistic Regression, ONNX) |
//| โมเดลทำนาย "ความน่าจะเป็นที่ไม้นี้จะจบด้วยกำไร" จากฟีเจอร์ ณ จุดเข้า 24 ตัว |
//| ฝึกด้วยข้อมูล 2018-01 ถึง 2024-09-17 (scripts/ml_export_meta.py)         |
//| ฝังไฟล์โมเดลเป็น resource ในตัว EA จึงไม่ต้องคัดลอกไฟล์ไปที่ MQL5\Files     |
//+------------------------------------------------------------------+

#resource "KNARES_Meta.onnx" as uchar g_meta_model_buf[]

#define META_N_FEATURES 24

long   g_meta_handle   = INVALID_HANDLE;
int    g_meta_blocks   = 0;
int    g_meta_passes   = 0;
datetime g_meta_block_until = 0;

bool MetaModelInit()
{
   if(!EnableMetaGate) return true;
   g_meta_handle = OnnxCreateFromBuffer(g_meta_model_buf, ONNX_DEFAULT);
   if(g_meta_handle == INVALID_HANDLE)
   {
      LogError("MetaModel: OnnxCreateFromBuffer failed, err=" + (string)GetLastError() + ". Meta gate disabled.");
      return true; // ไม่ล้ม EA ทั้งตัว: gate จะปล่อยผ่านเมื่อโมเดลโหลดไม่ได้
   }
   const long in_shape[]  = {1, META_N_FEATURES};
   const long out_shape[] = {1, 1};
   if(!OnnxSetInputShape(g_meta_handle, 0, in_shape) || !OnnxSetOutputShape(g_meta_handle, 0, out_shape))
   {
      LogError("MetaModel: tensor shape setup failed, err=" + (string)GetLastError());
      OnnxRelease(g_meta_handle);
      g_meta_handle = INVALID_HANDLE;
      return true;
   }
   LogInfo(StringFormat("MetaModel: loaded (24 features -> P(win)). Gate threshold = %.2f", MetaMinProb));
   return true;
}

void MetaModelDeinit()
{
   if(g_meta_handle != INVALID_HANDLE)
   {
      OnnxRelease(g_meta_handle);
      g_meta_handle = INVALID_HANDLE;
   }
   if(EnableMetaGate)
      LogInfo(StringFormat("MetaModel: passes=%d blocks=%d", g_meta_passes, g_meta_blocks));
}

/**
 * BuildMetaFeatures: สร้างเวกเตอร์ฟีเจอร์ 24 ตัวตามลำดับเดียวกับตอนฝึก (ml_common.py: DA)
 * ใช้สูตรเดียวกับ SampleExportEntry ใน FeatureExport.mqh เพื่อให้ฟีเจอร์ตอนฝึกกับตอนใช้งานตรงกัน
 */
bool BuildMetaFeatures(const SignalPack &signal, float &f[])
{
   MarketSnapshot s;
   if(!GetMarketSnapshot(signal.symbol, s)) return false;
   ComputeFeatures(signal.symbol, s);

   double atr = s.atr;
   if(atr <= 0.0) return false;
   double ref = (s.ask > 0.0) ? s.ask : s.bid;
   double px  = (signal.direction == SIGNAL_BUY) ? s.ask : s.bid;
   if(px <= 0.0 || ref <= 0.0) return false;
   double point = SymbolInfoDouble(signal.symbol, SYMBOL_POINT);
   double dir   = (signal.direction == SIGNAL_BUY) ? 1.0 : -1.0;
   double bbw   = s.bb_upper - s.bb_lower;
   double dcw   = s.donchian_high - s.donchian_low;
   double bbpos = (bbw > 0.0) ? (px - s.bb_lower) / bbw : 0.5;
   double dcpos = (dcw > 0.0) ? (px - s.donchian_low) / dcw : 0.5;
   double q_dir = (dir > 0) ? signal.smc_buy_quality  : signal.smc_sell_quality;
   double q_opp = (dir > 0) ? signal.smc_sell_quality : signal.smc_buy_quality;

   ArrayResize(f, META_N_FEATURES);
   f[0]  = (float)s.adx;
   f[1]  = (float)s.adx_slope;
   f[2]  = (float)(atr / ref * 1000.0);
   f[3]  = (float)(bbw / atr);
   f[4]  = (float)(dcw / atr);
   f[5]  = (float)(s.vol_median > 0.0 ? (double)s.volume / s.vol_median : 0.0);
   f[6]  = (float)(MathAbs(px - signal.stop_price) / atr);
   f[7]  = (float)(s.spread_points * point / atr);
   f[8]  = (float)signal.smc_zone;
   f[9]  = (float)signal.smc_buy_quality;
   f[10] = (float)signal.smc_sell_quality;
   f[11] = (float)signal.score;
   f[12] = (float)signal.confidence;
   f[13] = (float)((s.ema_fast - s.ema_slow) / atr * dir);
   f[14] = (float)(s.zscore * dir);
   f[15] = (float)(s.htf_trend * dir);
   f[16] = (float)(signal.smc_bias * dir);
   f[17] = (float)q_dir;
   f[18] = (float)q_opp;
   f[19] = (float)((s.rsi - 50.0) * dir);
   f[20] = (float)((bbpos - 0.5) * dir);
   f[21] = (float)((dcpos - 0.5) * dir);
   f[22] = (float)dir;
   f[23] = (float)(signal.engine_name == "TrendEngine" ? 1.0 : 0.0);
   for(int i = 0; i < META_N_FEATURES; i++)
      if(!MathIsValidNumber(f[i])) return false;
   return true;
}

/**
 * MetaGatePass: คืน true เมื่อควรเปิดออเดอร์ (ปิดใช้งาน, โมเดลไม่พร้อม หรือ P(win) >= MetaMinProb)
 */
bool MetaGatePass(const SignalPack &signal, double &prob_out)
{
   prob_out = -1.0;
   if(!EnableMetaGate || g_meta_handle == INVALID_HANDLE) return true;
   if(TimeCurrent() < g_meta_block_until) { g_meta_blocks++; return false; }
   float f[];
   if(!BuildMetaFeatures(signal, f)) return true;
   float out[1];
   if(!OnnxRun(g_meta_handle, ONNX_NO_CONVERSION, f, out)) return true;
   prob_out = (double)out[0];
   if(EnableSampleExport) LogInfo(StringFormat("MetaProb p=%.6f", prob_out));
   if(prob_out >= MetaMinProb) { g_meta_passes++; return true; }
   g_meta_blocks++;
   g_meta_block_until = TimeCurrent() + (datetime)(MetaBlockCooldownMin * 60);
   return false;
}

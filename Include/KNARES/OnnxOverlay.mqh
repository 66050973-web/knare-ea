#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| ONNX Overlay Module - เครื่องยนต์ AI ประสิทธิภาพสูงสุด (Apex Efficiency) |
//+------------------------------------------------------------------+

// ตัวแปรสำหรับเก็บ Handle ของโมเดล ONNX ที่ถูกโหลดเข้าสู่หน่วยความจำ
long onnx_handle = INVALID_HANDLE;

/**
 * เริ่มต้นการโหลดโมเดล AI ในรูปแบบ ONNX (Open Neural Network Exchange)
 * ทำการตรวจสอบความมีอยู่ของไฟล์และการตั้งค่าโครงสร้างของโมเดล (Input/Output Tensors)
 * @return true หากโหลดและตั้งค่าโมเดลสำเร็จ, false หากเกิดข้อผิดพลาด
 */
bool OnnxOverlayInit()
{
   // ตรวจสอบว่าผู้ใช้เปิดใช้งาน AI ONNX หรือไม่
   if(!EnableOnnxOverlay) return true;

   string model_filename = "KNARES_Model.onnx";
   
   // 1. ตรวจสอบว่ามีไฟล์โมเดลอยู่ในโฟลเดอร์ MQL5\Files หรือไม่
   if(!FileIsExist(model_filename))
   {
      LogWarning("ONNX model '" + model_filename + "' not found. AI filtering disabled.");
      return true; 
   }

   // 2. สร้าง Handle สำหรับใช้งานโมเดล โดยเปิดโหมด Default (ประมวลผลบน CPU/GPU ตามความเหมาะสม)
   onnx_handle = OnnxCreate(model_filename, ONNX_DEFAULT);
   
   if(onnx_handle == INVALID_HANDLE)
   {
      // แจ้งเตือนข้อผิดพลาด เช่น อาจลืมอนุญาตการใช้งาน DLL หรือไฟล์โมเดลไม่สมบูรณ์
      LogError("OnnxCreate Error: " + (string)GetLastError() + " - Ensure DLL is allowed and model is valid.");
      return false;
   }

   // 3. กำหนดโครงสร้างข้อมูลขาเข้า (Input) และขาออก (Output) ของ AI
   // Input: 8 features — [0]ADX, [1]RSI, [2]ATR%, [3]EMA_diff, [4]smc_bias, [5]smc_zone, [6]smc_buy_quality, [7]smc_sell_quality
   const long input_shape[] = {1, 8};
   const long output_shape[] = {1, 1};

   // ตั้งค่าโครงสร้าง Input Tensor (ดัชนีที่ 0)
   if(!OnnxSetInputShape(onnx_handle, 0, input_shape))
   {
      LogError("Failed to set ONNX Input Shape. Expected [1, 8] (4 technical + 4 SMC). Error: " + (string)GetLastError());
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      return false;
   }

   // ตั้งค่าโครงสร้าง Output Tensor (ดัชนีที่ 0)
   if(!OnnxSetOutputShape(onnx_handle, 0, output_shape))
   {
      LogError("Failed to set ONNX Output Shape. Expected [1, 1]. Error: " + (string)GetLastError());
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      return false;
   }

   LogInfo("ONNX Engine: Model loaded successfully. Tensors mapped [8] -> [1] (4 technical + 4 SMC features). Ready for Apex Inference.");
   return true;
}

/**
 * ปล่อยคืนทรัพยากรหน่วยความจำที่ใช้โดยโมเดล ONNX เมื่อจบการทำงาน
 */
void OnnxOverlayDeinit()
{
   if(onnx_handle != INVALID_HANDLE)
   {
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      LogInfo("ONNX Engine: Memory released securely.");
   }
}

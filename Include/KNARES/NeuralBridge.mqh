#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Logger.mqh"
#include "Types.mqh"
#include "Config.mqh"

//+------------------------------------------------------------------+
//| Neural Bridge - สะพานเชื่อมต่อ MT5 กับ Python แบบเรียลไทม์ (ZeroMQ / TCP) |
//+------------------------------------------------------------------+

// ตัวแปรเก็บ Handle ของ Socket สำหรับการเชื่อมต่อเครือข่าย
int g_neural_socket = INVALID_HANDLE;

/**
 * ฟังก์ชันเริ่มต้นการเชื่อมต่อไปยัง Python AI Server
 * ใช้สำหรับการรับส่งข้อมูลเพื่อการเรียนรู้และการทำนายผลแบบ Real-time
 * @return true หากเชื่อมต่อสำเร็จหรือปิดการใช้งาน, false หากเชื่อมต่อล้มเหลว
 */
bool NeuralBridgeInit()
{
   // ตรวจสอบว่าผู้ใช้เปิดใช้งาน Neural Bridge หรือไม่จากไฟล์ Config
   if(!EnableNeuralBridge) return true;

   // สร้าง Socket ใหม่
   g_neural_socket = SocketCreate();
   if(g_neural_socket != INVALID_HANDLE)
   {
      // พยายามเชื่อมต่อไปยัง Localhost (เครื่องเดียวกัน) ที่ Port 5555 พร้อมกำหนดเวลา Timeout 1 วินาที
      if(SocketConnect(g_neural_socket, "127.0.0.1", 5555, 1000))
      {
         LogInfo("Neural Bridge: Connected to Online Learning Server.");
         return true;
      }
      // หากเชื่อมต่อไม่สำเร็จ ให้ปิด Socket
      SocketClose(g_neural_socket);
      g_neural_socket = INVALID_HANDLE;
   }
   
   LogWarning("Neural Bridge: Connection Failed. Is Python Server running on port 5555?");
   return false;
}

/**
 * ฟังก์ชันปิดการเชื่อมต่อ Neural Bridge และคืนทรัพยากรระบบ
 */
void NeuralBridgeDeinit()
{
   if(g_neural_socket != INVALID_HANDLE)
   {
      SocketClose(g_neural_socket);
      g_neural_socket = INVALID_HANDLE;
      LogInfo("Neural Bridge: Disconnected.");
   }
}

/**
 * ส่งข้อมูลตลาดปัจจุบันไปให้ AI เพื่อทำการทำนายผล (Inference)
 * Input 8 features: ADX, RSI, ATR%, EMA_diff, smc_bias, smc_zone, smc_buy_quality, smc_sell_quality
 * @param features ข้อมูล Snapshot ของตลาด (ADX, RSI, ATR, EMA)
 * @param signal   SignalPack ที่ผ่านการ populate SMC fields แล้ว
 * @return ค่าความมั่นใจของ AI (-1.0 หากล้มเหลว, 0.0 ถึง 1.0 หากสำเร็จ)
 */
double NeuralBridgeInfer(const MarketSnapshot &features, const SignalPack &signal)
{
   if(g_neural_socket == INVALID_HANDLE) return -1.0;
   
   // เตรียมข้อมูลที่จะส่งในรูปแบบ String:
   // "INF,adx,rsi,atr_pct,ema_diff,smc_bias,smc_zone,smc_buy_quality,smc_sell_quality"
   double atr_pct = features.atr / features.ask * 1000.0;
   double ema_diff = features.ema_fast - features.ema_slow;
   string msg = StringFormat("INF,%.2f,%.2f,%.5f,%.5f,%.1f,%.1f,%.4f,%.4f",
                             features.adx, features.rsi, atr_pct, ema_diff,
                             signal.smc_bias, signal.smc_zone,
                             signal.smc_buy_quality, signal.smc_sell_quality);
   
   uchar req[], resp[];
   StringToCharArray(msg, req);
   
   // ส่งข้อมูลผ่าน Socket (ข้ามตัวอักษรจบ String ตัวสุดท้าย)
   if(SocketSend(g_neural_socket, req, ArraySize(req)-1) > 0)
   {
      // ระบบรับข้อมูลความเร็วสูงแบบ Non-blocking (รอผลลัพธ์กลับมาภายใน 5ms)
      uint start = GetTickCount();
      while(GetTickCount() - start < 5) 
      {
         uint len = SocketIsReadable(g_neural_socket);
         if(len > 0)
         {
            // อ่านข้อมูลตอบกลับจาก AI
            SocketRead(g_neural_socket, resp, len, 5);
            return StringToDouble(CharArrayToString(resp));
         }
      }
   }
   return -1.0;
}

/**
 * ส่งข้อมูลการเทรดที่จบแล้วกลับไปให้ AI เพื่อใช้ในการเรียนรู้เพิ่มเติม (Online Learning)
 * เรียกเฉพาะเมื่อปิดออเดอร์สำเร็จ (DEAL_ENTRY_OUT) เท่านั้น ไม่ใช่ตอนเปิด
 * @param features ข้อมูล Snapshot ในขณะที่เปิดคำสั่ง (4 technical features)
 * @param signal   SignalPack สำหรับดึงค่า SMC fields (smc_bias, smc_zone, buy/sell quality)
 * @param label    ผลลัพธ์จริง: 1=กำไร (pnl>0), 0=ขาดทุน (pnl<=0) ใช้ pnl รวม commission+swap
 */
void NeuralBridgeTrain(const MarketSnapshot &features, const SignalPack &signal, int label)
{
   if(g_neural_socket == INVALID_HANDLE) return;
   
   double atr_pct = features.atr / features.ask * 1000.0;
   double ema_diff = features.ema_fast - features.ema_slow;
   
   // เตรียมข้อมูลในรูปแบบ String:
   // "TRN,adx,rsi,atr_pct,ema_diff,smc_bias,smc_zone,smc_buy_quality,smc_sell_quality,label"
   string msg = StringFormat("TRN,%.2f,%.2f,%.5f,%.5f,%.1f,%.1f,%.4f,%.4f,%d",
                             features.adx, features.rsi, atr_pct, ema_diff,
                             signal.smc_bias, signal.smc_zone,
                             signal.smc_buy_quality, signal.smc_sell_quality,
                             label);
   
   uchar req[];
   StringToCharArray(msg, req);
   // ส่งข้อมูลแบบ "Fire and Forget" (ส่งแล้วไปต่อทันที ไม่รอการตอบกลับ) เพื่อรักษาความเร็วของระบบเทรด
   SocketSend(g_neural_socket, req, ArraySize(req)-1);
}

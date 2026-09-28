#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Market Depth Module - ระบบวิเคราะห์ความลึกของตลาด (Level 2)          |
//| ทำหน้าที่: ติดตามและวิเคราะห์ข้อมูล Order Book (Depth of Market)        |
//| เพื่อประเมินแรงซื้อแรงขายจริงในตลาด (Order Flow Analysis)             |
//+------------------------------------------------------------------+

/**
 * MarketDepthInit: ฟังก์ชันเริ่มต้นการใช้งาน Market Depth (DOM)
 * อธิบายกระบวนการ:
 * 1. เรียกใช้ฟังก์ชัน MarketBookAdd เพื่อบอกให้ Terminal เริ่มส่งข้อมูล Order Book
 * 2. ตรวจสอบผลลัพธ์: หากโบรกเกอร์ไม่รองรับข้อมูลประเภทนี้ จะมีการแจ้งเตือน (Warning)
 * 3. หากสำเร็จ ข้อมูล DOM จะถูกอัปเดตแบบ Real-time เข้ามาใน Buffer ของ Terminal
 */
bool MarketDepthInit(string symbol)
{
   // ลงทะเบียนเพื่อรับข้อมูลระดับ Level 2 สำหรับคู่เงินที่ต้องการ
   if(!MarketBookAdd(symbol))
   {
      LogWarning("Market Depth: Failed to subscribe to DOM for " + symbol + ". Feature might be disabled by broker.");
      return false;
   }
   LogInfo("Market Depth: Subscribed to DOM for " + symbol);
   return true;
}

/**
 * MarketDepthDeinit: ฟังก์ชันยกเลิกการสมัครรับข้อมูล Market Depth (DOM)
 * อธิบายกระบวนการ:
 * - เรียกใช้ MarketBookRelease เพื่อคืนทรัพยากรและหยุดการส่งข้อมูล DOM ของคู่เงินนั้นๆ
 * - ควรเรียกใช้เมื่อปิด EA เพื่อลดภาระการประมวลผลและ Bandwidth
 */
void MarketDepthDeinit(string symbol)
{
   MarketBookRelease(symbol);
}

/**
 * ComputeDOMImbalance: คำนวณค่าความไม่สมดุลของแรงซื้อและแรงขาย (Imbalance)
 * อธิบายกระบวนการ:
 * 1. ดึงรายการคำสั่งซื้อขายทั้งหมด (MqlBookInfo) ณ ปัจจุบัน
 * 2. วนลูปคำนวณน้ำหนัก (Weight) ให้กับแต่ละระดับราคา:
 *    - คำสั่งที่อยู่ใกล้ราคาปัจจุบัน (Mid Price) จะได้รับน้ำหนักสูงที่สุด
 *    - คำสั่งที่อยู่ไกลออกไป น้ำหนักจะลดลงแบบ Exponential เพื่อป้องกันข้อมูลหลอก (Spoofing)
 * 3. สะสมวอลลุ่มแยกตามฝั่ง: weighted_bid_vol (แรงซื้อ) และ weighted_ask_vol (แรงขาย)
 * 4. คำนวณค่า Imbalance ในช่วง -1.0 ถึง 1.0 (หากเป็นบวกแสดงว่าแรงซื้อหนาแน่นกว่า)
 */
bool ComputeDOMImbalance(string symbol, MarketSnapshot &snapshot)
{
   MqlBookInfo book[];
   // ดึงข้อมูลคำสั่งซื้อขายทั้งหมดที่รออยู่ในตลาด
   if(!MarketBookGet(symbol, book)) return false;

   double weighted_bid_vol = 0;
   double weighted_ask_vol = 0;
   // ราคาตรงกลางระหว่าง Bid และ Ask
   double mid_price = (SymbolInfoDouble(symbol, SYMBOL_BID) + SymbolInfoDouble(symbol, SYMBOL_ASK)) / 2.0;

   int size = ArraySize(book);
   for(int i = 0; i < size; i++)
   {
      // คำนวณระยะห่าง (Distance) ในหน่วยจุด
      double distance = MathAbs(book[i].price - mid_price) / (SymbolInfoDouble(symbol, SYMBOL_POINT) > 0 ? SymbolInfoDouble(symbol, SYMBOL_POINT) : 0.00001);
      if(distance == 0) distance = 0.5; 

      // ให้น้ำหนักกับคำสั่งที่พร้อมจะจับคู่ (ใกล้ราคาปัจจุบัน) มากที่สุด
      double weight = 1.0 / MathPow(distance, 0.5); 
      
      // รวมน้ำหนักวอลลุ่มแยกฝั่ง
      if(book[i].type == BOOK_TYPE_BUY || book[i].type == BOOK_TYPE_BUY_MARKET)
         weighted_bid_vol += (double)book[i].volume * weight;
      else if(book[i].type == BOOK_TYPE_SELL || book[i].type == BOOK_TYPE_SELL_MARKET)
         weighted_ask_vol += (double)book[i].volume * weight;
   }

   // สรุปค่าความแตกต่างสุทธิ
   double total_weighted_vol = weighted_bid_vol + weighted_ask_vol;
   if(total_weighted_vol > 0)
   {
      double imb = (weighted_bid_vol - weighted_ask_vol) / total_weighted_vol;
      
      // ควบคุมความถูกต้องของตัวเลข
      if(!MathIsValidNumber(imb)) imb = 0;
      imb = MathMax(-1.0, MathMin(1.0, imb)); // ปรับขอบเขตให้อยู่ในช่วง -1 ถึง 1
      
      snapshot.dom_imbalance = imb;
   }
   else
      snapshot.dom_imbalance = 0;

   return true;
}

/**
 * IsDOMPressureAgainst: ระบบตรวจสอบแรงต้านจากผู้เล่นรายใหญ่ (Veto System)
 * อธิบายกระบวนการ:
 * 1. รับทิศทางสัญญาณ (BUY/SELL) และค่า Imbalance ล่าสุด
 * 2. ตรวจสอบว่าทิศทางที่จะเข้าเทรด สวนทางกับ "กำแพง" ราคาขนาดใหญ่หรือไม่:
 *    - หากจะ Buy: แต่ค่า Imbalance ติดลบมาก (แรงขายหนาแน่น) จะสั่งบล็อกการเข้าเทรด
 *    - หากจะ Sell: แต่ค่า Imbalance เป็นบวกมาก (แรงซื้อหนาแน่น) จะสั่งบล็อกการเข้าเทรด
 * 3. ช่วยลดความเสี่ยงในการเข้าเทรดตรงจังหวะที่มีรายใหญ่ขวางราคาอยู่
 */
bool IsDOMPressureAgainst(const SignalPack &signal, const MarketSnapshot &snapshot)
{
   // ดึงค่าเกณฑ์ความเข้มงวดในการตรวจสอบ
   double sell_pressure_threshold = -G_DOM_VETO_THRESHOLD; 
   double buy_pressure_threshold  = G_DOM_VETO_THRESHOLD;

   // กรณีสัญญาณ Buy: เช็คว่าเจอแรงขายในระดับ 2 ขวางอยู่หรือไม่
   if(signal.direction == SIGNAL_BUY && snapshot.dom_imbalance < sell_pressure_threshold)
   {
      LogWarning(StringFormat("DOM VETO: Buy signal blocked by heavy SELL pressure (Imbalance: %.2f)", snapshot.dom_imbalance));
      return true; // พบแรงต้านสวนทาง: ให้บล็อก
   }

   // กรณีสัญญาณ Sell: เช็คว่าเจอแรงซื้อในระดับ 2 ขวางอยู่หรือไม่
   if(signal.direction == SIGNAL_SELL && snapshot.dom_imbalance > buy_pressure_threshold)
   {
      LogWarning(StringFormat("DOM VETO: Sell signal blocked by heavy BUY pressure (Imbalance: %.2f)", snapshot.dom_imbalance));
      return true; // พบแรงต้านสวนทาง: ให้บล็อก
   }

   return false; // ผ่านการตรวจสอบ
}

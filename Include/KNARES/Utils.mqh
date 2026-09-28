#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

//+------------------------------------------------------------------+
//| Utils Module - ฟังก์ชันช่วยเหลือทั่วไป                               |
//| ทำหน้าที่: ปรับแต่งราคา, ตรวจสอบเงื่อนไขโบรกเกอร์ และคำนวณมูลค่าจุด       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ตรวจสอบว่าระดับ SL/TP อยู่ในเกณฑ์ที่โบรกเกอร์อนุญาตหรือไม่              |
//| symbol: คู่เงิน, price: ราคาที่อ้างอิง, sl: ระดับตัดขาดทุน, tp: ระดับทำกำไร |
//| คืนค่า: true หากระดับราคาถูกกฎการเทรด (Stop/Freeze Level)           |
//+------------------------------------------------------------------+
bool CheckLevels(string symbol, double price, double sl, double tp)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   // ดึงระยะห่างขั้นต่ำที่โบรกเกอร์กำหนด (Stops Level และ Freeze Level)
   double stop_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double freeze_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
   double spread = (SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID));
   
   // Safety Buffer: เพิ่มระยะเผื่อเล็กน้อยเพื่อป้องกันความผิดพลาด 10016 (Invalid Stops) เมื่อราคาผันผวน
   double safety = ModifySafetyBufferPoints * point;
   double min_dist = MathMax(stop_level, MathMax(freeze_level, spread)) + safety;

   // ตรวจสอบระยะห่างของ SL เทียบกับราคาปัจจุบัน
   if(sl != 0 && MathAbs(price - sl) < min_dist)
   {
      // LogWarning(StringFormat("Modify Guard: SL too close (Dist: %.2f pts < Min: %.2f pts)", MathAbs(price-sl)/point, min_dist/point));
      return false;
   }
   // ตรวจสอบระยะห่างของ TP เทียบกับราคาปัจจุบัน
   if(tp != 0 && MathAbs(price - tp) < min_dist)
   {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ปรับปรุงระดับ SL/TP ก่อนส่งคำสั่งเข้าตลาด เพื่อให้ผ่านเกณฑ์ระยะห่างขั้นต่ำ   |
//| order_type: ประเภทออเดอร์, entry_price: ราคาเข้า, sl_in/tp_in: ค่าตั้งต้น |
//| sl_out/tp_out: ค่าที่ปรับแต่งแล้วสำหรับส่งคำสั่งจริง                      |
//+------------------------------------------------------------------+
bool PrepareStopsForEntry(string symbol, ENUM_ORDER_TYPE order_type, double entry_price, double sl_in, double tp_in, double &sl_out, double &tp_out)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long stops_level_pts = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level_pts = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   // คำนวณระยะห่างขั้นต่ำสุดที่เป็นไปได้
   double min_dist = MathMax((double)stops_level_pts, (double)freeze_level_pts) * point;
   if(min_dist <= 0.0)
      min_dist = point;

   // ปรับทศนิยมราคาให้ตรงตามมาตรฐานของคู่เงิน (Normalize)
   sl_out = (sl_in == 0.0) ? 0.0 : NormalizePrice(symbol, sl_in);
   tp_out = (tp_in == 0.0) ? 0.0 : NormalizePrice(symbol, tp_in);
   double price = NormalizePrice(symbol, entry_price);

   // ตรวจสอบและปรับระยะ SL/TP ให้อยู่ในฝั่งที่ถูกต้องและห่างพอตามกฎ
   if(order_type == ORDER_TYPE_BUY)
   {
      // สำหรับหน้า Buy: SL ต้องต่ำกว่าราคา และ TP ต้องสูงกว่าราคา
      if(sl_out != 0.0 && (price - sl_out) < min_dist)
         sl_out = NormalizePrice(symbol, price - min_dist);
      if(tp_out != 0.0 && (tp_out - price) < min_dist)
         tp_out = NormalizePrice(symbol, price + min_dist);
      // ตรวจสอบ Logic Error
      if(sl_out != 0.0 && sl_out >= price) return false;
      if(tp_out != 0.0 && tp_out <= price) return false;
   }
   else if(order_type == ORDER_TYPE_SELL)
   {
      // สำหรับหน้า Sell: SL ต้องสูงกว่าราคา และ TP ต้องต่ำกว่าราคา
      if(sl_out != 0.0 && (sl_out - price) < min_dist)
         sl_out = NormalizePrice(symbol, price + min_dist);
      if(tp_out != 0.0 && (price - tp_out) < min_dist)
         tp_out = NormalizePrice(symbol, price - min_dist);
      // ตรวจสอบ Logic Error
      if(sl_out != 0.0 && sl_out <= price) return false;
      if(tp_out != 0.0 && tp_out >= price) return false;
   }
   else
   {
      return false;
   }

   // ตรวจสอบความถูกต้องขั้นสุดท้ายก่อนส่งออก
   return CheckLevels(symbol, price, sl_out, tp_out);
}

//+------------------------------------------------------------------+
//| ปรับปรุงราคาให้ตรงกับ Tick Size ของโบรกเกอร์ (Rounding)            |
//| ช่วยป้องกัน Error 10015 (Invalid Price)                             |
//+------------------------------------------------------------------+
double NormalizePrice(string symbol, double price)
{
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size == 0) return price;
   // ปัดเศษราคาให้หารด้วย Tick Size ลงตัว
   return MathRound(price / tick_size) * tick_size;
}

//+------------------------------------------------------------------+
//| ตรวจสอบสถานะการเปิดทำการของตลาด (Trading Sessions)                |
//+------------------------------------------------------------------+
bool IsMarketOpen(string symbol)
{
   ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   // ตลาดต้องไม่อยู่ในโหมด Disabled หรือ Close Only (ซึ่งส่งคำสั่งเปิดไม่ได้)
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return false;
      
   return true;
}

//+------------------------------------------------------------------+
//| แปลงระยะจุด (Points) ให้เป็นมูลค่าเงินตามขนาด Lot ที่ระบุ               |
//| ใช้สำหรับการคำนวณ Risk in Dollars                                  |
//+------------------------------------------------------------------+
double PointsToMoney(string symbol, double points, double lots)
{
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(tick_size == 0) return 0;
   // สูตรคำนวณมูลค่ากำไร/ขาดทุนจากระยะราคาและขนาด Lot
   return (points * point) * (tick_value / tick_size) * lots;
}

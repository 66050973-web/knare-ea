#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#ifndef __KNARES_SMC_VISUALIZER_MQH__
#define __KNARES_SMC_VISUALIZER_MQH__

#include "Types.mqh"
#include "SMCContext.mqh"

//+------------------------------------------------------------------+
//| SMC Visual Overlay - ระบบแสดงผลข้อมูล Smart Money Concepts         |
//| Purpose: draw lightweight Smart Money Concepts context on MT5      |
//| chart for Strategy Tester Visual Mode and live debugging.          |
//| This is a visual/debug layer only. It must not affect trade logic. |
//| (เป็นเพียงเลเยอร์แสดงผลบนกราฟ ไม่ส่งผลต่อตรรกะการเทรดแต่อย่างใด)          |
//+------------------------------------------------------------------+

/**
 * สร้างคำนำหน้าชื่อ (Prefix) สำหรับวัตถุบนกราฟ
 * เพื่อให้ง่ายต่อการจัดการและลบวัตถุทั้งหมดที่เกี่ยวข้องกับ SMC ออกจากกราฟ
 * @param symbol ชื่อคู่เงิน
 * @return String ที่เป็น Prefix สำหรับชื่อ Object
 */
string SMCVisualPrefix(const string symbol)
{
   return "KNARES_SMC_" + symbol + "_";
}

/**
 * กำหนดสีตามทิศทางความได้เปรียบของตลาด (Bias)
 * @param bias สถานะความได้เปรียบ (Bullish, Bearish, Neutral)
 * @return สีที่จะใช้แสดงผล
 */
color SMCVisualBiasColor(const ENUM_SMC_BIAS bias)
{
   if(bias == SMC_BIAS_BULLISH) return clrLime;    // ขาขึ้นใช้สีเขียว
   if(bias == SMC_BIAS_BEARISH) return clrTomato;  // ขาลงใช้สีแดง
   return clrSilver;                               // สภาวะไม่ชัดเจนใช้สีเทา
}

/**
 * กำหนดสีตามโซนราคาของ SMC
 * @param zone โซนราคา (Premium, Discount, Equilibrium)
 * @return สีที่จะใช้แสดงผล
 */
color SMCVisualZoneColor(const ENUM_SMC_ZONE zone)
{
   if(zone == SMC_ZONE_PREMIUM) return clrTomato;     // โซนราคาแพง (Premium) ใช้สีแดง
   if(zone == SMC_ZONE_DISCOUNT) return clrLime;      // โซนราคาถูก (Discount) ใช้สีเขียว
   if(zone == SMC_ZONE_EQUILIBRIUM) return clrGray;   // โซนราคาสมดุล (Equilibrium) ใช้สีเทา
   return clrSilver;
}

/**
 * ตรวจสอบว่าควรทำการอัปเดตการแสดงผลบนกราฟหรือไม่
 * ใช้เพื่อป้องกันการประมวลผลกราฟซ้ำซ้อนซึ่งอาจทำให้ระบบหน่วง (Lag)
 * @param symbol ชื่อคู่เงิน
 * @param is_new_bar สถานะว่าเป็นแท่งเทียนใหม่หรือไม่
 * @return true หากควรทำการอัปเดต, false หากยังไม่ต้องอัปเดต
 */
bool SMCVisualShouldUpdate(const string symbol, const bool is_new_bar)
{
   // หากผู้ใช้ปิดการแสดงผลอินดิเคเตอร์ SMC ให้ข้ามไปทันที
   if(!ShowSMCIndicator)
      return false;

   // กรณีตั้งค่าให้อัปเดตเฉพาะแท่งเทียนใหม่
   if(ShowSMCOnlyOnNewBar && !is_new_bar)
   {
      static string keys[];
      static datetime last_update[];
      datetime now = TimeCurrent();
      string key = symbol;
      int idx = -1;
      // ค้นหาดัชนีของคู่เงินในหน่วยความจำชั่วคราว
      for(int i = 0; i < ArraySize(keys); i++)
      {
         if(keys[i] == key) { idx = i; break; }
      }
      // หากยังไม่มีข้อมูลคู่เงินนี้ ให้เพิ่มเข้าสู่ระบบ
      if(idx < 0)
      {
         idx = ArraySize(keys);
         ArrayResize(keys, idx + 1);
         ArrayResize(last_update, idx + 1);
         keys[idx] = key;
         last_update[idx] = 0;
      }
      // ตรวจสอบว่าเวลาที่ผ่านไปถึงกำหนดการอัปเดตที่ตั้งไว้หรือไม่ (SMCVisualUpdateSeconds)
      if(now - last_update[idx] < SMCVisualUpdateSeconds)
         return false;
      last_update[idx] = now;
   }
   return true;
}

/**
 * วาดหรืออัปเดตข้อความแบบ Label (ยึดตามตำแหน่งหน้าจอ ไม่ใช่ตามราคา)
 */
void SMCVisualDrawLabel(const string name, const string text, const int x, const int y, const color clr, const int font_size = 10)
{
   // หากยังไม่มี Object นี้บนกราฟ ให้ทำการสร้างใหม่
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); // ยึดมุมซ้ายบน
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); // ห้ามผู้ใช้ลากหรือคลิกเลือก
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);     // ซ่อนจากรายการวัตถุ
   }

   // อัปเดตข้อความและสี
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

/**
 * วาดเส้นแนวนอน (Horizontal Line) สำหรับแสดงแนวรับแนวต้านสำคัญ
 */
void SMCVisualDrawHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style = STYLE_DOT, const int width = 1)
{
   if(price <= 0.0) return;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);       // ไว้ด้านหลังกราฟแท่งเทียน
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
}

/**
 * วาดกล่องสี่เหลี่ยม (Rectangle) สำหรับแสดงโซนราคาต่างๆ (Premium/Discount)
 */
void SMCVisualDrawRect(const string name, const datetime t1, const datetime t2, const double price_high, const double price_low, const color clr)
{
   if(price_high <= price_low || t1 <= 0 || t2 <= 0) return;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price_high, t2, price_low);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, ShowSMCZoneFill); // เลือกว่าจะระบายสีทึบหรือไม่
   }

   ObjectMove(0, name, 0, t1, price_high);
   ObjectMove(0, name, 1, t2, price_low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, ShowSMCZoneFill);
}

/**
 * วาดข้อความกำกับที่ตำแหน่งราคาและเวลาที่กำหนดบนกราฟ
 */
void SMCVisualDrawTextAtPrice(const string name, const datetime t, const double price, const string text, const color clr, const int font_size = 9)
{
   if(price <= 0.0 || t <= 0) return;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

/**
 * วาดแผงควบคุม Dashboard แสดงสรุปสถานะ SMC อย่างย่อบนกราฟ
 */
void SMCVisualDrawDashboard(const string symbol, const SMCContext &ctx, const MarketSnapshot &snap, const ENUM_REGIME_TYPE runtime_regime, const string status_text, const string reason_text)
{
   if(!ShowSMCDashboard) return;

   string p = SMCVisualPrefix(symbol);
   int x = SMCVisualDashboardX;
   int y = SMCVisualDashboardY;
   int line = 16; // ระยะห่างระหว่างแต่ละบรรทัด

   // เตรียมข้อมูลที่จะแสดงผล
   string bias = ctx.valid ? SMCBiasToString(ctx.bias) : "NA";
   string zone = ctx.valid ? SMCZoneToString(ctx.zone) : "NA";
   double pos = ctx.valid ? ctx.position_in_range : -1.0;
   double q_buy = ctx.valid ? ctx.buy_quality : 0;
   double q_sell = ctx.valid ? ctx.sell_quality : 0;

   // ตัดข้อความเหตุผลให้สั้นลงหากยาวเกินไปเพื่อไม่ให้ล้นหน้าจอ
   string reason = reason_text;
   if(StringLen(reason) > 34) reason = StringSubstr(reason, 0, 31) + "...";

   // วาดแต่ละส่วนของ Dashboard
   SMCVisualDrawLabel(p + "TITLE",  "SMC Context", x, y, clrWhite, 9);
   SMCVisualDrawLabel(p + "STATUS", status_text, x + 110, y, (StringFind(status_text, "BLOCK") >= 0 ? clrTomato : clrLime), 8);
   SMCVisualDrawLabel(p + "BIAS",   "Bias " + bias + " | Zone " + zone + " " + DoubleToString(pos, 2), x, y + line, ctx.valid ? SMCVisualBiasColor(ctx.bias) : clrSilver, 8);
   SMCVisualDrawLabel(p + "QUALITY", "Quality (B/S): " + DoubleToString(q_buy, 2) + " / " + DoubleToString(q_sell, 2), x, y + line*2, clrYellow, 8);
   SMCVisualDrawLabel(p + "REGIME", "Regime " + EnumToString(runtime_regime) + " | HTF " + DoubleToString(snap.htf_trend,0) + " | ADX " + DoubleToString(snap.adx,1), x, y + line*3, clrSilver, 8);
   SMCVisualDrawLabel(p + "REASON", reason, x, y + line*4, clrOrange, 8);
}

/**
 * วาดพื้นที่โซนราคาสำคัญ (Premium, Equilibrium, Discount) ลงบนกราฟ
 */
void SMCVisualDrawZones(const string symbol, const SMCContext &ctx)
{
   if(!ShowSMCZones || !ctx.valid) return;
   if(ctx.range_high <= ctx.range_low) return;

   // กำหนดขอบเขตเวลาที่จะแสดงกล่องโซน (ย้อนหลังและไปข้างหน้า)
   datetime t1 = iTime(symbol, _Period, SMCVisualZoneLookbackBars);
   if(t1 <= 0) t1 = TimeCurrent() - PeriodSeconds(_Period) * SMCVisualZoneLookbackBars;
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * SMCVisualZoneForwardBars;

   // คำนวณขอบเขตราคาของแต่ละโซนตามเปอร์เซ็นต์ที่กำหนดใน Config
   double range = ctx.range_high - ctx.range_low;
   double premium_high = ctx.range_high;
   double premium_low = ctx.range_low + range * SMCPremiumLevel;
   double eq_high = premium_low;
   double eq_low = ctx.range_low + range * SMCDiscountLevel;
   double discount_high = eq_low;
   double discount_low = ctx.range_low;

   string p = SMCVisualPrefix(symbol);
   // วาดกล่องสี่เหลี่ยมแสดงทั้ง 3 โซน
   SMCVisualDrawRect(p + "PREMIUM_ZONE", t1, t2, premium_high, premium_low, SMCVisualPremiumColor);
   SMCVisualDrawRect(p + "EQUILIBRIUM_ZONE", t1, t2, eq_high, eq_low, SMCVisualEquilibriumColor);
   SMCVisualDrawRect(p + "DISCOUNT_ZONE", t1, t2, discount_high, discount_low, SMCVisualDiscountColor);

   // วาดเส้นแนวนอนแสดงขอบเขต Range สูงสุด, ต่ำสุด และจุดกึ่งกลาง
   SMCVisualDrawHLine(p + "RANGE_HIGH", ctx.range_high, clrTomato, STYLE_SOLID, 1);
   SMCVisualDrawHLine(p + "RANGE_LOW", ctx.range_low, clrLime, STYLE_SOLID, 1);
   SMCVisualDrawHLine(p + "RANGE_MID", ctx.range_mid, clrSilver, STYLE_DOT, 1);
}

/**
 * วาดป้ายกำกับโครงสร้างราคาที่สำคัญ เช่น BOS (Break of Structure) หรือ CHoCH (Change of Character)
 */
void SMCVisualDrawStructureLabels(const string symbol, const SMCContext &ctx)
{
   if(!ShowSMCStructureLabels || !ctx.valid) return;

   datetime t = TimeCurrent();
   // คำนวณระยะห่างเพื่อไม่ให้ข้อความซ้อนทับกับเส้นราคา
   double offset = MathMax(_Point * 50, (ctx.range_high - ctx.range_low) * 0.03);
   string p = SMCVisualPrefix(symbol);

   // แสดงป้ายกำกับตามสภาวะโครงสร้างที่ตรวจพบ
   if(ctx.bullish_bos) SMCVisualDrawTextAtPrice(p + "BULL_BOS", t, ctx.range_high + offset, "Bullish BOS", clrLime);
   if(ctx.bearish_bos) SMCVisualDrawTextAtPrice(p + "BEAR_BOS", t, ctx.range_low - offset, "Bearish BOS", clrTomato);
   if(ctx.bullish_choch) SMCVisualDrawTextAtPrice(p + "BULL_CHOCH", t, ctx.range_mid + offset, "Bullish CHoCH", clrAqua);
   if(ctx.bearish_choch) SMCVisualDrawTextAtPrice(p + "BEAR_CHOCH", t, ctx.range_mid - offset, "Bearish CHoCH", clrOrange);
}

/**
 * ลบวัตถุแสดงผลรุ่นเก่าที่ค้างอยู่บนกราฟเพื่อป้องกันหน่วยความจำเต็ม
 */
void SMCVisualDeleteLegacyBlockMarkers(const string symbol)
{
   string prefix = SMCVisualPrefix(symbol) + "BLOCK_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

/**
 * วาดเครื่องหมายระบุจุดที่สัญญาณถูกบล็อก (Block Marker) พร้อมระบุเหตุผลอย่างย่อ
 */
void SMCVisualDrawBlockMarker(const string symbol, const SignalPack &signal, const string reason_text)
{
   if(!ShowSMCBlockLabels || reason_text == "") return;

   double price = (signal.direction == SIGNAL_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   if(price <= 0.0) price = iClose(symbol, _Period, 0);

   datetime t = iTime(symbol, _Period, 0);
   if(t <= 0) t = TimeCurrent();

   string side = (signal.direction == SIGNAL_BUY ? "BUY" : (signal.direction == SIGNAL_SELL ? "SELL" : "SIG"));
   string name = SMCVisualPrefix(symbol) + "LAST_BLOCK_" + side;

   string short_reason = reason_text;
   if(StringLen(short_reason) > 80) short_reason = StringSubstr(short_reason, 0, 80) + "...";

   string txt = side + " BLOCK: " + short_reason;
   SMCVisualDrawTextAtPrice(name, t, price, txt, clrOrange, 8);
}

/**
 * ฟังก์ชันหลักในการสั่งวาดเลเยอร์แสดงผล SMC ทั้งหมดลงบนกราฟ
 */
void PlotSMCOverlay(const string symbol, const SMCContext &ctx, const MarketSnapshot &snap, const ENUM_REGIME_TYPE runtime_regime, const bool is_new_bar, const string status_text, const string reason_text)
{
   // ตรวจสอบว่าถึงเวลาอัปเดตกราฟหรือยัง
   if(!SMCVisualShouldUpdate(symbol, is_new_bar)) return;

   // เรียกใช้ฟังก์ชันย่อยในการวาดส่วนต่างๆ
   SMCVisualDrawDashboard(symbol, ctx, snap, runtime_regime, status_text, reason_text);
   SMCVisualDrawZones(symbol, ctx);
   SMCVisualDrawStructureLabels(symbol, ctx);
   
   // สั่งให้กราฟทำการวาดภาพใหม่ทันที
   ChartRedraw(0);
}

/**
 * ลบวัตถุทั้งหมดที่เกี่ยวข้องกับ SMC ออกจากกราฟ (ใช้ตอนปิด EA)
 */
void ClearSMCVisualObjects(const string symbol)
{
   string prefix = SMCVisualPrefix(symbol);
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

#endif // __KNARES_SMC_VISUALIZER_MQH__

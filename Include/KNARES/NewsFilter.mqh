#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| News Filter Module - ระบบกรองข่าวสารเพื่อหลีกเลี่ยงความผันผวนสูง        |
//+------------------------------------------------------------------+

// โครงสร้างข้อมูลสำหรับเก็บรายละเอียดของแต่ละเหตุการณ์ข่าว
struct NewsEvent
{
   datetime time;   // วันเวลาที่เกิดข่าว
   string   symbol; // คู่เงินหรือเศรษฐกิจที่เกี่ยวข้อง (เช่น USD, EUR, ALL)
   int      impact; // ระดับความรุนแรงของข่าว (1=ต่ำ, 2=กลาง, 3=สูง)
};

// อาร์เรย์สำหรับเก็บรายการข่าวที่มีความสำคัญสูงทั้งหมด
NewsEvent high_impact_news[];

/**
 * เริ่มต้นการทำงานของระบบกรองข่าวสาร
 * ทำการล้างข้อมูลเดิมและเตรียมพื้นที่สำหรับรับข้อมูลใหม่
 * @return true เสมอในรุ่นนี้
 */
bool NewsFilterInit()
{
   if(!EnableNewsFilter) return true;
   
   // ล้างข้อมูลในอาร์เรย์รายการข่าวให้ว่างเปล่า
   ArrayResize(high_impact_news, 0);
   
   LogInfo("News Filter Framework initialized.");
   return true;
}

/**
 * ตรวจสอบว่าในขณะนี้มีข่าวสารสำคัญที่กำลังส่งผลกระทบต่อคู่เงินที่ระบุหรือไม่
 * @param symbol ชื่อคู่เงินที่ต้องการตรวจสอบ
 * @return true หากอยู่ในช่วงเวลาที่ควรเลี่ยงการเทรดเนื่องจากข่าว, false หากปลอดภัย
 */
bool IsNewsActive(string symbol)
{
   // หากปิดการใช้งานระบบกรองข่าว ให้ถือว่าปลอดภัยเสมอ
   if(!EnableNewsFilter) return false;

   datetime now = TimeCurrent();
   
   // กำหนดขอบเขตเวลาความปลอดภัย: ห้ามเทรดก่อนข่าว 30 นาที และหลังข่าว 60 นาที
   int minutes_before = 30;
   int minutes_after  = 60;

   // วนลูปตรวจสอบรายการข่าวทั้งหมดที่มี
   for(int i=0; i<ArraySize(high_impact_news); i++)
   {
      // ตรวจสอบความเกี่ยวข้องของข่าวกับคู่เงิน (เช่น เป็นข่าว USD หรือข่าวที่ส่งผลต่อทุกคู่เงิน)
      if(high_impact_news[i].symbol == symbol || high_impact_news[i].symbol == "USD" || high_impact_news[i].symbol == "ALL")
      {
         // ตรวจสอบว่าเวลาปัจจุบันอยู่ภายในขอบเขตอันตราย (Buffer Zone) หรือไม่
         if(now >= high_impact_news[i].time - (minutes_before * 60) &&
            now <= high_impact_news[i].time + (minutes_after * 60))
         {
            return true; // อยู่ในช่วงข่าวสำคัญ ให้หยุดการเทรด
         }
      }
   }

   return false;
}

/**
 * ฟังก์ชันสำหรับเพิ่มข้อมูลข่าวสารเข้าสู่ระบบ
 * @param news_time เวลาเกิดข่าว
 * @param sym คู่เงินที่เกี่ยวข้อง
 * @param impact ระดับความสำคัญ
 */
void AddNews(datetime news_time, string sym, int impact)
{
   int size = ArraySize(high_impact_news);
   // ขยายขนาดอาร์เรย์เพื่อรองรับข้อมูลใหม่
   ArrayResize(high_impact_news, size + 1);
   high_impact_news[size].time = news_time;
   high_impact_news[size].symbol = sym;
   high_impact_news[size].impact = impact;
}

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "SharedGlobals.mqh"
#include "NewsFilter.mqh"

//+------------------------------------------------------------------+
//| News Connector Module - ระบบจัดการข่าวสารความเร็วสูง (Apex Engine)    |
//+------------------------------------------------------------------+
// หมายเหตุ: g_is_news_active / g_next_news_name / g_minutes_to_next_news
// ถูกย้ายไปประกาศไว้ที่ SharedGlobals.mqh แล้ว (เพื่อให้ Visualization.mqh ใช้ได้ก่อน include ไฟล์นี้)

/**
 * อัปเดตสถานะข่าวสารโดยตรวจสอบจากรายการข่าวที่มีอยู่
 * ฟังก์ชันนี้ควรเรียกใช้เป็นระยะ (เช่น ทุก 1 นาที) ผ่านระบบ Timer
 * @param symbol ชื่อคู่เงินที่ต้องการตรวจสอบ
 */
void UpdateNewsStatus(string symbol)
{
   // หากปิดใช้งานระบบกรองข่าว หรือไม่มีข้อมูลข่าวสาร ให้ข้ามการทำงาน
   if(!EnableNewsFilter || ArraySize(high_impact_news) == 0) return;

   datetime now = TimeCurrent();
   g_is_news_active = false;
   g_minutes_to_next_news = 999;

   for(int i=0; i<ArraySize(high_impact_news); i++)
   {
      // คำนวณความต่างเวลาเป็นนาทีระหว่างปัจจุบันกับเวลาเกิดข่าว
      int diff_minutes = (int)((high_impact_news[i].time - now) / 60);
      
      // 1. ตรวจสอบว่าเวลาปัจจุบันอยู่ในช่วง "ห้ามเทรด" (ก่อนข่าว 30 นาที ถึงหลังข่าว 60 นาที) หรือไม่
      if(now >= high_impact_news[i].time - (30 * 60) && now <= high_impact_news[i].time + (60 * 60))
      {
         // ตรวจสอบว่าเป็นข่าวของคู่เงินที่กำลังเทรด หรือข่าวรวมที่มีผลกระทบกว้าง (เช่น USD)
         if(high_impact_news[i].symbol == symbol || high_impact_news[i].symbol == "USD" || high_impact_news[i].symbol == "ALL")
         {
            g_is_news_active = true;
            g_next_news_name = high_impact_news[i].symbol + " High Impact";
            break; // พบข่าวที่ส่งผลกระทบแล้ว ไม่ต้องหาต่อในลูปนี้
         }
      }
      
      // 2. ค้นหาข่าวในอนาคตที่ใกล้ที่สุดเพื่อนำไปแสดงผลบน Dashboard
      if(diff_minutes > 0 && diff_minutes < g_minutes_to_next_news)
      {
         g_minutes_to_next_news = diff_minutes;
      }
   }
}

/**
 * ตรวจสอบสถานะว่าระบบข่าวมีการแจ้งเตือนว่าห้ามเทรดหรือไม่
 * @param symbol ชื่อคู่เงิน
 * @return true หากอยู่ในช่วงข่าวสารสำคัญ, false หากสภาวะปกติ
 */
bool IsNewsConnectorActive(string symbol)
{
   // ส่งคืนค่าจากตัวแปร Global เพื่อความรวดเร็วในการประมวลผล (O(1))
   return g_is_news_active;
}

/**
 * ดึงข้อมูลข่าวสารจาก ForexFactory API พร้อมระบบ Caching รายวัน
 */
void FetchRealNews()
{
   string cache_file = "KNARES_NewsCache_" + TimeToString(TimeCurrent(), TIME_DATE) + ".json";
   StringReplace(cache_file, ".", ""); // Remove dots from date format (e.g. 20260816)
   
   // Check if today's cache file exists
   if(FileIsExist(cache_file))
   {
      int handle = FileOpen(cache_file, FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         string json_data = "";
         while(!FileIsEnding(handle))
         {
            json_data += FileReadString(handle);
         }
         FileClose(handle);
         
         LogInfo("News Engine: Loaded today's news from cache (" + cache_file + ")");
         ParseNewsJSON(json_data);
         return;
      }
   }
   
   // If not, fetch from API
   LogInfo("News Engine: Fetching fresh news from nfs.faireconomy.media...");
   
   string cookie=NULL, headers;
   char post[], result[];
   string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
   
   int res = WebRequest("GET", url, cookie, NULL, 5000, post, 0, result, headers);
   
   if(res == 200)
   {
      string json_data = CharArrayToString(result);
      
      // Save to cache
      int handle = FileOpen(cache_file, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         FileWriteString(handle, json_data);
         FileClose(handle);
      }
      
      LogInfo("News Engine: Successfully fetched and cached news.");
      ParseNewsJSON(json_data);
   }
   else
   {
      LogError("News Engine: Failed to fetch news. HTTP Error " + IntegerToString(res) + " (Check 'Allow WebRequest' in Options)");
   }
}

/**
 * แยกข้อมูลข่าวสารจาก JSON String แบบรวดเร็วโดยไม่พึ่งพิง Library ภายนอก
 */
void ParseNewsJSON(string data)
{
   int pos = 0;
   int added_count = 0;
   
   while(pos >= 0)
   {
      int start_obj = StringFind(data, "{", pos);
      if(start_obj < 0) break;
      int end_obj = StringFind(data, "}", start_obj);
      if(end_obj < 0) break;
      
      string obj_str = StringSubstr(data, start_obj, end_obj - start_obj + 1);
      pos = end_obj + 1;
      
      // Extract country
      string country = "";
      int c_idx = StringFind(obj_str, "\"country\":");
      if(c_idx >= 0)
      {
         int q1 = StringFind(obj_str, "\"", c_idx + 10);
         int q2 = StringFind(obj_str, "\"", q1 + 1);
         country = StringSubstr(obj_str, q1 + 1, q2 - q1 - 1);
         StringTrimLeft(country); StringTrimRight(country);
      }
      
      // Extract date
      string date_str = "";
      int d_idx = StringFind(obj_str, "\"date\":");
      if(d_idx >= 0)
      {
         int q1 = StringFind(obj_str, "\"", d_idx + 7);
         int q2 = StringFind(obj_str, "\"", q1 + 1);
         date_str = StringSubstr(obj_str, q1 + 1, q2 - q1 - 1);
      }
      
      // Extract impact
      string impact_str = "";
      int i_idx = StringFind(obj_str, "\"impact\":");
      if(i_idx >= 0)
      {
         int q1 = StringFind(obj_str, "\"", i_idx + 9);
         int q2 = StringFind(obj_str, "\"", q1 + 1);
         impact_str = StringSubstr(obj_str, q1 + 1, q2 - q1 - 1);
      }
      
      if(StringLen(date_str) >= 19 && StringLen(country) > 0)
      {
         string d_part = StringSubstr(date_str, 0, 10);
         string t_part = StringSubstr(date_str, 11, 8);
         StringReplace(d_part, "-", ".");
         datetime n_time = StringToTime(d_part + " " + t_part);
         
         int n_imp = 1;
         if(impact_str == "High") n_imp = 3;
         else if(impact_str == "Medium") n_imp = 2;
         else n_imp = 1;
         
         // Only track Medium and High impact news to save memory
         if(n_imp >= 2 && n_time > TimeCurrent() - 86400)
         {
            AddNews(n_time, country, n_imp);
            added_count++;
         }
      }
   }
   
   LogInfo("News Engine: Successfully parsed " + IntegerToString(added_count) + " upcoming events.");
}

/**
 * ทำการแยกข้อมูลข่าวสารจากรูปแบบ CSV (Comma-Separated Values)
 * @param data ข้อมูลดิบในรูปแบบ String CSV
 */
void ParseNewsCSV(string data)
{
   string lines[];
   // แยกข้อมูลออกเป็นแต่ละบรรทัด
   int count = StringSplit(data, '\n', lines);
   int valid_news = 0;
   
   for(int i = 1; i < count; i++) // เริ่มที่ index 1 เพื่อข้าม Header บรรทัดแรก
   {
      // ตัดช่องว่างส่วนเกินหน้าและหลังข้อความ
      StringTrimLeft(lines[i]); StringTrimRight(lines[i]);
      if(StringLen(lines[i]) < 5) continue; // ข้ามบรรทัดว่างที่สั้นเกินไป
      
      string columns[];
      // แยกข้อมูลในบรรทัดออกเป็นคอลัมน์ (Time, Symbol, Impact)
      if(StringSplit(lines[i], ',', columns) >= 3)
      {
         datetime n_time = StringToTime(columns[0]);
         string   n_sym  = columns[1];
         StringTrimLeft(n_sym); StringTrimRight(n_sym);
         int      n_imp  = (int)StringToInteger(columns[2]);
         
         // กรองเฉพาะข่าวในอนาคต หรือข่าวในอดีตไม่เกิน 24 ชั่วโมง เพื่อลดการใช้หน่วยความจำ
         if(n_time > TimeCurrent() - 86400)
         {
            // เพิ่มข่าวที่ผ่านการตรวจสอบเข้าสู่ระบบ
            AddNews(n_time, n_sym, n_imp);
            valid_news++;
         }
      }
   }
}

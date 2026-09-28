#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Sentiment Filter Module - กรองสัญญาณเทรดตามความรู้สึกตลาดจากข่าว (News Sentiment)|
//| อ่านค่าจากไฟล์ JSON ที่สคริปต์ Python (fetch_sentiment.py) เขียนไว้เป็นระยะ  |
//| ถ้า EnableSentimentFilter=false ระบบจะไม่สน sentiment เลย (เทรดตามปกติ)   |
//+------------------------------------------------------------------+

/**
 * ดึงค่าตัวเลขที่ตามหลัง key ที่ระบุใน JSON string แบบง่าย (manual parse ไม่พึ่ง library ภายนอก)
 */
bool ExtractJsonNumber(const string &json_data, const string key, double &out_value)
{
   int idx = StringFind(json_data, "\"" + key + "\"");
   if(idx < 0) return false;

   int colon = StringFind(json_data, ":", idx);
   if(colon < 0) return false;

   int end = colon + 1;
   int len = StringLen(json_data);
   while(end < len && (StringGetCharacter(json_data, end) == ' ')) end++;
   int start = end;
   while(end < len)
   {
      ushort ch = StringGetCharacter(json_data, end);
      if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-') end++;
      else break;
   }

   string num_str = StringSubstr(json_data, start, end - start);
   if(StringLen(num_str) == 0) return false;

   out_value = StringToDouble(num_str);
   return true;
}

/**
 * ดึงค่า string ที่ตามหลัง key ที่ระบุใน JSON string แบบง่าย (manual parse)
 */
bool ExtractJsonString(const string &json_data, const string key, string &out_value)
{
   int idx = StringFind(json_data, "\"" + key + "\"");
   if(idx < 0) return false;

   int colon = StringFind(json_data, ":", idx);
   if(colon < 0) return false;

   int q1 = StringFind(json_data, "\"", colon + 1);
   if(q1 < 0) return false;
   int q2 = StringFind(json_data, "\"", q1 + 1);
   if(q2 < 0) return false;

   out_value = StringSubstr(json_data, q1 + 1, q2 - q1 - 1);
   return true;
}

/**
 * อ่านค่า aggregate_score จากไฟล์ JSON cache
 * @param score  ค่า sentiment score ที่อ่านได้ (-1.0 ถึง 1.0)
 * @param age_minutes อายุของข้อมูล (นาที) คำนวณจาก field "generated_at_utc" ที่ฝังมาใน JSON เอง
 *                    (ไม่ใช้ FileGetInteger(FILE_MODIFY_DATE) เพราะค่านั้นอิงเวลาท้องถิ่นของเครื่อง
 *                     ต่างจาก TimeGMT() ทำให้อายุคำนวณผิดเพี้ยนตาม timezone ของเครื่อง เช่น ติดลบหรือมากเกินจริง)
 * @return true หากอ่านไฟล์และดึงค่าได้สำเร็จ
 */
bool ReadSentimentCache(double &score, int &age_minutes)
{
   score = 0.0;
   age_minutes = 999999;

   if(!FileIsExist(SentimentCacheFileName))
   {
      return false;
   }

   int handle = FileOpen(SentimentCacheFileName, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      return false;
   }

   string json_data = "";
   while(!FileIsEnding(handle))
   {
      json_data += FileReadString(handle);
   }
   FileClose(handle);

   if(!ExtractJsonNumber(json_data, "aggregate_score", score))
      return false;

   // แปลง "generated_at_utc": "2026-09-18T15:52:09Z" -> datetime UTC โดยตรง
   // ทั้ง TimeGMT() และเวลาที่ parse ได้เป็น UTC เหมือนกัน จึงลบกันได้ตรง ๆ ไม่ขึ้นกับ timezone เครื่อง
   string gen_str;
   if(ExtractJsonString(json_data, "generated_at_utc", gen_str))
   {
      StringReplace(gen_str, "-", ".");
      StringReplace(gen_str, "T", " ");
      StringReplace(gen_str, "Z", "");
      datetime gen_time = StringToTime(gen_str);
      if(gen_time > 0)
         age_minutes = (int)((TimeGMT() - gen_time) / 60);
   }

   return true;
}

/**
 * แปลงค่า sentiment score ตัวเลขให้เป็น label อ่านง่าย สำหรับแสดงผลบน Dashboard
 */
string SentimentScoreToLabel(const double score)
{
   if(score <= -0.35) return "Bearish";
   if(score <= -0.15) return "Somewhat-Bearish";
   if(score < 0.15)   return "Neutral";
   if(score < 0.35)   return "Somewhat-Bullish";
   return "Bullish";
}

/**
 * ตรวจสอบว่าสัญญาณที่กำลังจะเข้า (dir) สวนทางกับ Sentiment ข่าวแรงพอที่จะข้ามหรือไม่
 * @param dir ทิศทางสัญญาณที่กำลังพิจารณา (SIGNAL_BUY / SIGNAL_SELL)
 * @return true หากควรข้าม (Skip) การเข้าเทรดรอบนี้เพราะ Sentiment สวนทางแรง
 */
bool IsSentimentConflicting(const ENUM_SIGNAL_DIRECTION dir)
{
   if(!EnableSentimentFilter) return false;

   double score = 0.0;
   int age_minutes = 0;

   if(!ReadSentimentCache(score, age_minutes))
   {
      // ไม่มีไฟล์หรืออ่านไม่ได้ -> ไม่บล็อก ปล่อยเทรดตามปกติ (fail-open)
      return false;
   }

   if(age_minutes > SentimentCacheMaxAgeMin)
   {
      // ข้อมูลเก่าเกินไป (Python script อาจหยุดทำงาน) -> ไม่ใช้กรอง เพื่อไม่ให้ EA ค้าง
      return false;
   }

   if(MathAbs(score) < SentimentSkipThreshold) return false;

   // Sentiment เป็นบวกแรง (Bullish ต่อ USD) = แรงกดดันขาลงต่อทองคำ (XAUUSD สวนทาง USD)
   // ดังนั้นตีความ: score > 0 (USD Bullish) ควรระวังฝั่ง BUY ทอง, score < 0 (USD Bearish) ควรระวังฝั่ง SELL ทอง
   if(dir == SIGNAL_BUY && score >= SentimentSkipThreshold) return true;
   if(dir == SIGNAL_SELL && score <= -SentimentSkipThreshold) return true;

   return false;
}

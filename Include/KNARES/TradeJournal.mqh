#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Trade Journal Module - ระบบบันทึกประวัติการเทรดลงไฟล์ CSV             |
//| ทำหน้าที่: บันทึกทุกธุรกรรมการเทรดอย่างละเอียด และสร้างรายงานสรุปรายสัปดาห์ |
//+------------------------------------------------------------------+

string journal_filename = ""; // ชื่อไฟล์บันทึกประวัติ (Log) ของคู่เงินปัจจุบัน

//+------------------------------------------------------------------+
//| ฟังก์ชันเขียนหัวตาราง (Header) สำหรับไฟล์ CSV                          |
//| file_handle: ตำแหน่งอ้างอิงของไฟล์ที่เปิดอยู่                            |
//+------------------------------------------------------------------+
void JournalWriteHeader(const int file_handle)
{
   FileWrite(file_handle,
      "Time","Symbol","Event","Action","Side","Lots","Price","SL","TP",
      "RetCode","RetcodeDesc","Deal","Order","Position","EntryType","Profit","Comment");
}

//+------------------------------------------------------------------+
//| ฟังก์ชันเริ่มต้นระบบบันทึก Log (ตรวจสอบโครงสร้างโฟลเดอร์และไฟล์)           |
//+------------------------------------------------------------------+
void JournalInit()
{
   string folder = "KNARES_Logs"; // โฟลเดอร์สำหรับเก็บไฟล์ Log ของระบบ
   if(!FolderCreate(folder))
   {
      // หากสร้างไม่ได้ อาจเป็นเพราะโฟลเดอร์มีอยู่แล้ว ให้ดำเนินการต่อ
   }
   
   // กำหนดชื่อไฟล์ตามสัญลักษณ์คู่เงินและ Magic Number เพื่อป้องกันข้อมูลปนกัน
   journal_filename = folder + "\\TradeJournal_" + _Symbol + "_" + (string)MagicNumber + ".csv";
   
   // หากยังไม่มีไฟล์ ให้สร้างขึ้นใหม่พร้อมเขียนหัวตารางกำกับคอลัมน์
   if(!FileIsExist(journal_filename))
   {
      int file_handle = FileOpen(journal_filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
      if(file_handle != INVALID_HANDLE)
      {
         JournalWriteHeader(file_handle);
         FileClose(file_handle);
      }
      else
      {
         LogError("JournalInit failed to create: " + journal_filename);
      }
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันสร้างรายงานสรุปผลการเทรดรายสัปดาห์ในรูปแบบ HTML (Reporting)    |
//| ทำหน้าที่: รวบรวมสถิติการเทรดย้อนหลัง 7 วัน และจัดฟอร์แมตเพื่อความสวยงาม |
//+------------------------------------------------------------------+
void GenerateWeeklySummary()
{
   // ดึงข้อมูลประวัติการเทรดย้อนหลัง 7 วันจนถึงปัจจุบัน
   if(!HistorySelect(TimeCurrent() - 7*24*3600, TimeCurrent())) return;

   string report_filename = "KNARES_Logs\\WeeklyReport_" + _Symbol + ".html";
   int handle = FileOpen(report_filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(handle != INVALID_HANDLE)
   {
      double total_pnl = 0;
      int trades = 0, wins = 0;
      
      // วนลูปคำนวณกำไร/ขาดทุนสุทธิ (PnL) ของออเดอร์ที่ปิดแล้วในช่วงสัปดาห์
      for(int i=0; i<HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealSelect(ticket) && HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         {
            double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(pnl != 0)
            {
               total_pnl += pnl;
               trades++;
               if(pnl > 0) wins++;
            }
         }
      }
      
      double win_rate = trades > 0 ? (double)wins/trades*100.0 : 0;
      string pnl_color = total_pnl >= 0 ? "green" : "red";
      
      // สร้างเนื้อหาไฟล์ HTML พร้อมการตกแต่งด้วย CSS (Internal Stylesheet)
      string html = "<!DOCTYPE html><html><head><style>";
      html += "body { font-family: 'Segoe UI', Arial, sans-serif; background-color: #121212; color: #ffffff; padding: 20px; }";
      html += ".card { background-color: #1e1e1e; padding: 20px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.5); max-width: 600px; margin: auto; border: 1px solid #333; }";
      html += "h2 { color: #f39c12; border-bottom: 2px solid #f39c12; padding-bottom: 10px; margin-bottom: 20px; }";
      html += ".stat { font-size: 18px; margin: 12px 0; border-bottom: 1px dashed #333; padding-bottom: 5px; }";
      html += ".value { font-weight: bold; float: right; color: #85c1e9; }";
      html += "</style></head><body>";
      
      html += "<div class='card'><h2>KNARES MT5 Weekly Performance</h2>";
      html += "<div class='stat'>Period: <span class='value'>" + TimeToString(TimeCurrent() - 7*24*3600, TIME_DATE) + " to " + TimeToString(TimeCurrent(), TIME_DATE) + "</span></div>";
      html += "<div class='stat'>Total Trades: <span class='value'>" + (string)trades + "</span></div>";
      html += "<div class='stat'>Win Rate: <span class='value'>" + DoubleToString(win_rate, 1) + "%</span></div>";
      html += "<div class='stat'>Net Profit: <span class='value' style='color:" + pnl_color + "'>" + DoubleToString(total_pnl, 2) + " USD</span></div>";
      html += "<div style='margin-top:25px; font-size:11px; color:#7f8c8d; text-align:center;'>Generated by KNARES Institutional Engine Core</div>";
      html += "</div></body></html>";
      
      FileWrite(handle, html);
      FileClose(handle);
      LogInfo("Weekly HTML summary report generated: " + report_filename);
   }
}

//+------------------------------------------------------------------+
//| ฟังก์ชันบันทึกธุรกรรมการเทรดรายไม้ลงในไฟล์ CSV (Transaction Logging) |
//| trans: ข้อมูลธุรกรรม, request: คำสั่งที่ส่งไป, result: ผลลัพธ์ตอบกลับ    |
//+------------------------------------------------------------------+
void JournalTrade(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   // ตรวจสอบความพร้อมของไฟล์ Log
   if(journal_filename == "") JournalInit();

   if(journal_filename == "") return;
   int file_handle = FileOpen(journal_filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(file_handle == INVALID_HANDLE)
   {
      LogError("JournalTrade open failed: " + journal_filename);
      return;
   }

   // เลื่อนตำแหน่งการเขียนไปที่ท้ายสุดของไฟล์ (Append Mode)
   FileSeek(file_handle, 0, SEEK_END);

   string symbol = trans.symbol;
   if(symbol == "") symbol = request.symbol;
   if(symbol == "") symbol = _Symbol;

   string action_str = EnumToString(trans.type);
   string side_str = EnumToString(request.type);
   string comment = request.comment;
   double lots = request.volume;
   double price = request.price;
   double sl = request.sl;
   double tp = request.tp;
   double profit = 0.0;
   string event_name = "REQUEST";
   string entry_type = "";
   ulong deal_ticket = trans.deal;
   ulong order_ticket = trans.order;
   ulong position_ticket = trans.position;

   // พิจารณาเหตุการณ์สำคัญ: การเพิ่มข้อมูลดีล (Deal Add) ซึ่งบ่งบอกว่าออเดอร์ได้รับการ Match แล้ว
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      event_name = "DEAL_ADD";
      if(HistoryDealSelect(trans.deal))
      {
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         // บันทึกเฉพาะดีลที่เป็นของ EA ตัวนี้ (Magic Number)
         if(magic != (long)MagicNumber)
         {
            FileClose(file_handle);
            return;
         }
         // ดึงข้อมูลจริงจากประวัติการเทรดที่เกิดขึ้นจริงบนเซิร์ฟเวอร์
         symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         lots = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         side_str = EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE));
         entry_type = EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY));
         comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
         position_ticket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
      }
   }

   string ret_desc = result.comment;
   if(ret_desc == "") ret_desc = comment;

   // บันทึกข้อมูลเรียงตามคอลัมน์ที่กำหนดไว้ในหัวตาราง
   FileWrite(file_handle,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      symbol,
      event_name,
      action_str,
      side_str,
      DoubleToString(lots, 2),
      DoubleToString(price, 5),
      DoubleToString(sl, 5),
      DoubleToString(tp, 5),
      (string)result.retcode,
      ret_desc,
      (string)deal_ticket,
      (string)order_ticket,
      (string)position_ticket,
      entry_type,
      DoubleToString(profit, 2),
      comment
   );
   FileClose(file_handle);
}

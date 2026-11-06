#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#ifndef __KNARES_SMC_BOOKMAP_MQH__
#define __KNARES_SMC_BOOKMAP_MQH__

//+------------------------------------------------------------------+
//| SMC Book Map                                                     |
//| แผนที่โครงสร้างตามนิยามในตำรา Alchemist Trading (เล่ม SMC):        |
//| swing = pivot N แท่ง + valid pullback แบบ wick, BoS = ปิดเลย swing |
//| ล่าสุดตามทิศแผนที่, CHoCH = ปิดเลย protected level เท่านั้น         |
//| ใช้เฉพาะแท่งที่ปิดแล้ว และ swing ใช้ได้หลังแท่งยืนยันเท่านั้น        |
//+------------------------------------------------------------------+

struct BookPivot
{
   int    bar;      // ดัชนีแท่งที่ทำ pivot
   double level;    // high (pivot high) หรือ low (pivot low)
   double other;    // low ของแท่ง (pivot high) หรือ high ของแท่ง (pivot low) ใช้ตัดสิน valid pullback
   int    evaluated; // แท่งสุดท้ายที่ตรวจ valid pullback แล้ว
};

class CSMCBookMap
{
private:
   double    m_h[];
   double    m_l[];
   double    m_c[];
   int       m_n;
   int       m_N;
   BookPivot m_pend_h[];
   BookPivot m_pend_l[];
   bool      m_has_lh, m_has_ll, m_has_ch, m_has_cl;
   double    m_lh, m_ll, m_ch, m_cl;
   int       m_lh_bar, m_ll_bar, m_ch_bar, m_cl_bar;
   int       m_dir;
   double    m_prot;
   double    m_ext;
   int       m_since;

   double MaxHigh(const int from, const int to) const
   {
      double v = m_h[from];
      for(int k = from + 1; k <= to; k++) if(m_h[k] > v) v = m_h[k];
      return v;
   }

   double MinLow(const int from, const int to) const
   {
      double v = m_l[from];
      for(int k = from + 1; k <= to; k++) if(m_l[k] < v) v = m_l[k];
      return v;
   }

   void AddPending(BookPivot &arr[], const int bar, const double level, const double other)
   {
      int sz = ArraySize(arr);
      ArrayResize(arr, sz + 1);
      arr[sz].bar = bar;
      arr[sz].level = level;
      arr[sz].other = other;
      arr[sz].evaluated = bar;
   }

   // รวม swing ที่ยืนยันในแท่งนี้ (เรียงตาม level แล้ว bar ตามลำดับเดียวกับตัวต้นแบบ Python)
   void ApplyConfirmed(const bool is_high, BookPivot &conf[])
   {
      int cnt = ArraySize(conf);
      for(int a = 1; a < cnt; a++)
      {
         BookPivot key = conf[a];
         int b = a - 1;
         while(b >= 0 && (conf[b].level > key.level || (conf[b].level == key.level && conf[b].bar > key.bar)))
         {
            conf[b + 1] = conf[b];
            b--;
         }
         conf[b + 1] = key;
      }
      for(int a = 0; a < cnt; a++)
      {
         if(is_high)
         {
            m_has_lh = m_has_ch = true;
            m_lh = m_ch = conf[a].level;
            m_lh_bar = m_ch_bar = conf[a].bar;
         }
         else
         {
            m_has_ll = m_has_cl = true;
            m_ll = m_cl = conf[a].level;
            m_ll_bar = m_cl_bar = conf[a].bar;
         }
      }
   }

   void UpdatePending(const bool is_high, const int t, BookPivot &conf[])
   {
      BookPivot keep[];
      BookPivot src[];
      if(is_high) ArrayCopy(src, m_pend_h); else ArrayCopy(src, m_pend_l);
      int cnt = ArraySize(src);
      for(int a = 0; a < cnt; a++)
      {
         BookPivot p = src[a];
         bool dropped = false, confirmed = false;
         for(int k = p.evaluated + 1; k <= t; k++)
         {
            if(is_high)
            {
               if(m_h[k] > p.level) { dropped = true; break; }
               if(m_l[k] < p.other) { confirmed = true; break; }
            }
            else
            {
               if(m_l[k] < p.level) { dropped = true; break; }
               if(m_h[k] > p.other) { confirmed = true; break; }
            }
         }
         if(dropped) continue;
         if(confirmed)
         {
            int sz = ArraySize(conf);
            ArrayResize(conf, sz + 1);
            conf[sz] = p;
            continue;
         }
         p.evaluated = t;
         int ks = ArraySize(keep);
         ArrayResize(keep, ks + 1);
         keep[ks] = p;
      }
      if(is_high) { ArrayResize(m_pend_h, ArraySize(keep)); for(int a = 0; a < ArraySize(keep); a++) m_pend_h[a] = keep[a]; }
      else        { ArrayResize(m_pend_l, ArraySize(keep)); for(int a = 0; a < ArraySize(keep); a++) m_pend_l[a] = keep[a]; }
   }

public:
   CSMCBookMap() : m_n(0), m_N(3), m_has_lh(false), m_has_ll(false), m_has_ch(false), m_has_cl(false),
                   m_lh(0.0), m_ll(0.0), m_ch(0.0), m_cl(0.0), m_lh_bar(-1), m_ll_bar(-1), m_ch_bar(-1), m_cl_bar(-1),
                   m_dir(0), m_prot(EMPTY_VALUE), m_ext(0.0), m_since(0) {}

   void Reset(const int pivot_n)
   {
      m_n = 0;
      m_N = MathMax(1, pivot_n);
      ArrayResize(m_h, 0);
      ArrayResize(m_l, 0);
      ArrayResize(m_c, 0);
      ArrayResize(m_pend_h, 0);
      ArrayResize(m_pend_l, 0);
      m_has_lh = m_has_ll = m_has_ch = m_has_cl = false;
      m_dir = 0;
      m_prot = EMPTY_VALUE;
      m_ext = 0.0;
      m_since = 0;
   }

   int    Direction() const { return m_dir; }
   double Protected() const { return m_prot; }
   int    BarsSinceBreak() const { return m_since; }

   // ป้อนแท่งที่ปิดแล้วทีละแท่ง (เรียงจากเก่าไปใหม่)
   void ProcessBar(const double high, const double low, const double close)
   {
      int t = m_n;
      ArrayResize(m_h, t + 1);
      ArrayResize(m_l, t + 1);
      ArrayResize(m_c, t + 1);
      m_h[t] = high;
      m_l[t] = low;
      m_c[t] = close;
      m_n = t + 1;

      // ตรวจ pivot ที่เพิ่งมีแท่งขวาครบ N แท่ง
      int i = t - m_N;
      if(i >= m_N)
      {
         double lmax = MaxHigh(i - m_N, i - 1);
         double rmax = MaxHigh(i + 1, t);
         if(m_h[i] > lmax && m_h[i] >= rmax)
            AddPending(m_pend_h, i, m_h[i], m_l[i]);
         double lmin = MinLow(i - m_N, i - 1);
         double rmin = MinLow(i + 1, t);
         if(m_l[i] < lmin && m_l[i] <= rmin)
            AddPending(m_pend_l, i, m_l[i], m_h[i]);
      }

      // valid pullback: pivot นับเมื่อราคาผ่านกรอบแท่งแม่ก่อนทำ extreme ใหม่
      BookPivot conf_h[], conf_l[];
      UpdatePending(true, t, conf_h);
      UpdatePending(false, t, conf_l);
      ApplyConfirmed(true, conf_h);
      ApplyConfirmed(false, conf_l);

      double c = m_c[t];
      bool any_break = (m_has_lh && c > m_lh && m_lh_bar < t) || (m_has_ll && c < m_ll && m_ll_bar < t);
      m_since = any_break ? 0 : m_since + 1;

      if(m_dir >= 0 && m_has_ch && c > m_ch && m_ch_bar < t)
      {
         m_prot = MinLow(m_ch_bar, t);
         m_dir = 1;
         m_ext = m_h[t];
         m_has_ch = false;
      }
      else if(m_dir <= 0 && m_has_cl && c < m_cl && m_cl_bar < t)
      {
         m_prot = MaxHigh(m_cl_bar, t);
         m_dir = -1;
         m_ext = m_l[t];
         m_has_cl = false;
      }
      else if(m_dir == 1 && m_prot != EMPTY_VALUE && c < m_prot)
      {
         m_prot = m_ext;
         m_dir = -1;
         m_ext = m_l[t];
      }
      else if(m_dir == -1 && m_prot != EMPTY_VALUE && c > m_prot)
      {
         m_prot = m_ext;
         m_dir = 1;
         m_ext = m_h[t];
      }

      if(m_dir == 1 && m_h[t] > m_ext) m_ext = m_h[t];
      if(m_dir == -1 && m_l[t] < m_ext) m_ext = m_l[t];
   }
};

CSMCBookMap g_smc_book_map;
datetime    g_smc_book_last_bar = 0;
string      g_smc_book_symbol = "";
ENUM_TIMEFRAMES g_smc_book_tf = PERIOD_CURRENT;

/**
 * ฟังก์ชัน SMCBookMapUpdate: อัปเดตแผนที่ให้ถึงแท่งปิดล่าสุดของไทม์เฟรมที่กำหนด (เริ่มด้วย warm-up จากประวัติ)
 */
bool SMCBookMapUpdate(const string symbol, ENUM_TIMEFRAMES tf, const int pivot_n, const int warm_bars, const bool log_dir)
{
   datetime newest = iTime(symbol, tf, 1);
   if(newest <= 0) return false;
   if(g_smc_book_last_bar == newest && g_smc_book_symbol == symbol && g_smc_book_tf == tf) return true;

   MqlRates rates[];
   int need = 0;
   bool fresh = (g_smc_book_last_bar == 0 || g_smc_book_symbol != symbol || g_smc_book_tf != tf);
   if(!fresh)
   {
      int shift = iBarShift(symbol, tf, g_smc_book_last_bar, false);
      need = shift - 1;
      if(shift < 1 || need > warm_bars) fresh = true;
   }
   if(fresh)
   {
      g_smc_book_map.Reset(pivot_n);
      need = MathMax(50, warm_bars);
   }
   if(need <= 0) { g_smc_book_last_bar = newest; return true; }

   int copied = CopyRates(symbol, tf, 1, need, rates);
   if(copied <= 0) return false;
   int h = INVALID_HANDLE;
   if(log_dir)
      h = FileOpen("KNARES_BookMap_" + symbol + ".csv", FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h != INVALID_HANDLE) FileSeek(h, 0, SEEK_END);
   for(int i = 0; i < copied; i++)
   {
      g_smc_book_map.ProcessBar(rates[i].high, rates[i].low, rates[i].close);
      if(h != INVALID_HANDLE && !fresh)
         FileWriteString(h, StringFormat("%I64d,%d\n", (long)rates[i].time, g_smc_book_map.Direction()));
   }
   if(h != INVALID_HANDLE) FileClose(h);
   g_smc_book_last_bar = rates[copied - 1].time;
   g_smc_book_symbol = symbol;
   g_smc_book_tf = tf;
   return true;
}

/**
 * ฟังก์ชัน SMCBookMapDirection: ทิศของแผนที่ ณ แท่งปิดล่าสุด (+1 ขึ้น, -1 ลง, 0 ยังไม่มีทิศ)
 */
int SMCBookMapDirection(const string symbol, ENUM_TIMEFRAMES tf, const int pivot_n, const int warm_bars, const bool log_dir)
{
   if(!SMCBookMapUpdate(symbol, tf, pivot_n, warm_bars, log_dir)) return 0;
   return g_smc_book_map.Direction();
}

#endif // __KNARES_SMC_BOOKMAP_MQH__

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

// Cache ของ indicator handle: สร้างครั้งเดียวต่อ (indicator, symbol, tf, period) แล้วใช้ซ้ำ
// เดิมสร้าง/ทำลาย handle ใหม่ทุกรอบ ซึ่งช้ามากใน Strategy Tester
string g_hc_keys[];
int    g_hc_handles[];

int HC_Get(const string key, const int created_handle_if_missing_marker)
{
   for(int i = 0; i < ArraySize(g_hc_keys); i++)
      if(g_hc_keys[i] == key) return g_hc_handles[i];
   return -2;
}

void HC_Store(const string key, const int handle)
{
   int n = ArraySize(g_hc_keys);
   ArrayResize(g_hc_keys, n + 1);
   ArrayResize(g_hc_handles, n + 1);
   g_hc_keys[n] = key;
   g_hc_handles[n] = handle;
}

int HC_MA(const string symbol, const ENUM_TIMEFRAMES tf, const int period)
{
   string key = StringFormat("MA|%s|%d|%d", symbol, (int)tf, period);
   int h = HC_Get(key, 0);
   if(h != -2) return h;
   h = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h != INVALID_HANDLE) HC_Store(key, h);
   return h;
}

int HC_ATR(const string symbol, const ENUM_TIMEFRAMES tf, const int period)
{
   string key = StringFormat("ATR|%s|%d|%d", symbol, (int)tf, period);
   int h = HC_Get(key, 0);
   if(h != -2) return h;
   h = iATR(symbol, tf, period);
   if(h != INVALID_HANDLE) HC_Store(key, h);
   return h;
}

void HC_ReleaseAll()
{
   for(int i = 0; i < ArraySize(g_hc_handles); i++)
      if(g_hc_handles[i] != INVALID_HANDLE) IndicatorRelease(g_hc_handles[i]);
   ArrayFree(g_hc_keys);
   ArrayFree(g_hc_handles);
}

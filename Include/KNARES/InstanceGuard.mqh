#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Instance Guard Module - ระบบป้องกันการรัน EA ซ้ำซ้อน                  |
//| ทำหน้าที่: ควบคุมให้ EA ทำงานเพียงตัวเดียวต่อหนึ่งคู่เงินและ Magic Number   |
//| โดยใช้ระบบ Global Variables ของ Terminal ในการจองสิทธิ์ (Mutex)       |
//+------------------------------------------------------------------+

// ตัวแปรเก็บข้อมูลสถานะ Single Instance
datetime g_last_instance_heartbeat = 0; // เวลาล่าสุดที่อัปเดตสถานะการทำงาน
string   g_instance_owner_key = "";     // ชื่อคีย์สำหรับเก็บ ID ของเจ้าของ (Owner)
string   g_instance_heartbeat_key = ""; // ชื่อคีย์สำหรับเก็บเวลา Heartbeat
double   g_instance_owner_id = 0.0;     // ID ของ EA ตัวปัจจุบัน (ใช้ Chart ID)
bool     g_instance_guard_owned = false; // สถานะว่าเราเป็นเจ้าของสิทธิ์หรือไม่

/**
 * BuildInstanceBaseKey: สร้างคีย์พื้นฐานสำหรับระบุตัวตนของ EA
 * อธิบายกระบวนการ:
 * - นำเลขที่บัญชี (Login), Magic Number และชื่อคู่เงินมาประกอบกันเป็นข้อความ
 * - เพื่อให้ได้คีย์ที่ไม่ซ้ำกันในแต่ละการตั้งค่าพอร์ต
 */
string BuildInstanceBaseKey()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   return StringFormat("KNARES_INST_%I64d_%I64u_%s", login, MagicNumber, _Symbol);
}

/**
 * IsSameOwner: ตรวจสอบว่า ID เจ้าของเป็นคนเดียวกันหรือไม่
 */
bool IsSameOwner(const double a, const double b)
{
   // ใช้ระยะห่างทางตัวเลขเพื่อหลีกเลี่ยงปัญหาทศนิยมในการเปรียบเทียบ
   return MathAbs(a - b) < 0.5;
}

/**
 * GetSingleInstanceOwnerString: คืนค่า ID เจ้าของในรูปแบบข้อความ
 */
string GetSingleInstanceOwnerString()
{
   return StringFormat("%.0f", g_instance_owner_id);
}

/**
 * AcquireSingleInstanceGuard: พยายามครอบครองสิทธิ์การรัน EA เพียงตัวเดียว
 * อธิบายกระบวนการ:
 * 1. ข้ามการตรวจสอบหากอยู่ในโหมด Backtest (Tester)
 * 2. ตรวจสอบคีย์ใน Global Variable ว่ามีใครจองไว้ก่อนหรือไม่
 * 3. หากมีเจ้าของอยู่แล้ว จะตรวจสอบค่า Heartbeat:
 *    - หาก Heartbeat ไม่มีการขยับเกินเวลาที่กำหนด (Stale) จะถือว่า EA ตัวเดิมค้างหรือปิดไม่สมบูรณ์
 *    - หาก Heartbeat ยังขยับอยู่และไม่ใช่ ID ของเรา จะแจ้งเตือนและไม่อนุญาตให้ทำงาน
 * 4. หากไม่มีใครจอง หรือของเดิมหมดอายุ จะทำการเขียน ID และ Heartbeat ของเราลงไปเพื่อจองสิทธิ์
 */
bool AcquireSingleInstanceGuard()
{
   if(MQLInfoInteger(MQL_TESTER)) return true; // ข้ามการตรวจสอบหากอยู่ในโหมด Tester
   if(!EnableSingleInstanceGuard) return true;

   string base = BuildInstanceBaseKey();
   g_instance_owner_key = base + "_OWNER";
   g_instance_heartbeat_key = base + "_HB";
   g_instance_owner_id = (double)ChartID();

   datetime now = TimeCurrent();
   bool owner_exists = GlobalVariableCheck(g_instance_owner_key);
   bool hb_exists = GlobalVariableCheck(g_instance_heartbeat_key);

   // ตรวจสอบว่ามี EA ตัวอื่นกำลังรันอยู่หรือไม่
   if(owner_exists && hb_exists)
   {
      double existing_owner = GlobalVariableGet(g_instance_owner_key);
      datetime hb = (datetime)GlobalVariableGet(g_instance_heartbeat_key);
      // ตรวจสอบว่าสถานะของเจ้าของเดิมค้างหรือไม่ (Stale)
      bool stale = ((now - hb) > MathMax(30, SingleInstanceStaleSec));

      // ถ้าเจ้าของไม่ใช่เรา และสถานะยังไม่หมดอายุ (ไม่ Stale)
      if(!IsSameOwner(existing_owner, g_instance_owner_id) && !stale)
      {
         LogError(StringFormat("Single-instance guard: another active instance detected for %s (owner=%.0f, this=%.0f).",
                               _Symbol, existing_owner, g_instance_owner_id));
         return false;
      }
   }

   // ทำการจองสิทธิ์โดยการเขียนข้อมูลลง Global Variables
   GlobalVariableSet(g_instance_owner_key, g_instance_owner_id);
   GlobalVariableSet(g_instance_heartbeat_key, (double)now);
   g_instance_guard_owned = true;
   g_last_instance_heartbeat = now;
   return true;
}

/**
 * RefreshSingleInstanceHeartbeat: อัปเดตสถานะการทำงาน (Heartbeat) ของ EA
 * อธิบายกระบวนการ:
 * - จะทำงานเป็นระยะๆ ตามเวลาที่ตั้งไว้ (เช่น ทุก 5-10 วินาที)
 * - เขียนเวลาปัจจุบันลงไปใน Global Variable เพื่อบอกระบบว่า EA ตัวนี้ยังทำงานอยู่ปกติ
 * - หากไม่ทำการ Refresh ตัวอื่นที่เปิดขึ้นมาภายหลังจะสามารถแย่งสิทธิ์ไปได้ (เพราะถือว่า Stale)
 */
void RefreshSingleInstanceHeartbeat()
{
   if(!EnableSingleInstanceGuard || !g_instance_guard_owned) return;
   datetime now = TimeCurrent();
   // ตรวจสอบว่าถึงเวลาอัปเดตหรือยัง
   if((now - g_last_instance_heartbeat) < MathMax(5, SingleInstanceHeartbeatSec))
      return;
   g_last_instance_heartbeat = now;
   GlobalVariableSet(g_instance_owner_key, g_instance_owner_id);
   GlobalVariableSet(g_instance_heartbeat_key, (double)now);
}

/**
 * ReleaseSingleInstanceGuard: ปล่อยสิทธิ์การควบคุมเมื่อปิด EA
 * อธิบายกระบวนการ:
 * - เมื่อ EA ถูกปิด (Deinit) จะทำการลบ Global Variables ที่เคยจองไว้
 * - เพื่อให้ EA ตัวอื่นสามารถเข้ามาเริ่มทำงานใหม่ได้ทันทีโดยไม่ต้องรอให้สถานะหมดอายุ
 */
void ReleaseSingleInstanceGuard()
{
   if(!EnableSingleInstanceGuard || !g_instance_guard_owned) return;
   if(GlobalVariableCheck(g_instance_owner_key))
   {
      double owner = GlobalVariableGet(g_instance_owner_key);
      // ต้องลบเฉพาะในกรณีที่เราเป็นเจ้าของสิทธิ์เท่านั้น
      if(IsSameOwner(owner, g_instance_owner_id))
      {
         GlobalVariableDel(g_instance_owner_key);
         if(GlobalVariableCheck(g_instance_heartbeat_key))
            GlobalVariableDel(g_instance_heartbeat_key);
      }
   }
   g_instance_guard_owned = false;
}

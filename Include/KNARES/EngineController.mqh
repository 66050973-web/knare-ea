#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "Metrics.mqh"

//+------------------------------------------------------------------+
//| Engine Controller Module - ระบบควบคุมสถานะเครื่องมือเทรด                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Engine Controller Module - ระบบควบคุมสถานะเครื่องมือเทรด                |
//+------------------------------------------------------------------+

/**
 * EngineIndexByName: แปลงชื่อเครื่องมือเทรด (Engine) เป็นดัชนี (Index)
 * อธิบายกระบวนการ:
 * - รับชื่อ Engine เป็นข้อความ
 * - คืนค่าเป็นตัวเลขดัชนีเพื่อใช้เข้าถึงอาเรย์ engine_metrics
 * - 0: TrendEngine, 1: BreakoutEngine, 2: MeanRevEngine
 * - คืนค่า -1 หากไม่พบชื่อที่ระบุ
 */
int EngineIndexByName(const string engine_name)
{
   if(engine_name == "TrendEngine") return 0;
   if(engine_name == "BreakoutEngine") return 1;
   if(engine_name == "MeanRevEngine") return 2;
   return -1;
}

/**
 * EngineNameByIndex: แปลงดัชนีเป็นชื่อเครื่องมือเทรด
 * อธิบายกระบวนการ:
 * - รับตัวเลขดัชนี (0-2) และคืนค่ากลับมาเป็นชื่อ Engine ในรูปแบบ String
 */
string EngineNameByIndex(const int idx)
{
   if(idx == 0) return "TrendEngine";
   if(idx == 1) return "BreakoutEngine";
   if(idx == 2) return "MeanRevEngine";
   return "UnknownEngine";
}

/**
 * EngineStatusToString: แปลงสถานะ Enum เป็นข้อความ (String) เพื่อแสดงผลบนหน้าจอ Dashboard
 */
string EngineStatusToString(ENUM_ENGINE_STATUS status)
{
   switch(status)
   {
      case ENGINE_ACTIVE: return "ACTIVE"; // พร้อมทำงานปกติ
      case ENGINE_PAUSED_BY_ROLLING_PF: return "PAUSED_PF"; // หยุดพักเพราะผลงานล่าสุดไม่ดี
      case ENGINE_DISABLED_BY_CONFIG: return "DISABLED_CFG"; // ปิดใช้งานผ่านการตั้งค่าในไฟล์ Config
      case ENGINE_DISABLED_BY_GUARD: return "DISABLED_GRD"; // ปิดถาวรเพราะขาดทุนเกินเกณฑ์ที่กำหนด
      case ENGINE_COOLDOWN: return "COOLDOWN"; // อยู่ในช่วงพักหลังจบการเทรด
      default: return "UNKNOWN";
   }
}

/**
 * GetEngineStatus: ตรวจสอบสถานะการทำงานปัจจุบันของเครื่องมือเทรด
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบว่า Engine นี้ถูกเปิดใช้งานใน Config หรือไม่ (EnableTrendEngine, etc.)
 * 2. ตรวจสอบระบบ Engine Guard ว่ามีการสั่งปิดถาวร (Disabled by Guard) หรือไม่
 * 3. คำนวณ Rolling Profit Factor (PF): ถ้า PF ของออเดอร์หลังๆ ต่ำกว่า 0.65 จะสั่ง Pause ชั่วคราว
 * 4. ตรวจสอบ Global Variable เพื่อดูว่ามีการสั่งหยุดพัก (Pause) ตามเวลาที่กำหนดไว้หรือไม่
 * 5. หากผ่านทุกเงื่อนไขจะคืนสถานะ ACTIVE (พร้อมเทรด)
 */
ENUM_ENGINE_STATUS GetEngineStatus(const string engine_name)
{
   int idx = EngineIndexByName(engine_name);
   if(idx < 0) return ENGINE_DISABLED_BY_CONFIG;
   
   // 1. ตรวจสอบการเปิด/ปิด ใช้งานพื้นฐานผ่าน User Input / Config
   if(engine_name == "TrendEngine" && !EnableTrendEngine) return ENGINE_DISABLED_BY_CONFIG;
   if(engine_name == "BreakoutEngine" && !EnableBreakoutEngine) return ENGINE_DISABLED_BY_CONFIG;
   if(engine_name == "MeanRevEngine" && !EnableMeanRevEngine) return ENGINE_DISABLED_BY_CONFIG;

   // 2. ตรวจสอบจากระบบความปลอดภัย (Guard) - หากติด Guard จะถูกปิดจนกว่าจะรีสตาร์ท EA
   if(engine_metrics[idx].status == ENGINE_DISABLED_BY_GUARD) return ENGINE_DISABLED_BY_GUARD;

   // 3. ระบบ Auto-Pause: หยุดพักอัตโนมัติหาก Profit Factor ในช่วงการเทรดล่าสุด (Window) ต่ำเกินไป
   if(EnableEngineAutoPause && engine_metrics[idx].trades >= RollingPFWindow)
   {
      // คำนวณ Rolling PF ใหม่เมื่อจำนวนเทรดเปลี่ยน (เดิมไม่มีใครเรียก UpdateRollingMetrics ทำให้ rolling_pf ค้างที่ 0
      // และ Engine ถูกหยุดถาวรทันทีที่เทรดครบ RollingPFWindow)
      static int s_rolling_calc_trades[3] = {-1, -1, -1};
      if(s_rolling_calc_trades[idx] != engine_metrics[idx].trades)
      {
         UpdateRollingMetrics(idx);
         s_rolling_calc_trades[idx] = engine_metrics[idx].trades;
      }
      double r_pf = engine_metrics[idx].rolling_pf;

      // พักชั่วคราวแทนการพักถาวร: เมื่อ PF ต่ำ พัก EnginePausedCooldownHours ชั่วโมง แล้วกลับมาเทรดต่อ
      // โดยยกเว้นการตรวจ Rolling PF อีก EngineResumeGraceTrades ไม้ (ไม่งั้นไม่มีเทรดใหม่มาเปลี่ยนค่า PF และ Engine จะไม่กลับมาอีกเลย)
      static datetime s_pause_until[3]  = {0, 0, 0};
      static int      s_resume_trades[3] = {-1, -1, -1};
      bool in_grace = (s_resume_trades[idx] >= 0 && engine_metrics[idx].trades < s_resume_trades[idx] + EngineResumeGraceTrades);
      if(!in_grace && r_pf < 0.65)
      {
         if(s_pause_until[idx] == 0)
         {
            s_pause_until[idx] = TimeCurrent() + (datetime)EnginePausedCooldownHours * 3600;
            LogWarning(StringFormat("EngineAutoPause: %s paused for %dh (Rolling PF %.2f < 0.65)", engine_name, EnginePausedCooldownHours, r_pf));
         }
         if(TimeCurrent() < s_pause_until[idx]) return ENGINE_PAUSED_BY_ROLLING_PF;
         s_pause_until[idx]  = 0;
         s_resume_trades[idx] = engine_metrics[idx].trades;
         LogInfo(StringFormat("EngineAutoPause: %s resumed (grace %d trades)", engine_name, EngineResumeGraceTrades));
      }
   }

   // 4. ตรวจสอบการหยุดพักชั่วคราวที่ถูกบันทึกไว้ในระบบ Global Variables ของ Terminal
   string gv_key = "KNARES_PAUSE_" + engine_name;
   if(GlobalVariableCheck(gv_key))
   {
      datetime until = (datetime)GlobalVariableGet(gv_key);
      if(TimeCurrent() < until) return ENGINE_PAUSED_BY_ROLLING_PF;
      else GlobalVariableDel(gv_key); // ลบคีย์ทิ้งหากหมดเวลาพักแล้ว
   }

   return ENGINE_ACTIVE;
}

/**
 * IsEngineDisabled: ฟังก์ชันตัวช่วยสำหรับเช็คว่า Engine ถูกระงับการทำงานหรือไม่
 * คืนค่า true หากสถานะไม่ใช่ ACTIVE
 */
bool IsEngineDisabled(const string engine_name)
{
   ENUM_ENGINE_STATUS status = GetEngineStatus(engine_name);
   int idx = EngineIndexByName(engine_name);
   // อัปเดตสถานะล่าสุดลงใน Metrics เพื่อให้ Dashboard แสดงผลได้ถูกต้อง
   if(idx >= 0) engine_metrics[idx].status = status;
   return (status != ENGINE_ACTIVE);
}

/**
 * EvaluateEngineGuard: ระบบป้องกันความเสียหายวิกฤตรายกลยุทธ์ (Engine-level Guard)
 * อธิบายกระบวนการ:
 * 1. ตรวจสอบว่าเปิดใช้งานระบบ Guard หรือไม่ และจำนวนการเทรดถึงเกณฑ์ที่ตั้งไว้หรือยัง
 * 2. คำนวณ Profit Factor รวมตั้งแต่เริ่มทำงาน
 * 3. หาก PF ต่ำกว่าเกณฑ์วิกฤต (Default: 0.10 หรือตาม Config) 
 *    จะสั่งปิด Engine นั้นถาวร (DISABLED_BY_GUARD) เพื่อป้องกันพอร์ตเสียหายหนัก
 */
void EvaluateEngineGuard(const int idx)
{
   if(!EnableEnginePerformanceGuard || idx < 0 || idx > 2) return;
   // ต้องมีการเทรดอย่างน้อย 5 ออเดอร์ หรือตามค่าใน Config ก่อนจะเริ่มประเมิน
   if(engine_metrics[idx].trades < MathMax(5, EnginePerfMinTrades)) return;
   
   double pf = engine_metrics[idx].pf;
   // ตรวจสอบว่า Profit Factor แย่กว่าเกณฑ์ที่ยอมรับได้หรือไม่
   bool should_disable = (pf < MathMax(0.10, EnginePerfDisablePF));
   if(should_disable && engine_metrics[idx].status != ENGINE_DISABLED_BY_GUARD)
   {
      engine_metrics[idx].status = ENGINE_DISABLED_BY_GUARD;
      LogWarning(StringFormat("EngineGuard: disabled %s due to PF %.2f < %.2f (trades=%d)",
                              engine_metrics[idx].name, pf, EnginePerfDisablePF, engine_metrics[idx].trades));
   }
}

/**
 * GetAutoGuardPauseRemainingSec: คำนวณเวลาที่เหลือ (วินาที) สำหรับการหยุดเทรดของระบบ Auto-Guard
 */
int GetAutoGuardPauseRemainingSec()
{
   if(g_autoguard_pause_until <= TimeCurrent()) return 0;
   return (int)(g_autoguard_pause_until - TimeCurrent());
}

/**
 * GetRegimePauseRemainingSec: คำนวณเวลาที่เหลือ (วินาที) สำหรับการหยุดพักเมื่อมีการเปลี่ยนสภาวะตลาด
 * (เช่น หยุดพัก 5 นาทีหลังจากจบเทรนด์ เพื่อรอให้ตลาดเซ็ตตัวใหม่)
 */
int GetRegimePauseRemainingSec()
{
   string pause_key = "KNARES_RegimeExit_PauseUntil";
   if(!GlobalVariableCheck(pause_key)) return 0;
   datetime t = (datetime)GlobalVariableGet(pause_key);
   if(t <= TimeCurrent()) return 0;
   return (int)(t - TimeCurrent());
}

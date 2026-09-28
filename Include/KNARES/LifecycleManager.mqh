#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Config.mqh"
#include "Types.mqh"
#include "SharedGlobals.mqh"
#include "Logger.mqh"
#include "Metrics.mqh"
#include "SignalRescue.mqh"
#include "RiskAccounting.mqh"

//+------------------------------------------------------------------+
//| Lifecycle Manager Module - ระบบจัดการวงจรชีวิตและสรุปผลรายงาน           |
//| ทำหน้าที่: จัดเตรียมข้อมูลเริ่มต้น, รายงานสถานะการทำงาน และสรุปสถิติประสิทธิภาพ  |
//+------------------------------------------------------------------+

/**
 * NormalizeSymbolList: ตรวจสอบและเตรียมรายชื่อ Symbol ให้พร้อมใช้งาน
 * อธิบายกระบวนการ:
 * 1. วนลูปรายชื่อคู่เงินทั้งหมดจาก symbol_list
 * 2. ล้างช่องว่างหน้าและหลังชื่อ (Trim)
 * 3. ตรวจสอบว่าคู่เงินนั้นสามารถใช้งานได้จริงบน Terminal หรือไม่ (SymbolSelect)
 * 4. จัดเก็บรายชื่อที่ "สะอาด" และ "ใช้ได้จริง" กลับลงใน symbol_list อีกครั้ง
 */
void NormalizeSymbolList()
{
   string clean[];
   for(int i = 0; i < ArraySize(symbol_list); i++)
   {
      string sym = symbol_list[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "") continue;
      
      // ตรวจสอบว่า Broker มีคู่เงินนี้และสามารถเปิดใช้งานได้หรือไม่ (ยกเว้นในโหมด Tester)
      if(!MQLInfoInteger(MQL_TESTER) && !SymbolSelect(sym, true))
      {
         LogWarning("Skipping symbol (SymbolSelect failed): " + sym);
         continue;
      }
      
      // เพิ่มคู่เงินที่ผ่านการตรวจสอบลงในรายการใหม่
      int n = ArraySize(clean);
      ArrayResize(clean, n + 1);
      clean[n] = sym;
   }
   // อัปเดตรายการ Global symbol_list ด้วยข้อมูลที่จัดระเบียบแล้ว
   ArrayResize(symbol_list, ArraySize(clean));
   ArrayCopy(symbol_list, clean);
}

/**
 * LogRuntimeConfig: สรุปค่าพารามิเตอร์หลักที่ระบบใช้งานตอนเริ่มต้น
 * อธิบายกระบวนการ:
 * - บันทึกค่า Config สำคัญลงใน Log เพื่อให้ Dev ทราบสภาวะการทำงานเริ่มต้น
 * - ครอบคลุมถึง: เวอร์ชัน Build, สถานะโมดูลกู้คืน (Rescue), การป้องกัน Drawdown, 
 *   กลยุทธ์ที่เปิดใช้งาน (Trend, Breakout, etc.), และรูปแบบการปิดออเดอร์ (Trailing, Partial)
 */
void LogRuntimeConfig()
{
   LogInfo(StringFormat("RuntimeConfig Version: Build=%s", KNARES_BUILD_TAG));
   
   // รายงานสถานะโมดูล Pipeline Rescue และ Smart Money Concepts (SMC)
   LogInfo(StringFormat("SMCFull=true | PipelineRescue=%s | RescueOutcome=%s", 
                        EnableBuyContinuationPipelineRescue?"ON":"OFF", EnableRescueOutcomeAttribution?"ON":"OFF"));
   LogInfo(StringFormat("SMCQualityGate=%s | LotAware=true | ContextExit=%s", 
                        EnableRescueSMCQualityGate?"ON":"OFF", EnableContextExitRescueCooldown?"ON":"OFF"));
   LogInfo(StringFormat("DailyLossCluster=%s | ThinPanes=%s", 
                        EnableDailyLossClusterGuard?"ON":"OFF", CompactIndicatorPanes?"ON":"OFF"));
   
   // รายงานกลยุทธ์การเทรด (Engine Status)
   LogInfo(StringFormat("RuntimeConfig-Strategy: Trend=%s Breakout=%s MeanRev=%s ScaleIn=%s",
                        EnableTrendEngine?"ON":"OFF", EnableBreakoutEngine?"ON":"OFF", 
                        EnableMeanRevEngine?"ON":"OFF", EnableScaleIn?"ON":"OFF"));
                        
   // รายงานระบบการปิดออเดอร์และกำไร (Exit Logic)
   LogInfo(StringFormat("RuntimeConfig-Exit: ATRTrail=%s Partial=%s AccelTrail=%s",
                        EnableTrailingStop?"ON":"OFF", EnablePartialClose?"ON":"OFF", 
                        EnableAcceleratedTrailing?"ON":"OFF"));
}

/**
 * LogHardSLSummary: สรุปประวัติการชน Stop Loss แบบเต็มจำนวน (Hard SL)
 * อธิบายกระบวนการ:
 * 1. เข้าถึงประวัติการเทรด (History) ทั้งหมด
 * 2. คัดกรองเฉพาะรายการที่ปิดด้วยเหตุผล "Stop Loss" (DEAL_REASON_SL) และตรงกับ Magic Number ของเรา
 * 3. คำนวณจำนวนครั้งและผลรวมการขาดทุนทั้งหมด (Net Loss รวมค่าคอมมิชชันและสวอป)
 * 4. บันทึกผลสรุปลงใน Log เพื่อใช้วิเคราะห์ความเสี่ยงที่เกิดขึ้นจริง
 */
void LogHardSLSummary()
{
   int count = 0;
   double total_loss = 0;
   
   // เลือกประวัติการเทรดตั้งแต่เริ่มต้นจนถึงปัจจุบัน
   if(HistorySelect(0, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i=0; i<total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealSelect(ticket))
         {
            // ตรวจสอบว่าดีลนี้เป็นของ EA เราและเป็นการชน SL หรือไม่
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(ticket, DEAL_REASON) == DEAL_REASON_SL)
            {
               // คำนวณผลกำไร/ขาดทุนสุทธิของดีลนี้
               double p = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
               if(p < 0)
               {
                  count++;
                  total_loss += MathAbs(p);
               }
            }
         }
      }
   }
   LogInfo("--- HardSLSummary ---");
   LogInfo(StringFormat("HardSLCount: %d", count));
   LogInfo(StringFormat("HardSLTotalLoss: %.2f", total_loss));
   LogInfo("---------------------");
}

/**
 * LogLotAwareSummary: สรุปประสิทธิภาพการบริหารความเสี่ยงและขนาดลอต (Lot Efficiency)
 * อธิบายกระบวนการ:
 * 1. อัปเดตข้อมูล Metrics ล่าสุดจากระบบหลัก
 * 2. รายงานกำไรสุทธิเทียบกับค่าที่ถูก Normalized (ปรับมาตรฐานลอต) เพื่อดูประสิทธิภาพที่แท้จริง
 * 3. รายงานค่าทางสถิติสำคัญ: Profit Factor, Expectancy, Max Drawdown
 * 4. รายงานสถิติการถูกระงับโดยระบบความปลอดภัย (Exposure Cap, Heat Cap)
 * 5. สรุปผลการทำงานของระบบ Rescue (การแก้ไม้) และ Context Exit (การปิดออเดอร์ล่วงหน้าตามสภาวะตลาด)
 */
void LogLotAwareSummary()
{
   // อัปเดตสถิติปัจจุบันก่อนทำการรายงาน
   UpdateMetrics();
   
   LogInfo("--- LotAwareSummary ---");
   LogInfo(StringFormat("FixedLotSize: %.2f", FixedLotSize));
   
   // รายงานกำไรสุทธิทั้งแบบตัวเงินจริงและแบบปรับมาตรฐานลอต (Normalized)
   LogInfo(StringFormat("NetProfit: %.2f (Normalized: %.2f)", current_metrics.net_pnl, current_metrics.lot_normalized_net));
   LogInfo(StringFormat("ProfitFactor: %.2f", current_metrics.profit_factor));
   
   // Expectancy (RAR) และ Max Drawdown
   LogInfo(StringFormat("Expectancy: %.2f (Normalized: %.2f)", current_metrics.rar, current_metrics.lot_normalized_expectancy));
   LogInfo(StringFormat("MaxDrawdown: %.2f (Normalized: %.2f)", current_metrics.max_drawdown_usd, current_metrics.lot_normalized_drawdown));
   
   // คะแนนประสิทธิภาพการใช้ลอตและการโดนบล็อกโดย Risk Guard
   LogInfo(StringFormat("LotEfficiencyScore: %.2f", current_metrics.lot_efficiency_score));
   LogInfo(StringFormat("ExposureCapHits: %d", current_metrics.exposure_cap_hits));
   LogInfo(StringFormat("HeatCapHits: %d", current_metrics.heat_cap_hits));
   
   // สถิติการชน SL และผลงานของโมเดล Rescue (แก้พอร์ต)
   LogInfo(StringFormat("HardSLCount: %d (Loss: %.2f)", current_metrics.loss_trades, current_metrics.total_loss));
   LogInfo(StringFormat("RescueTrades: %d (PF: %.2f)", g_rescue_trades_count, (g_rescue_gross_loss > 0 ? g_rescue_gross_profit / g_rescue_gross_loss : (g_rescue_gross_profit > 0 ? 99.0 : 1.0))));
   
   // จำนวนครั้งที่มีการปิดออเดอร์ก่อนกำหนดเนื่องจากสภาวะตลาดไม่เอื้ออำนวย
   LogInfo(StringFormat("ContextExitExits: %d", g_early_inv_count));
   LogInfo("-----------------------");
}

#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

#include "Types.mqh"

#define KNARES_BUILD_TAG "KNARES-SMC-FULL-LOT-AWARE"

//+------------------------------------------------------------------+
//| Shared Globals - รวบรวมตัวแปร Global ที่ใช้ร่วมกันระหว่างโมดูล         |
//+------------------------------------------------------------------+

// รายชื่อคู่เงินที่ต้องการเทรด
string symbol_list[];

// จำนวนแท่งเทียนที่ต้องการสำหรับการคำนวณอินดิเคเตอร์
const int REQUIRED_WARMUP_BARS = 150;

// สถานะข่าวสาร (อัปเดตโดย NewsConnector.mqh) — ย้ายมาไว้ที่นี่เพื่อให้ Visualization.mqh อ่านได้ก่อน include NewsConnector.mqh
bool     g_is_news_active = false;      // สถานะว่าปัจจุบันอยู่ในช่วงเวลาข่าวสำคัญหรือไม่
string   g_next_news_name = "None";     // ชื่อหัวข้อข่าวถัดไป
int      g_minutes_to_next_news = 999;  // จำนวนนาทีที่เหลือก่อนถึงข่าวถัดไป

// ตัวแปรควบคุมการทำงานหลัก
string   g_last_symbol = "";
double   g_last_expected_loss = 0.0;
datetime g_last_heartbeat = 0;
datetime g_last_kpi_log = 0;
datetime g_last_init_log = 0;
datetime g_last_deinit_log = 0;
int      g_last_deinit_reason = -1;
datetime g_autoguard_pause_until = 0;
datetime g_last_autotrade_disabled_log = 0;
bool     g_test_force_once_consumed = false;
datetime g_last_decision_trace_log = 0;

// อาร์เรย์เก็บชื่อเหตุผลที่ไม่ได้เข้าเทรดและจำนวนครั้งที่พบ
string g_skip_reasons[];
int    g_skip_counts[];

// สถานะ Pipeline (สำหรับแสดงผลและวิเคราะห์)
string g_pipeline_trend = "INIT";
string g_pipeline_breakout = "INIT";
string g_pipeline_meanrev = "INIT";
string g_pipeline_score = "INIT";
string g_pipeline_conf = "INIT";
string g_pipeline_htf = "INIT";
string g_pipeline_dom = "INIT";
string g_pipeline_final = "INIT";

// สถิติการปิดออเดอร์
int g_close_reason_counts[13]; // Indexed by ENUM_KNARES_CLOSE_DETAIL

// การติดตามออเดอร์และ Engine
ulong g_pos_ids[];
int   g_pos_engine_idx[];

// การติดตามข้อมูล SMC ประจำออเดอร์ (สำหรับ AI Training)
double g_pos_smc_bias[];
double g_pos_smc_zone[];
double g_pos_smc_buy_q[];
double g_pos_smc_sell_q[];

// ตัวนับสถิติการทำงาน (Counters)
int    g_breakout_stage_total[8]; 
int    g_limit_gate_counts[8];    
int    g_manage_positions_called = 0;
double g_early_inv_net = 0; 
int    g_early_inv_count = 0;

// สถิติการกู้คืนสัญญาณ (Rescue)
int      g_rescue_trades_count = 0;
double   g_rescue_gross_profit = 0;
double   g_rescue_gross_loss = 0;
datetime g_rescue_pause_until = 0;

// การติดตามการปิดไม้ด้วยบริบท (Context Exit)
datetime g_last_context_exit_times[5];
int      g_context_exit_ptr = 0;
datetime g_context_exit_pause_until = 0;

// สถิติช่วยเหลืออื่นๆ
int g_pipeline_rescue_candidates = 0;
int g_pipeline_rescue_soft_hits = 0;

// การติดตาม Hard Stop Loss
datetime g_last_hardsl_times[5];
int      g_hardsl_ptr = 0;
datetime g_hardsl_pause_until = 0;

// การติดตามเวลาการเข้าเทรดล่าสุด (Entry Cooldown)
datetime g_last_entry_time_per_symbol[];
string   g_last_entry_symbol_per_symbol[];

// การติดตามการ Bypass สภาวะ Unknown
string   g_regime_bypass_keys[];
datetime g_regime_bypass_until[];

// ค่าคงที่สำหรับการแสดงผล (Dashboard)
const int DashboardUpdateIntervalSec = 2;

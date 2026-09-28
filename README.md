# KNARES MT5: Knowledge-Navigator Expert Advisor
**Professional Institutional-Grade Multi-Strategy Trading Framework**

## 1. บทนำ (Introduction)
KNARES MT5 ไม่ใช่เพียง Expert Advisor ธรรมดา แต่เป็น **Framework การเทรดอัตโนมัติระดับสถาบัน (Institutional-Grade)** ที่สร้างขึ้นบนสถาปัตยกรรมแบบ Modular ความซับซ้อนของระบบไม่ได้อยู่ที่การมีอินดิเคเตอร์จำนวนมาก แต่อยู่ที่ **"กระบวนการตัดสินใจ (Decision-Making Process)"** ที่เลียนแบบวิธีคิดของกองทุนระดับมืออาชีพ

ระบบให้ความสำคัญสูงสุดกับการประเมิน **สภาวะตลาด (Market Regime)** และ **โครงสร้างราคา (SMC - Smart Money Concepts)** เป็นอันดับแรก ก่อนที่จะพิจารณาสัญญาณเข้าเทรด และมีการปกป้องเงินทุนอย่างเข้มงวดด้วยระบบบริหารความเสี่ยงแบบไดนามิก (Dynamic Risk Management)

---

## 2. ปรัชญาการออกแบบ (Core Philosophies)
*   **Context First (บริบทต้องมาก่อนสัญญาณ):** สัญญาณเทรดที่ดีในสภาวะตลาดที่ผิด ย่อมนำไปสู่ความเสียหาย ระบบจะไม่รันกลยุทธ์ใดๆ จนกว่าจะระบุสภาวะตลาดปัจจุบัน (Regime) ได้ชัดเจน
*   **Defense Wins Championships (เกมรับคือผู้ชนะ):** ระบบมีกลไกป้องกันพอร์ตหลายชั้น ตั้งแต่ระดับออเดอร์ (SL, Trailing), ระดับคู่เงิน (Exposure Cap, Price Clustering), ไปจนถึงระดับพอร์ตโฟลิโอโดยรวม (Portfolio Heat, Kill Switch)
*   **Dynamic Adaptation (การปรับตัวแบบไดนามิก):** ระบบไม่เคยอยู่นิ่ง แต่จะปรับ Lot Size, ขยายเพดานความเสี่ยง, หรือหยุดเทรดชั่วคราว (Auto-Guard) ตามประสิทธิภาพของพอร์ตและสภาวะตลาดแบบ Real-time
*   **Transparency & Traceability (โปร่งใสและตรวจสอบได้):** ทุกการตัดสินใจ ไม่ว่าจะเป็นการเข้าเทรด การปฏิเสธคำสั่ง หรือการปิดออเดอร์ จะถูกบันทึกเหตุผลไว้อย่างละเอียด (Reason Logging & Decision Trace) เพื่อการวิเคราะห์ย้อนหลัง

---

## 3. สถาปัตยกรรมระบบ (Architectural Deep Dive)
ระบบถูกออกแบบในลักษณะ **Event-Driven + Pipeline Orchestration** ทำงานประสานกันผ่านโมดูลหลักต่างๆ ดังนี้:

### 3.1 Market Regime Classifier (การจำแนกสภาวะตลาด)
ไฟล์: `RegimeClassifier.mqh`
ทำหน้าที่วิเคราะห์ชุดข้อมูล (Features) จากตลาด เพื่อจำแนกสภาวะตลาดออกเป็น 12 ประเภท:
*   `REGIME_TREND_UP` / `REGIME_TREND_DOWN`: เทรนด์ชัดเจนและแข็งแรง (อ้างอิงจาก ADX และความชันของ EMA)
*   `REGIME_RANGE` / `REGIME_CHOPPY`: ตลาดแกว่งตัวในกรอบ หรือแกว่งตัวแบบไร้ทิศทางและผันผวน
*   `REGIME_BREAKOUT_PREP` / `REGIME_BREAKOUT_READY`: ตลาดบีบตัวรุนแรง (Squeeze) เตรียมระเบิดทิศทาง (อ้างอิงจาก ATR Percentile และ Donchian Channels)
*   `REGIME_VOLATILITY_SHOCK`: เกิดความผันผวนรุนแรงผิดปกติ ระบบจะเข้าสู่โหมดป้องกันตัวทันที
*   `REGIME_TRANSITION`: สภาวะรอยต่อ (เช่น ADX สูงแต่ EMA Slope เริ่มแบนราบ) บ่งชี้ความเป็นไปได้ของการกลับตัว
*   `REGIME_RISK_OFF`: สภาพคล่องต่ำ สเปรดกว้างผิดปกติ ระบบจะระงับการเทรด
*   `REGIME_UNKNOWN`: หากข้อมูลไม่ชัดเจนพอ จะไม่ฝืนเข้าเทรด

### 3.2 Smart Money Concepts (SMC) Context Layer
ไฟล์: `SMCContext.mqh`
วิเคราะห์โครงสร้างราคาเชิงลึก เพื่อหาโซนราคาที่รายใหญ่ (Smart Money) น่าจะเข้าทำกำไร:
*   **Structure & Bias:** คำนวณ Swing High/Low เพื่อหาทิศทางหลัก (Higher TF) และทิศทางรอง (Internal TF)
*   **BOS & CHoCH:** ตรวจจับ Break of Structure (ยืนยันเทรนด์) และ Change of Character (สัญญาณกลับตัว)
*   **Premium / Discount Zones:** ระบุโซนราคาแพง/ถูก อิงตาม Fibonacci ของรอบสวิงล่าสุด เพื่อไม่ให้เข้าซื้อที่ยอดดอย หรือขายที่ก้นเหว
*   **Deep Confirmation (Phase 40):** ค้นหาพฤติกรรมเฉพาะ เช่น Liquidity Sweeps (การล่า Stop Loss), Displacement (การพุ่งแรง), และ Retest (การย่อทดสอบ) เพื่อคำนวณคะแนนคุณภาพของ Setup (Setup Quality Score)

### 3.3 The Pipeline Controller (สมองส่วนกลาง)
ไฟล์: `PipelineController.mqh`
กระบวนการคัดกรองและให้คะแนนสัญญาณ (Signal Aggregation & Scoring):
1.  **Generation:** รับสัญญาณดิบจาก Trading Engines (Trend, Breakout, Mean Reversion)
2.  **Contextual Multipliers:** คูณคะแนนความน่าจะเป็นของสัญญาณด้วยน้ำหนักของ Regime (เช่น สัญญาณ Trend จะถูกเพิ่มน้ำหนักหากตลาดเป็น `REGIME_TREND_UP`)
3.  **Penalties:** หักคะแนนหากสัญญาณขัดแย้งกับเทรนด์ใหญ่ (HTF Mismatch) หรือตลาดอยู่ในสภาวะคลุมเครือ (`REGIME_UNKNOWN`)
4.  **Rescue Logic:** หากสัญญาณดิบมีคะแนนไม่ผ่านเกณฑ์เพียงเล็กน้อย แต่บริบท SMC แข็งแกร่งมาก (High Buy/Sell Quality) ระบบจะทำการ "กู้สัญญาณ" เพื่อให้ผ่านเกณฑ์การเข้าเทรด
5.  **Final Arbitration:** เลือกสัญญาณที่ดีที่สุดที่ผ่านเกณฑ์ทั้งหมด

### 3.4 Position Management & Exit Arbitration
ไฟล์: `PositionManager.mqh`
ระบบควบคุมลำดับความสำคัญในการจัดการออเดอร์ (Priority-based Exit Intent):
1.  **Forced Close (Priority 100/95):** ปิดหนีตายทันทีเมื่อเจอ Volatility Shock หรือถือครองนานเกินเวลา (Timeout)
2.  **Regime Exit (Priority 90/80):** ปิดออเดอร์ทันทีหากสภาวะตลาดเปลี่ยนไปขัดแย้งกับออเดอร์ (เช่น ถือ Buy แต่ตลาดเป็น Trend Down) โดยมีระบบ Hysteresis เพื่อป้องกันการโดนหลอก (Whipsaw)
3.  **Early Invalidation (Priority 85):** ตัดขาดทุนก่อนชน SL หากตรวจพบว่าโครงสร้างราคาเริ่มเสียทรง (EMA Slope กลับตัวอย่างชัดเจน)
4.  **Partial Close & Breakeven (Priority 80/60):** แบ่งปิดกำไรเมื่อถึงเป้า 1R และเลื่อน SL มาบังหน้าทุนเพื่อการันตีไม่ขาดทุน (Risk-Free Trade)
5.  **Profit Lock / Accelerated Trailing (Priority 70):** เลื่อน SL เพื่อล็อกกำไรตามขั้นบันได (R-Multiple) และเร่งความเร็วการเลื่อนให้แคบลงเมื่อราคาพุ่งทะยานแรงๆ
6.  **ATR Trailing (Priority 50):** เลื่อน SL อิงตามความผันผวน (ATR) เพื่อให้พื้นที่ราคาวิ่ง

---

## 4. ระบบความปลอดภัยและการจัดการความเสี่ยง (Safety Guards & Risk)

### 4.1 ขีดจำกัดระดับพอร์ต (Limit Gate)
ทุกสัญญาณต้องผ่านประตูด่านความปลอดภัย 5 ชั้นก่อนถูกส่งไปโบรกเกอร์:
*   **Portfolio Drawdown:** ปฏิเสธไม้ใหม่หาก Drawdown พอร์ตเกินกำหนด
*   **Exposure Cap:** จำกัดปริมาณ Lot รวม (Leverage) ไม่ให้เกินเพดานที่ตั้งไว้ (มีเพดานแยกสำหรับ FX และ XAU)
*   **Heat Cap:** จำกัดความเสี่ยงรวมที่เป็นเงินจริง (Total Risk Value)
*   **Price Clustering Block:** ห้ามเปิดไม้ซ้ำในบริเวณราคาเดียวกัน (บังคับให้กระจายความเสี่ยง)
*   **Max Positions:** ควบคุมจำนวนไม้สูงสุดต่อ 1 คู่เงิน

### 4.2 ระบบแก้พอร์ตและปรับตัว (Smart Recovery & Adaptation)
*   **Dynamic Risk Reduction:** หากมี Loss Streak ระบบจะลด Lot Size ลง (เช่น 50%) และเปลี่ยนโหมดเป็น `DEFENSIVE`
*   **Smart Recovery:** หากออเดอร์เดิมขาดทุนถึงระดับที่กำหนด และมีสัญญาณฝั่งตรงข้ามที่มีความเชื่อมั่นสูงมาก (High Confidence Reversal) ระบบจะเปิดไม้แก้พอร์ตแบบฉลาด
*   **Aggregate Profit Exit:** หากพอร์ตมีการติดลบสะสม เมื่อผลรวมทุกออเดอร์กลับมากำไรถึงเป้าที่ตั้งไว้ ระบบจะทำการปิดรวบ (Basket Close) ทันที

### 4.3 ระบบป้องกันเชิงระบบ (System Guards)
*   **Single Instance Guard:** ป้องกันผู้ใช้เผลอลาก EA ใส่กราฟซ้อนกัน ทำให้เบิ้ลไม้
*   **Auto-Guard:** หากโบรกเกอร์ปฏิเสธคำสั่ง (Reject) ถี่เกินไป (เช่น จากปัญหาเน็ตเวิร์ก) EA จะเข้าสู่โหมดหลับ (Pause) ชั่วคราวเพื่อป้องกันการโดนแบนบัญชี
*   **DOM Soft Veto:** ตรวจสอบความไม่สมดุลของ Order Book หากฝั่งตรงข้ามมีวอลลุ่มดักรอหนาแน่นมาก ระบบจะยกเลิกการเปิดออเดอร์นั้น

---

## 5. การตั้งค่าและการปรับจูน (Configuration Guide)
พารามิเตอร์หลักทั้งหมดอยู่ในไฟล์ `Config.mqh` แบ่งเป็นหมวดหมู่ดังนี้:

*   **1. BASIC TRADING & RISK:** ตั้งค่า Symbol, Timeframe, Lot Mode (Fixed หรือ % Risk)
*   **2. CORE STRATEGY TOGGLES:** เปิดปิด Trading Engines, Smart Recovery
*   **3. TAKE PROFIT & STOP LOSS:** ตั้งเป้าหมาย RRR, ตัวคูณ ATR สำหรับจุดตัดขาดทุน
*   **4. PORTFOLIO & SAFETY GUARDS:** ตั้งค่า Kill Switch, Max Exposure, Max Drawdown
*   **ADVANCED TUNING:** ส่วนนี้ใช้สำหรับปรับจูนความเซนซิทีฟของ SMC, Pipeline Penalties, โหมดการทำ Partial Close และเงื่อนไข Regime Exit **(แนะนำให้แก้ไขเฉพาะผู้ที่มีความเข้าใจโครงสร้างระบบเท่านั้น)**

---

## 6. โครงสร้างไฟล์ (Directory Structure)

```text
/MQL5/
├── Experts/
│   └── KNARES.mq5                 # เมนไฟล์ของ Expert Advisor
├── Include/
│   └── KNARES/
│       ├── Config.mqh             # รวมพารามิเตอร์การตั้งค่า
│       ├── Types.mqh              # กำหนด Structs และ Enums
│       ├── SharedGlobals.mqh      # ตัวแปร Global ภายในระบบ
│       ├── Logger.mqh             # ระบบบันทึก Log และแจ้งเตือน
│       ├── SMCContext.mqh         # ระบบวิเคราะห์ SMC & Structure
│       ├── RegimeClassifier.mqh   # ระบบวิเคราะห์สภาวะตลาด
│       ├── PipelineController.mqh # ควบคุมการคัดกรองสัญญาณ
│       ├── PositionManager.mqh    # ควบคุมออเดอร์ที่เปิดแล้ว
│       ├── MarketData.mqh         # ดึงและสร้าง Market Snapshot
│       ├── MarketPolicy.mqh       # ตรวจสอบกฎการเทรดและ Exposure
│       ├── DynamicThreshold.mqh   # คำนวณเกณฑ์คะแนนแบบไดนามิก
│       ├── EngineController.mqh   # ควบคุมเปิด/ปิดกลยุทธ์ย่อย
│       ├── SignalRescue.mqh       # ระบบกู้คืนสัญญาณคุณภาพดี
│       ├── ReasonLogger.mqh       # บันทึกเหตุผลการไม่เทรด
│       ├── ApexAnalytics.mqh      # วิเคราะห์ Stat-Arb & HMM
│       └── ... (และโมดูลย่อยอื่นๆ สำหรับ Trade Event, Metric, Dashboard)
```

---

## 7. วิธีการติดตั้ง (Installation)

1.  คัดลอกโฟลเดอร์ `KNARES` ทั้งหมดไปวางไว้ที่ `[โฟลเดอร์ข้อมูล MT5]/MQL5/Include/`
2.  คัดลอกไฟล์ `KNARES.mq5` ไปวางไว้ที่ `[โฟลเดอร์ข้อมูล MT5]/MQL5/Experts/`
3.  เปิดโปรแกรม **MetaEditor** 
4.  เปิดไฟล์ `KNARES.mq5` และกดปุ่ม **Compile (F7)** (ต้องไม่มี Error)
5.  กลับไปที่ MetaTrader 5 ลาก EA `KNARES` ลงบนกราฟที่ต้องการ (แนะนำ Timeframe **M1, M5, M15**)
6.  ในหน้าต่างตั้งค่า ตรวจสอบแท็บตั้งค่า (Inputs) โดยเฉพาะรายชื่อ `Symbols`
7.  ตรวจสอบให้แน่ใจว่าปุ่ม **"Algo Trading"** บนเมนูบาร์ของ MT5 เป็นสีเขียว (อนุญาตให้รัน EA)

---

## 8. คำเตือน (Disclaimer)
ตลาด Forex และ Gold มีความผันผวนสูงมาก **KNARES MT5** ถูกพัฒนาขึ้นเพื่อใช้กระบวนการทางสถิติและตรรกะขั้นสูงเพื่อสร้างความได้เปรียบ (Edge) และจำกัดความเสี่ยงอย่างเป็นระบบ 
*   **ระบบไม่รับประกันผลกำไร** หรือปกป้องคุณจากความเสียหายได้ 100% ในกรณีตลาดเกิด Black Swan Events
*   ผู้ใช้งานควรทำการ Backtest และรันบนบัญชี **Demo** เป็นระยะเวลาหนึ่งเพื่อทำความเข้าใจการทำงานของ Dynamic Risk และการปรับตัวของระบบ ก่อนนำไปใช้กับบัญชีเงินจริง

**Copyright 2026, Dr.Kittimasak Naijit**
*KNARES (Knowledge-Navigator) - Data-Driven, Structure-Guided, Risk-Controlled.*

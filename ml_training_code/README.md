# โค้ดขั้นตอนการเทรนโมเดล Meta-label (ONNX) ของ KNARES

โฟลเดอร์นี้รวมโค้ด ข้อมูล และผลที่ใช้ตอบคำถามเรื่องการเทรนโมเดล ทุกไฟล์เป็นสำเนา ต้นฉบับอยู่ที่ `Documents/Knare_ea/` และ EA ปัจจุบันไม่ถูกแก้

## โครงสร้าง

| โฟลเดอร์ | เนื้อหา |
|---|---|
| `scripts/` | สคริปต์ Python ทั้งหมด (รันจากในโฟลเดอร์นี้ได้เลย) |
| `ml_data/` | ไฟล์ข้อมูลที่ EA ส่งออก (Entry_/Exit_ CSV) และสรุปผล |
| `ea_side/` | ฝั่ง EA: `FeatureExport.mqh` (ส่งออกฟีเจอร์), `MetaModel.mqh` (gate), `KNARES_Meta.onnx` (โมเดลที่ฝังอยู่) |
| `figure/` | แผนภาพขั้นตอน (UML Activity Diagram 3 เลน) |

## ขั้นตอนตามแผนภาพ ↔ ไฟล์

| ขั้นตอน | ไฟล์ |
|---|---|
| 1) EA ส่งออกฟีเจอร์ตอนเข้าไม้ และผลตอนปิดไม้ | `ea_side/FeatureExport.mqh` (เปิดด้วย `EnableSampleExport`) |
| 2) รวม Entry/Exit ด้วย PosId, ติดป้าย `Win = R > 0` | `scripts/ml_common.py` (`load()`) |
| 3) แบ่งช่วงตามเวลา, ตัดไม้ที่ปิดหลังวันตัดช่วง | `scripts/ml_final.py`, `ml_common.py` (`folds()`) |
| 4) ฝึก StandardScaler + Logistic Regression (C = 0.05, 24 ฟีเจอร์) | `scripts/ml_final.py` (`fit()`) |
| 5) ส่งออก ONNX (รวมการปรับมาตรฐานเข้าน้ำหนัก) และตรวจกับ scikit-learn | `scripts/ml_final.py` (ส่วนท้าย) |
| 6) ใช้เป็น Gate ใน EA | `ea_side/MetaModel.mqh` (`MetaGatePass()`) |

## วิธีรัน (โมเดลสุดท้าย)

```bash
cd scripts
python ml_final.py ../out_test.onnx
```

ผลที่ควรได้ (ตรวจแล้ว): AUC ช่วงตรวจสอบ 0.5848, AUC OOS 0.5470, gate ที่ 0.45 ทำให้กำไรสุทธิ OOS 726 → 397 USD, และไฟล์ ONNX ที่ได้เหมือน `ea_side/KNARES_Meta.onnx` ทุกไบต์ (ค่าต่างจาก scikit-learn < 1e-7)

## สคริปต์ที่ใช้เลือกแนวทาง (ก่อนได้โมเดลสุดท้าย)

| ไฟล์ | หน้าที่ |
|---|---|
| `ml_walkforward.py` | Walk-forward 5 fold เทียบ LR / LightGBM / Ensemble (AUC 0.570 / 0.575 / 0.578) |
| `ml_oof.py` | AUC แบบ out-of-fold รวม และตาราง threshold บนช่วงฝึก |
| `ml_oos_eval.py` | ประเมิน OOS ครั้งเดียวโดยกำหนด threshold จากช่วงฝึกล่วงหน้า |
| `ml_wf2.py`, `ml_wf3.py` | ลองทำนาย R แบบ regression และฟีเจอร์ราคาเพิ่ม (ไม่ช่วยให้ AUC ดีขึ้น) |
| `ml_export_meta.py` | การส่งออก ONNX รอบแรก (ฝึกบนชุด `train` เดิม ก่อนฝึกซ้ำบน EA ชุดสุดท้ายด้วย `ml_final.py`) |
| `ml_gate_compare.py` | อ่านรายงาน HTML ของ Strategy Tester (รอบไม่ใช้ gate กับรอบใช้ gate) มาเทียบกำไร/PF/Sharpe/Drawdown ใช้ path เฉพาะเครื่องนี้ จึงรันที่อื่นไม่ได้ถ้าไม่แก้ path |

## สภาพแวดล้อมที่ใช้

Python 3.11.3, scikit-learn 1.6.1, numpy 2.4.4, pandas 2.3.3, torch 2.11.0 (ใช้สร้างกราฟ ONNX), onnxruntime 1.24.4, lightgbm 4.6.0

## สิ่งที่ควรบอกอาจารย์ตรงๆ

- โมเดลฝึกและประเมินบนไม้ของ EA กรอบ **M5** (เปิดตัวกรอง SMC) ไม่ใช่ชุด M15 สุดท้าย
- **ไม่ได้ทำ Hyperparameter Tuning** (ไม่มี Grid/Random Search) ค่า `C = 0.05` และพารามิเตอร์ LightGBM กำหนดไว้ล่วงหน้า สิ่งที่เทียบคือชนิดโมเดล
- ช่วง OOS ถูกใช้ประเมินหลายครั้ง (มีบันทึกใน `ml_data/ML_RESULTS_SUMMARY.md`)
- ป้ายเป็นแบบ Meta-label (`R > 0` ของไม้จริง) ไม่ใช่ Triple Barrier
- ฝึกแบบ Offline และตรึงน้ำหนัก ไม่ใช่ Online Learning
- gate ไม่ช่วยกำไร OOS จึงปิดไว้ (`EnableMetaGate = false`)
- `ml_wf3.py` อ่านข้อมูลราคา M5 จาก `%APPDATA%\MetaQuotes\Terminal\Common\Files\gs_xau_m5_full.csv` ซึ่งไม่ได้รวมไว้ในโฟลเดอร์นี้

## ฝึกซ้ำบนชุด M15 สุดท้าย (6 พ.ย. 2569)
- ข้อมูล: `ml_data/*_m15dev|m15val|m15oos.csv` (ส่งออกจาก EA ชุดสุดท้าย M15) สคริปต์ `scripts/ml_final_m15.py` ผลสรุปที่ `ml_data/ML_RESULTS_M15.md`
- ผล: AUC ช่วงตรวจสอบ 0.521, ช่วงนอกตัวอย่าง 0.508 (ใกล้เดาสุ่ม) ตัวกรองที่ 0.45 ลดกำไรสุทธิ OOS จาก 1,470 เหลือ 315 ดอลลาร์
- ไม่ได้นำโมเดลนี้ไปฝังใน EA (ไฟล์ `KNARES_Meta_M15.onnx` อยู่ใน ml_data เท่านั้น)

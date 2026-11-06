# Meta-label retrain on the FINAL M15 config (2026-11-06)
Data: EA exports from MT5 Strategy Tester, KNARES_LIVE, XAUUSD M15, M1-OHLC model, deposit 50,000, fixed 0.01 lot, final-spec set (Trend+MeanRev, simple SMC filter, HMM/Breakout off).
Files: Entry/Exit_XAUUSDm_m15dev (2018-01-03..2021-12-31, 286 trades; 242 of them in 2021), m15val (2022-01-03..2024-09-17, 1,101), m15oos (2024-09-18..2026-09-17, 831 after cleaning).
Script: scripts/ml_final_m15.py (same pipeline as ml_final.py: LR C=0.05, StandardScaler, 24 features, gate 0.45).

dev -> val : AUC 0.521 ; gate 0.45 keeps 448/1101, meanR -0.010 (all +0.041), net -191 (all +143)
dev+val -> OOS : AUC 0.508 ; all 831 trades meanR +0.100, net +1,470
  gate 0.40: keep 583, meanR +0.080, net +794
  gate 0.45: keep 332, meanR +0.054, net +315
  gate 0.50: keep 135, meanR +0.101, net +321
max |onnx - sklearn| = 1.3e-7 (export OK). Output model: ml_data/KNARES_Meta_M15.onnx (+ .json). NOT embedded in the EA.
Reading: AUC ~0.5 on M15 = no usable signal (OOS SE of AUC ~0.02); gate reduces profit. Only 2,218 trades in total; the 2018-2020 dev period has very few trades (10-23 per year).

## Transfer test: M5-trained model (KNARES_Meta_v2.json, embedded in EA) applied to the M15 trades, no refit
m15dev  n=285 AUC 0.630 (train period overlaps; ignore)
m15val  n=1101 AUC 0.541 (calendar-overlaps the M5 training period)
m15oos  n=831  AUC 0.557 (bootstrap 95% CI 0.514..0.591); gate 0.45 keeps 586, meanR +0.116 (all +0.100), net +1,411 (all +1,470)
vs M15-refit OOS AUC 0.508. Reading: M5 model ranks M15 trades slightly better (more training data: 6,660 vs 1,387 trades), but the gate still does not raise net profit.

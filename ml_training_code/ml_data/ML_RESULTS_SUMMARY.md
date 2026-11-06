# KNARES meta-label model: results summary (generated 2026-10-30)

Data: EA exports (Entry_/Exit_XAUUSDm_*.csv). Config: Trend+MeanRev, M5, HMM off, 0.01 lot, Exness Trial7 history.
Label: win = price-based R > 0, R = (exit-entry)*dir/|entry-SL|.  Train = 2018-01-02..2024-09-17 (12,867 trades). OOS = 2024-09-19..2026-09-17 (4,089 trades).

## Base strategy (no model)
- Train: win 45.1%, mean R -0.047 (negative every year 2018-2024). OOS: win 51.9%, mean R +0.028.
- Avg win +0.71R, avg loss -0.67R, break-even win rate 48.5%. Early-invalidation exits = 35% of trades (all losses, avg -0.53R).

## Model (24 features at entry -> P(win)), logistic regression, exported to ONNX (embedded in EA)
- Walk-forward AUC (test years 2020-2024): LR 0.570, LightGBM 0.575, ensemble 0.578; all 5 folds > 0.5.
- Rule-based Score alone: AUC 0.486 (slightly inverse); ADX alone 0.468. SMC quality in trade direction 0.527.
- Extra price-derived features (returns, vol ratio, range) did NOT help (AUC unchanged). Expected-R regression: Spearman ~0.02 (no usable signal).
- Win rate by P(win) decile (pooled OOF): 36% (lowest) -> 57-60% (highest), monotone.
- OOS AUC: LR 0.576, LightGBM 0.579 (no degradation vs walk-forward).

## As a trading gate (p >= 0.45, block cooldown 30 min)
| block | trades | win | mean R | net USD | max equity DD |
| validation 2023-01..2024-09 (model fit <=2022): OFF | 3641 | 46.4% | -0.043 | -710 | 716 USD |
| validation: ON | 2498 | 52.0% | -0.025 | -177 | 254 USD |
| OOS 2024-09..2026-09: OFF | 4089 | 51.9% | +0.028 | +1733 | 433 USD (6.95%) |
| OOS: ON (final) | 3195 | 55.2% | +0.030 | +919 | 475 USD (7.89%), PF 1.07 vs 1.11, Sharpe 1.85 vs 2.58 |
- Gate WITHOUT the cooldown was worse on OOS (+527 USD): a blocked signal is re-evaluated next tick and eventually passes -> selection by waiting.
- NOTE: OOS was looked at twice (first gate version, then cooldown version); cooldown mechanism itself was chosen on the validation block.

## Verdict
Model has real, stable discriminative power (AUC ~0.575) but it does not turn the strategy profitable and does not raise total profit on OOS.
It helped (loss -75%, DD -65%) in a losing regime and reduced profit in a winning regime -> shipped as OPTIONAL (EnableMetaGate=false by default).

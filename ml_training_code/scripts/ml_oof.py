import sys, warnings
import numpy as np, pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, folds, RAW, DIRADJ
warnings.filterwarnings("ignore")
d = load("train")
YEARS = [2020, 2021, 2022, 2023, 2024]
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]
mk = {"LR": lambda: make_pipeline(StandardScaler(), LogisticRegression(C=0.05, max_iter=500)),
      "LGBM": lambda: lgb.LGBMClassifier(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8,
                                         subsample_freq=1, colsample_bytree=0.7, reg_lambda=10.0, random_state=7, verbose=-1, n_jobs=4)}
oof = []
for y, tr, te in folds(d, YEARS):
    t = d.loc[te, ["Time", "R", "Win"]].copy(); t["year"] = y
    for k, f in mk.items():
        m = f(); m.fit(d.loc[tr, DA], d.loc[tr, "Win"]); t[k] = m.predict_proba(d.loc[te, DA])[:, 1]
    oof.append(t)
o = pd.concat(oof)
o["ENS"] = (o.LR.rank(pct=True) + o.LGBM.rank(pct=True)) / 2
print("pooled OOF AUC:", {k: round(roc_auc_score(o.Win, o[k]), 4) for k in ("LR", "LGBM", "ENS")})
for k in ("LR", "LGBM", "ENS"):
    o["bin"] = pd.qcut(o[k], 10, labels=False, duplicates="drop")
    g = o.groupby("bin").agg(n=("R", "size"), win=("Win", "mean"), meanR=("R", "mean"))
    print(f"\n{k} deciles (0=lowest score .. 9=highest):"); print(g.round(3).T.to_string())
print("\nbase win rate", round(o.Win.mean(), 3), "| meanR", round(o.R.mean(), 4), "| n", len(o))
# probability-threshold table for LR (calibrated probs)
print("\nLR threshold table (pooled OOF):")
for t in (0.40, 0.45, 0.48, 0.50, 0.52, 0.55):
    s = o[o.LR >= t]
    per = s.groupby("year").R.mean().round(3).to_dict()
    print(f" p>={t:.2f}: keep {len(s)/len(o):5.1%}  meanR {s.R.mean():+.3f}  win {s.Win.mean():.3f}  sumR {s.R.sum():+7.1f} | per-year meanR {per}")

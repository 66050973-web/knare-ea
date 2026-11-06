"""ONE-SHOT out-of-sample evaluation. Models are fit on train (<=2024-09-18) only; thresholds fixed beforehand from train OOF."""
import sys, warnings, joblib
import numpy as np, pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, RAW, DIRADJ
warnings.filterwarnings("ignore")
tr, te = load("train"), load("oos")
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]
lr = make_pipeline(StandardScaler(), LogisticRegression(C=0.05, max_iter=500)).fit(tr[DA], tr.Win)
gb = lgb.LGBMClassifier(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8, subsample_freq=1,
                        colsample_bytree=0.7, reg_lambda=10.0, random_state=7, verbose=-1, n_jobs=4).fit(tr[DA], tr.Win)
te = te.copy(); te["LR"] = lr.predict_proba(te[DA])[:, 1]; te["GB"] = gb.predict_proba(te[DA])[:, 1]
print("OOS n", len(te), "| base win", round(te.Win.mean(), 3), "meanR", round(te.R.mean(), 4), "sumR", round(te.R.sum(), 1))
print("OOS AUC  LR", round(roc_auc_score(te.Win, te.LR), 4), " LGBM", round(roc_auc_score(te.Win, te.GB), 4))
for k in ("LR", "GB"):
    te["bin"] = pd.qcut(te[k], 5, labels=False)
    print(f"\n{k} quintiles:"); print(te.groupby("bin").agg(n=("R", "size"), win=("Win", "mean"), meanR=("R", "mean")).round(3).T.to_string())
print("\nLR threshold filter (thresholds fixed from train OOF):")
for t in (0.40, 0.45, 0.48, 0.50):
    s = te[te.LR >= t]
    print(f" p>={t:.2f}: keep {len(s)/len(te):5.1%} n={len(s)} meanR {s.R.mean():+.3f} win {s.Win.mean():.3f} sumR {s.R.sum():+.1f}")
joblib.dump({"lr": lr, "cols": DA}, "meta_lr_candidate.joblib")

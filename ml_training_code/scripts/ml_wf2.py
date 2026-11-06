"""Walk-forward v2: predict expected R (regression) and tail outcomes; TRAIN set only."""
import sys, warnings
import numpy as np, pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, folds, RAW, DIRADJ, EXTRA
warnings.filterwarnings("ignore")
d = load("train")
YEARS = [2020, 2021, 2022, 2023, 2024]
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]

def reg(**kw):
    p = dict(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8, subsample_freq=1,
             colsample_bytree=0.7, reg_lambda=10.0, random_state=7, verbose=-1, n_jobs=4)
    p.update(kw); return lgb.LGBMRegressor(**p)
def clf(**kw):
    p = dict(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8, subsample_freq=1,
             colsample_bytree=0.7, reg_lambda=10.0, random_state=7, verbose=-1, n_jobs=4)
    p.update(kw); return lgb.LGBMClassifier(**p)

d["BigLoss"] = (d.R <= -0.95).astype(int)      # stopped out at full risk
d["GoodWin"] = (d.R >= 0.5).astype(int)
EXPS = {
 "reg R (LGBM)":      (lambda: reg(), "R", +1),
 "reg R huber":       (lambda: reg(objective="huber", alpha=1.0), "R", +1),
 "reg R ridge":       (lambda: make_pipeline(StandardScaler(), Ridge(alpha=300)), "R", +1),
 "clf BigLoss (avoid)": (lambda: clf(), "BigLoss", -1),
 "clf GoodWin":       (lambda: clf(), "GoodWin", +1),
}
for name, (mk, target, sign) in EXPS.items():
    rows = []
    for y, tr, te in folds(d, YEARS):
        m = mk(); m.fit(d.loc[tr, DA], d.loc[tr, target])
        s = m.predict(d.loc[te, DA]) if target == "R" else m.predict_proba(d.loc[te, DA])[:, 1]
        s = s * sign
        t = d.loc[te].copy(); t["s"] = s
        keep50 = t[t.s >= t.s.quantile(0.5)]; keep70 = t[t.s >= t.s.quantile(0.3)]
        rows.append(dict(year=y, spearman=spearmanr(t.s, t.R)[0], R_all=t.R.mean(), R_keep70=keep70.R.mean(), R_keep50=keep50.R.mean(),
                         sumR_all=t.R.sum(), sumR_keep50=keep50.R.sum()))
    r = pd.DataFrame(rows)
    print(f"\n== {name}: mean spearman {r.spearman.mean():+.3f} | meanR all {r.R_all.mean():+.3f} keep70% {r.R_keep70.mean():+.3f} keep50% {r.R_keep50.mean():+.3f}"
          f" | folds keep50>all {(r.R_keep50>r.R_all).sum()}/{len(r)}")
    print(r.round(3).to_string(index=False))

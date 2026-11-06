import sys, warnings
import numpy as np, pandas as pd
from scipy.stats import spearmanr
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, folds, RAW, DIRADJ, EXTRA, PRICE_FEATS, add_price_features
warnings.filterwarnings("ignore")
d = add_price_features(load("train"))
print("NaN rate of price feats:", d[PRICE_FEATS].isna().mean().round(3).to_dict())
d = d.dropna(subset=PRICE_FEATS).reset_index(drop=True)
YEARS = [2020, 2021, 2022, 2023, 2024]
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]
SETS = {"base": DA, "base+price": DA + PRICE_FEATS, "price only": PRICE_FEATS + ["Dir", "IsTrend"]}
def lg():
    return lgb.LGBMClassifier(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8, subsample_freq=1,
                              colsample_bytree=0.7, reg_lambda=10.0, random_state=7, verbose=-1, n_jobs=4)
def lr():
    return make_pipeline(StandardScaler(), LogisticRegression(C=0.05, max_iter=500))
for sname, cols in SETS.items():
    for mname, mk in (("LGBM", lg), ("LR", lr)):
        aucs, rall, r50, r30 = [], [], [], []
        for y, tr, te in folds(d, YEARS):
            m = mk(); m.fit(d.loc[tr, cols], d.loc[tr, "Win"])
            p = m.predict_proba(d.loc[te, cols])[:, 1]
            t = d.loc[te].copy(); t["p"] = p
            aucs.append(roc_auc_score(t.Win, p)); rall.append(t.R.mean())
            r50.append(t[t.p >= t.p.quantile(.5)].R.mean()); r30.append(t[t.p >= t.p.quantile(.7)].R.mean())
        print(f"{sname:11s} {mname:5s} AUC {np.round(aucs,3)} mean {np.mean(aucs):.3f} | meanR all {np.mean(rall):+.3f} top50 {np.mean(r50):+.3f} top30 {np.mean(r30):+.3f}")

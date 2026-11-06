"""Walk-forward evaluation of meta-label models on the TRAIN set only (2018 -> 2024-09-18).
The out-of-sample set (ml_data/*_oos.csv) is never touched here."""
import sys, warnings
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score
import lightgbm as lgb
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, folds, RAW, DIRADJ, EXTRA

warnings.filterwarnings("ignore")
d = load("train")
YEARS = [2020, 2021, 2022, 2023, 2024]
FS = {
    "raw": RAW,
    "diradj": [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"],
    "diradj+ctx": [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + EXTRA,
}


def lgbm(seed=7, **kw):
    p = dict(n_estimators=250, learning_rate=0.03, num_leaves=8, min_child_samples=150, subsample=0.8, subsample_freq=1,
             colsample_bytree=0.7, reg_lambda=10.0, random_state=seed, verbose=-1, n_jobs=4)
    p.update(kw)
    return lgb.LGBMClassifier(**p)


MODELS = {
    "LR": lambda: make_pipeline(StandardScaler(), LogisticRegression(C=0.05, max_iter=500)),
    "LGBM": lambda: lgbm(),
}


def evaluate(fs, mname, label="Win"):
    rows = []
    cols = FS[fs]
    for y, tr, te in folds(d, YEARS):
        m = MODELS[mname]()
        m.fit(d.loc[tr, cols], d.loc[tr, label])
        p = m.predict_proba(d.loc[te, cols])[:, 1]
        t = d.loc[te].copy()
        t["p"] = p
        auc = roc_auc_score(t.Win, p)
        top = t[t.p >= t.p.quantile(0.5)]
        top3 = t[t.p >= t.p.quantile(0.7)]
        rows.append(dict(year=y, n=len(t), auc=auc, R_all=t.R.mean(), R_top50=top.R.mean(), R_top30=top3.R.mean(),
                         win_all=t.Win.mean(), win_top50=top.Win.mean()))
    r = pd.DataFrame(rows)
    return r


if __name__ == "__main__":
    print("samples", len(d), "| years", d.Time.dt.year.value_counts().sort_index().to_dict())
    print("hold minutes median/90%:", d.HoldMin.median().round(0), d.HoldMin.quantile(0.9).round(0))
    # benchmark: how informative is the EA's own rule-based score?
    for c in ("Score", "Confidence", "SMCQ_d", "ADX"):
        aucs = []
        for y, tr, te in folds(d, YEARS):
            aucs.append(roc_auc_score(d.loc[te, "Win"], d.loc[te, c]))
        print(f"benchmark AUC of {c:11s}:", np.round(aucs, 3), "mean", round(np.mean(aucs), 3))
    for fs in FS:
        for mname in MODELS:
            r = evaluate(fs, mname)
            print(f"\n== {fs} / {mname}   mean AUC {r.auc.mean():.3f}  | meanR all {r.R_all.mean():+.3f}  top50 {r.R_top50.mean():+.3f}  top30 {r.R_top30.mean():+.3f}"
                  f" | folds where top50>all: {(r.R_top50 > r.R_all).sum()}/{len(r)}")
            print(r.round(3).to_string(index=False))

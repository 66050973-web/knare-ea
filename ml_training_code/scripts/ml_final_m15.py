"""Meta-label model on the FINAL M15 EA config (KNARES_FINAL, SMC on). Fit dev+val, evaluate on OOS; also dev->val check.
   Exports ONNX (input float[1,24] -> sigmoid) + json next to this script's parent ml_data."""
import sys, os, json, warnings
import numpy as np, pandas as pd
import torch, torch.nn as nn
import onnxruntime as ort
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ml_common import load, RAW, DIRADJ
warnings.filterwarnings("ignore")
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]
OUT = sys.argv[1]
dev, val, oos = load("m15dev"), load("m15val"), load("m15oos")
print("OOS span", oos.Time.min(), "->", oos.ExitTime.max(), "n", len(oos))
CUT = pd.Timestamp("2024-09-19")
val = val[val.ExitTime < CUT].reset_index(drop=True)


def fit(tr):
    sc = StandardScaler().fit(tr[DA])
    lr = LogisticRegression(C=0.05, max_iter=1000).fit(sc.transform(tr[DA]), tr.Win)
    return sc, lr


def prob(sc, lr, d):
    return lr.predict_proba(sc.transform(d[DA]))[:, 1]


def gate_report(name, d, p, th=0.45):
    keep = p >= th
    print(f"  {name}: AUC={roc_auc_score(d.Win, p):.4f} | all n={len(d)} meanR={d.R.mean():+.3f} | "
          f"kept(p>={th}) n={keep.sum()} meanR={d.R[keep].mean():+.3f} netPnl={d.Pnl[keep].sum():+.0f} (all {d.Pnl.sum():+.0f})")


print("dev -> val")
sc, lr = fit(dev)
gate_report("val", val, prob(sc, lr, val))
print("dev+val -> OOS")
tr = pd.concat([dev, val]).sort_values("Time").reset_index(drop=True)
tr = tr[tr.ExitTime < CUT - pd.Timedelta(days=1)].reset_index(drop=True)
sc, lr = fit(tr)
p_oos = prob(sc, lr, oos)
for th in (0.40, 0.45, 0.50):
    gate_report(f"oos th={th}", oos, p_oos, th)
w = lr.coef_[0] / sc.scale_
b = float(lr.intercept_[0] - np.sum(lr.coef_[0] * sc.mean_ / sc.scale_))


class M(nn.Module):
    def __init__(s):
        super().__init__(); s.l = nn.Linear(len(DA), 1)
        with torch.no_grad(): s.l.weight[:] = torch.tensor(w, dtype=torch.float32)[None]; s.l.bias[:] = b
    def forward(s, x): return torch.sigmoid(s.l(x))


torch.onnx.export(M().eval(), torch.randn(1, len(DA)), OUT, input_names=["input"], output_names=["output"], opset_version=14, dynamo=False)
sess = ort.InferenceSession(OUT)
X = oos[DA].values.astype(np.float32)
p_onnx = np.concatenate([sess.run(None, {"input": X[i:i+1]})[0] for i in range(len(X))]).ravel()
print("max |onnx - sklearn| =", float(np.abs(p_onnx - p_oos).max()))
print("top coef:", sorted(zip(DA, lr.coef_[0].round(3)), key=lambda t: -abs(t[1]))[:8])
json.dump({"features": DA, "mean": sc.mean_.tolist(), "scale": sc.scale_.tolist(), "w": w.tolist(), "b": b, "threshold": 0.45,
           "train_range": f"{tr.Time.min().date()}..{tr.ExitTime.max().date()}", "n_train": int(len(tr))}, open(OUT.replace(".onnx", ".json"), "w"), indent=1)

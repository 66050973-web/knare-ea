"""Fit the final meta-label logistic model on TRAIN (<= 2024-09-18) and export it as a tiny ONNX graph
   input float[1,24] -> sigmoid(w.x + b) -> float[1,1]   (standardisation folded into w,b)."""
import sys, json, warnings
import numpy as np, pandas as pd
import torch, torch.nn as nn
import onnxruntime as ort
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from ml_common import load, RAW, DIRADJ
warnings.filterwarnings("ignore")
DA = [c for c in RAW if c not in ("EMADiffATR", "ZScore", "HTFTrend", "SMCBias", "RSI", "BBPos", "DonchianPos")] + DIRADJ + ["Dir", "IsTrend"]
CUT = pd.Timestamp(sys.argv[1]) if len(sys.argv) > 1 else None
OUT = sys.argv[2] if len(sys.argv) > 2 else "KNARES_Meta.onnx"
tr, te = load("train"), load("oos")
if CUT is not None:
    tr = tr[tr.ExitTime < CUT - pd.Timedelta(days=1)].reset_index(drop=True)
    te = load("train"); te = te[te.Time >= CUT].reset_index(drop=True)
print("fit rows", len(tr), "| eval rows", len(te))
sc = StandardScaler().fit(tr[DA]); lr = LogisticRegression(C=0.05, max_iter=1000).fit(sc.transform(tr[DA]), tr.Win)
w = lr.coef_[0] / sc.scale_; b = float(lr.intercept_[0] - np.sum(lr.coef_[0] * sc.mean_ / sc.scale_))
class M(nn.Module):
    def __init__(s):
        super().__init__(); s.l = nn.Linear(len(DA), 1)
        with torch.no_grad(): s.l.weight[:] = torch.tensor(w, dtype=torch.float32)[None]; s.l.bias[:] = b
    def forward(s, x): return torch.sigmoid(s.l(x))
m = M().eval()
torch.onnx.export(m, torch.randn(1, len(DA)), OUT, input_names=["input"], output_names=["output"], opset_version=14, dynamo=False)
sess = ort.InferenceSession(OUT)
X = te[DA].values.astype(np.float32)
p_onnx = np.concatenate([sess.run(None, {"input": X[i:i+1]})[0] for i in range(len(X))]).ravel()
p_skl = lr.predict_proba(sc.transform(te[DA]))[:, 1]
print("max |onnx - sklearn| =", float(np.abs(p_onnx - p_skl).max()), "| OOS AUC (onnx)", round(roc_auc_score(te.Win, p_onnx), 4))
print("features (order):", DA)
json.dump({"features": DA, "mean": sc.mean_.tolist(), "scale": sc.scale_.tolist(), "w": w.tolist(), "b": b, "threshold": 0.45,
           "train_range": "2018-01-02..2024-09-17", "n_train": int(len(tr))}, open(OUT.replace(".onnx", ".json"), "w"), indent=1)
print("coef (standardised) top:", sorted(zip(DA, lr.coef_[0].round(3)), key=lambda t: -abs(t[1]))[:8])

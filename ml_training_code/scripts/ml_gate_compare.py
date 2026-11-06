import re, sys, shutil, os
import pandas as pd, numpy as np
sys.path.insert(0, ".")
D = r"C:\Users\Asus\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
def rep(tag):
    s = open(f"{D}\KNARES_{tag}.htm", encoding="utf-16", errors="ignore").read()
    def g(k):
        i = s.find(k); t = re.sub(r"<[^>]+>", " ", s[i:i + 400]); return re.sub(r"\s+", " ", t)
    out = {}
    for k in ("Total Net Profit:", "Profit Factor:", "Sharpe Ratio:", "Total Trades:", "Equity Drawdown Maximal:", "Balance Drawdown Maximal:"):
        out[k] = g(k)[:70]
    return out
for tag in ("sample_oos", "gate_oos"):
    print("==", tag)
    for k, v in rep(tag).items(): print("  ", v)

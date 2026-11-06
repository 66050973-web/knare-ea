"""Shared data loading / feature engineering for the KNARES meta-label model.

Inputs : ml_data/Entry_XAUUSDm_<tag>.csv  (features at entry, written by the EA)
         ml_data/Exit_XAUUSDm_<tag>.csv   (one row per closing deal)
Label  : R = (exit - entry) * dir / |entry - SL|  (price based; RiskMoney is distorted by the 0.01 min lot)
"""
import os
import numpy as np
import pandas as pd

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ml_data")
POINT = 0.001  # XAUUSDm point size

# stationary raw features (no absolute price levels)
RAW = ["ADX", "ADXSlope", "RSI", "ATRx1000", "EMADiffATR", "BBPos", "BBWidthATR", "DonchianPos",
       "DonchianWidthATR", "ZScore", "HTFTrend", "VolRatio", "SLDistATR", "SpreadATR",
       "SMCBias", "SMCZone", "SMCBuyQ", "SMCSellQ", "Score", "Confidence"]
# the same information expressed in the trade direction
DIRADJ = ["EMADiffATR_d", "ZScore_d", "HTFTrend_d", "SMCBias_d", "SMCQ_d", "SMCQ_opp", "RSI_d", "BBPos_d", "DonchianPos_d"]
EXTRA = ["Dir", "IsTrend", "RegimeUp", "RegimeDown", "RegimeRange", "HourSin", "HourCos", "Dow"]


def load(tag):
    e = pd.read_csv(os.path.join(DATA, f"Entry_XAUUSDm_{tag}.csv"))
    x = pd.read_csv(os.path.join(DATA, f"Exit_XAUUSDm_{tag}.csv"))
    e["Time"] = pd.to_datetime(e["Time"])
    x["Time"] = pd.to_datetime(x["Time"])
    g = x.groupby("PosId").agg(ExitPrice=("Price", "last"), Pnl=("Pnl", "sum"), ExitTime=("Time", "last"),
                               CloseReason=("CloseReasonIdx", "last")).reset_index()
    d = e.merge(g, on="PosId", how="inner").sort_values("Time").reset_index(drop=True)
    d["R"] = (d.ExitPrice - d.Entry) * d.Dir / (d.Entry - d.SL).abs()
    d["Win"] = (d.R > 0).astype(int)
    d["HoldMin"] = (d.ExitTime - d.Time).dt.total_seconds() / 60.0
    # features
    d["SpreadATR"] = d.SpreadPts * POINT / d.ATR.replace(0, np.nan)
    d["EMADiffATR_d"] = d.EMADiffATR * d.Dir
    d["ZScore_d"] = d.ZScore * d.Dir
    d["HTFTrend_d"] = d.HTFTrend * d.Dir
    d["SMCBias_d"] = d.SMCBias * d.Dir
    d["SMCQ_d"] = np.where(d.Dir > 0, d.SMCBuyQ, d.SMCSellQ)
    d["SMCQ_opp"] = np.where(d.Dir > 0, d.SMCSellQ, d.SMCBuyQ)
    d["RSI_d"] = (d.RSI - 50.0) * d.Dir
    d["BBPos_d"] = (d.BBPos - 0.5) * d.Dir
    d["DonchianPos_d"] = (d.DonchianPos - 0.5) * d.Dir
    d["IsTrend"] = (d.Engine == "TrendEngine").astype(int)
    d["RegimeUp"] = (d.Regime == 1).astype(int)
    d["RegimeDown"] = (d.Regime == 2).astype(int)
    d["RegimeRange"] = (d.Regime == 3).astype(int)
    hr = d.Time.dt.hour + d.Time.dt.minute / 60.0
    d["HourSin"] = np.sin(2 * np.pi * hr / 24.0)
    d["HourCos"] = np.cos(2 * np.pi * hr / 24.0)
    d["Dow"] = d.Time.dt.dayofweek
    d = d.replace([np.inf, -np.inf], np.nan).dropna(subset=RAW).reset_index(drop=True)
    return d


def folds(d, test_years, embargo_days=1):
    """Expanding-window walk-forward. Training rows whose trade was still open at the test start are purged."""
    out = []
    for y in test_years:
        t0 = pd.Timestamp(f"{y}-01-01")
        t1 = pd.Timestamp(f"{y + 1}-01-01")
        tr = d[(d.ExitTime < t0 - pd.Timedelta(days=embargo_days))]
        te = d[(d.Time >= t0) & (d.Time < t1)]
        if len(tr) > 500 and len(te) > 100:
            out.append((y, tr.index.values, te.index.values))
    return out


PRICE_FEATS = ["r1_d", "r3_d", "r12_d", "r48_d", "r288_d", "RVRatio", "RoomFwd48", "RoomBack48", "Range288ATR",
               "Streak_d", "ATRtoMean"]


def add_price_features(d):
    """Features computed offline from the M5 history strictly BEFORE the entry bar (no look-ahead).
    The EA must reproduce these with iClose/iHigh/iLow at entry time to use them live."""
    src = os.path.join(os.environ["APPDATA"], "MetaQuotes", "Terminal", "Common", "Files", "gs_xau_m5_full.csv")
    c = pd.read_csv(src)
    c["t"] = pd.to_datetime(c.time, unit="s")
    c = c.set_index("t")
    cl, hi, lo = c.close, c.high, c.low
    tr = pd.concat([hi - lo, (hi - cl.shift()).abs(), (lo - cl.shift()).abs()], axis=1).max(axis=1)
    atr = tr.rolling(14).mean()
    lr = np.log(cl / cl.shift())
    F = pd.DataFrame(index=c.index)
    for n in (1, 3, 12, 48, 288):
        F[f"r{n}"] = (cl - cl.shift(n)) / atr
    F["RVRatio"] = lr.rolling(12).std() / lr.rolling(288).std()
    F["hi48"] = (hi.rolling(48).max() - cl) / atr
    F["lo48"] = (cl - lo.rolling(48).min()) / atr
    F["Range288ATR"] = (hi.rolling(288).max() - lo.rolling(288).min()) / atr
    sgn = np.sign(cl.diff()).fillna(0)
    grp = (sgn != sgn.shift()).cumsum()
    F["streak"] = sgn * (sgn.groupby(grp).cumcount() + 1)
    F["ATRtoMean"] = atr / atr.rolling(288).mean()
    # use the last CLOSED bar before the entry bar
    bar = d.Time.dt.floor("5min") - pd.Timedelta(minutes=5)
    G = F.reindex(bar.values)
    G.index = d.index
    dd = d.copy()
    for n in (1, 3, 12, 48, 288):
        dd[f"r{n}_d"] = G[f"r{n}"] * d.Dir
    dd["RVRatio"] = G.RVRatio
    dd["RoomFwd48"] = np.where(d.Dir > 0, G.hi48, G.lo48)
    dd["RoomBack48"] = np.where(d.Dir > 0, G.lo48, G.hi48)
    dd["Range288ATR"] = G.Range288ATR
    dd["Streak_d"] = G.streak * d.Dir
    dd["ATRtoMean"] = G.ATRtoMean
    return dd.replace([np.inf, -np.inf], np.nan)

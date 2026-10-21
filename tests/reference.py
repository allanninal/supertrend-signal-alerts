# SPDX-License-Identifier: MPL-2.0
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not
# distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/
# SuperTrend: method by Olivier Seban; TradingView "SuperTrend" script by KivancOzbilgic.
"""Independent Python reference for SuperTrend Signal Alerts, written from the TradingView Pine script's semantics
(KivancOzbilgic's "SuperTrend"), not translated from the MQL5 code:

    src   = hl2
    atr   = changeATR ? ta.atr(Periods) : ta.sma(ta.tr, Periods)       # ta.tr: first bar = high - low
    up    = src - Multiplier * atr;  up1 = nz(up[1], up)
    up    := close[1] > up1 ? max(up, up1) : up
    dn    = src + Multiplier * atr;  dn1 = nz(dn[1], dn)
    dn    := close[1] < dn1 ? min(dn, dn1) : dn
    trend = nz(trend[1], 1)
    trend := trend == -1 and close > dn1 ? 1 : trend == 1 and close < up1 ? -1 : trend
    line  = trend == 1 ? up : dn
    buy   = trend == 1 and trend[1] == -1;  sell = trend == -1 and trend[1] == 1

ta.atr is Wilder's RMA seeded with the SMA of the first `period` true ranges (as on TradingView).
Additions in the MT5 product: optional EMA trend filter (EMA of the close, SMA-seeded: buy only close > EMA, sell
only close < EMA) and RSI filter (ta.rsi: RMA of gains/losses seeded with the SMA of the first `period` changes;
buy only RSI > 50, sell only RSI < 50)."""
import numpy as np

NAN = np.nan


def above(a, b):
    """Strict a > b ignoring floating-point noise (a band can tie a close exactly in real arithmetic); same as MQL5."""
    return a - b > 1e-10 * abs(b)


def below(a, b):
    return b - a > 1e-10 * abs(b)


def true_range(h, l, c):
    tr = h - l
    tr[1:] = np.maximum(tr[1:], np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
    return tr


def sma(x, n):
    """Plain SMA. Each window is summed left to right (like Pine's ta.sma and the MQL5 loop); a running cumsum
    difference would carry ~1e-13 noise, and SuperTrend compares close against bands that can tie exactly."""
    out = np.full(len(x), NAN)
    for i in range(n - 1, len(x)):
        s = 0.0
        for v in x[i - n + 1:i + 1]:
            s += v
        out[i] = s / n
    return out


def rma(x, n):
    """RMA seeded with the SMA of x[:n]; x may carry leading NaN (then seeded at the first full window)."""
    out = np.full(len(x), NAN)
    first = int(np.argmax(~np.isnan(x))) if (~np.isnan(x)).any() else len(x)
    s = first + n - 1
    if s >= len(x):
        return out
    out[s] = x[first:first + n].mean()
    for i in range(s + 1, len(x)):
        out[i] = (out[i - 1] * (n - 1) + x[i]) / n
    return out


def ema(x, n):
    out = np.full(len(x), NAN)
    if len(x) < n:
        return out
    out[n - 1] = x[:n].mean()
    k = 2.0 / (n + 1)
    for i in range(n, len(x)):
        out[i] = out[i - 1] + k * (x[i] - out[i - 1])
    return out


def rsi(c, n):
    ch = np.concatenate(([NAN], np.diff(c)))
    up, dn = rma(np.where(np.isnan(ch), NAN, np.maximum(ch, 0)), n), rma(np.where(np.isnan(ch), NAN, np.maximum(-ch, 0)), n)
    out = np.full(len(c), NAN)
    for i in range(len(c)):
        if np.isnan(up[i]):
            continue
        out[i] = 100.0 if dn[i] == 0 else 0.0 if up[i] == 0 else 100.0 - 100.0 / (1.0 + up[i] / dn[i])
    return out


def supertrend(o, h, l, c, period=10, mult=3.0, rma_atr=True, use_ema=False, ema_period=200,
               use_rsi=False, rsi_period=14):
    """Returns (line, buy, sell) arrays; buy/sell hold the arrow price (low/high) or NaN.
    The last bar is treated as still forming: no signal on it."""
    n = len(c)
    src = (h + l) / 2.0
    tr = true_range(h, l, c)
    atr = rma(tr, period) if rma_atr else sma(tr, period)
    e, r = ema(c, ema_period), rsi(c, rsi_period)
    up, dn, trend = np.full(n, NAN), np.full(n, NAN), np.full(n, NAN)
    line, buy, sell = np.full(n, NAN), np.full(n, NAN), np.full(n, NAN)
    for i in range(n):
        if np.isnan(atr[i]):
            continue
        u, d = src[i] - mult * atr[i], src[i] + mult * atr[i]
        u1 = up[i - 1] if i > 0 and not np.isnan(up[i - 1]) else u      # nz(up[1], up)
        d1 = dn[i - 1] if i > 0 and not np.isnan(dn[i - 1]) else d
        if i > 0 and above(c[i - 1], u1):
            u = max(u, u1)
        if i > 0 and below(c[i - 1], d1):
            d = min(d, d1)
        t_prev = trend[i - 1] if i > 0 and not np.isnan(trend[i - 1]) else 1.0
        t = t_prev
        if t == -1 and above(c[i], d1):
            t = 1.0
        elif t == 1 and below(c[i], u1):
            t = -1.0
        up[i], dn[i], trend[i] = u, d, t
        line[i] = u if t == 1 else d
        if i == 0 or i == n - 1 or np.isnan(trend[i - 1]):
            continue
        b, s = t == 1 and trend[i - 1] == -1, t == -1 and trend[i - 1] == 1
        if use_ema:
            b = b and not np.isnan(e[i]) and c[i] > e[i]
            s = s and not np.isnan(e[i]) and c[i] < e[i]
        if use_rsi:
            b = b and not np.isnan(r[i]) and r[i] > 50
            s = s and not np.isnan(r[i]) and r[i] < 50
        if b:
            buy[i] = l[i]
        if s:
            sell[i] = h[i]
    return line, buy, sell

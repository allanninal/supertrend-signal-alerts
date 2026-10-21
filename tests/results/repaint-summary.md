# Repaint check results (copied from the run output files of the development repo)

MT5, Strategy Tester every-tick run, EURUSD H1, default inputs (RepaintProbe EA):

| field | value |
|---|---|
| ticks processed | 10,411,052 |
| closed bars checked | 4,644 |
| signals seen when the bar closed | 126 |
| values changed after the close | 0 |
| signals ever shown on the live bar | 0 |

MT4, Strategy Tester (Dump4.mqh + SuperTrendDump.mq4), 37 runs = 4 symbols (EURUSD, XAUUSD, GBPJPY, BTCUSD) x M15/H1/H4 x 3 input sets
(+1 every-tick EURUSD H1 run, 8,417,316 tick events), totals over all 37 runs:

| field | value |
|---|---|
| closed bars checked | 756,852 |
| signals seen when the bar closed | 22,449 |
| mismatches with the final values | 0 |
| signals on the live bar | 0 |
| bars not found again | 0 |

The raw price dumps behind the parity runs are not published (broker price data).

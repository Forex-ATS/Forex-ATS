
# Price Action Breakout Trading System (MT5)

This repository contains an open‑source Expert Advisor (EA) for MetaTrader 5 implementing a simple yet robust price‑action breakout strategy. The system looks for the close of the last completed **H1** candle to break above (or below) the highs (or lows) of the two preceding candles and aligns trades with the dominant **Daily (D1)** and **4‑hour (H4)** trends.  

## How It Works

* **Signal Generation**: At the open of each new H1 bar, the EA checks the last closed candle (signal candle). If its closing price has broken above the highs (or below the lows) of the previous two candles, it generates a long (or short) signal.  
* **Trend Filter**: Trades are taken only when both the D1 and H4 timeframes agree with the signal direction (e.g. both bullish for longs).  
* **Range Filter**: The EA measures the range of the signal candle (High–Low) and compares it to the median range of the 20 prior candles. A trade is taken only if the signal candle’s range is at least `1.5×` the median range.  
* **Risk Management**: Risk per trade is fixed at **1 %** of account balance. A stop‑loss is placed below (or above) the signal candle’s low (or high) with a 5‑pip buffer, and the take‑profit is set at **1.3×** the stop‑loss distance.  
* **Trading Session**: The EA operates from **06:00** to **19:00** server time, Monday through Thursday. Trading on Fridays is disabled by default. Only one position can be open at a time.

## Performance Summary

The EA was backtested on **EUR/USD H1** data from **10 August 2020** to **8 August 2025** with the above parameters:

| Metric                | Value         |
|-----------------------|--------------:|
| Initial balance       | 10 000 units  |
| Final balance         | ~33 616 units |
| Total trades          | 782           |
| Winning trades        | 395 (≈50.5 %) |
| Losing trades         | 387           |
| Average monthly return| ≈3.9 %        |
| Max trades per day    | <1 trade/day  |

> **Disclaimer**: These results are based on historical data and do not guarantee future performance. Always test on a demo account before trading live.

## Files

* **PA_Break2_Optimized_1pct.mq5** – The Expert Advisor source code written in MQL5.  
* **README.md** – This documentation file.  
* **LICENSE** – MIT License.

## Usage

1. Copy `PA_Break2_Optimized_1pct.mq5` into your MetaTrader 5 `Experts` folder.  
2. Compile the file using MetaEditor.  
3. Attach the expert to an H1 chart of the desired symbol (EUR/USD recommended).  
4. Adjust input parameters as desired.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

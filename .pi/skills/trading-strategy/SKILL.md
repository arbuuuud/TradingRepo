---
name: trading-strategy
description: Architectural guidelines and signal patterns for MQL5 Expert Advisors. Covers modular signal engines, multi-timeframe analysis, session filters, trailing stops, and backtesting considerations.
---

# Trading Strategy Architecture in MQL5

## 1. Modular Strategy Pattern

Separate strategy logic into dedicated layers:
1. **Signal Engine (`SignalEngine.mqh`)**: Evaluates market conditions and emits signals (`SIGNAL_BUY`, `SIGNAL_SELL`, `SIGNAL_NONE`).
2. **Risk Manager (`RiskManager.mqh`)**: Dictates volume, stop loss distance, and account safety filters.
3. **Execution Layer (`TradeExecution.mqh`)**: Translates signals and volume into MT5 order tickets.
4. **EA Main (`MyEA.mq5`)**: Glues all components together inside `OnInit()`, `OnTick()`, and `OnDeinit()`.

## 2. Common Signal Patterns

### Trend Following (Moving Average Cross + Filter)
- Entry Buy: Fast EMA crosses above Slow EMA AND Trend Filter (e.g. 200 EMA or RSI > 50).
- Entry Sell: Fast EMA crosses below Slow EMA AND Trend Filter.

### Mean Reversion / Oversold-Overbought
- Entry Buy: Price touches Lower Bollinger Band OR RSI < 30, with rejection candlestick.
- Entry Sell: Price touches Upper Bollinger Band OR RSI > 70, with rejection candlestick.

### Breakout Strategy
- Break of London session high/low or Donchian Channel.
- Volume confirmation using Tick Volume or ATR expansion.

## 3. Session / Time Filtering

Forex and Gold volatility varies by market session:
- **Asian Session (Tokyo):** 00:00 - 08:00 UTC (Lower volatility, ranging).
- **London Session:** 07:00 - 15:00 UTC (Trend breakouts, highest volume).
- **New York Session:** 12:00 - 20:00 UTC (High momentum, US news releases).

Code sample:
```cpp
bool IsTradingTimeAllowed(int startHour, int endHour)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= startHour && dt.hour < endHour);
}
```

## 4. Backtesting & Optimization Rules
1. **Always use "Every tick based on real ticks"** in Strategy Tester for accurate slippage and spread simulation.
2. **Do not overfit:** Avoid tuning 20 parameters to match a single historical month. Keep core strategy parameters to 3 - 5 variables max.
3. **Forward Testing:** Test on out-of-sample data (e.g. optimize on 2023-2024, test on 2025).

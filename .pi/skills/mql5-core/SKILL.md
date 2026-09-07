---
name: mql5-core
description: Technical reference for MQL5 programming on MetaTrader 5. Covers lifecycle (OnInit, OnTick, OnDeinit), CTrade standard library, indicator handles, buffer copying, error codes, and compile workflows.
---

# MQL5 Core — Technical Reference

## 1. MQL5 Program Lifecycle

Every Expert Advisor (EA) follows three essential event handlers:

```cpp
int OnInit()
{
   // 1. Validate user inputs
   // 2. Initialize modules (Risk, Trade, Signal)
   // 3. Create indicator handles (iMA, iRSI, iATR)
   // Return INIT_SUCCEEDED or INIT_PARAMETERS_INCORRECT or INIT_FAILED
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   // Release indicator handles via IndicatorRelease()
   // Remove visual chart objects (ObjectDelete)
}

void OnTick()
{
   // Main event triggered on every price movement
   // Best Practice: Check if new bar has completed before calculating signals
}
```

## 2. Standard Trade Execution with `CTrade`

Do NOT use low-level `OrderSend` directly when developing MQL5 EAs. Always use MetaTrader's official `CTrade` class:

```cpp
#include <Trade\Trade.mqh>

CTrade trade;

// Initialize in OnInit
trade.SetExpertMagicNumber(123456);
trade.SetDeviationInPoints(10);
trade.SetTypeFillingBySymbol(_Symbol);

// Buying
trade.Buy(lotSize, _Symbol, askPrice, stopLossPrice, takeProfitPrice, "EA Comment");

// Selling
trade.Sell(lotSize, _Symbol, bidPrice, stopLossPrice, takeProfitPrice, "EA Comment");
```

## 3. Working with Indicators & Buffers

In MQL5, indicators are created as integer **handles** in `OnInit()` and read using `CopyBuffer()` in `OnTick()`:

```cpp
// 1. Create Handle in OnInit
int maHandle = iMA(_Symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
if(maHandle == INVALID_HANDLE)
{
   Print("Failed to create MA handle: ", GetLastError());
   return INIT_FAILED;
}

// 2. Read values in OnTick (Index 1 = bar just closed, non-repainting)
double buffer[2];
if(CopyBuffer(maHandle, 0, 1, 2, buffer) < 2)
{
   return; // Not enough history
}

// buffer[0] = Bar 2 value, buffer[1] = Bar 1 value

// 3. Cleanup in OnDeinit
IndicatorRelease(maHandle);
```

## 4. Avoiding Intra-Bar False Signals (Repainting)

A common mistake is reading bar 0 (the currently moving bar). High volatility can trigger signals that disappear before candle close.
Always check for a **New Bar**:

```cpp
bool IsNewBar(string symbol, ENUM_TIMEFRAMES timeframe)
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(symbol, timeframe, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}
```

## 5. Price Normalization & Digits

Never pass unnormalized double prices to trade functions:
```cpp
int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
double normPrice = NormalizeDouble(price, digits);
```

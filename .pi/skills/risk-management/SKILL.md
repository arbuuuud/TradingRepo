---
name: risk-management
description: Risk management principles and algorithms for algorithmic trading in MQL5. Covers dynamic lot sizing (% risk vs stop loss), spread filters, maximum daily drawdown protection, and asset class tick differences (Forex, Gold/XAUUSD, Indices).
---

# Algorithmic Risk Management in MQL5

## 1. Dynamic Lot Sizing Formula

Fixed lot size (e.g. 0.01) does not protect accounts during drawdowns or scale profits as the account grows. The standard institutional approach is **Risk Percentage per Trade**:

$$Lot = \frac{AccountEquity \times Risk\%}{PointsAtRisk \times ValuePerPoint}$$

### MQL5 Calculation Code:
```cpp
double CalculateLotSize(string symbol, double riskPercent, double stopLossPoints)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (riskPercent / 100.0);

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickSize <= 0 || tickValue <= 0 || point <= 0 || stopLossPoints <= 0)
      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double pointsPerTick = tickSize / point;
   double ticksRisked   = stopLossPoints / pointsPerTick;
   double lossPerLot    = ticksRisked * tickValue;

   if(lossPerLot <= 0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double calculatedLot = riskMoney / lossPerLot;

   // Clamp and normalize to broker step
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double normalized = MathFloor(calculatedLot / lotStep) * lotStep;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;

   return normalized;
}
```

## 2. Spread Filter Protection

Broker spreads widen significantly during news events (NFP, CPI, FOMC) and daily rollover (00:00 server time). Opening trades during wide spreads causes immediate slippage loss.

```cpp
bool IsSpreadSafe(string symbol, int maxSpreadPoints)
{
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (spread <= maxSpreadPoints);
}
```

## 3. Daily Maximum Drawdown Protection

Prop firms (FTMO, FundedNext, etc.) and smart capital management require a strict daily loss limit (usually 3% to 5%). If the loss limit is reached, all positions must close and no new trades can open until the next day.

- Track starting equity at `00:00` server time.
- Calculate current equity drawdown: `((startEquity - currentEquity) / startEquity) * 100`.
- If drawdown >= limit, halt execution.

## 4. Minimum Stop Distance (`SYMBOL_TRADE_STOPS_LEVEL`)

Brokers define a minimum distance between market price and StopLoss/TakeProfit:
```cpp
long stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
if(stopLossPoints < stopsLevel)
{
   Print("Warning: Stop loss is closer than broker minimum stops level: ", stopsLevel);
}
```

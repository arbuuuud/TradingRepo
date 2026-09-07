---
name: mql5-trade-manager
description: Architectural guidelines for trade lifecycle management in MQL5. Covers division of work between OnTick vs OnTimer, dynamic lot sizing (% risk vs entry-to-SL distance), multi-stage partial TP (TP1-TP5), Breakeven/SafeMode, and Force Exit mechanisms (EOD 23:55, Session close, Max Drawdown).
---

# MQL5 Trade Lifecycle & Smart Management

## 1. Work Distribution: `OnTick()` vs `OnTimer()`

To maintain optimal execution speed without latency or UI freezing in MetaTrader 5 on Wine:

### A. `OnTick()` Responsibilities (Ultra-Light, Real-Time Only)
Executed on every micro-movement of price:
1. **Spread Gate**: Reject entry if current spread exceeds `InpMaxSpreadPoints`.
2. **Equity Kill Switch**: If current floating equity breaches `InpMaxDailyLossPct`, close all and halt.
3. **Smart SL & Trailing Trajectory**:
   - Check if price moved $\ge$ TP1 distance ➡️ activate **Safe Mode / Move SL to BE + Buffer**.
   - Check pending TP limit orders or trailing steps.
4. **Trigger Signal Check**: Check if LTF trigger condition (e.g. M1) is met to enter market.

### B. `OnTimer()` Responsibilities (Periodic Housekeeping, e.g. 1s - 10s)
Executed periodically independent of incoming ticks:
1. **Market Session Detection**: Convert GMT time to identify Active Sessions (Asian `00:00-09:00`, London `08:00-16:00`, New York `13:00-21:00`).
2. **End-of-Day (EOD) Force Exit**: At `23:55` GMT, close all positions and cancel all pending orders before daily broker rollover and spread spike.
3. **Chart Visual Cleanup**: Delete expired swing rectangles, lines, and text objects.
4. **Broker Server Sync**: Reconcile internal position arrays with official broker tickets.

---

## 2. Dynamic Lot Sizing (Entry-to-SL Distance)

Every trade volume must be dynamically calculated based on the precise distance between the Entry Price and the Stop Loss level:

$$RiskMoney = Equity \times \frac{Risk\%}{100}$$

$$DistanceInPoints = \frac{|EntryPrice - StopLossPrice|}{Point}$$

$$LossPerLot = \frac{DistanceInPoints \times TickValue}{PointsPerTick}$$

$$CalculatedLot = \frac{RiskMoney}{LossPerLot}$$

### Code Pattern:
```cpp
double CalculateLotFromSL(string symbol, double entryPrice, double slPrice, double riskPercent)
{
   if(entryPrice == slPrice || riskPercent <= 0) 
      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPercent / 100.0);

   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(point <= 0 || tickValue <= 0 || tickSize <= 0) 
      return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double distPoints   = MathAbs(entryPrice - slPrice) / point;
   double pointsPerTick = tickSize / point;
   double lossPerLot   = (distPoints / pointsPerTick) * tickValue;

   if(lossPerLot <= 0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double rawLot   = riskAmount / lossPerLot;
   double minLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double stepLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double normalized = MathFloor(rawLot / stepLot) * stepLot;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;

   return normalized;
}
```

---

## 3. Multi-Tier Target & Partial Exits (TP1 - TP5)

To lock in profits along trend legs while allowing runners:
- **TP1 (e.g. 1R or 1.0 distance)**: Close 20% - 30% volume & move SL to Entry + SpreadBuffer (**Breakeven / Safe Mode**).
- **TP2 (e.g. 2R)**: Close additional partial volume.
- **TP3 / TP4 / TP5**: Trailing stop runner towards HTF Liquidity / Opposite Main Swing.

---

## 4. Force Exit Conditions
A position must be forcefully exited (market close) under any of these triggers:
1. **EOD Rollover Guard**: GMT time is `23:55`.
2. **Structure Invalidation**: A confirmed opposing Main Structure Break occurs (e.g., in a Buy position, HTF/MTF forms a confirmed CHoCH to Bearish).
3. **Maximum Daily Drawdown Breached**: Total floating + realized loss for the day reaches the cap.

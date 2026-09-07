---
name: mql5-mtf-structure
description: Standards and technical guidelines for Multi-Timeframe (MTF) Market Structure in MQL5. Covers 3-tier MTF hierarchy (HTF Bias, Base Setup, LTF Trigger), Main vs Internal Structure (HH, HL, LH, LL), TF whitelisting, and event-driven candle close optimization.
---

# MQL5 Multi-Timeframe (MTF) Market Structure

## 1. 3-Tier Multi-Timeframe Hierarchy

Trading strategies must not mix timeframes arbitrarily. Every MTF strategy must map its timeframes into a clear 3-tier matrix:

| Tier | Role | Example (M3 Entry Strategy) | Event Trigger | Output / Responsibility |
|---|---|---|---|---|
| **Tier 1: Macro Bias (HTF)** | Directional Filter | **H1 + M15** | Closed H1 / M15 Bar | Trend state: `TREND_BULL`, `TREND_BEAR`, or `TREND_NONE` |
| **Tier 2: Setup Base (MTF)** | Swing Structure & POI | **M3** | Closed M3 Bar | Main HH/HL/LH/LL, Equilibrium (Premium/Discount), POI (OB/FVG) |
| **Tier 3: Execution Trigger (LTF)** | Precision Entry & Min SL | **M1** | Closed M1 Bar / Real-time | Candle pattern (rejection, engulfing), Liquidity sweep, or LTF CHoCH |

### Core Rule of Alignment:
No trade may open unless the 3 tiers align:
$$\text{Macro Bias (Tier 1)} == \text{Setup Direction (Tier 2)} == \text{Trigger Signal (Tier 3)}$$

---

## 2. Main Structure vs Internal Structure

### A. Main Structure (Macro Swings)
- **Definition**: The validated primary swing highs and swing lows of the timeframe.
- **Validation Criteria**:
  - A swing is **only confirmed** when the opposing swing is broken by a **Candle Body Close** (Break of Structure / BOS or Change of Character / CHoCH).
  - A wick sweep that closes back inside does NOT confirm a new main swing — it is classified as a **Liquidity Sweep**.
- **Labels**: `HH` (Higher High), `HL` (Higher Low), `LH` (Lower High), `LL` (Lower Low).

### B. Internal Structure (Sub-Structure / Pullback)
- **Definition**: Any swings occurring *inside* the range between the most recent Main High and Main Low.
- **Role**: Captures retracements, equilibrium pullbacks, and counter-trend movements without invalidating the Main Structure.
- **Rule**: Internal structure breaks do not change the Macro Trend; they only indicate the start or end of a pullback.

---

## 3. Performance Rule: Event-Driven Candle Close (`IsNewBar`)

**CRITICAL PERFORMANCE RULE:**  
Never loop or recalculate multi-timeframe candle rates on every `OnTick()`. Doing so causes severe CPU spikes and freezes in MT5 Wine.

### Correct Pattern:
```cpp
// Check new bar per timeframe
bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES period)
{
   static datetime lastTimes[10]; // indexed by timeframe map
   datetime currentTime = iTime(symbol, period, 0);
   if(currentTime != lastTimes[idx])
   {
      lastTimes[idx] = currentTime;
      return true; // New bar just formed!
   }
   return false;
}

// In OnTick():
if(IsNewBar(_Symbol, PERIOD_H1))
   UpdateStructure(PERIOD_H1);

if(IsNewBar(_Symbol, PERIOD_M15))
   UpdateStructure(PERIOD_M15);

if(IsNewBar(_Symbol, PERIOD_M3))
   UpdateStructure(PERIOD_M3);
```

---

## 4. Timeframe Whitelisting (Selective Subscriptions)

Never process all 8 timeframes by default. The strategy must register only the timeframes it uses:
```cpp
StructureManager.RegisterTimeframe(PERIOD_H1,  ROLE_HTF_BIAS);
StructureManager.RegisterTimeframe(PERIOD_M15, ROLE_HTF_BIAS);
StructureManager.RegisterTimeframe(PERIOD_M3,  ROLE_SETUP_BASE);
StructureManager.RegisterTimeframe(PERIOD_M1,  ROLE_LTF_TRIGGER);
```
Unregistered timeframes must consume 0 CPU and 0 buffer memory.

---

## 5. Strict Struct Definitions
All structure structs must follow strict MQL5 standards:
- Always terminate with `;` after `}`.
- Always include an `Init()` reset function.
- Array members must be manipulated with `ArrayResize()` and passed by reference `&`.

```cpp
struct STFStructure
{
   string            label;        // "HH", "HL", "LH", "LL"
   datetime          candleTime;   // Exact swing time
   double            priceH;       // High price
   double            priceL;       // Low price
   bool              isLiquidated; // True if swept
   bool              isMain;       // True = Main Structure, False = Internal

   void Init()
   {
      label        = "";
      candleTime   = 0;
      priceH       = 0.0;
      priceL       = 0.0;
      isLiquidated = false;
      isMain       = false;
   }
};
```

---
name: mql5-tester-analytics
description: Technical reference for empirical Strategy Tester data analysis in MQL5. Covers TSV file parsing, location of MT5 Common Files in Wine on macOS, 20-column data schema, mathematical formulas for DNA pillar metrics, combinatorial synergy evaluation, and reporting conventions.
---

# MQL5 Strategy Tester TSV Analytics Reference Guide

This skill provides domain knowledge and technical procedures for analyzing Strategy Tester trade exports produced by `TradeDataLogger.mqh`.

---

## 1. File Locations & Environment (Wine on macOS)

When `TradeDataLogger.mqh` runs inside MetaTrader 5 under Wine, files opened with `FILE_COMMON` are stored in:
```bash
/Users/alami/mt5prefix/drive_c/users/alami/AppData/Roaming/MetaQuotes/Terminal/Common/Files/
```
File naming convention:
```
rbr_dbd_analytics_<SYMBOL>_<TIMEFRAME>_<YYYYMMDD_HHMMSS>.tsv
```
Example:
```
rbr_dbd_analytics_XAUUSD_PERIOD_M1_20250410_164500.tsv
```

---

## 2. 20-Column TSV Data Schema

| Index | Column Header | Type | Description / Accepted Values |
|:---:|---|:---:|---|
| 0 | `DealTicket` | ulong | Unique closing deal ticket identifier |
| 1 | `PosID` | ulong | Position ID uniting entry and exit deals |
| 2 | `Symbol` | string | Instrument (e.g. `XAUUSD`) |
| 3 | `TradeType` | string | `BUY` or `SELL` (original position side) |
| 4 | `ZoneType` | string | `RBR` (Demand) or `DBD` (Supply) |
| 5 | `ZoneTF` | string | Origin timeframe (`M1`, `M5`, `M15`, etc.) |
| 6 | `DNA` | string | 4-character flag (e.g. `TBFH`, `TB--`, `----`) |
| 7 | `Pillar_T` | int | 1 = Passed Tightness, 0 = Failed |
| 8 | `Pillar_B` | int | 1 = Passed BOS Body Close, 0 = Failed |
| 9 | `Pillar_F` | int | 1 = Passed Direct Attached FVG, 0 = Failed |
| 10 | `Pillar_H` | int | 1 = Passed HTF Parent Reaction, 0 = Failed |
| 11 | `Strength` | int | 0 = Weak (0-1★), 1 = Moderate (2★), 2 = Master (3-4★) |
| 12 | `ExhLevel` | int | Exhaustion level when order placed (0 to 5) |
| 13 | `OpenTime` | datetime | YYYY.MM.DD HH:MM:SS |
| 14 | `CloseTime` | datetime | YYYY.MM.DD HH:MM:SS |
| 15 | `OpenPrice` | double | Initial executed entry price |
| 16 | `ClosePrice` | double | Position closing price |
| 17 | `ProfitUSD` | double | Net profit in account currency (inc. comm & swap) |
| 18 | `ProfitPoints` | double | Net gain / loss in points |
| 19 | `ExitReason` | string | `FULL_TP`, `BREAK_EVEN`, `CUT_PROFIT`, `HARD_SL`, `FORCE_EXIT` |
| 20 | `Comment` | string | Raw original comment (e.g. `RBR:M1:TBFH:S2:L0`) |

---

## 3. Core Quantitative Formulas

### 1. Win Rate ($WR$)
$$WR = \frac{\text{Count}(\text{ProfitUSD} > 0)}{\text{Total Closed Trades}} \times 100\%$$

### 2. Profit Factor ($PF$)
$$PF = \frac{\sum \text{Gross Profits}}{\sum |\text{Gross Losses}|}$$

### 3. Trade Expectancy ($E$)
$$E = (P_{win} \times \text{AvgWinUSD}) - (P_{loss} \times \text{AvgLossUSD})$$

### 4. Break-Even Rate ($BER$)
$$BER = \frac{\text{Count}(\text{ExitReason} == \text{"BREAK\_EVEN"})}{\text{Total Closed Trades}} \times 100\%$$

### 5. Cut-Profit Evacuation Efficiency ($CPE$)
$$CPE = \frac{\text{Count}(\text{ExitReason} == \text{"CUT\_PROFIT"})}{\text{Total Closed Trades}} \times 100\%$$

---

## 4. Think-in-Code Analysis Workflow

To maintain context efficiency, do **NOT** load raw TSV files into LLM conversation tokens.
Instead, use the CLI analytics runner:
```bash
node scripts/analyze-tester-results.js [path/to/file.tsv]
```
The script outputs:
1. High-level summary (Total Trades, Net PnL, Win Rate, Profit Factor).
2. Performance ranked by Strength (Strength 0 vs 1 vs 2).
3. Individual pillar impact ($T$, $B$, $F$, $H$).
4. Complete 16-combination DNA ranking ($2^4 = 16$ setups).
5. Exhaustion level decay curve (L0 Fresh $\rightarrow$ L4 Critical).

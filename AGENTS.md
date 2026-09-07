# TradingRepo — Expert Advisor (MT5) Agent Guide

> **Project:** MetaTrader 5 Expert Advisor Development (MQL5)  
> **Host Environment:** macOS + Wine (Prefix: `~/mt5prefix`)  
> **Compiler:** MetaEditor 64-bit via Wine CLI & GUI  

---

## 📊 Ringkasan Project

| Folder / File | Deskripsi | Target di Wine MT5 |
|---|---|---|
| `experts/` | Berisi file utama EA (`.mq5`) | Symlinked ke `MQL5/Experts/TradingRepo` |
| `include/MTFStructure/` | Core Multi-Timeframe Structure Engine | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/TradeManager/` | Smart SL/TP, BE, EOD 23:55 Force Exit | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/Strategy/` | Pluggable Strategy Entry Engines (Base + M3 SMC, etc.) | Symlinked ke `MQL5/Include/TradingRepo` |
| `scripts/` | Script otomasi symlink & kompilasi Wine | - |
| `.pi/` | Definisi Subagents & Skills | - |

---

## 🧠 Subagents & Skills (Project-Scoped)

### Subagents (`/run`)

| Agent | Peran | Cara Pakai |
|---|---|---|
| `ea-architect` | Merancang konsep strategi 3-tier MTF, parameter input, dan model risk management | `/run ea-architect "Rancang strategi Scalping M1 dengan HTF Bias H1/M15"` |
| `dev-mql5` | Menulis/mengedit kode MQL5 modular, optimasi OnCandleClose vs OnTick/OnTimer | `/run dev-mql5 "Implementasikan M15 Breakout Engine ke MTFStructureEA"` |
| `ea-reviewer` | Mengaudit kode untuk memory leak, CPU load MTF, validasi broker & SL/BE logic | `/run ea-reviewer "Audit MTFStructureEA.mq5 untuk kesiapan live"` |

### Skills (Technical Reference)

| Skill | Topik | Path |
|---|---|---|
| `mql5-mtf-structure` | 3-tier MTF hierarchy, Main vs Internal HH/HL, TF whitelist, Candle Close events | `.pi/skills/mql5-mtf-structure/SKILL.md` |
| `mql5-trade-manager` | OnTick vs OnTimer division, Dynamic Lot (% risk vs entry-SL), BE, EOD 23:55 exit | `.pi/skills/mql5-trade-manager/SKILL.md` |
| `mql5-core` | MQL5 lifecycle, CTrade library, indicator handle, strict syntax rules | `.pi/skills/mql5-core/SKILL.md` |
| `risk-management` | Kalkulasi lot dinamis (% risk), drawdown harian, spread filter | `.pi/skills/risk-management/SKILL.md` |
| `trading-strategy` | Pola signal non-repainting, session filter, multi-timeframe | `.pi/skills/trading-strategy/SKILL.md` |

---

## 📋 Standard Workflow

```
[ Ide Trading ]
       │
       ▼
1. ea-architect   ──► Merancang arsitektur input, rules entry/exit, dan risk model
       │
       ▼
2. dev-mql5       ──► Menulis kode di include/*.mqh dan experts/*.mq5
       │          ──► Menjalankan ./scripts/compile.sh experts/<EA>.mq5
       ▼
3. ea-reviewer    ──► Audit memory leak, order safety, dan edge cases
       │
       ▼
4. MetaTrader 5   ──► Backtest di Strategy Tester (Ctrl+R) & Visual Mode di Wine
```

---

## 🛠️ CLI Quick Commands

### 1. Hubungkan Symlink ke MT5 Wine
```bash
./scripts/setup-symlink.sh
```

### 2. Kompilasi EA Tanpa Buka MetaEditor (Headless CLI)
```bash
./scripts/compile.sh experts/StarterEA.mq5
```
Binary `.ex5` otomatis tercipta dan langsung terbaca oleh MT5!

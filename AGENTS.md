# TradingRepo — Expert Advisor (MT5) Agent Guide

> **Project:** MetaTrader 5 Expert Advisor Development (MQL5)  
> **Host Environment:** macOS + Wine (Prefix: `~/mt5prefix`)  
> **Compiler:** MetaEditor 64-bit via Wine CLI & GUI  

---

## 📊 Ringkasan Project

| Folder / File | Deskripsi | Target di Wine MT5 |
|---|---|---|
| `experts/` | Berisi file utama EA (`.mq5`) | Symlinked ke `MQL5/Experts/TradingRepo` |
| `include/` | Reusable modules (`.mqh`) | Symlinked ke `MQL5/Include/TradingRepo` |
| `scripts/` | Script otomasi symlink & kompilasi Wine | - |
| `.pi/` | Definisi Subagents & Skills | - |

---

## 🧠 Subagents & Skills (Project-Scoped)

### Subagents (`/run`)

| Agent | Peran | Cara Pakai |
|---|---|---|
| `ea-architect` | Merancang konsep strategi, parameter input, dan model risk management | `/run ea-architect "Rancang strategi Scalping Gold M5 dengan EMA & ATR"` |
| `dev-mql5` | Menulis/mengedit kode MQL5 modular dan memastikan compile 0 error | `/run dev-mql5 "Implementasikan Trailing Stop ATR pada StarterEA"` |
| `ea-reviewer` | Mengaudit kode untuk memory leak, slippage, margin protection, dan validasi broker | `/run ea-reviewer "Audit StarterEA.mq5 untuk kesiapan live trading"` |

### Skills (Technical Reference)

| Skill | Topik | Path |
|---|---|---|
| `mql5-core` | MQL5 lifecycle, CTrade library, indicator handle, buffer copy | `.pi/skills/mql5-core/SKILL.md` |
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

# TradingRepo — Expert Advisor (MT5) Agent Guide

> **Project:** MetaTrader 5 Expert Advisor Development (MQL5)  
> **Host Environment:** macOS + Wine (Prefix: `~/mt5prefix`)  
> **Compiler:** MetaEditor 64-bit via Wine CLI & GUI  

---

## 📊 Ringkasan Project & Dokumen Acuan

| Folder / File | Deskripsi | Target di Wine MT5 |
|---|---|---|
| `experts/` | Berisi file utama EA (`.mq5`) | Symlinked ke `MQL5/Experts/TradingRepo` |
| `include/arbud/structure/` | Core Engine RBR/DBD & LivingTradingArea | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/arbud/trade/` | Limit Placer, Loss Prevention, & TSV Logger | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/MTFStructure/` | Core Multi-Timeframe Structure Engine | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/TradeManager/` | Smart SL/TP, BE, EOD 23:55 Force Exit | Symlinked ke `MQL5/Include/TradingRepo` |
| `include/Strategy/` | Pluggable Strategy Entry Engines (Base + M3 SMC, etc.) | Symlinked ke `MQL5/Include/TradingRepo` |
| `scripts/` | Script otomasi symlink, kompilasi Wine, & TSV analytics | - |
| `.pi/` | Definisi Subagents & Skills | - |
| `docs/rbr-dbd-implementation-plan-and-test-matrix.md` | **Master Roadmap & Status Tracking Phase 1 - 7** | - |
| `docs/rbr-dbd-high-probability-generator-spec.md` | Spesifikasi 4 Pilar RBR/DBD (T-B-F-H DNA) | - |
| `docs/strategy-tester-tsv-analytics-guide.md` | Panduan AI Operator untuk Analisis Strategy Tester TSV | - |

---

## 🚦 Status Fase Kerja Saat Ini (Active Phase Tracking)

> **Posisi Saat Ini:** **PHASE 7: Strategy Tester TSV Analytics & RBR/DBD DNA Probability Engine**  
> **Branch Git Aktif:** `feat/phase7-strategy-tester-tsv-analytics`  
> **Langkah Aktif (Current Step):** **Step 4 — Subagent (`ea-data-scientist`) & Skill Analytics (`mql5-tester-analytics`)**

### Ringkasan Status Phase:
- ✅ **Phase 1**: M1 Memory Pool, Dynamic GC, & Recursive MTF Base Scanner (Selesai)
- ✅ **Phase 2**: 4 Pilar Kualitas RBR/DBD (`TBFH` DNA, Star Scoring 0-4★, Strength 0/1/2) (Selesai)
- ✅ **Phase 3**: Dynamic Buffer Calculation (`min(10-Swing, 2x Base)`) (Selesai)
- ✅ **Phase 4**: `LivingTradingArea.mqh` (3-Cascade Fallback, 6-Stage L0-L5 Exhaustion, Adaptive M5 Swing) (Selesai)
- ✅ **Phase 5**: `ProactiveLimitPlacer.mqh` (Virgin Depth Mapping, Anchor Orders, Dynamic Capacity) (Selesai)
- ✅ **Phase 6**: Proactive Loss Prevention (Clash of Strength, BE+ Evacuation, Unified Weighted Batch Exit) (Selesai)
- 🟡 **Phase 7**: **Strategy Tester TSV Analytics & RBR/DBD DNA Probability Engine** (SEDANG BERJALAN)
  - [x] Step 1: Dokumentasi & Blueprint Arsitektur (`docs/strategy-tester-tsv-analytics-guide.md`)
  - [x] Step 2: Switch Input & Penurunan Filter Strength 0 (`InpAllowStrength0`)
  - [x] Step 3: Modul Logger TSV MQL5 (`TradeDataLogger.mqh`)
  - [ ] Step 4: Subagent (`ea-data-scientist`) & Skill Analytics (`mql5-tester-analytics`)
  - [ ] Step 5: Skrip CLI Node.js/Bun Think-in-Code Analyzer (`scripts/analyze-tester-results.js`)
  - [ ] Step 6: Uji Coba Strategy Tester & Review Data Pertama

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

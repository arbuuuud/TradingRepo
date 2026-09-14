# Strategy Tester TSV Analytics & RBR/DBD DNA Probability Engine

> **Document Version:** 1.0.0  
> **Status:** Active Development (Step-by-Step)  
> **Target Asset:** XAUUSD (Gold) / Multi-Asset  
> **Objective:** Merekam setiap eksekusi trade ke format TSV terstruktur, mengekstrak data probabilitas dari 4 Pilar RBR/DBD (T-B-F-H), membandingkan performa kombinasi (single, pair, trio, quad vs control baseline 0★), dan menyediakan panduan permanen bagi AI berikutnya pasca-compaction.

---

## 🎯 1. Latar Belakang & Tujuan (Goals)

Untuk menentukan kualitas pembentukan zona Supply & Demand (RBR / DBD) yang paling akurat secara statistik di MetaTrader 5 Strategy Tester, sistem membutuhkan mekanisme pencatatan data objektif tanpa bias (*unbiased data collection*).

### 4 Pilar Kualitas RBR / DBD yang Diuji (DNA Code: `TBFH`):
1. **`T` (Base Tightness & MTF Reflection)**: Base kompak ($\le 0.80\times$ Leg-Out) dan tercermin rapi di ladder MTF.
2. **`B` (BOS Body Close)**: Candle Leg-Out menembus dan menutup body candle di atas swing high (RBR) atau di bawah swing low (DBD) pada timeframe asal.
3. **`F` (Direct Attached FVG)**: Terdapat Fair Value Gap valid langsung menempel pada candle Leg-Out.
4. **`H` (HTF POI Reaction)**: Base bertumpu pada HTF RBR/DBD parent zone atau HTF structural swing high/low.

### Target Evaluasi Hasil Trade:
- 🟢 **Bagus (Win / Full TP)**: Trade mencapai target Hard TP 50% atau take profit penuh.
- 🟡 **Sedang (Break Even / Cut Profit / Evakuasi)**: Trade ditutup pada saat transisi corridor baru, Clash of Strength, atau BE+ spread buffer dengan net profit $\ge 0$.
- 🔴 **Jelek (Loss / Hard SL)**: Trade menyentuh Hard SL (-30% / +130% atau fallback breathing room SL).

---

## 🗺️ 2. Roadmap Implementasi Bertahap (Step-by-Step)

| Step | Deskripsi | Status | Output / File |
|:---:|---|:---:|---|
| **Step 1** | **Dokumentasi & Blueprint Arsitektur** | 🟢 Selesai | `docs/strategy-tester-tsv-analytics-guide.md` |
| **Step 2** | **Switch Input & Penurunan Filter Strength 0** | 🟢 Selesai | `experts/rbrdbdV1Sample.mq5`, `rbrdbdV1.mqh`, `LivingTradingArea.mqh`, `ProactiveLimitPlacer.mqh` |
| **Step 3** | **Modul Logger TSV MQL5 (`TradeDataLogger.mqh`)** | 🟢 Selesai | `include/arbud/trade/TradeDataLogger.mqh` |
| **Step 4** | **Subagent & Skill Analytics Permanen** | 🟢 Selesai | `.pi/agents/ea-data-scientist.md`, `.pi/skills/mql5-tester-analytics/SKILL.md` |
| **Step 5** | **Skrip CLI Node.js/Bun Think-in-Code Analyzer** | 🟢 Selesai | `scripts/analyze-tester-results.js` |
| **Step 6** | **Uji Coba Strategy Tester & Review Data Pertama** | 🟡 Siap Uji Coba | Laporan Analisis Probabilitas DNA |

---

## 📊 3. Spesifikasi Skema Data TSV (`reports/tester_results.tsv`)

Setiap baris data mencatat satu siklus trade lengkap yang ditutup (`DEAL_ENTRY_OUT`):

| No | Nama Kolom | Tipe | Contoh Nilai | Keterangan |
|:---:|---|:---:|---|---|
| 1 | `ticket` | ulong | `1024501` | Ticket deal close MT5 |
| 2 | `order_ticket` | ulong | `1024480` | Ticket order posisi awal |
| 3 | `type` | string | `BUY` / `SELL` | Arah transaksi |
| 4 | `open_time` | string | `2024.01.02 08:15` | Waktu entry |
| 5 | `close_time` | string | `2024.01.02 08:42` | Waktu exit |
| 6 | `open_price` | double | `2062.50` | Harga rata-rata entry |
| 7 | `close_price` | double | `2066.80` | Harga exit |
| 8 | `volume` | double | `0.01` | Lot size |
| 9 | `profit_usd` | double | `43.00` | Net profit transaksi dalam USD |
| 10 | `profit_points` | double | `430` | Profit dalam points |
| 11 | `dna` | string | `TBFH` / `TB-H` / `----` | Kode DNA 4 pilar dari zone pembentuk |
| 12 | `stars` | int | `0` - `4` | Total bintang kualitas (0 - 4★) |
| 13 | `strength` | int | `0` - `2` | Kekuatan resmi (0=Weak, 1=Mod, 2=A+) |
| 14 | `T` | int | `0` / `1` | Lolos pilar Base Tightness |
| 15 | `B` | int | `0` / `1` | Lolos pilar BOS Body Close |
| 16 | `F` | int | `0` / `1` | Lolos pilar Direct Attached FVG |
| 17 | `H` | int | `0` / `1` | Lolos pilar HTF POI Reaction |
| 18 | `exh_level` | string | `L0` - `L4` | Exhaustion level zone saat order terpasang |
| 19 | `exit_reason` | string | `FULL_TP` / `BREAK_EVEN` / `CUT_PROFIT` / `HARD_SL` | Kategori hasil penutupan trade |

---

## 🤖 4. Panduan Operasional AI Pasca-Compaction (AI Operator Guide)

Ketika sesi chat di-compact dan context kembali ke kondisi baru, AI harus mengikuti langkah berikut:

### 1. Jalankan Analisis Data Menggunakan `ctx_execute`:
```bash
node scripts/analyze-tester-results.js
```
*Jangan membaca seluruh file TSV langsung ke context memory! Gunakan script sandboxed `ctx_execute` agar token tetap efisien.*

### 2. Format Tabel Summary Hasil yang Wajib Disajikan:
1. **Tabel Keseluruhan (Global Overview)**: Total Trade, Win Rate, Net Profit, Profit Factor.
2. **Matriks 16 Kombinasi DNA**: Membandingkan 16 variasi DNA dari `TBFH` sampai `----`.
3. **Analisis Sensitivitas Tiap Pilar**: Seberapa besar dampak kehadiran masing-masing pilar $T$, $B$, $F$, dan $H$ terhadap kenaikan win rate.
4. **Rekomendasi Parameter Optimal**: Kombinasi minimal pilar yang layak digunakan untuk mode live.

---

## 📝 5. Catatan Perubahan & Status Brainstorming
- **Branch Kerja Aktif**: `feat/phase7-strategy-tester-tsv-analytics`
- **Baseline Git Checkpoint**: Tag `checkpoint-stable-phase4-cascade` dan `78f0da8`
- **Diskusi Terbuka Step 2**: Memastikan aktivasi Strength 0 tidak merusak logika safety live trading (dikontrol via input parameter switch `InpAllowStrength0 = true`).

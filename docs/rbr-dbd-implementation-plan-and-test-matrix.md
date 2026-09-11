# Rencana Implementasi & Matriks Uji Coba: RBR & DBD High-Probability Generator (XAUUSD)

> **Dokumen Perencanaan Pengembangan Bertahap (Step-by-Step Implementation & Test Matrix)**  
> **Target:** `include/arbud/structure/rbrdbdV1.mqh` & `experts/rbrdbdV1Sample.mq5` (serta strategi turunan)  
> **Instrumen:** XAUUSD (Gold) | **Primary TF:** M3 (dengan MTF M1, M5, M15, H1)  
> **Status:** Draft Perencanaan & Brainstorming  

---

## 🧭 Prinsip Pengembangan (Engineering Principles)

1. **Modularitas Tanpa Gandeng Liar (*Loose Coupling*)**:
   - Tiap filter diimplementasikan sebagai fungsi evaluasi independen (dapat di-ON/OFF via parameter input untuk keperluan isolasi pengujian dan backtest).
2. **Event-Driven & Efisiensi CPU**:
   - Kalkulasi formasi pola hanya dievaluasi pada `OnCandleClose` (saat lilin selesai terbentuk).
   - `OnTick` hanya difungsikan secara ringan untuk memperbarui penetrasi harga (retest tracking) dan eksekusi order.
3. **Verifikasi Visual First**:
   - Setiap kali step baru selesai diimplementasikan, hasilnya wajib langsung divisualisasikan pada chart MT5 (kotak zona, label info, garis BOS/ChoCH, blok FVG) agar developer dan trader dapat langsung melakukan audit visual secara objektif.

---

## 🏗️ Tahapan Implementasi Bertahap (Step-by-Step Roadmap)

```
[ Step 1: Base Geometry & Retest Tracking ] ──► [ Step 2: FVG Menempel (Direct Retest Magnet) ]
                                                                       │
                                                                       ▼
[ Step 4: MTF Reflection & HTF POI Gate ]  ◄── [ Step 3: Body Close BOS / ChoCH ]
             │
             ▼
[ Step 5: OB Tagging (Decisional vs Extreme) ]
             │
             ▼
[ Step 6: Big Figure Sweep & Final Backtest ]
```

---

### 🔹 STEP 1: Penguatan Kepadatan Base & Retest/Mitigation Engine (Foundation)
*Status: Selesai di-refactor (Base), Siap Ditingkatkan*

#### 🎯 Deskripsi & Logika:
- Deteksi murni triplet lilin: `Leg-In` $\rightarrow$ `Base (1–5 lilin)` $\rightarrow$ `Leg-Out`.
- **Kepadatan Base (*Base Tightness*)**:
  - Ukur rasio *Total Range Base* terhadap rata-rata range lilin.
  - Saring lilin di dalam Base agar berstatus lilin pasif (*boring candle*): body $\le 60\%-65\%$ dari total candle height.
- **Dynamic Mitigation / Retest Tracking**:
  - Tracking penetrasi harga ke zona:
    - *Fresh*: $0\%$ retest (belum pernah disentuh setelah Leg-Out).
    - *Retested/Used*: $1\% - 99\%$ penetrasi.
    - *Mitigated*: $100\%$ ditembus penuh (kotak dipotong pada lilin yang menembus).

#### 🧪 Harapan / Expected Test Result:
1. Chart bersih dari zona acak/lebar; zona RBR/DBD yang muncul memiliki kotak konsolidasi tipis/rapat.
2. Lilin Leg-Out tidak lagi memuat base yang renggang/lebar.
3. Saat lilin berikutnya menguji zona, warna kotak dan label berganti *realtime* (Fresh $\rightarrow$ Retested $\rightarrow$ Mitigated).
4. Kotak yang tertembus $100\%$ tidak memanjang ke masa depan, menjaga chart tetap rapi.

---

### 🔹 STEP 2: Deteksi Imbalance / Fair Value Gap (FVG) Menempel

#### 🎯 Deskripsi & Logika:
- Menguji apakah lilin **Leg-Out** adalah lilin impulsif sejati yang meninggalkan ketidakseimbangan harga (*Imbalance / FVG*).
- **Syarat FVG RBR (Bullish)**:
  - Ada gap harga antara `High lilin sebelum Leg-Out` (atau batas atas Base) dengan `Low lilin setelah Leg-Out` (atau lilin berjalan).
  - Minimal gap: $\ge X$ points (dapat disetel via input, misal $\ge 50-100$ points pada XAUUSD).
- **Syarat "Menempel Langsung" (*Direct Attached*)**:
  - Batas bawah FVG harus bersinggungan langsung dengan garis *Proximal* (atap Base RBR) atau selisih maksimal $\le$ beberapa points.
  - FVG yang terbentuk jauh di atas base (setelah beberapa candle terbang) **ditolak** sebagai magnet entri langsung Base.

#### 🧪 Harapan / Expected Test Result:
1. Setiap zona RBR/DBD yang valid akan memiliki indikator visual tambahan: area bayangan FVG tipis tepat di atas Base (RBR) atau di bawah Base (DBD).
2. Zona-zona RBR/DBD yang Leg-Out-nya lambat atau bertahap (tidak meninggalkan FVG) otomatis tereliminasi (*filtered out*).
3. Terbukti di chart: Ketika harga retest turun ke FVG yang menempel ini, harga langsung bereaksi di batas Base tanpa drop terlalu dalam.

---

### 🔹 STEP 3: Validasi BOS dan ChoCH (Wajib Body Close)

#### 🎯 Deskripsi & Logika:
- Mencegah pola RBR/DBD palsu yang hanya terbentuk di tengah ayunan tanpa mematahkan struktur pasar.
- Mengintegrasikan engine swing point (High/Low sebelumnya).
- **Aturan Body Close**:
  - **RBR**: Lilin Leg-Out **wajib ditutup (Close)** di atas Swing High terdekat sebelumnya. Jika hanya *wick* (ekor) yang melewati swing high lalu close di bawahnya, itu adalah *Liquidity Sweep*, bukan BOS! Zona RBR tersebut dinyatakan **INVALID**.
  - **DBD**: Lilin Leg-Out **wajib ditutup (Close)** di bawah Swing Low terdekat sebelumnya. Jika hanya wick yang menembus, dinyatakan **INVALID**.
- Mengklasifikasikan apakah penembusan tersebut adalah kelanjutan (*BOS*) atau pembalikan arah (*ChoCH*).

#### 🧪 Harapan / Expected Test Result:
1. Jumlah zona RBR/DBD berkurang drastis $\approx 40\%-60\%$ dibanding Step 1, namun zona yang tersisa memiliki *win-rate* reaksi yang sangat tinggi.
2. Di chart muncul garis horizontal putus-putus berlabel `BOS` atau `ChoCH` yang ditarik dari swing yang ditembus oleh Leg-Out.
3. Tereliminasi semua kasus "fakeout breakout" di mana harga hanya menjilat High lalu berbalik arah turun tajam.

---

### 🔹 STEP 4: Refleksi Multi-Timeframe (MTF) & HTF POI Gatekeeper

#### 🎯 Deskripsi & Logika:
- **Refleksi HTF**:
  - Saat Base terbentuk di M3 (terdiri dari 1–5 lilin M3), sistem memeriksa candle di M15/H1 pada rentang waktu yang sama.
  - Base M3 wajib tampak sebagai **1–3 lilin bersih/kompak di M15**. Jika di M15 terlihat lilin raksasa atau tren panjang, base M3 tersebut dianggap *noise* dan diabaikan.
- **HTF POI Gatekeeper (Anti-No Man's Land)**:
  - Base M1–M5 **tidak boleh berdiri sendiri di tengah ruang kosong**.
  - RBR M3 hanya valid jika titik awal Leg-In bersumber dari reaksi pantulan pada zona Demand M15/H1.
  - DBD M3 hanya valid jika titik awal Leg-In bersumber dari reaksi pantulan pada zona Supply M15/H1.

#### 🧪 Harapan / Expected Test Result:
1. Zona RBR/DBD M3 hanya akan muncul saat pasar memang sedang berada di area diskon/premium HTF.
2. Tidak ada lagi sinyal Buy RBR di pucuk tren (*overbought*) atau Sell DBD di dasar jurang (*oversold*).
3. Konsistensi arah: Sinyal M3 bergerak serasi dengan arus pergerakan modal besar institusi di TF M15/H1.

---

### 🔹 STEP 5: Klasifikasi Order Block (OB): Decisional vs. Extreme

#### 🎯 Deskripsi & Logika:
- Membedah anatomi lilin untuk menentukan titik entri paling optimal:
  - **Decisional Zone**:
    - Candle berlawanan arah terakhir (misal candle bearish terakhir sebelum rally) berada **tepat di dalam Base**.
    - Ditandai sebagai zona entri agresif/utama jika pasar memiliki momentum tinggi.
  - **Extreme Zone**:
    - Candle berlawanan arah terakhir berada di **akar/pangkal Leg-In**.
    - Base RBR difungsikan sebagai Decisional (TP pertama atau scalping cepat), sedangkan pangkal Leg-In ditandai sebagai zona pengaman ekstrem (*low-risk pullback*).

#### 🧪 Harapan / Expected Test Result:
1. Kotak zona pada chart menampilkan badge/teks: `[DECISIONAL]` atau `[EXTREME]`.
2. Trader/EA memiliki rencana ganda: jika Decisional tertembus, sistem tidak panik karena level Extreme telah dipetakan sebagai benteng pertahanan terakhir.

---

### 🔹 STEP 6: Big Figure Liquidity Sweep Confluence & Final Backtest

#### 🎯 Deskripsi & Logika:
- **Deteksi Level Psikologis Bulat XAUUSD**:
  - Level-level penting: kelipatan `$10.0` (misal 2650.00, 2660.00) dan `$50.0` (2600.00, 2650.00, 2700.00).
- **Pemeriksaan Sweep**:
  - Jika Base terbentuk dalam jarak $\le 20-30$ pips dari level Big Figure:
    - Apakah ekor candle Base pernah menembus level tersebut lalu kembali masuk sebelum Leg-Out meledak?
    - Jika **YA** (sudah sweep likuiditas): Zona berstatus **HIGH CONFLUENCE (A+ Setup)**.
    - Jika **TIDAK** (hanya mengambang pasrah di atas/bawah level): Zona diberi tanda bahaya / di-filter keluar untuk menghindari *Stop Hunt trap*.

#### 🧪 Harapan / Expected Test Result:
1. Zona yang memiliki label `[BIG FIGURE SWEEP]` menghasilkan respon harga dengan *slippage* rendah dan pergerakan impulsif instan begitu harga kembali menyentuh zona.
2. Metrik Backtest Komparatif:
   - Win Rate meningkat signifikan pada XAUUSD (target win-rate zona reaksi $\ge 68\%-75\%$).
   - *Maximum Drawdown* berkurang drastis karena menyaring setup jebakan di angka bulat.

---

## 📊 Matriks Pengujian & Verifikasi (Test Verification Matrix)

| Step | Modul Yang Diuji | Input / Test Case | Kriteria Kelulusan (Success Criteria) | Status |
|---|---|---|---|:---:|
| **1** | Base Geometry & Retest Tracking | M3 XAUUSD, Bar history 500 | Base padat $\le 5$ candle, body $\le 65\%$, visual status Fresh/Retested/Mitigated tampil akurat | 🟢 Selesai |
| **2** | Direct Attached FVG | XAUUSD M3, Min FVG Gap $\ge 50$ pts | Kotak FVG menempel pada Proximal Base; tolak jika Leg-Out lambat tanpa FVG | ⚪ To-Do |
| **3** | Body Close BOS / ChoCH | XAUUSD M3, Swing detection lookback | Leg-Out wajib Body Close menembus swing; tolak jika hanya wick sweep | ⚪ To-Do |
| **4** | MTF Reflection & POI Gate | XAUUSD M3 + M15/H1 context | Base M3 tampak 1-3 candle di M15; tolak zona di area No Man's Land | ⚪ To-Do |
| **5** | OB Tagging (Decisional vs Extreme) | Evaluasi candle sebelum Leg-Out & Leg-In | Label `[DECISIONAL]` dan `[EXTREME]` terpetakan secara presisi di chart | ⚪ To-Do |
| **6** | Big Figure Sweep Confluence | Level kelipatan 10 / 50 XAUUSD | Validasi apakah level bulat ter-sweep sebelum Leg-Out; saring floating trap | ⚪ To-Do |

---

## 💡 Topik Diskusi & Brainstorming (Untuk Disepakati Bersama)

1. **Toleransi Ukuran FVG Menempel**:
   - Untuk XAUUSD M3, berapakah ambang batas minimal gap FVG yang dianggap signifikan? (Rekomendasi awal: 50 hingga 100 points / $0.50 - $1.00 pada Gold).
2. **Definisi Swing Point untuk BOS**:
   - Berapa bar lookback yang ideal untuk mendeteksi Swing High/Low terdekat sebelum Leg-Out? (Apakah fractal 3-5 bar atau struktur swing zigzag?).
3. **Prioritas Eksekusi Entri**:
   - Apakah EA nantinya hanya akan memasang limit order di **Decisional Zone** jika ada konfirmasi FVG, ataukah membagi lot (split risk 50:50 antara Decisional dan Extreme)?

---
*Dokumen ini akan terus diperbarui seiring berjalannya proses brainstorming dan implementasi di TradingRepo.*

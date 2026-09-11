# Cetak Biru Arsitektur & Tahapan Implementasi: Living Trading Area & Dual Proactive Agent Framework (XAUUSD M1)

> **Spesifikasi Rekayasa Sistem Algoritmik S&D Terpadu**  
> **Target Arsitektur:** Single-TF Focus (M1) $\rightarrow$ Living TradingArea Object $\rightarrow$ Proactive Limit Grid Engine $\rightarrow$ Proactive Loss Prevention Engine  
> **Target File:** `include/arbud/structure/` & `experts/rbrdbdV1Sample.mq5` (serta Next-Gen EA)  
> **Instrumen:** XAUUSD (Gold) | **Base Timeframe:** M1  

---

## 🧠 Filosofi Desain Sistem (System Architecture Core)

Sistem ini merevolusi penentuan range harga dengan memisahkan tanggung jawab ke dalam 4 pilar modular:
1. **Pure Pattern Storage & Memory Lifecycle**: Objek RBR dan DBD disimpan rapi di memori dinamis, terhubung dengan lifecycle harga, dan dibersihkan otomatis saat tidak lagi relevan (*garbage collected*).
2. **Buffer Algoritmik Min-Variance**: Penentuan batas atas Roof dan batas bawah Floor menggunakan komparasi cerdas antara struktur ekstrem 10 candle ke belakang vs formula $2 \times \text{Base Height}$ (mengambil nilai terkecil/paling konservatif).
3. **Living TradingArea (Stateful Living Object)**: Objek dinamis yang membungkus 1 Floor (RBR) dan 1 Roof (DBD), memetakan area transaksi Buy (0–25%), Sell (0–25% dari Roof), Hard TP (tepat di 50%), Hard SL (30% di luar batas), serta secara *realtime* mengelola status kelelahan zona (**Exhaustion Level 0 sampai 5**).
4. **Dual Proactive Autonomous Agents**:
   - **Agent 1: Proactive Limit Order Placer**: Memasang grid pending order limit hanya pada sub-area yang belum tersentuh (*fresh depth*), dengan alokasi lot/jumlah posisi yang menyesuaikan *exhaustion level* secara proporsional (*round down*).
   - **Agent 2: Proactive Loss Prevention & Order Guard**: Secara proaktif memantau posisi aktif dan pending order. Jika terdeteksi sinyal pembalikan (*engulfing, doji, hammer*) atau pembentukan RBR/DBD lawan di harga saat ini, agen langsung menutup posisi (*emergency cut*) dan membatalkan pending order yang berisiko.

---

## 🗺️ Roadmap Tahapan Implementasi (Step-by-Step Milestones)

```
[ PHASE 1: Pure M1 RBR/DBD Memory & Lifecycle ] 
       │
       ▼
[ PHASE 2: Dynamic Buffer Calculation (10-Candle Swing vs 2x Base) ]
       │
       ▼
[ PHASE 3: Living TradingArea Engine & 6-Stage Exhaustion State Machine ]
       │
       ▼
[ PHASE 4: Agent Proactive Limit Order Grid (Dynamic Allocation & Depth Mapping) ]
       │
       ▼
[ PHASE 5: Agent Proactive Loss Prevention (Price Action & Counter RBR/DBD Guard) ]
       │
       ▼
[ PHASE 6: Integrated End-to-End Simulation & Verification ]
```

---

## 📋 Rincian Tahapan, Logika Matematis, & Harapan Hasil Uji (Expected Results)

### 🔹 PHASE 1: Penguatan Memory Lifecycle RBR & DBD (M1 Focus)
*Fokus: Memastikan pool data RBR & DBD di timeframe M1 tersimpan rapi, ringan, dan memiliki siklus hidup yang terdefinisi.*

#### 1. Logika & Mekanisme:
- **Struct `CRBRDBDMemoryPool`**:
  - Menyimpan array aktif objek RBR (Demand) dan DBD (Supply) yang terdeteksi murni di M1.
- **Kriteria Relevansi & Garbage Collection (Pembersihan Otomatis)**:
  - Objek RBR/DBD dihapus dari memori jika:
    1. Telah tertembus $100\%$ (*fully mitigated*) dan jarak harga saat ini sudah menjauh melampaui $N$ ATR/points.
    2. Usia zona melampaui ambang batas bar (*max memory bars*, misal $> 1000$ bar M1).
    3. Terbentuk struktur baru yang secara hierarki membatalkan relevansi zona tersebut.
- **Visualisasi**:
  - Hanya menampilkan zona yang masih relevan/hidup di chart M1.

#### 🧪 Harapan / Expected Test Result:
- Memory footprint stabil (tidak ada kebocoran memori array bertambah terus tanpa batas).
- Saat zona lama sudah ditembus dan harga bergerak jauh, objek chart terhapus bersih dari layar secara otomatis.
- Fungsi kueri RBR terdekat di bawah harga dan DBD terdekat di atas harga dapat merespon secara instan ($O(N)$ sangat kecil).

---

### 🔹 PHASE 2: Penentuan Buffer Algoritmik (10-Candle Extreme vs $2\times$ Base)
*Fokus: Menentukan garis batas luar yang presisi untuk Floor dan Roof.*

#### 1. Logika & Formulasi Matematis:
Untuk setiap RBR (Floor) dan DBD (Roof) yang terpilih, kita tetapkan nilai **Buffer**:
1. **Komponen A (10-Candle Extreme)**:
   - Dari titik bar awal Base ke belakang 10 candle:
     - Untuk **Floor (RBR)**: Cari titik terendah terendah ($\text{LowestLow}_{10}$).
       $$\Delta \text{Swing}_{\text{Floor}} = |\text{Base.distal} - \text{LowestLow}_{10}|$$
     - Untuk **Roof (DBD)**: Cari titik tertinggi tertinggi ($\text{HighestHigh}_{10}$).
       $$\Delta \text{Swing}_{\text{Roof}} = |\text{HighestHigh}_{10} - \text{Base.distal}|$$
2. **Komponen B (Formula $2 \times$ Base Height)**:
   $$\Delta \text{BaseFormula} = 2.0 \times \text{Base.zoneHeight}$$
3. **Seleksi Buffer (Ambil Nilai Paling Sedikit/Konservatif)**:
   $$\text{Buffer} = \min(\Delta \text{Swing}, \Delta \text{BaseFormula})$$
4. **Penetapan Batas Akhir**:
   - **Garis Final Floor**: $\text{Base.distal} - \text{Buffer}_{\text{Floor}}$
   - **Garis Final Roof**: $\text{Base.distal} + \text{Buffer}_{\text{Roof}}$

#### 🧪 Harapan / Expected Test Result:
- Pada chart, garis Floor dan Roof memiliki batas penyangga (*buffer line*) yang proporsional.
- Jika ada *spike* anomali tajam pada 10 candle ke belakang, formula $2 \times \text{Base}$ mencegah buffer menjadi terlalu lebar secara tidak wajar.
- Sebaliknya, jika base sangat mini namun pergerakan harga stabil, swing 10 candle menjaga buffer agar tidak terlalu sempit (mencegah *noise stop out*).

---

### 🔹 PHASE 3: Objek `Living TradingArea` & Mesin Status Kelelahan (Exhaustion Level 0–5)
*Fokus: Menciptakan objek "hidup" yang menghubungkan Floor dan Roof serta memantau saturasi area secara realtime.*

#### 1. Definisi Geometri & Level Harga `TradingArea`:
- **Rentang Area ($\text{Range}$)**:
  $$\text{Range} = \text{Final Roof} - \text{Final Floor}$$
- **Titik Kunci**:
  - **Roof (100%)**: Batas atas zona DBD (+ Buffer).
  - **Floor (0%)**: Batas bawah zona RBR (- Buffer).
  - **Hard TP (50%)**: Tepat di tengah-tengah:
    $$\text{TP}_{50} = \text{Final Floor} + (0.50 \times \text{Range})$$
  - **Sell Area**: Rentang $75\% - 100\%$ (yaitu $0\% - 25\%$ dihitung turun dari Roof).
    $$\text{SellZone}_{\text{Start}} = \text{Final Roof} - (0.25 \times \text{Range}), \quad \text{SellZone}_{\text{End}} = \text{Final Roof}$$
  - **Buy Area**: Rentang $0\% - 25\%$ dihitung naik dari Floor.
    $$\text{BuyZone}_{\text{Start}} = \text{Final Floor}, \quad \text{BuyZone}_{\text{End}} = \text{Final Floor} + (0.25 \times \text{Range})$$
  - **Roof Hard SL (-30% dari batas atas)**:
    $$\text{Roof}_{\text{HardSL}} = \text{Final Roof} + (0.30 \times \text{Range})$$
  - **Floor Hard SL (-30% dari batas bawah)**:
    $$\text{Floor}_{\text{HardSL}} = \text{Final Floor} - (0.30 \times \text{Range})$$

#### 2. Mesin Status Kelelahan (*Living Exhaustion State Machine*):
Status kelelahan dipantau independen untuk **Buy Area** dan **Sell Area**:
- **Level 0 (Fresh / 0% Touched)**: Harga belum pernah masuk sama sekali ke area $0-25\%$. Ruang penetrasi masih murni $100\%$.
- **Level 1 (25% Consumed)**: Harga telah menembus sedalam $\ge 25\%$ dari ketebalan area transaksi ($0.25 \times \text{SubRange}$).
- **Level 2 (50% Consumed)**: Harga telah menembus sedalam $\ge 50\%$ dari ketebalan area transaksi.
- **Level 3 (75% Consumed)**: Harga telah menembus sedalam $\ge 75\%$ dari ketebalan area transaksi.
- **Level 4 (> 75% Consumed)**: Penetrasi di atas $75\%$ namun belum menyentuh $100\%$. Sinyal bahaya saturasi tinggi.
- **Level 5 (100% Fully Exhausted)**: Area transaksi telah tertembus total ($100\%$). Area dinyatakan mati / *invalidated*.

#### 🧪 Harapan / Expected Test Result:
- Kotak `TradingArea` terlukis rapi di chart: area Buy (bawah), area Sell (atas), garis tengah Hard TP 50%, dan garis putus-putus Hard SL $\pm 30\%$.
- Terdapat HUD/Label interaktif di chart yang menampilkan:
  - `TradingArea #ID | Buy Exhaustion: Level [0-5] (X%) | Sell Exhaustion: Level [0-5] (Y%)`.
- Saat harga bergerak naik/turun mengikis area, angka persentase dan level kelelahan langsung naik secara presisi (*one-way ratchet*: tidak bisa turun kembali ke level 0 jika sudah tertembus).

---

### 🔹 PHASE 4: Agent Proactive Limit Order Placer (Dynamic Grid & Fresh Depth Mapping)
*Fokus: Agen proaktif yang menghitung alokasi posisi dan menempatkan limit order hanya pada kedalaman harga yang masih perawan.*

#### 1. Aturan Alokasi Posisi Berdasarkan Exhaustion Level:
Diberikan parameter input `Max_Pos_per_Trading_Area` (misal $= 10$ posisi):
- **Formula Alokasi Kapasitas**:
  $$\text{AllowedPositions} = \text{Floor}\left(\text{Max\_Pos} \times \text{Factor}(\text{ExhaustionLevel})\right)$$
  - **Level 0 (Fresh)**: Kapasitas $100\%$ $\rightarrow \lfloor 10 \times 1.0 \rfloor = 10$ order.
  - **Level 1 (25% touched)**: Kapasitas tersisa $75\%$ $\rightarrow \lfloor 10 \times 0.75 \rfloor = 7$ order.
  - **Level 2 (50% touched)**: Kapasitas tersisa $50\%$ $\rightarrow \lfloor 10 \times 0.50 \rfloor = 5$ order.
  - **Level 3 (75% touched)**: Kapasitas tersisa $25\%$ $\rightarrow \lfloor 10 \times 0.25 \rfloor = 2$ order.
  - **Level 4 (>75% touched)**: Kapasitas tersisa $10\%$ $\rightarrow \lfloor 10 \times 0.10 \rfloor = 1$ order (atau $0$ jika diset konservatif).
  - **Level 5 (100% exhausted)**: Kapasitas $0\%$ $\rightarrow 0$ order (semua limit tersisa wajib dicancel).

#### 2. Pemetaan Kedalaman Segar (*Fresh Depth Placement*):
- Agen **dilarang menaruh limit order pada koordinat harga yang sudah pernah ditembus** oleh ekor candle sebelumnya.
- Jika area sudah berada di Level 2 (50% sudah tertembus), agen hanya membagi sisa kuota order (misal 5 order) secara merata di dalam rentang $50\% - 100\%$ sub-area yang masih *fresh*.
- Setiap limit order otomatis memiliki:
  - **TP**: Terpasang tepat di level **Hard TP 50%**.
  - **SL**: Terpasang tepat di level **Hard SL $\pm 30\%$**.

#### 🧪 Harapan / Expected Test Result:
- Limit order tidak pernah bertumpuk di harga yang sudah dilewati (*no reordering in breached levels*).
- Jumlah limit order yang aktif selalu sesuai dengan kuota pembulatan ke bawah (*round down*).
- Ketika harga menyentuh TP 50%, seluruh posisi profit ter-liquidasi dan sisa pending limit dibatalkan secara bersih.

---

### 🔹 PHASE 5: Agent Proactive Loss Prevention (Price Action & Counter RBR/DBD Guard)
*Fokus: Agen pengawal risiko yang memantau floating position secara aktif untuk keluar dini sebelum terkena Hard SL.*

#### 1. Pemicu Deteksi Reversal (*Proactive Cut Conditions*):
Agen terus memonitor pergerakan candle M1 (dan live tick) saat posisi aktif terbuka:
1. **Pola Candlestick Reversal Kuat**:
   - Terbentuk **Bearish Engulfing** (untuk posisi Buy aktif) atau **Bullish Engulfing** (untuk posisi Sell aktif).
   - Terbentuk **Doji Breakdown/Breakout** yang mematahkan momentum.
   - Terbentuk **Hammer / Shooting Star / Pinbar** dengan panjang ekor penolakan $\ge 60\%$ menentang arah posisi kita.
2. **Pembentukan Counter RBR / DBD**:
   - Jika kita sedang memegang posisi **Buy** di Floor, namun tiba-tiba di atas harga berjalan terbentuk **DBD baru (Supply baru)** yang menolak kenaikan harga.
   - Jika kita sedang memegang posisi **Sell** di Roof, namun tiba-tiba di bawah harga berjalan terbentuk **RBR baru (Demand baru)**.

#### 2. Tindakan Eksekusi Agen:
- **Tutup Posisi Aktif Segera**: Melakukan market close seketika (*Emergency Early Exit*) untuk mengamankan sisa modal atau mengunci profit kecil.
- **Batalkan Sisa Pending Order**: Membatalkan semua limit order yang tersisa pada `TradingArea` tersebut agar tidak terjemput oleh momentum lawan.
- **Lockout Area**: Mengunci `TradingArea` tersebut ke status *Cool-Down* agar agen pembuat order tidak memasang order baru kembali ke area yang sudah berbahaya.

#### 🧪 Harapan / Expected Test Result:
- Saat harga gagal memantul dan membentuk *engulfing* berlawanan, EA tidak menunggu harga menyeret akun hingga menyentuh Hard SL 30%. Kerugian berhasil dipotong jauh lebih kecil.
- Tidak ada limit order tertinggal yang tereksekusi secara sengaja ke arah tren lawan yang baru meledak.
- Log jurnal MT5 mencatat alasan penutupan dengan jelas: `[PROACTIVE GUARD] Closed Pos #12345 due to Bearish Engulfing / Counter DBD detected!`.

---

### 🔹 PHASE 6: Integrasi Sistem Penuh, Logging & Backtest Benchmark
*Fokus: Penggabungan seluruh komponen menjadi EA utuh yang teruji di Strategy Tester Wine MT5.*

#### 1. Skenario Pengujian Komprehensif:
1. **Uji Kasus Normal (*Ideal Swing*)**:
   - Harga masuk ke Buy Area Level 0 $\rightarrow$ Jemput 10 order $\rightarrow$ Memantul menuju TP 50%.
   - *Verifikasi*: Semua order profit ter-close di 50%, sisa order dibersihkan.
2. **Uji Kasus Penetrasi Parsial (*Step-in Revisit*)**:
   - Harga masuk 25% (Level 1) $\rightarrow$ Naik sedikit $\rightarrow$ Masuk lagi lebih dalam ke 60% (Level 2).
   - *Verifikasi*: Order kedua hanya dipasang di kedalaman $>50\%$, kuota berkurang sesuai round down.
3. **Uji Kasus Pembalikan Mendadak (*Spike Reversal*)**:
   - Harga masuk Buy Area $\rightarrow$ Jemput 4 posisi $\rightarrow$ Tiba-tiba membentuk Bearish Engulfing besar.
   - *Verifikasi*: Agent 2 langsung menutup 4 posisi dan menghapus sisa 6 pending order seketika.

#### 🧪 Harapan / Expected Test Result:
- Backtest menghasilkan grafik pertumbuhan ekuitas (*equity curve*) yang stabil dan halus (*smooth*).
- *Maximum Drawdown* terpangkas secara signifikan berkat peran aktif Agent Proactive Loss Prevention.
- Zero error, zero memory leak, dan efisiensi eksekusi tinggi di MT5 Wine.

---

## 📊 Matriks Status & Verifikasi Tahapan (Roadmap Tracking)

| Phase | Komponen Utama | Milestone Deliverables | Target File | Status |
|---|---|---|---|:---:|
| **1** | M1 RBR/DBD Memory Pool | Storage dinamis & auto-cleanup zona invalid | `rbrdbdV1.mqh` | 🟡 Siap Desain |
| **2** | Min-Variance Buffer Engine | Evaluasi $\min(\text{Swing}_{10}, 2\times\text{Base})$ untuk Floor & Roof | `rbrdbdV1.mqh` | ⚪ Menunggu Ph 1 |
| **3** | Living TradingArea & State 0–5 | Objek living area, 6-level exhaustion, Hard TP/SL | `TradingArea.mqh` | ⚪ Menunggu Ph 2 |
| **4** | Agent Proactive Limit Order | Kuota dinamis, fresh depth grid, auto-cancel pada TP | `AgentGridPlacer.mqh` | ⚪ Menunggu Ph 3 |
| **5** | Agent Proactive Loss Prevention | Deteksi Engulfing/Doji/Counter-zone, emergency close | `AgentLossGuard.mqh` | ⚪ Menunggu Ph 4 |
| **6** | Integrated EA & Backtest Suite | Demonstrator terpadu & pengujian di XAUUSD M1 | `rbrdbdV2Sample.mq5` | ⚪ Menunggu Ph 5 |

---

*Dokumen ini merupakan panduan implementasi resmi TradingRepo untuk pengembangan Living TradingArea dan Dual Proactive Agent Framework.*

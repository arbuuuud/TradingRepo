# Cetak Biru Arsitektur & Tahapan Implementasi: Living Trading Area & Dual Proactive Agent Framework (XAUUSD M1)

> **Spesifikasi Rekayasa Sistem Algoritmik S&D Terpadu**  
> **Target Arsitektur:** Single-TF Focus (M1) $\rightarrow$ RBR/DBD Strength Scoring (0, 1, 2) $\rightarrow$ Living TradingArea Object $\rightarrow$ Proactive Limit Grid Engine $\rightarrow$ Proactive Loss Prevention Engine  
> **Target File:** `include/arbud/structure/` & `experts/rbrdbdV1Sample.mq5` (serta Next-Gen EA)  
> **Instrumen:** XAUUSD (Gold) | **Base Timeframe:** M1  

---

## 🧠 Filosofi Desain Sistem (System Architecture Core)

Sistem ini merevolusi penentuan range harga dengan memisahkan tanggung jawab ke dalam 5 pilar modular:
1. **Pure Pattern Storage & Memory Lifecycle**: Objek RBR dan DBD disimpan rapi di memori dinamis, terhubung dengan lifecycle harga, dan dibersihkan otomatis saat tidak lagi relevan (*garbage collected*).
2. **RBR/DBD Strength Scoring Engine (Tingkat Kekuatan 0, 1, 2)**: Setiap zona RBR/DBD diuji menggunakan parameter ketat dari `rbr-dbd-high-probability-generator-spec.md` (Base Tightness, BOS Body Close, Direct Attached FVG, MTF Reflection / POI, dan Liquidity Sweep) untuk menghasilkan skor kekuatan zona (**Strength 0 = Weak / Raw, Strength 1 = Moderate, Strength 2 = High-Probability / A+ Setup**).
3. **Buffer Algoritmik Min-Variance**: Penentuan batas atas Roof dan batas bawah Floor menggunakan komparasi cerdas antara struktur ekstrem 10 candle ke belakang vs formula $2 \times \text{Base Height}$ (mengambil nilai terkecil/paling konservatif).
4. **Living TradingArea (Stateful Living Object)**: Objek dinamis yang membungkus 1 Floor (RBR) dan 1 Roof (DBD), memetakan area transaksi Buy (0–25%), Sell (0–25% dari Roof), Hard TP (tepat di 50%), Hard SL (30% di luar batas), serta secara *realtime* mengelola status kelelahan zona (**Exhaustion Level 0 sampai 5**).
5. **Dual Proactive Autonomous Agents**:
   - **Agent 1: Proactive Limit Order Placer**: Memasang grid pending order limit hanya pada sub-area yang belum tersentuh (*fresh depth*), dengan alokasi lot/jumlah posisi yang menyesuaikan *exhaustion level* secara proporsional (*round down*) dan memperhitungkan *Strength score* zona.
   - **Agent 2: Proactive Loss Prevention & Order Guard**: Secara proaktif memantau posisi aktif dan pending order. Jika terdeteksi sinyal pembalikan (*engulfing, doji, hammer*) atau pembentukan RBR/DBD lawan di harga saat ini, agen langsung menutup posisi (*emergency cut*) dan membatalkan pending order yang berisiko.

---

## 🗺️ Roadmap Tahapan Implementasi (Step-by-Step Milestones)

```
[ PHASE 1: Pure M1 RBR/DBD Memory & Lifecycle ] 
       │
       ▼
[ PHASE 2: RBR/DBD Strength Scoring Sub-Modules (0, 1, 2) ]
       ├─► Phase 2.1: Base Tightness & MTF Reflection (M5/M15)
       ├─► Phase 2.2: BOS / ChoCH Wajib Body Close
       ├─► Phase 2.3: Direct Attached FVG (Magnet Retest)
       ├─► Phase 2.4: HTF POI Reaction (Anti-No Man's Land)
       └─► Phase 2.5: Liquidity Sweep & Big Figure ($xx00, $xx50)
       │
       ▼
[ PHASE 3: Dynamic Buffer Calculation (10-Candle Swing vs 2x Base) ]
       │
       ▼
[ PHASE 4: Living TradingArea Engine & 6-Stage Exhaustion State Machine ]
       │
       ▼
[ PHASE 5: Agent Proactive Limit Order Grid (Dynamic Allocation & Depth Mapping) ]
       │
       ▼
[ PHASE 6: Agent Proactive Loss Prevention (Price Action & Counter RBR/DBD Guard) ]
       │
       ▼
[ PHASE 7: Integrated End-to-End Simulation & Verification ]
```

---

## 📋 Rincian Tahapan, Logika Matematis, & Harapan Hasil Uji (Expected Results)

### 🔹 PHASE 1: Penguatan Memory Lifecycle RBR & DBD & MTF Base Consolidation Scanner (Default M1)
*Fokus: Memastikan pool data RBR & DBD tersimpan rapi di memori dinamis, memiliki auto-cleanup, serta mengimplementasikan Recursive MTF Base Scanner jika base di M1 terlalu banyak lilin.*

#### 1. Logika & Mekanisme:
- **Default Base Timeframe**: M1.
- **Recursive MTF Base Consolidation Scanner (Menemukan TF Murni 1–3 Lilin Base)**:
  - Saat mendeteksi pembentukan RBR atau DBD di M1:
    - Jika jumlah candle di Base **sangat banyak / melebar** (misal $> 5$ candle di M1):
      - Sistem **tidak langsung membuang** pola tersebut, melainkan melakukan penelusuran naik timeframe secara rekursif:
        $$\text{Ladder Timeframe: } \text{M1} \rightarrow \text{M3} \rightarrow \text{M5} \rightarrow \text{M15} \rightarrow \text{H1}$$
      - Pada rentang waktu base yang sama, sistem memeriksa candle pada TF yang lebih tinggi:
        - Apakah rentang base tersebut termampatkan menjadi **1–3 candle bersih/padat** di timeframe tersebut?
        - Begitu ditemukan TF di mana base-nya terkonsolidasi bersih menjadi 1–3 candle (misal di M3 atau M5), maka RBR/DBD tersebut resmi **didaftarkan sebagai zona milik Period tersebut** (`area.period = PERIOD_M3` atau `PERIOD_M5`).
        - Jika setelah dinaikkan sampai batas maksimal (misal M15/H1) base tetap tidak bersih/tidak kompak $\rightarrow$ Pola ditolak sebagai *noise*.
- **Struct `SRBRDBDArea` (Penambahan Identitas Period)**:
  - Menyimpan properti `ENUM_TIMEFRAMES period;` (menyimpan apakah zona berakar di M1, M3, M5, dst.).
- **Struct `CRBRDBDMemoryPool`**:
  - Menyimpan array aktif objek RBR (Demand) dan DBD (Supply).
- **Kriteria Relevansi & Garbage Collection (Pembersihan Otomatis)**:
  - Objek RBR/DBD dihapus dari memori jika:
    1. Telah tertembus $100\%$ (*fully mitigated*) dan jarak harga saat ini sudah menjauh melampaui $N$ ATR/points.
    2. Usia zona melampaui ambang batas bar (*max memory bars*, misal $> 1000$ bar M1).
    3. Terbentuk struktur baru yang secara hierarki membatalkan relevansi zona tersebut.
- **Visualisasi**:
  - Menampilkan zona yang masih relevan/hidup di chart M1 dengan label timeframe asalnya:  
    misal `M1 RBR [1 C Base]` atau `M3 RBR [2 C Base in M3] (Detected via M1 Escalation)`.

#### 🧪 Harapan / Expected Test Result:
- Memory footprint stabil (tidak ada kebocoran memori array bertambah terus tanpa batas).
- Saat zona lama sudah ditembus dan harga bergerak jauh, objek chart terhapus bersih dari layar secara otomatis.
- Terbukti di chart: Base yang tadinya berantakan (misal 9 candle di M1) tidak menjadi sampah, melainkan dinaikkan secara presisi ke M3 (tampak 3 candle bersih) dan diberi tag `PERIOD_M3`.
- Fungsi kueri RBR terdekat di bawah harga dan DBD terdekat di atas harga dapat merespon secara instan ($O(N)$ sangat kecil).

---

### 🔹 PHASE 2: RBR/DBD Strength Scoring Engine (Tingkat Kekuatan 0, 1, 2)
*Fokus: Menguji 5 pilar SMC secara modular satu per satu, mengumpulkan poin validasi (0–5), dan memetakan zona ke dalam skor Strength 0, 1, atau 2.*

---

#### 🔸 Phase 2.1: Base Tightness & MTF Reflection (M5 / M15)
- **Logika Matematis**:
  - **M1 Base Tightness**: Untuk setiap candle base ($b_1 \dots b_k$, $1 \le k \le 5$), ukur rasio body:
    $$\frac{|\text{Close}_i - \text{Open}_i|}{\text{High}_i - \text{Low}_i} \le 0.60 \quad (\text{Wajib Boring Candle})$$
    Rasio total range base terhadap rata-rata candle height harus ketat (kompresi harga nyata).
  - **MTF Reflection**: Waktu rentang Base M1 ($\text{baseStart}$ s.d. $\text{baseEnd}$) dikonversikan ke bar M5 / M15. Pada M5 / M15, rentang ini wajib tampak sebagai **1–3 candle konsolidasi bersih** (bukan candle raksasa satu arah).
- **Poin Tambahan**: +1 Poin jika kedua syarat lolos.
- **🧪 Harapan / Expected Test Result**:
  - Zona RBR/DBD M1 dengan base melebar atau memiliki lilin momentum liar di dalamnya langsung tereliminasi dari penerima poin.
  - Pada chart tampak label info: `[Tightness: PASS | MTF Refl: PASS (+1 pt)]`.
  - Terbukti secara visual: Ketika chart di-switch ke M5/M15, base M1 tampak sebagai konsolidasi rapat 1–3 candle yang sangat rapi.

---

#### 🔸 Phase 2.2: BOS / ChoCH Wajib Body Close
- **Logika Matematis**:
  - Deteksi Swing High dan Swing Low terdekat sebelum Leg-Out diselaraskan langsung pada Timeframe Asal zona (`area.period` $\in \{\text{M1, M3, M5, dst.}\}$).
  - Menggunakan **5-Bar Structural Pivot (2 kiri, 2 kanan)** dengan jeda (*clearance*) minimal 2 bar dari Base dan validasi kedalaman lembah (*valley pullback depth* $\ge \text{zoneHeight}$).
  - **RBR (Bullish Breakout)**:
    - Harga `rates[legOutIdx].close > SwingHigh_Terdekat` (Wajib **Body Close** melampaui level swing).
    - Jika `rates[legOutIdx].high > SwingHigh` tapi `rates[legOutIdx].close <= SwingHigh`: Ini terdeteksi sebagai **Wick Sweep**, bukan BOS $\rightarrow$ Ditolak!
  - **DBD (Bearish Breakdown)**:
    - Harga `rates[legOutIdx].close < SwingLow_Terdekat` (Wajib **Body Close** melampaui level swing).
    - Jika hanya ekor low yang menembus swing low lalu close di atasnya $\rightarrow$ Ditolak!
- **Poin Tambahan**: +1 Poin jika lolos Body Close BOS / ChoCH.
- **Visual Reference Line**:
  - Garis horizontal putus-putus berwana Aqua (RBR) atau Orange-Red (DBD) ditarik dari puncak Swing High/Low ke lilin Leg-Out.
- **📌 Catatan Pengembangan (Engineering Note / Backlog)**:
  - *Deteksi swing untuk penentuan BOS saat ini telah bekerja secara fungsional dan cukup akurat untuk bare minimum MVP.*
  - *Dapat ditingkatkan lebih lanjut di masa mendatang (misal: penyempurnaan deteksi sub-struktur zig-zag dinamis / adaptive multi-bar ATR clearance), namun ditunda (deferred) untuk menjaga fokus pada penyelesaian modul-modul fungsional utama terlebih dahulu.*
- **🧪 Harapan / Expected Test Result**:
  - Pada chart muncul garis horizontal putus-putus berlabel `BOS (Body Close)` yang ditarik dari swing yang ditembus.
  - Sinyal fakeout di mana harga hanya menjilat swing high/low dengan ekor panjang (*liquidity grab*) tidak lagi mendapatkan poin BOS.
  - Tereliminasi zona RBR/DBD yang terbentuk di tengah-tengah rentang tanpa mematahkan struktur pasar apapun.

---

#### 🔸 Phase 2.3: Direct Attached FVG (Magnet Retest)
- **Logika Matematis**:
  - Menguji ada atau tidaknya *Fair Value Gap* (FVG) yang ditinggalkan oleh Leg-Out:
    - **RBR (Bullish FVG)**: Celah harga antara `High candle sebelum Leg-Out` (atau atap Base) dengan `Low candle setelah Leg-Out` (atau candle berjalan).
      $$\text{FVG}_{\text{Gap}} = \text{Low}_{\text{Next}} - \text{High}_{\text{Prev}} \ge \text{MinGapPoints} \quad (\text{Default: } \ge 50 \text{ pts / } \$0.50 \text{ XAUUSD})$$
    - **DBD (Bearish FVG)**: Celah harga antara `High candle setelah Leg-Out` dengan `Low candle sebelum Leg-Out` (atau lantai Base).
      $$\text{FVG}_{\text{Gap}} = \text{Low}_{\text{Prev}} - \text{High}_{\text{Next}} \ge \text{MinGapPoints}$$
  - **Syarat Menempel Langsung (*Direct Attached*)**:
    - Untuk RBR: Batas bawah FVG harus menempel tepat pada garis Proximal (atap Base) dengan toleransi celah $\le 10$ points. FVG yang melayang jauh di atas Base tidak dianggap menempel.
- **Poin Tambahan**: +1 Poin jika terdapat FVG signifikan yang menempel langsung.
- **🧪 Harapan / Expected Test Result**:
  - Kotak semi-transparan tipis (highlight FVG) terlukis menyambung langsung di atas atap Base RBR atau di bawah lantai Base DBD.
  - Label info menampilkan: `[FVG: Attached (Gap: X pts) (+1 pt)]`.
  - Terbukti saat retest pertama: Harga turun masuk ke celah FVG dan langsung memantul (*reject*) tepat di batas Base tanpa penetrasi terlalu dalam.

---

#### 🔸 Phase 2.4: HTF POI Reaction (Anti-No Man's Land)
- **Logika Matematis**:
  - Menghubungkan titik awal Leg-In dengan zona POI di Timeframe Tinggi (M15 / H1).
  - **Syarat RBR (Demand)**:
    - Ekor terendah dari Leg-In wajib bersentuhan atau memantul dari zona Demand / Support / FVG di TF M15 atau H1.
  - **Syarat DBD (Supply)**:
    - Ekor tertinggi dari Leg-In wajib bersentuhan atau memantul dari zona Supply / Resistance / FVG di TF M15 atau H1.
  - Jika Leg-In terbentuk di ruang kosong tanpa referensi HTF POI (*No Man's Land*), tidak berhak mendapat poin.
- **Poin Tambahan**: +1 Poin jika Leg-In berasal dari reaksi HTF POI.
- **🧪 Harapan / Expected Test Result**:
  - Label info menampilkan: `[HTF POI: M15 Demand Reaction (+1 pt)]` atau `[HTF POI: None (0 pt)]`.
  - Mencegah pola RBR palsu yang terbentuk saat harga sedang terjun bebas di tengah tren bearish HTF.
  - Seluruh zona M1 yang memiliki poin ini terbukti bergerak searah dengan bias institusional HTF.

---

#### 🔸 Phase 2.5: Liquidity Sweep & Big Figure Confluence ($xx00, $xx50)
- **Logika Matematis**:
  - **Level Psikologis Bulat (*Big Figure*)**: Kelipatan `$10.0` (misal 2650.00, 2660.00) dan `$50.0` (2600.00, 2650.00, 2700.00).
  - **Pemeriksaan Sweep**:
    - Apakah candle Base pernah menembus level psikologis bulat tersebut atau menembus Equal Highs / Equal Lows (EQH/EQL) di sebelah kirinya dengan ekor wick, lalu kembali ditutup di dalam Base sebelum Leg-Out meledak?
    - Jika **YA**: Telah terjadi pembersihan likuiditas (*Stop Hunt completed*).
    - Jika **TIDAK** (Base hanya menempel pasrah tepat di atas/bawah angka bulat): Sangat rawan jebakan stop hunt.
- **Poin Tambahan**: +1 Poin jika terjadi valid sweep pada level bulat atau EQH/EQL.
- **🧪 Harapan / Expected Test Result**:
  - Label info menampilkan: `[Sweep: Confirmed at 2650.00 (+1 pt)]`.
  - Terhindar dari zona jebakan di angka bulat yang sering kali dihantam tembus oleh pergerakan manipulasi London/NY open.
  - Respon harga begitu kembali ke zona ini menghasilkan reaksi cepat (*instant bounce*).

---

#### 🔸 Phase 2 Final Aggregator: Pemetaan Skor Strength (0, 1, 2)
Akumulasi total poin ($0 - 5$) dipetakan menjadi tingkatan kekuatan resmi:

| Total Poin | Skor Strength | Label Visual di Chart | Warna Visual Border / Teks | Perlakuan Eksekusi |
|:---:|:---:|:---:|:---:|---|
| **0 – 1 Poin** | **Strength 0** | `M1 RBR/DBD [Str 0: WEAK]` | Abu-abu / Netral | **Diabaikan** untuk grid order, atau hanya sebagai zona referensi pasif. |
| **2 – 3 Poin** | **Strength 1** | `M1 RBR/DBD [Str 1: MODERATE]` | Biru / Cokelat Muda | **Trading Normal**: Membuka grid limit dengan alokasi lot terukur. |
| **4 – 5 Poin** | **Strength 2** | `M1 RBR/DBD [Str 2: HIGH-PROB / A+]` | Emas (*Gold*) / Tebal Menyala | **A+ Setup Prioritas**: Alokasi grid penuh dengan tingkat keyakinan maksimal. |

**🧪 Harapan Akhir Phase 2**:
- Di chart MT5, setiap kotak RBR/DBD memiliki identitas visual instan berdasarkan kekuatannya (Str 0, Str 1, Str 2).
- Tester dapat melakukan inspeksi visual satu per satu: mengklik atau membaca keterangan poin untuk memverifikasi mengapa zona tersebut mendapat Str 0, 1, atau 2.

---

### 🔹 PHASE 3: Penentuan Buffer Algoritmik (10-Candle Extreme vs $2\times$ Base)
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

### 🔹 PHASE 4: Objek `Living TradingArea` & Mesin Status Kelelahan (Exhaustion Level 0–5)
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
  - `TradingArea #ID | Buy Exhaustion: Level [0-5] (X%) | Sell Exhaustion: Level [0-5] (Y%) | Floor Str: [0-2] | Roof Str: [0-2]`.
- Saat harga bergerak naik/turun mengikis area, angka persentase dan level kelelahan langsung naik secara presisi (*one-way ratchet*: tidak bisa turun kembali ke level 0 jika sudah tertembus).

---

### 🔹 PHASE 5: Agent Proactive Limit Order Placer (Dynamic Grid & Fresh Depth Mapping)
*Fokus: Agen proaktif yang menghitung alokasi posisi dan menempatkan limit order hanya pada kedalaman harga yang masih perawan.*

#### 1. Aturan Alokasi Posisi Berdasarkan Exhaustion Level & Strength:
Diberikan parameter input `Max_Pos_per_Trading_Area` (misal $= 10$ posisi):
- **Filter Berdasarkan Strength**:
  - Jika zona Floor/Roof pendukung berstatus **Strength 0**, agen menolak menempatkan limit order (*0 position*).
  - Jika zona berstatus **Strength 1**, agen mengizinkan alokasi order standar.
  - Jika zona berstatus **Strength 2**, agen mengaktifkan alokasi penuh dengan prioritas utama.
- **Formula Alokasi Kapasitas Berdasarkan Exhaustion Level**:
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

### 🔹 PHASE 6: Agent Proactive Loss Prevention (Price Action, Cut Profit & Period-Dependent Cut Loss Guard)
*Fokus: Agen pengawal risiko yang memantau floating position secara aktif untuk Cut Profit dan Period-Dependent Cut Loss sebelum terkena Hard SL 30%.*

#### 1. Mekanisme CUT PROFIT (Early Exit Lock):
- Berlaku saat posisi aktif sedang menghasilkan *floating net profit* $> 0$:
  1. **Pola Candlestick Reversal M1**:
     - Terbentuk **Bearish Engulfing** (pada posisi Buy aktif) atau **Bullish Engulfing** (pada posisi Sell aktif).
     - Terbentuk **Doji Breakdown/Breakout** yang mematahkan momentum ke arah TP.
     - Terbentuk **Hammer / Shooting Star / Pinbar** dengan panjang ekor penolakan $\ge 60\%$ menentang arah posisi kita.
  2. **Pembentukan Counter RBR / DBD**:
     - Jika sedang memegang posisi **Buy** di Floor, namun tiba-tiba di atas harga berjalan terbentuk **DBD baru (Supply baru)**.
     - Jika sedang memegang posisi **Sell** di Roof, namun tiba-tiba di bawah harga berjalan terbentuk **RBR baru (Demand baru)**.
- **Tindakan**: Langsung tutup seluruh posisi aktif (*Cut Profit Market Close*), batalkan semua sisa pending limit order dari area tersebut, dan kunci area (*lockout*).

#### 2. Mekanisme CUT LOSS Berbasis Timeframe Zona (*Period-Dependent Candle Close Cut Loss*):
- **Logika Dependensi Timeframe (*Period-Aware Exit*)**:
  - Batas cut loss bukan sekadar titik tick, melainkan mengacu pada **Candle Close di Timeframe asal RBR/DBD tersebut**:
    - Jika zona Floor/Roof berakar dari **Period M1**: Evaluasi **Candle Close M1**. Jika ada candle M1 yang ditutup (*Close*) di luar batas buffer Floor/Roof $\rightarrow$ **Auto Close Semua Posisi (Cut Loss)** seketika!
    - Jika zona Floor/Roof berakar dari **Period M3** (hasil eskalasi MTF Phase 1): Evaluasi **Candle Close M3**. Penembusan ekor wick M1 diabaikan; Cut Loss baru terpicu jika **Candle M3 resmi ditutup** di luar batas buffer!
    - Jika zona Floor/Roof berakar dari **Period M5 / M15**: Menunggu konfirmasi **Candle Close M5 / M15** di luar batas buffer Floor/Roof.
- **Keunggulan**: Memberikan ruang napas (*breathing room*) yang tepat sesuai bobot timeframe zona. Posisi pada zona M3/M5 tidak akan terkena *whipsaw* atau *noise spike* ekor 1 menit yang belum terkonfirmasi oleh candle close timeframe zona tersebut!

#### 3. Tindakan Eksekusi Agen:
- **Tutup Posisi Aktif Segera**: Melakukan market close seketika (*Emergency Early Exit / Cut Loss*) untuk membatasi kerugian jauh sebelum Hard SL 30%.
- **Batalkan Sisa Pending Order**: Membatalkan semua limit order yang tersisa pada `TradingArea` tersebut agar tidak terjemput oleh momentum lawan yang menembus batas.
- **Lockout Area**: Mengunci `TradingArea` tersebut ke status *Cool-Down* agar agen pembuat order tidak memasang order baru kembali ke area yang sudah breached.

#### 🧪 Harapan / Expected Test Result:
- **Pada Skenario Profit**: Saat harga mendekati TP tapi berbalik membentuk *engulfing*, profit yang ada langsung dikunci (*Cut Profit*), tidak dibiarkan berbalik menjadi floating minus.
- **Pada Skenario Loss**:
  - Untuk zona M1: Candle close M1 di bawah Floor buffer langsung mengeksekusi cut loss cepat.
  - Untuk zona M3: Ekor candle M1 yang menusuk sesaat di luar buffer tidak memicu cut loss prematur selama candle M3 belum ditutup di luar buffer. Begitu candle M3 close di luar buffer, cut loss langsung dieksekusi secara disiplin.
- Tidak ada limit order tertinggal yang tereksekusi secara sengaja ke arah tren lawan yang baru meledak.
- Log jurnal MT5 mencatat alasan penutupan dengan jelas:  
  `[PROACTIVE GUARD] Cut Loss triggered: M3 Candle Closed outside Floor Buffer (Closed Price: 2645.20 vs Buffer: 2646.00)`.

---

### 🔹 PHASE 7: Integrasi Sistem Penuh, Logging & Backtest Benchmark
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
- *Maximum Drawdown* terpangkas secara signifikan berkat peran aktif Agent Proactive Loss Prevention dan filter Strength zona.
- Zero error, zero memory leak, dan efisiensi eksekusi tinggi di MT5 Wine.

---

## 📊 Matriks Status & Verifikasi Tahapan (Roadmap Tracking)

| Phase | Komponen Utama | Milestone Deliverables | Target File | Status |
|---|---|---|---|:---:|
| **1** | M1 Memory & MTF Escalation | Storage dinamis, cleanup invalid, & recursive TF climb (1-3 candle base) | `rbrdbdV1.mqh` | 🟢 Selesai (Tested) |
| **2.1** | Base Tightness & MTF Refl | Bobot +1 poin: Base padat $\le 60\%$ body & 1-3 candle di M5/M15 | `rbrdbdV1.mqh` | 🟡 Siap Desain |
| **2.2** | BOS/ChoCH Body Close | Bobot +1 poin: Wajib close menembus swing, tolak wick sweep | `rbrdbdV1.mqh` | ⚪ Menunggu 2.1 |
| **2.3** | Direct Attached FVG | Bobot +1 poin: Celah $\ge 50$ pts menempel langsung di batas base | `rbrdbdV1.mqh` | ⚪ Menunggu 2.2 |
| **2.4** | HTF POI Reaction Gate | Bobot +1 poin: Reaksi dari M15/H1 POI, tolak No Man's Land | `rbrdbdV1.mqh` | ⚪ Menunggu 2.3 |
| **2.5** | Liquidity Sweep / Big Figure | Bobot +1 poin: Sweep di level bulat ($xx00, $xx50) atau EQH/EQL | `rbrdbdV1.mqh` | ⚪ Menunggu 2.4 |
| **2 Final** | Strength Aggregator (0, 1, 2) | Klasifikasi final Str 0, 1, 2 + visual warna badge di chart | `rbrdbdV1.mqh` | ⚪ Menunggu 2.5 |
| **3** | Min-Variance Buffer Engine | Evaluasi $\min(\text{Swing}_{10}, 2\times\text{Base})$ untuk Floor & Roof | `rbrdbdV1.mqh` | ⚪ Menunggu Ph 2 |
| **4** | Living TradingArea & State 0–5 | Objek living area, 6-level exhaustion, Hard TP/SL | `TradingArea.mqh` | ⚪ Menunggu Ph 3 |
| **5** | Agent Proactive Limit Order | Kuota dinamis, fresh depth grid, auto-cancel pada TP | `AgentGridPlacer.mqh` | ⚪ Menunggu Ph 4 |
| **6** | Proactive Loss Prevention | Cut Profit (Engulfing/Counter-zone) & Period-Aware Cut Loss (Close outside buffer) | `AgentLossGuard.mqh` | ⚪ Menunggu Ph 5 |
| **7** | Integrated EA & Backtest Suite | Demonstrator terpadu & pengujian di XAUUSD M1 | `rbrdbdV2Sample.mq5` | ⚪ Menunggu Ph 6 |

---

*Dokumen ini merupakan panduan implementasi resmi TradingRepo untuk pengembangan Living TradingArea dan Dual Proactive Agent Framework.*

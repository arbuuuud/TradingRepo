# RBR & DBD High-Probability Generator Specification (XAUUSD Precision)

> **Dokumen Panduan Teknis & Riset Arsitektur Sistem S&D / SMC**  
> **Target Instrumen:** XAUUSD (Gold)  
> **Status:** Reference Specification & Development Blueprint  
> **Penulis / Analis:** TradingRepo Specialist (Supply & Demand & Smart Money Concepts)  

---

## 🎯 Executive Summary & Filosofi Dasar

Dokumen ini mendokumentasikan spesifikasi riset dan panduan pengembangan algoritma deteksi zona **RBR (Rally-Base-Rally)** dan **DBD (Drop-Base-Drop)** dengan presisi dan win-rate tinggi (*High-Probability Generator*).

Di pasar **XAUUSD**, pola Supply & Demand konvensional seringkali gagal akibat *volatility spikes*, manipulasi likuiditas (*stop hunt*), dan *false breakout*. Algoritma ini dirancang dengan mengintegrasikan **5 Aturan Filter Mutlak** berlandaskan prinsip **Smart Money Concepts (SMC)** untuk memastikan setiap zona yang tervalidasi bukan terbentuk di area kosong (*No Man's Land*), melainkan didorong oleh *Institutional Order Flow*.

---

## 🛡️ 5 Aturan Filter Mutlak (The 5 Golden Rules)

### 1. Validasi Struktur Base & Refleksi Multi-Timeframe (MTF)

#### A. Definisi Pola
* **RBR (Demand / Floor)**: Rally (*Leg-In*) $\rightarrow$ Base (*konsolidasi padat/rentang sempit*) $\rightarrow$ Rally (*Leg-Out*).
* **DBD (Supply / Roof)**: Drop (*Leg-In*) $\rightarrow$ Base (*konsolidasi padat/rentang sempit*) $\rightarrow$ Drop (*Leg-Out*).

#### B. Kepadatan Base (*Base Tightness*)
* Base diukur dari **ketatnya range body candle** (*tight price consolidation*), bukan sekadar kuantitas/jumlah candle.
* Candle dalam base wajib bersifat *boring* (volatilitas rendah, body tidak dominan, rentang harga terkompresi).

#### C. Matriks Refleksi Multi-Timeframe (LTF vs HTF)
Base di timeframe eksekusi/eksplorasi (LTF) harus terefleksi sebagai konsolidasi bersih di timeframe yang lebih tinggi:
* **Entry M1 / M3**: Base wajib terefleksi sebagai **1–3 candle bersih di M5 / M15**.
* **Entry M5**: Base wajib terefleksi sebagai **1–3 candle bersih di M15 / H1**.
* **Entry M15 / M30**: Base wajib terefleksi sebagai **1–3 candle bersih di H1 / H4**.

#### D. Aturan Khusus Scalping (M1 – M5)
* **Anti-No Man’s Land**: RBR/DBD pada M1–M5 **dilarang keras berdiri sendiri** di area kosong.
* **Syarat**: Zona M1–M5 wajib terbentuk **hanya setelah harga bereaksi** dari *Point of Interest* (POI) atau zona utama HTF (M15 / H1 / H4).

---

### 2. Filter Validasi BOS dan ChoCH (Wajib Body Close)

Pola RBR/DBD tidak bernilai tanpa adanya konfirmasi perubahan struktur pasar:
* **BOS (Break of Structure)**:
  * *Leg-Out* **wajib menghasilkan Body Close Candle** menembus struktur Swing High/Low sebelumnya untuk mengonfirmasi kelanjutan tren (*continuation*).
  * **Tolak/Abaikan jika Leg-Out hanya berupa *Wick Sweep* (ekor candle)**.
* **ChoCH (Change of Character)**:
  * Pada zona pembalikan arah (*reversal*), *Leg-Out* **wajib Body Close** menembus Swing High/Low utama terakhir.
* **Alignment**:
  * Struktur BOS/ChoCH yang dihasilkan oleh Leg-Out harus searah dengan arah bias utama Timeframe Tinggi (HTF Bias).

---

### 3. Imbalance / FVG Menempel (Direct Retest Magnet)

* **Impulsive Momentum Candle**:
  * *Leg-Out* wajib berupa lilin marubozu atau lilin impulsif berkekuatan besar (*Extended Range Candle*).
* **Fair Value Gap (FVG)**:
  * *Leg-Out* wajib meninggalkan ketidakseimbangan harga (*Imbalance / FVG*) yang signifikan.
* **Posisi FVG (Direct Retest Magnet)**:
  * FVG harus **menyambung langsung dari batas luar Base** (*proximal line*).
  * **Tujuan Mekanis**: Memastikan saat harga melakukan mitigasi/retest pertama kali, reaksi pantulan langsung terpicu pada batas Base tanpa perlu penetrasi terlalu dalam yang dapat merusak rasio *Risk-to-Reward* (RR).

---

### 4. Klasifikasi Order Block (OB): Decisional vs. Extreme

Setiap formasi yang lolos filter diklasifikasikan ke dalam tipe Order Block (OB):

| Tipe Zona | Letak OB | Karakteristik & Strategi Entri |
|---|---|---|
| **Decisional Zone** | Tepat di dalam **Base** | OB (candle berlawanan arah terakhir sebelum Leg-Out meledak) berada di dalam Base. Ditetapkan sebagai **Main Entry Zone (High Probability)**. Cocok untuk momentum pasar kuat. |
| **Extreme Zone** | Berada di **Leg-In** | OB utama terletak di pangkal Leg-In. Base RBR/DBD difungsikan sebagai **Decisional / Scalping Zone** (untuk kondisi *hyper-trend*), sedangkan OB di Leg-In disimpan sebagai **Extreme Entry Zone (Low Risk / Backup Area)** jika harga mengalami *deep pullback*. |

---

### 5. Liquidity Sweep & Big Figure Confluence (BB)

* **Syarat Khusus Big Figure / Psychological Level**:
  * Base yang berdekatan dengan angka bulat psikologis XAUUSD (misal: round number `$xx00`, `$xx50`, dll.) **wajib sudah melakukan Liquidity Sweep** terhadap level tersebut atau terhadap *Equal Highs / Equal Lows (EQH/EQL)* di sebelah kirinya sebelum Leg-Out meledak.
* **Filter Risiko Stop Hunt**:
  * **Hindari Base yang hanya menempel/pasrah** persis di atas atau di bawah level Big Figure tanpa adanya *sweep* terlebih dahulu. Zona semacam ini merupakan area likuiditas rentan yang paling sering dihajar oleh *Smart Money Stop Hunt*.

---

## 📋 Standar Format Output Deteksi

Setiap kali modul scanner/analis mendeteksi atau memetakan zona RBR/DBD, format laporan output terstruktur wajib mengikuti standar berikut:

```text
================================================================================
RBR & DBD HIGH-PROBABILITY DETECTION REPORT (XAUUSD)
================================================================================
1. Jenis Zona          : [RBR (Demand) / DBD (Supply)]
2. Timeframe Eksekusi  : [M1 / M3 / M5 / M15 / M30]
3. Koordinat Harga     : Upper Line: [Price] | Lower Line: [Price] (Height: [Points/Pips])
4. Status Konfirmasi   : [VALID / INVALID]
   - Base Tightness    : [Pass / Fail]
   - MTF Reflection    : [Pass / Fail] (Refleksi HTF: [TF])
   - POI HTF Reaction  : [Pass / Fail] (Sumber HTF: [TF & Price])
   - BOS / ChoCH Type  : [BOS / ChoCH] (Status Body Close: [Confirmed / Rejected])
   - FVG Confluence    : [Direct Attached / Separated / None]
5. Klasifikasi Entri   : [DECISIONAL ZONE / EXTREME ZONE]
6. Confluence Tambahan :
   - FVG Range         : [Upper] - [Lower]
   - Structure Broken  : [Swing High/Low at Price]
   - Liquidity Swept   : [EQH / EQL / Big Figure Level at Price]
================================================================================
```

---

## 🗺️ Roadmap Integrasi ke MQL5 Engine

Tahapan implementasi spesifikasi ini ke dalam codebase MQL5 (`TradingRepo`):

```
                      [ SPESIFIKASI RISET (Dokumen Ini) ]
                                      │
                                      ▼
             [ FASE 1: Deteksi Geometris Murni (M3 Engine) ]
             • Identifikasi Leg-In, Base padat, Leg-Out
             • Tracking konsumsi/retest & visualisasi chart (Completed di rbrdbdV1)
                                      │
                                      ▼
             [ FASE 2: Modul FVG & Body Close BOS/ChoCH ]
             • Deteksi FVG menempel pada batas Base
             • Verifikasi Body Close pada swing point terdekat
                                      │
                                      ▼
             [ FASE 3: Multi-Timeframe Alignment & POI Gate ]
             • Validasi refleksi 1-3 candle di HTF (M5/M15/H1)
             • Gatekeeper: Hanya izinkan zona LTF jika harga memantul dari HTF POI
                                      │
                                      ▼
             [ FASE 4: Big Figure Liquidity Sweep & OB Tagging ]
             • Deteksi sweep pada level psikologis ($xx00, $xx50)
             • Klasifikasi Decisional vs Extreme Entry Levels
```

---
*Dokumen ini merupakan aset intelektual dan panduan arsitektur teknis resmi repositori TradingRepo.*

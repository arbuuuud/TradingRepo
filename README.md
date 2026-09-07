# TradingRepo — MetaTrader 5 Expert Advisor (MQL5)

Repositori ini adalah framework modular untuk pengembangan **Expert Advisor (EA)** MetaTrader 5 di lingkungan **macOS via Wine**.

## 🚀 Fitur Utama

- **Modular Architecture**: Pemisahan tegas antara Risk Management, Signal Generation, dan Trade Execution.
- **Mac + Wine Integration**: Otomasi symlink langsung ke direktori `MQL5/Experts` MT5 dan script kompilasi headless.
- **Dynamic Risk Sizing**: Perhitungan lot otomatis berbasis `% risk equity vs stop loss` dengan normalisasi broker.
- **Account Protection**: Dilengkapi Spread Filter dan Daily Drawdown Limiter.
- **AI Agent-Ready**: Terintegrasi dengan sistem Agent & Skill `.pi/` untuk iterasi strategi trading dengan cepat.

---

## 📁 Struktur Direktori

```
Trading/
├── .gitignore
├── AGENTS.md                  # Panduan subagents & workflows
├── README.md
├── .pi/                       # Konfigurasi Subagents & Skills
│   ├── agents/
│   │   ├── ea-architect.md
│   │   ├── dev-mql5.md
│   │   └── ea-reviewer.md
│   └── skills/
│       ├── mql5-core/SKILL.md
│       ├── risk-management/SKILL.md
│       └── trading-strategy/SKILL.md
├── include/                   # Modul MQL5 (.mqh)
│   ├── Defines.mqh            # Enums & struct
│   ├── RiskManager.mqh        # Kalkulator lot, spread filter, drawdown
│   ├── SignalEngine.mqh       # Manajemen handle indikator & sinyal
│   └── TradeExecution.mqh     # Wrapper CTrade standar
├── experts/                   # File utama EA (.mq5)
│   └── StarterEA.mq5          # Boilerplate EA siap pakai
└── scripts/
    ├── setup-symlink.sh       # Link project ke Wine MT5
    └── compile.sh             # Kompilasi EA via MetaEditor CLI
```

---

## 💻 Cara Menggunakan

### 1. Hubungkan ke MT5 Wine
Jalankan script symlink satu kali:
```bash
./scripts/setup-symlink.sh
```
Setelah ini, folder `TradingRepo` otomatis muncul di MetaEditor dan Navigator MT5 di bawah folder `Experts` dan `Include`.

### 2. Kompilasi EA
Anda bisa mengompilasi dari MetaEditor (F7) ATAU langsung dari terminal macOS:
```bash
./scripts/compile.sh experts/StarterEA.mq5
```
Hasil file binary `.ex5` akan langsung dibuat dan siap diuji.

### 3. Jalankan di MetaTrader 5
1. Buka MetaTrader 5 via Wine.
2. Buka **Strategy Tester** (`Ctrl+R` / `Cmd+R`).
3. Pilih Expert: `Experts/TradingRepo/StarterEA.ex5`.
4. Pilih Pair & Timeframe (contoh: EURUSD H1 atau XAUUSD H1).
5. Klik **Start** untuk mulai backtest!

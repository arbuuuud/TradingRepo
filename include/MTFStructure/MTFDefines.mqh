//+------------------------------------------------------------------+
//|                                                   MTFDefines.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_SMC_TREND
{
   TREND_NONE = 0,   // Sideways / Undefined
   TREND_BULL = 1,   // Bullish Trend (HH & HL)
   TREND_BEAR = -1   // Bearish Trend (LH & LL)
};

enum ENUM_TF_ROLE
{
   ROLE_HTF_BIAS        = 0, // Macro Trend Filter (e.g. H1, M15)
   ROLE_SETUP_BASE       = 1, // Structure & POI Base (e.g. M3, M5)
   ROLE_LTF_TRIGGER      = 2  // Precision Entry Trigger (e.g. M1)
};

enum ENUM_SWING_TYPE
{
   SWING_NONE = 0,
   SWING_HIGH = 1,
   SWING_LOW  = -1
};

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct STFStructure
{
   string            label;        // "HH", "HL", "LH", "LL"
   datetime          candleTime;   // Candle open time of the swing
   double            priceH;       // High price level
   double            priceL;       // Low price level
   bool              isLiquidated; // True if swept by subsequent wick
   bool              isMain;       // True = Main Structure, False = Internal Structure

   void Init()
   {
      label        = "";
      candleTime   = 0;
      priceH       = 0.0;
      priceL       = 0.0;
      isLiquidated = false;
      isMain       = false;
   }
};

struct STFData
{
   ENUM_TIMEFRAMES   tf;
   ENUM_TF_ROLE      role;
   ENUM_SMC_TREND    trend;
   datetime          lastBarTime;

   // Main and Internal tracking
   STFStructure      lastMainHigh;
   STFStructure      lastMainLow;
   STFStructure      lastInternalHigh;
   STFStructure      lastInternalLow;

   // Equilibrium
   double            equilibriumPrice; // 50% between lastMainHigh and lastMainLow

   void Init(ENUM_TIMEFRAMES period, ENUM_TF_ROLE tfRole)
   {
      tf = period;
      role = tfRole;
      trend = TREND_NONE;
      lastBarTime = 0;
      equilibriumPrice = 0.0;

      lastMainHigh.Init();
      lastMainLow.Init();
      lastInternalHigh.Init();
      lastInternalLow.Init();
   }
};

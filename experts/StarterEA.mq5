//+------------------------------------------------------------------+
//|                                                    StarterEA.mq5 |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "Starter EA with Modular Risk Management, Signal Engine, and Trade Execution"

//+------------------------------------------------------------------+
//| Include Modules                                                  |
//+------------------------------------------------------------------+
#include "..\include\Defines.mqh"
#include "..\include\RiskManager.mqh"
#include "..\include\TradeExecution.mqh"
#include "..\include\SignalEngine.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ulong             InpMagicNumber       = 888101;           // Magic Number (Unique ID)
input string            InpTradeComment      = "StarterEA-v1";   // Trade Comment
input int               InpSlippagePoints    = 10;               // Maximum Slippage (Points)

input group "=== Risk Management ==="
input ENUM_LOT_MODE     InpLotMode           = LOT_PERCENTAGE_RISK; // Lot Calculation Mode
input double            InpFixedLot          = 0.01;             // Fixed Lot Size
input double            InpRiskPercent       = 1.0;              // Risk % of Equity per Trade
input double            InpStopLossPoints    = 200.0;            // Stop Loss in Points (10 pips = 100 pts)
input double            InpTakeProfitPoints  = 400.0;            // Take Profit in Points (20 pips = 200 pts)
input int               InpMaxSpreadPoints   = 35;               // Max Allowed Spread in Points
input double            InpMaxDailyLossPct   = 5.0;              // Max Daily Drawdown % (0 to disable)

input group "=== Strategy Parameters ==="
input ENUM_TIMEFRAMES   InpTimeframe         = PERIOD_H1;        // Strategy Timeframe
input int               InpFastMAPeriod      = 9;                // Fast EMA Period
input int               InpSlowMAPeriod      = 21;               // Slow EMA Period
input int               InpRSIPeriod         = 14;               // RSI Period
input double            InpRSIOverbought     = 70.0;             // RSI Overbought Level
input double            InpRSISold           = 30.0;             // RSI Oversold Level

//+------------------------------------------------------------------+
//| Global Objects                                                   |
//+------------------------------------------------------------------+
CRiskManager    ExtRisk;
CTradeExecution ExtTrade;
CSignalEngine   ExtSignal;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [StarterEA] Initializing EA ===");

   // 1. Validate parameter ranges
   if(InpFastMAPeriod >= InpSlowMAPeriod)
   {
      Alert("[StarterEA] Error: Fast MA Period must be smaller than Slow MA Period!");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0)
   {
      Alert("[StarterEA] Warning: Risk percentage should be between 0.1% and 10%!");
      return INIT_PARAMETERS_INCORRECT;
   }

   // 2. Initialize Trade Execution module
   if(!ExtTrade.Init(InpMagicNumber, InpSlippagePoints))
   {
      Print("[StarterEA] Failed to initialize TradeExecution module!");
      return INIT_FAILED;
   }

   // 3. Initialize Signal Engine indicator handles
   if(!ExtSignal.Init(_Symbol, InpTimeframe, InpFastMAPeriod, InpSlowMAPeriod, InpRSIPeriod))
   {
      Print("[StarterEA] Failed to initialize SignalEngine handles!");
      return INIT_FAILED;
   }

   PrintFormat("[StarterEA] Init SUCCEEDED on %s (%s). Ready to trade.", _Symbol, EnumToString(InpTimeframe));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("=== [StarterEA] Deinitialized. Reason code: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Spread filter check
   if(!ExtRisk.IsSpreadAcceptable(_Symbol, InpMaxSpreadPoints))
      return;

   // 2. Daily drawdown check
   if(!ExtRisk.CheckDailyDrawdown(InpMaxDailyLossPct))
      return;

   // 3. Trade on completed candle/bar to avoid intra-bar false noise
   if(!ExtSignal.IsNewBar(_Symbol, InpTimeframe))
      return;

   // 4. One trade at a time for this strategy (per symbol & magic number)
   if(ExtTrade.CountOpenPositions(_Symbol) > 0)
      return;

   // 5. Evaluate trading signal
   ENUM_SIGNAL_TYPE signal = ExtSignal.CheckSignal(_Symbol, InpTimeframe, InpRSIOverbought, InpRSISold);
   if(signal == SIGNAL_NONE)
      return;

   // 6. Calculate dynamic lot size from risk manager
   double lot = ExtRisk.CalculateLotSize(_Symbol, InpLotMode, InpFixedLot, InpRiskPercent, InpStopLossPoints);

   // 7. Execute order
   if(signal == SIGNAL_BUY)
   {
      ExtTrade.OpenBuy(_Symbol, lot, InpStopLossPoints, InpTakeProfitPoints, InpTradeComment);
   }
   else if(signal == SIGNAL_SELL)
   {
      ExtTrade.OpenSell(_Symbol, lot, InpStopLossPoints, InpTakeProfitPoints, InpTradeComment);
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                             MTFStructureEA.mq5   |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "Multi-Timeframe SMC EA with Whitelisted TFs, Event-Driven Candle Close, and Smart SL/BE"

//+------------------------------------------------------------------+
//| Modular Includes                                                 |
//+------------------------------------------------------------------+
#include "..\include\MTFStructure\MTFStructureEngine.mqh"
#include "..\include\TradeManager\SmartTradeManager.mqh"
#include "..\include\Strategy\M3SMCStrategy.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General & Risk Settings ==="
input ulong             InpMagicNumber       = 888103;          // Magic Number
input double            InpRiskPercent       = 1.0;             // Risk % of Equity per Trade
input double            InpMaxDailyLossPct   = 5.0;             // Max Daily Drawdown % (0 to disable)
input int               InpMaxSpreadPoints   = 30;              // Max Allowed Spread (Points)
input int               InpSlippagePoints    = 10;              // Deviation / Slippage (Points)

input group "=== Smart SL & Breakeven ==="
input double            InpTP1Points         = 150.0;           // Distance to trigger BE (Points)
input double            InpBEBufferPoints    = 20.0;            // BE Profit Lock Buffer (Points)

input group "=== Strategy Engines Whitelist ==="
input bool              InpEnableM3Strategy  = true;            // Enable M3 SMC Pullback Engine

//+------------------------------------------------------------------+
//| Global Modular Components                                        |
//+------------------------------------------------------------------+
CMTFStructureEngine     ExtStructure;
CSmartTradeManager      ExtTradeManager;
CM3SMCStrategy          ExtM3Strategy(888103);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [MTFStructureEA] Initializing ===");

   // 1. Initialize Smart Trade Manager
   if(!ExtTradeManager.Init(InpMagicNumber, InpMaxDailyLossPct, InpSlippagePoints))
   {
      Print("[MTFStructureEA] Error: Failed to initialize SmartTradeManager!");
      return INIT_FAILED;
   }

   // 2. Selectively Register Timeframes (Whitelist - Point 1 & 2)
   ExtStructure.RegisterTimeframe(PERIOD_H1,  ROLE_HTF_BIAS);
   ExtStructure.RegisterTimeframe(PERIOD_M15, ROLE_HTF_BIAS);
   ExtStructure.RegisterTimeframe(PERIOD_M3,  ROLE_SETUP_BASE);
   ExtStructure.RegisterTimeframe(PERIOD_M1,  ROLE_LTF_TRIGGER);

   // 3. Configure Strategy Engine
   ExtM3Strategy.SetEnabled(InpEnableM3Strategy);

   // 4. Start 1-second Timer for OnTimer Housekeeping (Point 4)
   EventSetTimer(1);

   PrintFormat("[MTFStructureEA] Initialized on %s. Active Engines: %s", 
               _Symbol, InpEnableM3Strategy ? "M3-SMC" : "None");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("=== [MTFStructureEA] Deinitialized (Reason: %d) ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function (Ultra-Light Real-Time Execution)           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Update Market Structure ONLY on Candle Close (Never every tick for HTF)
   ExtStructure.UpdateOnCandleClose(_Symbol);

   // 2. Real-Time SL / BE Trailing and Drawdown Protection
   ExtTradeManager.OnTickManage(_Symbol, InpTP1Points, InpBEBufferPoints);

   // 3. One position at a time for this strategy
   if(PositionsTotal() > 0)
      return;

   // 4. Evaluate Entry Engines
   if(ExtM3Strategy.IsEnabled())
   {
      ExtM3Strategy.EvaluateEntry(_Symbol, ExtStructure, ExtTradeManager, InpRiskPercent, InpMaxSpreadPoints);
   }
}

//+------------------------------------------------------------------+
//| Periodic Timer function (Session Tracking & EOD Force Exit)      |
//+------------------------------------------------------------------+
void OnTimer()
{
   ExtTradeManager.OnTimerHousekeeping(_Symbol);
}
//+------------------------------------------------------------------+

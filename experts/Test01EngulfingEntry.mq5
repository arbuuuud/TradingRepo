//+------------------------------------------------------------------+
//|                                        Test01EngulfingEntry.mq5  |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "Test01: M3 Engulfing at Fib 0.382/0.618 with M1 Confirmation and M15+H1 Trend Alignment"

//+------------------------------------------------------------------+
//| Modular Includes                                                 |
//+------------------------------------------------------------------+
#include "..\include\MTFStructure\MTFStructureEngine.mqh"
#include "..\include\TradeManager\SmartTradeManager.mqh"
#include "..\include\Strategy\EngulfingStrategy.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General & Risk Settings ==="
input ulong                InpMagicNumber          = 888201;          // Magic Number
input double               InpRiskPercent          = 1.0;             // Risk % of Equity per Trade
input double               InpMaxDailyLossPct      = 5.0;             // Max Daily Loss % (0 to disable)
input int                  InpMaxSpreadPoints      = 30;              // Max Allowed Spread (Points)
input int                  InpSlippagePoints       = 10;              // Slippage Deviation (Points)

input group "=== Fibonacci & Strategy Settings ==="
input ENUM_FIBO_SOURCE_TF  InpFiboSource           = FIBO_FROM_M3;    // Structure TF for Fibonacci (M3 or M15)
input double               InpFibTolerancePoints   = 30.0;            // Fib Level Touch Tolerance (Points)
input double               InpRiskRewardRatio      = 2.0;             // Take Profit Risk:Reward Ratio

input group "=== Smart Trade Management ==="
input double               InpTP1Points            = 150.0;           // Profit Points to trigger Breakeven
input double               InpBEBufferPoints       = 20.0;            // Breakeven Buffer Points

//+------------------------------------------------------------------+
//| Global Components                                                |
//+------------------------------------------------------------------+
CMTFStructureEngine        ExtStructure;
CSmartTradeManager         ExtTradeManager;
CEngulfingStrategy         ExtStrategy(888201);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [Test01EngulfingEntry] Initializing EA ===");

   // 1. Initialize Smart Trade Manager
   if(!ExtTradeManager.Init(InpMagicNumber, InpMaxDailyLossPct, InpSlippagePoints))
   {
      Print("[Test01EngulfingEntry] Error initializing SmartTradeManager!");
      return INIT_FAILED;
   }

   // 2. Selectively Register Timeframes (Whitelist)
   ExtStructure.RegisterTimeframe(PERIOD_H1,  ROLE_HTF_BIAS);
   ExtStructure.RegisterTimeframe(PERIOD_M15, ROLE_HTF_BIAS);
   ExtStructure.RegisterTimeframe(PERIOD_M3,  ROLE_SETUP_BASE);
   ExtStructure.RegisterTimeframe(PERIOD_M1,  ROLE_LTF_TRIGGER);

   // 3. Configure Strategy Engine
   ExtStrategy.Configure(InpFiboSource, InpFibTolerancePoints, InpRiskRewardRatio);
   ExtStrategy.SetEnabled(true);

   // 4. Start 1-second Housekeeping Timer
   EventSetTimer(1);

   PrintFormat("[Test01EngulfingEntry] Init SUCCEEDED on %s. Setup TF: M3, Trigger TF: M1, Bias: H1+M15", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("=== [Test01EngulfingEntry] Deinitialized (Reason: %d) ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Update Market Structure ONLY on Candle Close of registered TFs
   ExtStructure.UpdateOnCandleClose(_Symbol);

   // 2. Real-Time SL / BE Trailing and Drawdown Protection
   ExtTradeManager.OnTickManage(_Symbol, InpTP1Points, InpBEBufferPoints);

   // 3. One position at a time for this strategy
   if(PositionsTotal() > 0)
      return;

   // 4. Evaluate Entry: M3 Engulfing at Fib 0.382/0.618 with M1 Engulfing confirmation
   ExtStrategy.EvaluateEntry(_Symbol, ExtStructure, ExtTradeManager, InpRiskPercent, InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Housekeeping: Session tracking & EOD 23:55 force exit
   ExtTradeManager.OnTimerHousekeeping(_Symbol);
}
//+------------------------------------------------------------------+

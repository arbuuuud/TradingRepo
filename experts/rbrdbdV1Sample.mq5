//+------------------------------------------------------------------+
//|                                           rbrdbdV1Sample.mq5     |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "2.00"
#property description "Pure M1 RBR (Demand) & DBD (Supply) Visualizer EA"

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include "..\include\arbud\structure\rbrdbdV1.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== M1 RBR/DBD Parameters ==="
input int               InpMinBaseM1         = 1;                 // Min Base Candles (1~5)
input int               InpMaxBaseM1         = 5;                 // Max Base Candles (1~5)
input double            InpLegRatioM1        = 1.0;               // Min Leg-Out vs Base Ratio (1.0 = equal)
input int               InpHistoryBars       = 500;               // History Bars to Scan on Init

input group "=== Visual Colors ==="
input color             InpColorFreshRBR     = clrMediumSeaGreen; // Fresh RBR (Demand)
input color             InpColorFreshDBD     = clrCrimson;        // Fresh DBD (Supply)
input color             InpColorUsed         = clrSandyBrown;     // Retested/Used Zone (1% - 99%)
input color             InpColorMitigated    = clrGray;           // Fully Mitigated Zone (100% Breached)

//+------------------------------------------------------------------+
//| Global Object                                                    |
//+------------------------------------------------------------------+
CRBRDBDV1 ExtRBRDBD;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [rbrdbdV1Sample] Initializing Pure M1 RBR/DBD Engine ===");

   // 1. Register Main Timeframe: M1
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1, 
                               InpMinBaseM1, 
                               InpMaxBaseM1, 
                               InpLegRatioM1, 
                               true, 
                               InpColorFreshRBR, 
                               InpColorFreshDBD, 
                               InpColorUsed, 
                               InpColorMitigated);

   // 2. Scan history bars and evaluate retests
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars);

   PrintFormat("[rbrdbdV1Sample] Initialized on %s (PERIOD_M1). Total active zones: %d", 
               _Symbol, ExtRBRDBD.GetValidAreasCount(PERIOD_M1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all rectangle boxes and text labels
   ExtRBRDBD.ClearChartObjects();
   PrintFormat("=== [rbrdbdV1Sample] Deinitialized. Objects cleared. Reason: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Event-driven update on completed candle close
   ExtRBRDBD.UpdateOnCandleClose(_Symbol);

   // 2. Real-time consumption update on live price tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask);
}
//+------------------------------------------------------------------+

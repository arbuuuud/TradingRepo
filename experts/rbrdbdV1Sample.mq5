//+------------------------------------------------------------------+
//|                                           rbrdbdV1Sample.mq5     |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "Multi-Timeframe RBR & DBD Sample EA with Dynamic Consumption Tracking (0% to 100%)"

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include "..\include\arbud\structure\rbrdbdV1.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Timeframe Selection (PeriodList) ==="
input bool              InpEnableM3          = true;            // Enable M3 Detection
input int               InpMinBaseM3         = 1;               // M3 Min Base Candles (1~9)
input int               InpMaxBaseM3         = 5;               // M3 Max Base Candles (1~9)
input double            InpLegRatioM3        = 1.0;             // M3 Min Leg-Out vs Base Ratio
input bool              InpDrawM3            = true;            // Draw M3 on Chart
input bool              InpDrawRoofFloorM3   = true;            // Draw Roof & Floor Channel M3

input bool              InpEnableM15         = false;           // Enable M15 Detection
input int               InpMinBaseM15        = 1;               // M15 Min Base Candles (1~9)
input int               InpMaxBaseM15        = 7;               // M15 Max Base Candles (1~9)
input double            InpLegRatioM15       = 1.0;             // M15 Min Leg-Out vs Base Ratio
input bool              InpDrawM15           = false;           // Draw M15 on Chart
input bool              InpDrawRoofFloorM15  = false;           // Draw Roof & Floor Channel M15

input group "=== Visual Colors ==="
input color             InpColorRBR          = clrMediumSeaGreen; // Fresh RBR (Demand)
input color             InpColorDBD          = clrCrimson;        // Fresh DBD (Supply)
input color             InpColorRoof         = clrIndianRed;      // Roof Top Border
input color             InpColorFloor        = clrLimeGreen;      // Floor Bottom Border

input group "=== History Scanning ==="
input int               InpHistoryBars       = 500;             // History Bars to Scan on Init

//+------------------------------------------------------------------+
//| Global Object                                                    |
//+------------------------------------------------------------------+
CRBRDBDV1 ExtRBRDBD;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [rbrdbdV1Sample] Initializing EA ===");

   // 1. Register selective timeframes (PeriodList)
   if(InpEnableM3)
   {
      ExtRBRDBD.RegisterTimeframe(PERIOD_M3, InpMinBaseM3, InpMaxBaseM3, InpLegRatioM3, InpDrawM3, InpDrawRoofFloorM3, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   }

   if(InpEnableM15)
   {
      ExtRBRDBD.RegisterTimeframe(PERIOD_M15, InpMinBaseM15, InpMaxBaseM15, InpLegRatioM15, InpDrawM15, InpDrawRoofFloorM15, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   }

   // 2. Scan historical bars and track past & current consumption
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars);

   PrintFormat("[rbrdbdV1Sample] Initialized on %s. Active M3 zones: %d", 
               _Symbol, ExtRBRDBD.GetValidAreasCount(PERIOD_M3));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all rectangle boxes and text labels
   ExtRBRDBD.ClearChartObjects();
   PrintFormat("=== [rbrdbdV1Sample] Deinitialized. Reason: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Event-driven update on completed candle close (scans new zones & closed bar retests)
   ExtRBRDBD.UpdateOnCandleClose(_Symbol);

   // 2. Real-time consumption update on live price tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask);
}
//+------------------------------------------------------------------+

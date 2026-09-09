//+------------------------------------------------------------------+
//|                                         StructureV1Sample.mq5    |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "StructureV1Sample: Visual test and standalone demonstrator for CStructureV0"

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include "..\include\arbud\structure\StructureV0.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Timeframe Selection (PeriodList) ==="
input bool              InpEnableM3          = true;            // Enable M3 Timeframe
input color             InpColorM3           = clrDodgerBlue;   // M3 Line Color
input int               InpWidthM3           = 2;               // M3 Line Width
input bool              InpDrawM3            = true;            // Draw M3 on Chart

input bool              InpEnableM15         = false;           // Enable M15 Timeframe
input color             InpColorM15          = clrGold;         // M15 Line Color
input int               InpWidthM15          = 2;               // M15 Line Width
input bool              InpDrawM15           = false;           // Draw M15 on Chart

input group "=== History Scanning ==="
input int               InpHistoryBars       = 500;             // History Bars to Scan on Init

//+------------------------------------------------------------------+
//| Global Object                                                    |
//+------------------------------------------------------------------+
CStructureV0 ExtStructure;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [StructureV1Sample] Initializing EA ===");

   // 1. Register selective timeframes (PeriodList)
   if(InpEnableM3)
   {
      ExtStructure.RegisterTimeframe(PERIOD_M3, InpColorM3, InpWidthM3, InpDrawM3);
   }

   if(InpEnableM15)
   {
      ExtStructure.RegisterTimeframe(PERIOD_M15, InpColorM15, InpWidthM15, InpDrawM15);
   }

   // 2. Scan historical bars and draw structure directly to chart
   ExtStructure.InitHistory(_Symbol, InpHistoryBars);

   PrintFormat("[StructureV1Sample] Initialized on %s. M3 Structures count: %d", 
               _Symbol, ExtStructure.GetStructuresCount(PERIOD_M3));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all visual lines and texts from chart
   ExtStructure.ClearChartObjects();
   PrintFormat("=== [StructureV1Sample] Deinitialized. Reason: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Event-driven update: only recalculates and redraws when candle close on registered TFs
   ExtStructure.UpdateOnCandleClose(_Symbol);
}
//+------------------------------------------------------------------+

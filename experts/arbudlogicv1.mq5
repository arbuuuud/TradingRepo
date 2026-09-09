//+------------------------------------------------------------------+
//|                                                arbudlogicv1.mq5  |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "arbudlogicv1: Main TF M1 - Structure M1, RBR/DBD M1, and Transaction Areas"

//+------------------------------------------------------------------+
//| Modular Includes                                                 |
//+------------------------------------------------------------------+
#include "..\include\arbud\structure\StructureV1.mqh"
#include "..\include\arbud\structure\rbrdbdV1.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input int               InpHistoryBars       = 500;             // History Bars to Scan on Init

input group "=== M1 Structure Settings ==="
input bool              InpEnableStructM1    = true;            // Enable M1 Structure Detection
input bool              InpDrawStructM1      = true;            // Draw M1 Structure on Chart
input color             InpColorStructM1     = clrDodgerBlue;   // M1 Structure Line Color
input int               InpWidthStructM1     = 1;               // M1 Structure Line Width

input group "=== M1 RBR / DBD Settings ==="
input bool              InpEnableRbrDbdM1    = true;            // Enable M1 RBR/DBD Detection
input bool              InpDrawRbrDbdM1      = true;            // Draw M1 RBR/DBD Rectangles on Chart
input bool              InpDrawRoofFloorM1   = true;            // Draw M1 Transaction Areas (Floor/Roof)
input int               InpMinBaseM1         = 1;               // M1 Min Base Candles (1~9)
input int               InpMaxBaseM1         = 5;               // M1 Max Base Candles (1~9)
input double            InpLegRatioM1        = 1.0;             // M1 Min Leg-Out vs Base Ratio

input group "=== Visual Colors ==="
input color             InpColorRBR          = clrMediumSeaGreen; // Fresh RBR (Demand)
input color             InpColorDBD          = clrCrimson;        // Fresh DBD (Supply)
input color             InpColorRoof         = clrIndianRed;      // 100% Roof Border
input color             InpColorFloor        = clrLimeGreen;      // 0% Floor Border

//+------------------------------------------------------------------+
//| Global Component Objects                                         |
//+------------------------------------------------------------------+
CStructureV1 ExtStructure;
CRBRDBDV1    ExtRBRDBD;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [arbudlogicv1] Initializing EA (Main TF: M1) ===");

   // ----------------------------------------------------------------
   // 1. Structure Registration (M1 - Active & Drawn, M3/M15/H1 background for fallback)
   // ----------------------------------------------------------------
   ExtStructure.RegisterTimeframe(PERIOD_M1,  InpColorStructM1, InpWidthStructM1, InpDrawStructM1);
   ExtStructure.RegisterTimeframe(PERIOD_M3,  clrDodgerBlue,    1, false);
   ExtStructure.RegisterTimeframe(PERIOD_M15, clrGold,          1, false);
   ExtStructure.RegisterTimeframe(PERIOD_H1,  clrOrange,        1, false);

   // ----------------------------------------------------------------
   // 2. RBR / DBD Registration (M1 - Active & Drawn, M3/M15/H1 background for fallback)
   // ----------------------------------------------------------------
   // M1: Draw RBR/DBD boxes + Draw Transaction Area Roof/Floor
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1,  InpMinBaseM1, InpMaxBaseM1, InpLegRatioM1, 
                               InpDrawRbrDbdM1, InpDrawRoofFloorM1, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);

   // M3, M15, H1: Calculated in background for fallback hierarchy
   ExtRBRDBD.RegisterTimeframe(PERIOD_M3,  1, 5, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_M15, 1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_H1,  1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);

   // ----------------------------------------------------------------
   // 3. Scan History on Init
   // ----------------------------------------------------------------
   ExtStructure.InitHistory(_Symbol, InpHistoryBars);
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars, &ExtStructure);

   PrintFormat("[arbudlogicv1] Init Succeeded on %s (Main TF: M1).", _Symbol);
   PrintFormat("Structure M1: %d swings | RBR/DBD M1: %d zones.",
               ExtStructure.GetStructuresCount(PERIOD_M1),
               ExtRBRDBD.GetValidAreasCount(PERIOD_M1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all visual objects
   ExtStructure.ClearChartObjects();
   ExtRBRDBD.ClearChartObjects();
   PrintFormat("=== [arbudlogicv1] Deinitialized. Reason: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Event-driven update on completed candle close (M1, M3, M15, H1)
   ExtStructure.UpdateOnCandleClose(_Symbol);
   ExtRBRDBD.UpdateOnCandleClose(_Symbol, &ExtStructure);

   // 2. Real-time consumption & Transaction Area update on tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask, &ExtStructure);
}
//+------------------------------------------------------------------+

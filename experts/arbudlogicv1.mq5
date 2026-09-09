//+------------------------------------------------------------------+
//|                                                arbudlogicv1.mq5  |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "arbudlogicv1: Multi-Timeframe Structure & RBR/DBD Roof-Floor EA (Main TF: M1)"

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

input group "=== Structure Visual Settings (Only M3 Drawn) ==="
input color             InpColorStructM3     = clrDodgerBlue;   // M3 Structure Line Color
input int               InpWidthStructM3     = 2;               // M3 Structure Line Width

input group "=== Roof & Floor Channel Colors ==="
input color             InpColorRoofM1       = clrLightPink;    // M1 Roof Line Color
input color             InpColorFloorM1      = clrLightGreen;   // M1 Floor Line Color

input color             InpColorRoofM3       = clrSalmon;       // M3 Roof Line Color
input color             InpColorFloorM3      = clrMediumSeaGreen; // M3 Floor Line Color

input color             InpColorRoofM15      = clrIndianRed;    // M15 Roof Line Color
input color             InpColorFloorM15     = clrSeaGreen;     // M15 Floor Line Color

input color             InpColorRoofH1       = clrFireBrick;    // H1 Roof Line Color
input color             InpColorFloorH1      = clrDarkGreen;    // H1 Floor Line Color

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
   // 1. Structure Registration (M1, M3, M15, H1)
   // Hanya M3 yang digambar di chart (drawOnChart = true)
   // ----------------------------------------------------------------
   ExtStructure.RegisterTimeframe(PERIOD_M1,  clrWhiteSmoke,    1, false); // M1: hitung saja, jangan gambar
   ExtStructure.RegisterTimeframe(PERIOD_M3,  InpColorStructM3, InpWidthStructM3, true); // M3: DIGAMBAR
   ExtStructure.RegisterTimeframe(PERIOD_M15, clrGold,          1, false); // M15: hitung saja, jangan gambar
   ExtStructure.RegisterTimeframe(PERIOD_H1,  clrOrange,        1, false); // H1: hitung saja, jangan gambar

   // ----------------------------------------------------------------
   // 2. RBR / DBD Registration (M1, M3, M15, H1)
   // drawOnChart = false (jangan gambar individual RBR/DBD rect)
   // drawRoofFloor = true (hanya gambar Roof & Floor channel)
   // ----------------------------------------------------------------
   // M1
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1,  1, 5, 1.0, false, true, clrSeaGreen, clrIndianRed, InpColorRoofM1,  InpColorFloorM1);
   // M3
   ExtRBRDBD.RegisterTimeframe(PERIOD_M3,  1, 5, 1.0, false, true, clrSeaGreen, clrIndianRed, InpColorRoofM3,  InpColorFloorM3);
   // M15
   ExtRBRDBD.RegisterTimeframe(PERIOD_M15, 1, 7, 1.0, false, true, clrSeaGreen, clrIndianRed, InpColorRoofM15, InpColorFloorM15);
   // H1
   ExtRBRDBD.RegisterTimeframe(PERIOD_H1,  1, 7, 1.0, false, true, clrSeaGreen, clrIndianRed, InpColorRoofH1,  InpColorFloorH1);

   // ----------------------------------------------------------------
   // 3. Scan History on Init
   // ----------------------------------------------------------------
   ExtStructure.InitHistory(_Symbol, InpHistoryBars);
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars);

   PrintFormat("[arbudlogicv1] Init Succeeded on %s. Main TF: M1.", _Symbol);
   PrintFormat("Structure: M1(%d), M3(%d - drawn), M15(%d), H1(%d)",
               ExtStructure.GetStructuresCount(PERIOD_M1),
               ExtStructure.GetStructuresCount(PERIOD_M3),
               ExtStructure.GetStructuresCount(PERIOD_M15),
               ExtStructure.GetStructuresCount(PERIOD_H1));
   PrintFormat("Roof-Floor Channels: M1, M3, M15, H1 active.");

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
   ExtRBRDBD.UpdateOnCandleClose(_Symbol);

   // 2. Real-time consumption & Roof-Floor update on tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask);
}
//+------------------------------------------------------------------+

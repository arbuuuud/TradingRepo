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

input group "=== Phase 2 Modular Testing Switches ==="
input bool              InpEnablePhase2_1    = true;              // Enable Phase 2.1 (Base Tightness & MTF Refl)
input bool              InpEnablePhase2_2    = true;              // Enable Phase 2.2 (Origin TF BOS Body Close)
input bool              InpEnablePhase2_3    = true;              // Enable Phase 2.3 (Origin TF Direct Attached FVG)
input bool              InpEnablePhase2_4A   = true;              // Enable Phase 2.4A (HTF RBR/DBD Parent Reaction)
input bool              InpEnablePhase2_4B   = true;              // Enable Phase 2.4B (HTF Swing High/Low Reaction)
input double            InpMinFVGGapPoints   = 50.0;              // Min FVG Gap in Points (50 pts = $0.50)

input group "=== Dynamic Memory & Garbage Collection ==="
input bool              InpEnableGC          = true;              // Enable Dynamic Garbage Collection
input int               InpMaxMemoryBars     = 1500;              // Max Zone Age in M1 Bars before Purge
input double            InpPurgeDistMult     = 3.0;               // Purge Mitigated Zone if Price > N * Height

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

   // 0. Configure Phase 2 Modular Test Switches
   ExtRBRDBD.SetPhase2Switches(InpEnablePhase2_1, InpEnablePhase2_2, InpEnablePhase2_3, InpEnablePhase2_4A, InpEnablePhase2_4B, InpMinFVGGapPoints);

   // 1. Register Timeframes: M1 (Main Visible) + M15 & H1 (HTF Parent Reference)
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1, 
                               InpMinBaseM1, 
                               InpMaxBaseM1, 
                               InpLegRatioM1, 
                               true, 
                               InpColorFreshRBR, 
                               InpColorFreshDBD, 
                               InpColorUsed, 
                               InpColorMitigated);

   // HTF Parent Reference Timeframes (Silent, draw=false)
   ExtRBRDBD.RegisterTimeframe(PERIOD_M15, 1, 5, 1.0, false);
   ExtRBRDBD.RegisterTimeframe(PERIOD_H1,  1, 5, 1.0, false);

   // 2. Scan history bars and evaluate retests for all registered timeframes
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
   static datetime lastM1Bar = 0;
   datetime currentM1Bar = iTime(_Symbol, PERIOD_M1, 0);

   // 1. Event-driven update on completed candle close
   if(currentM1Bar != lastM1Bar)
   {
      lastM1Bar = currentM1Bar;
      ExtRBRDBD.UpdateOnCandleClose(_Symbol);

      // Run dynamic garbage collection once per completed bar
      if(InpEnableGC)
      {
         double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         int purged = ExtRBRDBD.RunGarbageCollection(_Symbol, curPrice, InpMaxMemoryBars, InpPurgeDistMult);
         if(purged > 0)
         {
            PrintFormat("[rbrdbdV1Sample] Garbage Collector purged %d old/mitigated zones.", purged);
         }
      }
   }

   // 2. Real-time consumption update on live price tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask);

   // 3. Update Chart HUD Info
   SRBRDBDArea areas[];
   if(ExtRBRDBD.GetAreas(PERIOD_M1, areas))
   {
      int total = ArraySize(areas);
      int active = 0, escalated = 0, p21Passed = 0, bosPassed = 0, fvgPassed = 0, htfZonePassed = 0, htfSwingPassed = 0, htfPOIPassed = 0;
      int countStr0 = 0, countStr1 = 0, countStr2 = 0;
      for(int i = 0; i < total; i++)
      {
         if(!areas[i].isInvalid) active++;
         if(areas[i].isEscalated) escalated++;
         if(areas[i].scorePhase2_1 > 0) p21Passed++;
         if(areas[i].scorePhase2_2 > 0) bosPassed++;
         if(areas[i].scorePhase2_3 > 0) fvgPassed++;
         if(areas[i].scorePhase2_4A > 0) htfZonePassed++;
         if(areas[i].scorePhase2_4B > 0) htfSwingPassed++;
         if(areas[i].passHTFPOI)        htfPOIPassed++;

         if(areas[i].strengthLevel == 2) countStr2++;
         else if(areas[i].strengthLevel == 1) countStr1++;
         else countStr0++;
      }

      string modeHeader;
      if(InpEnablePhase2_4B && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4A)
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2.4B ISOLATED: HTF SWING STRUCTURE REACTION ONLY) ===";
      else if(InpEnablePhase2_4A && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4B)
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2.4A ISOLATED: HTF RBR/DBD REACTION ONLY) ===";
      else if(InpEnablePhase2_3 && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_4A && !InpEnablePhase2_4B)
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2.3 ISOLATED: DIRECT ATTACHED FVG ONLY) ===";
      else if(!InpEnablePhase2_1 && InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4A && !InpEnablePhase2_4B)
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2.2 ISOLATED: BOS ONLY) ===";
      else if(InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4A && !InpEnablePhase2_4B)
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2.1 ISOLATED: TIGHTNESS ONLY) ===";
      else
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2 COMBINED: 4-STAR & DNA TBFH MODE) ===";

      string qualityBreakdown;
      if(InpEnablePhase2_4B && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4A)
         qualityBreakdown = StringFormat("HTF Swing Pass Rate: %d / %d Zones (%.1f%%) [Pivot M15/H1 <= 50pts]", 
                                         htfSwingPassed, total, total > 0 ? (htfSwingPassed * 100.0 / total) : 0.0);
      else if(InpEnablePhase2_4A && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4B)
         qualityBreakdown = StringFormat("HTF Zone Pass Rate: %d / %d Zones (%.1f%%) [Parent M15/H1]", 
                                         htfZonePassed, total, total > 0 ? (htfZonePassed * 100.0 / total) : 0.0);
      else if(InpEnablePhase2_3 && !InpEnablePhase2_1 && !InpEnablePhase2_2 && !InpEnablePhase2_4A && !InpEnablePhase2_4B)
         qualityBreakdown = StringFormat("FVG Pass Rate: %d / %d Zones (%.1f%%) [MinGap: %.0f pts]", 
                                         fvgPassed, total, total > 0 ? (fvgPassed * 100.0 / total) : 0.0, InpMinFVGGapPoints);
      else if(!InpEnablePhase2_1 && InpEnablePhase2_2 && !InpEnablePhase2_3 && !InpEnablePhase2_4A && !InpEnablePhase2_4B)
         qualityBreakdown = StringFormat("BOS Pass Rate: %d / %d Zones (%.1f%%)", bosPassed, total, total > 0 ? (bosPassed * 100.0 / total) : 0.0);
      else
         qualityBreakdown = StringFormat("Pillars: [T]:%d | [B]:%d | [F]:%d | [H]:%d\n" +
                                         "Strength: Str0(Weak):%d | Str1(Mod):%d | Str2(A+):%d (Total:%d)", 
                                         p21Passed, bosPassed, fvgPassed, htfPOIPassed, countStr0, countStr1, countStr2, total);

      Comment(StringFormat("%s\n" +
                           "Total Zones: %d | Active: %d | Escalated (M3/M5): %d\n" +
                           "%s\n" +
                           "Garbage Collection: %s (MaxBars: %d, DistMult: %.1f)\n" +
                           "Live Bid: %.2f | Ask: %.2f",
                           modeHeader,
                           total, active, escalated,
                           qualityBreakdown,
                           InpEnableGC ? "ENABLED" : "DISABLED", InpMaxMemoryBars, InpPurgeDistMult,
                           bid, ask));
   }
}
//+------------------------------------------------------------------+

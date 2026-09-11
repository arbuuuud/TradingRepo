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
#include "..\include\arbud\structure\LivingTradingArea.mqh"
#include "..\include\arbud\trade\ProactiveLimitPlacer.mqh"

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

input group "=== Phase 3 Dynamic Buffer Calculation ==="
input bool              InpEnablePhase3      = true;              // Enable Phase 3 Dynamic Buffer (10-Sw vs 2xBase)

input group "=== Phase 4 Living TradingArea & Exhaustion ==="
input bool              InpEnablePhase4      = true;              // Enable Phase 4 Living TradingArea Corridor
input bool              InpDrawTradingArea   = true;              // Draw TradingArea (Buy/Sell Boxes, TP50, Hard SL)
input bool              InpHideZoneRectangles= true;              // Hide RBR/DBD Rectangles (Show Labels & TradingArea only)

input group "=== Phase 5 Proactive Limit Order Placer ==="
input bool              InpEnablePhase5      = true;              // Enable Phase 5 Proactive Limit Grid
input int               InpMaxPosPerSide     = 5;                 // Max Positions at Fresh L0 (1~10)
input double            InpFixedLot          = 0.01;              // Fixed Lot per Limit Order
input ulong             InpMagicNumber       = 888222;            // EA Magic Number

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
CRBRDBDV1                 ExtRBRDBD;
CLivingTradingAreaManager ExtTradingArea;
CProactiveLimitPlacer     ExtLimitPlacer;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [rbrdbdV1Sample] Initializing Pure M1 RBR/DBD Engine ===");

   // 0. Configure Phase 2 & 3 Modular Test Switches
   ExtRBRDBD.SetPhase2Switches(InpEnablePhase2_1, InpEnablePhase2_2, InpEnablePhase2_3, InpEnablePhase2_4A, InpEnablePhase2_4B, InpMinFVGGapPoints);
   ExtRBRDBD.SetPhase3Switch(InpEnablePhase3);
   ExtRBRDBD.SetHideRectangles(InpHideZoneRectangles);

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

   // 3. Configure TradingArea Manager
   ExtTradingArea.SetDrawEnabled(InpDrawTradingArea);
   ExtTradingArea.SetBaseTF(PERIOD_M1);

   // 4. Configure Proactive Limit Placer
   ExtLimitPlacer.Init(_Symbol, InpMagicNumber, InpMaxPosPerSide, InpFixedLot);

   PrintFormat("[rbrdbdV1Sample] Initialized on %s (PERIOD_M1). Total active zones: %d", 
               _Symbol, ExtRBRDBD.GetValidAreasCount(PERIOD_M1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all rectangle boxes, text labels, and TradingArea objects
   ExtRBRDBD.ClearChartObjects();
   ExtTradingArea.ClearChartObjects();

   // Cancel any pending limit orders when removed
   ExtLimitPlacer.CancelAllPendingOrders();

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

      // 4. Proactive Limit Order Placement & Management (Phase 5)
      // Placed strictly on candle close / new bar to prevent tick-level spamming!
      if(InpEnablePhase4 && InpEnablePhase5)
      {
         double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         ExtLimitPlacer.ManageLimitGrids(ExtTradingArea.GetActiveArea(), curBid, curAsk);
      }
   }

   // 2. Real-time consumption update on live price tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask);

   // 3. Update Living TradingArea & Exhaustion State Machine (Phase 4)
   if(InpEnablePhase4)
   {
      ExtTradingArea.UpdateTradingArea(_Symbol, ExtRBRDBD, bid, ask);
   }

   // 5. Update Chart HUD Info
   SRBRDBDArea areas[];
   if(ExtRBRDBD.GetAreas(PERIOD_M1, areas))
   {
      int total = ArraySize(areas);
      int active = 0, escalated = 0, p21Passed = 0, bosPassed = 0, fvgPassed = 0, htfZonePassed = 0, htfSwingPassed = 0, htfPOIPassed = 0;
      int countStr0 = 0, countStr1 = 0, countStr2 = 0;
      int countBufSwing = 0, countBuf2xBase = 0;
      double avgBufferPoints = 0.0;
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

         if(areas[i].bufferType == BUFFER_TYPE_10_SWING) countBufSwing++;
         else if(areas[i].bufferType == BUFFER_TYPE_2X_BASE) countBuf2xBase++;
         avgBufferPoints += areas[i].bufferPoints;
      }
      if(total > 0) avgBufferPoints /= total;

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
         modeHeader = "=== RBR/DBD ENGINE (PHASE 2 COMBINED + PHASE 3 DYNAMIC BUFFER) ===";

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
                                         "Strength: Str0(Weak):%d | Str1(Mod):%d | Str2(A+):%d (Total:%d)\n" +
                                         "Phase 3 Buffer: [10-Sw]:%d | [2xBase]:%d | Avg: %.1f pts (%.2f USD)", 
                                         p21Passed, bosPassed, fvgPassed, htfPOIPassed, countStr0, countStr1, countStr2, total,
                                         countBufSwing, countBuf2xBase, avgBufferPoints, avgBufferPoints * _Point);

      string tradingAreaHUD = "";
      if(InpEnablePhase4)
      {
         SLivingTradingArea area = ExtTradingArea.GetActiveArea();
         if(area.isValid)
         {
            string fStr = area.hasOrganicFloor ? StringFormat("Org RBR (Str%d|%s)", area.floorStrength, area.floorDNA) : "Synthetic";
            string rStr = area.hasOrganicRoof  ? StringFormat("Org DBD (Str%d|%s)", area.roofStrength, area.roofDNA)  : "Synthetic";
            string bExh = (area.buyExhaustionLevel == EXHAUSTION_L0_FRESH) ? "Fresh" : StringFormat("%.1f%%", area.buyMaxPenetrationPct);
            string sExh = (area.sellExhaustionLevel == EXHAUSTION_L0_FRESH) ? "Fresh" : StringFormat("%.1f%%", area.sellMaxPenetrationPct);

            string bOrderOK = area.hasOrganicFloor && area.floorStrength >= 1 ? "READY" : "BLOCKED";
            string sOrderOK = area.hasOrganicRoof  && area.roofStrength >= 1  ? "READY" : "BLOCKED";

            int openBuyPos  = ExtLimitPlacer.CountOpenPositionsByType(POSITION_TYPE_BUY);
            int activeBuyLim = ExtLimitPlacer.CountPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
            int openSellPos = ExtLimitPlacer.CountOpenPositionsByType(POSITION_TYPE_SELL);
            int activeSellLim = ExtLimitPlacer.CountPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);

            tradingAreaHUD = StringFormat("\n=== ACTIVE LIVING TRADING AREA (#%d) ===\n" +
                                          "Corridor Range: %.2f USD | Hard TP 50%%: %.2f\n" +
                                          "Floor: %.2f [%s] -> Buy Area [L%d (%s)] Limit: %s (Cap: %d | Active: %d | Open: %d)\n" +
                                          "Roof : %.2f [%s] -> Sell Area [L%d (%s)] Limit: %s (Cap: %d | Active: %d | Open: %d)\n" +
                                          "Hard SL Boundaries: Floor SL: %.2f | Roof SL: %.2f",
                                          area.areaId,
                                          area.totalRange, area.hardTP50,
                                          area.floorBoundary, fStr, (int)area.buyExhaustionLevel, bExh, bOrderOK,
                                          ExtLimitPlacer.CalculateAllowedCapacity(area.buyExhaustionLevel), activeBuyLim, openBuyPos,
                                          area.roofBoundary, rStr, (int)area.sellExhaustionLevel, sExh, sOrderOK,
                                          ExtLimitPlacer.CalculateAllowedCapacity(area.sellExhaustionLevel), activeSellLim, openSellPos,
                                          area.floorHardSL, area.roofHardSL);
         }
         else
         {
            tradingAreaHUD = "\n=== ACTIVE LIVING TRADING AREA ===\nStatus: WAITING FOR STRUCTURE (Searching Floor/Roof)";
         }
      }

      Comment(StringFormat("%s\n" +
                           "Total Zones: %d | Active: %d | Escalated (M3/M5): %d\n" +
                           "%s\n" +
                           "Garbage Collection: %s (MaxBars: %d, DistMult: %.1f)\n" +
                           "Live Bid: %.2f | Ask: %.2f%s",
                           modeHeader,
                           total, active, escalated,
                           qualityBreakdown,
                           InpEnableGC ? "ENABLED" : "DISABLED", InpMaxMemoryBars, InpPurgeDistMult,
                           bid, ask, tradingAreaHUD));
   }
}
//+------------------------------------------------------------------+

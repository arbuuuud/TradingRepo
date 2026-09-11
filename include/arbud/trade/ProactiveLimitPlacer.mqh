//+------------------------------------------------------------------+
//|                                             ProactiveLimitPlacer.mqh |
//|                                           Copyright 2025, Arbud. |
//|                                             https://www.mql5.com |
//|               Phase 5: Agent Proactive Limit Order Placer        |
//|               Dynamic Grid Capacity, Fresh Depth Mapping,        |
//|               DNA Comment & Auto Equilibrium Clean-Up            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arbud."
#property link      "https://www.mql5.com"
#property strict

#include <Trade\Trade.mqh>
#include "..\structure\LivingTradingArea.mqh"

//+------------------------------------------------------------------+
//| Class CProactiveLimitPlacer                                      |
//+------------------------------------------------------------------+
class CProactiveLimitPlacer
{
private:
   CTrade               m_trade;
   ulong                m_magicNumber;
   int                  m_maxPosPerSide;     // Max positions at Level 0 (e.g. 5)
   double               m_fixedLotSize;      // Lot size per grid position (e.g. 0.01)
   string               m_symbol;
   ulong                m_orderDeviation;
   datetime             m_lastSyncTime;              // Debounce timer: prevents multiple requests per second
   datetime             m_lastTrackedFloorBaseStart; // Tracks active Floor zone origin time
   datetime             m_lastTrackedRoofBaseStart;  // Tracks active Roof zone origin time

public:
   CProactiveLimitPlacer() : m_magicNumber(888222),
                             m_maxPosPerSide(5),
                             m_fixedLotSize(0.01),
                             m_symbol(""),
                             m_orderDeviation(10),
                             m_lastSyncTime(0),
                             m_lastTrackedFloorBaseStart(0),
                             m_lastTrackedRoofBaseStart(0)
   {
   }

   ~CProactiveLimitPlacer()
   {
   }

   //+------------------------------------------------------------------+
   //| Initialization                                                   |
   //+------------------------------------------------------------------+
   bool Init(const string symbol,
             const ulong magicNumber = 888222,
             const int maxPosPerSide = 5,
             const double fixedLot = 0.01)
   {
      m_symbol        = symbol;
      m_magicNumber   = magicNumber;
      m_maxPosPerSide = MathMax(1, maxPosPerSide);
      m_fixedLotSize  = MathMax(0.01, fixedLot);

      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(m_orderDeviation);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      PrintFormat("[ProactiveLimitPlacer] Initialized on %s (Magic: %I64u, MaxPos: %d, Lot: %.2f)",
                  m_symbol, m_magicNumber, m_maxPosPerSide, m_fixedLotSize);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Compute Allowed Limit Order Capacity based on Exhaustion Level   |
   //+------------------------------------------------------------------+
   int CalculateAllowedCapacity(const ENUM_EXHAUSTION_LEVEL level) const
   {
      double factor = 0.0;
      switch(level)
      {
         case EXHAUSTION_L0_FRESH:     factor = 1.00; break; // 100% (e.g. 5 pos)
         case EXHAUSTION_L1_TOUCHED:   factor = 0.80; break; // 80%  (e.g. 4 pos)
         case EXHAUSTION_L2_HALF:      factor = 0.60; break; // 60%  (e.g. 3 pos)
         case EXHAUSTION_L3_DEEP:      factor = 0.40; break; // 40%  (e.g. 2 pos)
         case EXHAUSTION_L4_CRITICAL:  factor = 0.20; break; // 20%  (e.g. 1 pos)
         case EXHAUSTION_L5_EXHAUSTED: factor = 0.00; break; // 0%   (0 pos, cancel all)
         default:                      factor = 0.00; break;
      }
      return (int)MathFloor(m_maxPosPerSide * factor);
   }

   //+------------------------------------------------------------------+
   //| Generate Compact DNA Order Comment                               |
   //| Format: [RBR/DBD]:[TF]:[DNA]:[Str]:[Lvl] (Max 31 chars)          |
   //+------------------------------------------------------------------+
   string GenerateOrderComment(const string typeStr,
                               const ENUM_TIMEFRAMES tf,
                               const string dna,
                               const int strength,
                               const ENUM_EXHAUSTION_LEVEL level) const
   {
      string tfStr = CRBRDBDV1::GetTFShortName(tf);
      string comment = StringFormat("%s:%s:%s:S%d:L%d", typeStr, tfStr, dna, strength, (int)level);
      return StringSubstr(comment, 0, 31); // Ensure <= 31 chars for broker compliance
   }

   //+------------------------------------------------------------------+
   //| Core Dispatcher: Manage Buy & Sell Limit Grids                   |
   //+------------------------------------------------------------------+
   void ManageLimitGrids(const SLivingTradingArea &area,
                         const double currentBid,
                         const double currentAsk)
   {
      if(!area.isValid) return;

      // Check if Floor or Roof zone physically migrated to a NEW distinct base
      // (Ignoring re-evaluations or FVG upgrades of the same active zone)
      bool floorMoved = (area.hasOrganicFloor && area.floorBaseStart != m_lastTrackedFloorBaseStart);
      bool roofMoved  = (area.hasOrganicRoof  && area.roofBaseStart  != m_lastTrackedRoofBaseStart);

      if(m_lastTrackedFloorBaseStart == 0) m_lastTrackedFloorBaseStart = area.floorBaseStart;
      if(m_lastTrackedRoofBaseStart  == 0) m_lastTrackedRoofBaseStart  = area.roofBaseStart;

      if(floorMoved || roofMoved)
      {
         m_lastTrackedFloorBaseStart = area.floorBaseStart;
         m_lastTrackedRoofBaseStart  = area.roofBaseStart;
         // Synchronize / adjust SL & TP for all existing open positions and pending orders
         SyncAreaTransitionRisk(area, currentBid, currentAsk);
      }

      // 1. Purge any pending orders that are OUTSIDE the active TradingArea bounds
      PurgeStaleOrders(area);

      // 2. Check Equilibrium Clean-up:
      // If price has reached Hard TP 50% from below (for Buy) or from above (for Sell)
      CheckEquilibriumCleanUp(area, currentBid, currentAsk);

      // 3. Synchronize Buy Limit Grid on Floor Side
      SyncBuyLimitGrid(area, currentAsk);

      // 4. Synchronize Sell Limit Grid on Roof Side
      SyncSellLimitGrid(area, currentBid);
   }

   //+------------------------------------------------------------------+
   //| Parse Strength level from order/position comment                 |
   //| e.g. "RBR:M1:TBFH:S2:L0" -> returns 2                            |
   //+------------------------------------------------------------------+
   int ParseStrengthFromComment(const string comment, const int fallbackStrength = 1) const
   {
      int pos = StringFind(comment, ":S");
      if(pos >= 0 && (pos + 2) < StringLen(comment))
      {
         string sStr = StringSubstr(comment, pos + 2, 1);
         int sVal = (int)StringToInteger(sStr);
         return MathMax(0, MathMin(2, sVal));
      }
      return fallbackStrength;
   }

   //+------------------------------------------------------------------+
   //| Synchronize SL & TP on TradingArea Change:                       |
   //| Proactive Loss Prevention & Clash of Strength Logic              |
   //| No panic close on floating minus! Dynamic Cut Profit & Def SL    |
   //+------------------------------------------------------------------+
   void SyncAreaTransitionRisk(const SLivingTradingArea &area,
                               const double currentBid,
                               const double currentAsk)
   {
      double spreadBufferPoints = 32.0 * _Point; // 32 points ($0.32) spread buffer on Gold
      double staticSLPoints     = 500.0 * _Point; // $5.00 static safety margin

      // 1. Synchronize & Protect Open Positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)m_magicNumber)
         {
            ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            string posComment   = PositionGetString(POSITION_COMMENT);

            if(pType == POSITION_TYPE_BUY)
            {
               // Check if position is floating profit or floating minus
               bool isFloatingMinus = (currentBid < posOpenPrice);

               if(!isFloatingMinus)
               {
                  // FLOATING PROFIT: Secure with BE+ and target new area Hard TP 50%
                  double newSL = NormalizeDouble(posOpenPrice + (10.0 * _Point), _Digits);
                  double newTP = area.hardTP50;
                  if(newTP <= (currentBid + (20.0 * _Point)))
                     newTP = NormalizeDouble(currentBid + (50.0 * _Point), _Digits);

                  m_trade.PositionModify(ticket, newSL, newTP);
                  PrintFormat("[AreaTransition] Buy #%I64u Floating Profit secured: BE+ SL %.2f, TP %.2f",
                              ticket, newSL, newTP);
               }
               else
               {
                  // FLOATING MINUS: CLASH OF STRENGTH & CUT PROFIT / BE ESCAPE ROUTE
                  int myRBRStrength = ParseStrengthFromComment(posComment, area.floorStrength);
                  int newDBDStrength = area.roofStrength;

                  double targetExit = 0.0;

                  // Clash of Strength:
                  // If RBR was stronger than new DBD, and DBD proximal is above entry + spread
                  if(myRBRStrength > newDBDStrength && area.hasOrganicRoof)
                  {
                     double dbdProximal = area.roofProximal;
                     if(dbdProximal > (posOpenPrice + spreadBufferPoints) && dbdProximal > (currentAsk + spreadBufferPoints))
                     {
                        // Target Exit = Bibir DBD (Cut Profit!)
                        targetExit = NormalizeDouble(dbdProximal, _Digits);
                     }
                     else
                     {
                        // Cannot cut profit at DBD, target Break Even
                        targetExit = NormalizeDouble(posOpenPrice + spreadBufferPoints, _Digits);
                     }
                  }
                  else
                  {
                     // DBD is equal or stronger: Emergency Break Even Evacuation
                     targetExit = NormalizeDouble(posOpenPrice + spreadBufferPoints, _Digits);
                  }

                  // Routing Target Exit to TP or SL:
                  double newTP = 0.0;
                  double newSL = 0.0;

                  if(targetExit > (currentBid + (20.0 * _Point)))
                  {
                     // Target exit is safely above current market price -> set as Take Profit
                     newTP = targetExit;

                     // Determine Protective SL: Default $5 drop from current price, or Floor Hard SL if closer
                     double staticSL = NormalizeDouble(currentBid - staticSLPoints, _Digits);
                     if(area.floorHardSL > staticSL && area.floorHardSL < currentBid)
                        newSL = area.floorHardSL;
                     else
                        newSL = staticSL;
                  }
                  else
                  {
                     // Price already plunged below target exit: Convert targetExit into Defensive Stop Loss!
                     newSL = targetExit;
                     newTP = area.hardTP50;
                  }

                  m_trade.PositionModify(ticket, newSL, newTP);
                  PrintFormat("[AreaTransition] Buy #%I64u Floating Minus managed: RBR_Str=%d vs DBD_Str=%d -> New TP %.2f, New SL %.2f",
                              ticket, myRBRStrength, newDBDStrength, newTP, newSL);
               }
            }
            else if(pType == POSITION_TYPE_SELL)
            {
               // Check if position is floating profit or floating minus
               bool isFloatingMinus = (currentAsk > posOpenPrice);

               if(!isFloatingMinus)
               {
                  // FLOATING PROFIT: Secure with BE+ and target new area Hard TP 50%
                  double newSL = NormalizeDouble(posOpenPrice - (10.0 * _Point), _Digits);
                  double newTP = area.hardTP50;
                  if(newTP >= (currentAsk - (20.0 * _Point)))
                     newTP = NormalizeDouble(currentAsk - (50.0 * _Point), _Digits);

                  m_trade.PositionModify(ticket, newSL, newTP);
                  PrintFormat("[AreaTransition] Sell #%I64u Floating Profit secured: BE+ SL %.2f, TP %.2f",
                              ticket, newSL, newTP);
               }
               else
               {
                  // FLOATING MINUS: CLASH OF STRENGTH & CUT PROFIT / BE ESCAPE ROUTE
                  int myDBDStrength = ParseStrengthFromComment(posComment, area.roofStrength);
                  int newRBRStrength = area.floorStrength;

                  double targetExit = 0.0;

                  // Clash of Strength:
                  // If DBD was stronger than new RBR, and RBR proximal is below entry - spread
                  if(myDBDStrength > newRBRStrength && area.hasOrganicFloor)
                  {
                     double rbrProximal = area.floorProximal;
                     if(rbrProximal < (posOpenPrice - spreadBufferPoints) && rbrProximal < (currentBid - spreadBufferPoints))
                     {
                        // Target Exit = Bibir RBR (Cut Profit!)
                        targetExit = NormalizeDouble(rbrProximal, _Digits);
                     }
                     else
                     {
                        // Cannot cut profit at RBR, target Break Even
                        targetExit = NormalizeDouble(posOpenPrice - spreadBufferPoints, _Digits);
                     }
                  }
                  else
                  {
                     // RBR is equal or stronger: Emergency Break Even Evacuation
                     targetExit = NormalizeDouble(posOpenPrice - spreadBufferPoints, _Digits);
                  }

                  // Routing Target Exit to TP or SL:
                  double newTP = 0.0;
                  double newSL = 0.0;

                  if(targetExit < (currentAsk - (20.0 * _Point)))
                  {
                     // Target exit is safely below current market price -> set as Take Profit
                     newTP = targetExit;

                     // Determine Protective SL: Default $5 rise from current price, or Roof Hard SL if closer
                     double staticSL = NormalizeDouble(currentAsk + staticSLPoints, _Digits);
                     if(area.roofHardSL < staticSL && area.roofHardSL > currentAsk)
                        newSL = area.roofHardSL;
                     else
                        newSL = staticSL;
                  }
                  else
                  {
                     // Price already surged above target exit: Convert targetExit into Defensive Stop Loss!
                     newSL = targetExit;
                     newTP = area.hardTP50;
                  }

                  m_trade.PositionModify(ticket, newSL, newTP);
                  PrintFormat("[AreaTransition] Sell #%I64u Floating Minus managed: DBD_Str=%d vs RBR_Str=%d -> New TP %.2f, New SL %.2f",
                              ticket, myDBDStrength, newRBRStrength, newTP, newSL);
               }
            }
         }
      }

      // 2. Synchronize Remaining Valid Pending Orders
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         ulong ticket = OrderGetTicket(j);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber)
         {
            ENUM_ORDER_TYPE oType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            double oPrice = OrderGetDouble(ORDER_PRICE_OPEN);

            if(oType == ORDER_TYPE_BUY_LIMIT)
            {
               double newSL = area.floorHardSL;
               double newTP = area.hardTP50;

               // If order price is below new SL or above new TP, order is invalid -> Delete
               if(oPrice <= newSL || oPrice >= newTP)
               {
                  m_trade.OrderDelete(ticket);
                  continue;
               }
               m_trade.OrderModify(ticket, oPrice, newSL, newTP, ORDER_TIME_GTC, 0);
            }
            else if(oType == ORDER_TYPE_SELL_LIMIT)
            {
               double newSL = area.roofHardSL;
               double newTP = area.hardTP50;

               // If order price is above new SL or below new TP, order is invalid -> Delete
               if(oPrice >= newSL || oPrice <= newTP)
               {
                  m_trade.OrderDelete(ticket);
                  continue;
               }
               m_trade.OrderModify(ticket, oPrice, newSL, newTP, ORDER_TIME_GTC, 0);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Purge Stale Orders: Cancel any orders outside current active area|
   //+------------------------------------------------------------------+
   void PurgeStaleOrders(const SLivingTradingArea &area)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber)
         {
            ENUM_ORDER_TYPE oType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            double oPrice = OrderGetDouble(ORDER_PRICE_OPEN);

            if(oType == ORDER_TYPE_BUY_LIMIT)
            {
               // If Floor is invalid/synthetic, or order price is outside [buyZoneStart, buyZoneEnd]
               if(!area.hasOrganicFloor || area.floorStrength < 1 ||
                  oPrice < (area.buyZoneStart - (5.0 * _Point)) || oPrice > (area.buyZoneEnd + (5.0 * _Point)))
               {
                  m_trade.OrderDelete(ticket);
               }
            }
            else if(oType == ORDER_TYPE_SELL_LIMIT)
            {
               // If Roof is invalid/synthetic, or order price is outside [sellZoneStart, sellZoneEnd]
               if(!area.hasOrganicRoof || area.roofStrength < 1 ||
                  oPrice < (area.sellZoneStart - (5.0 * _Point)) || oPrice > (area.sellZoneEnd + (5.0 * _Point)))
               {
                  m_trade.OrderDelete(ticket);
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Synchronize Buy Limit Grid (Demand / Floor Side)                 |
   //+------------------------------------------------------------------+
   void SyncBuyLimitGrid(const SLivingTradingArea &area, const double currentAsk)
   {
      // 1. Invalidation / Exclusion Checks:
      // - Must have organic RBR
      // - Strength must be >= 1 (Str 0 rejected)
      // - Exhaustion Level must be < Level 5
      if(!area.hasOrganicFloor || area.floorStrength < 1 || area.buyExhaustionLevel >= EXHAUSTION_L5_EXHAUSTED)
      {
         CancelPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
         return;
      }

      // 2. Calculate allowed capacity
      int targetCapacity = CalculateAllowedCapacity(area.buyExhaustionLevel);
      if(targetCapacity <= 0)
      {
         CancelPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
         return;
      }

      // 3. Determine Pristine / Virgin Depth Bounds:
      // In Buy area: Virgin space is from topFresh down to botFresh.
      // topFresh is buyMaxPenetratedPrice if already entered, else buyZoneEnd (top edge)
      double topFresh = area.buyZoneEnd;
      if(area.buyMaxPenetratedPrice > 0.0 && area.buyMaxPenetratedPrice < topFresh)
      {
         topFresh = area.buyMaxPenetratedPrice;
      }

      double botFresh = area.buyZoneStart; // Bottom edge (Final Floor)
      double freshSpan = topFresh - botFresh;

      // Minimum space required to place orders safely
      if(freshSpan < (15.0 * _Point))
      {
         CancelPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
         return;
      }

      // 4. Cancel any Buy Limit orders whose price has already been touched (>= topFresh)
      CancelBreachedBuyLimits(topFresh);

      // 5. Generate Target Grid Prices across Virgin Space:
      // Rule: Exactly 1 order at the topmost virgin edge, 1 order at the bottommost edge,
      // and remaining orders distributed evenly in between!
      double targetPrices[];
      ArrayResize(targetPrices, targetCapacity);

      double margin = MathMax(freshSpan * 0.02, 5.0 * _Point);
      double pTop = topFresh - margin;
      double pBot = botFresh + margin;

      if(targetCapacity == 1)
      {
         targetPrices[0] = NormalizeDouble((pTop + pBot) * 0.5, _Digits);
      }
      else
      {
         targetPrices[0]                  = NormalizeDouble(pTop, _Digits); // 1 at topmost virgin edge
         targetPrices[targetCapacity - 1] = NormalizeDouble(pBot, _Digits); // 1 at bottommost virgin edge

         if(targetCapacity > 2)
         {
            double innerSpan = pTop - pBot;
            double step = innerSpan / (double)(targetCapacity - 1);
            for(int m = 1; m < targetCapacity - 1; m++)
            {
               targetPrices[m] = NormalizeDouble(pTop - (m * step), _Digits);
            }
         }
      }

      // 6. Check existing orders vs target prices:
      // If an order or position already covers a target price, keep it!
      // Only place orders for missing virgin slots.
      double tolerance = MathMax((freshSpan / (double)(targetCapacity + 1)) * 0.40, 5.0 * _Point);
      string comment   = GenerateOrderComment("RBR", area.floorPeriod, area.floorDNA, area.floorStrength, area.buyExhaustionLevel);

      for(int i = 0; i < targetCapacity; i++)
      {
         double orderPrice = targetPrices[i];

         // Safety: order price must be below current Ask
         if(orderPrice >= currentAsk - (10.0 * _Point)) continue;
         if(orderPrice <= botFresh) continue;

         // If already covered by existing Buy Limit or Buy Position near this price -> DO NOT REORDER
         if(IsOrderOrPositionExistingNearPrice(ORDER_TYPE_BUY_LIMIT, orderPrice, tolerance))
            continue;

         // Place Limit Order in this untouched slot
         m_trade.BuyLimit(m_fixedLotSize, orderPrice, m_symbol, area.floorHardSL, area.hardTP50,
                          ORDER_TIME_GTC, 0, comment);
      }
   }

   //+------------------------------------------------------------------+
   //| Synchronize Sell Limit Grid (Supply / Roof Side)                 |
   //+------------------------------------------------------------------+
   void SyncSellLimitGrid(const SLivingTradingArea &area, const double currentBid)
   {
      // 1. Invalidation / Exclusion Checks:
      // - Must have organic DBD
      // - Strength must be >= 1 (Str 0 rejected)
      // - Exhaustion Level must be < Level 5
      if(!area.hasOrganicRoof || area.roofStrength < 1 || area.sellExhaustionLevel >= EXHAUSTION_L5_EXHAUSTED)
      {
         CancelPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
         return;
      }

      // 2. Calculate allowed capacity
      int targetCapacity = CalculateAllowedCapacity(area.sellExhaustionLevel);
      if(targetCapacity <= 0)
      {
         CancelPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
         return;
      }

      // 3. Determine Pristine / Virgin Depth Bounds:
      // In Sell area: Virgin space is from botFresh up to topFresh.
      // botFresh is sellMaxPenetratedPrice if already entered, else sellZoneStart (bottom edge)
      double botFresh = area.sellZoneStart;
      if(area.sellMaxPenetratedPrice > 0.0 && area.sellMaxPenetratedPrice > botFresh)
      {
         botFresh = area.sellMaxPenetratedPrice;
      }

      double topFresh = area.sellZoneEnd; // Top edge (Final Roof)
      double freshSpan = topFresh - botFresh;

      // Minimum space required to place orders safely
      if(freshSpan < (15.0 * _Point))
      {
         CancelPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
         return;
      }

      // 4. Cancel any Sell Limit orders whose price has already been touched (<= botFresh)
      CancelBreachedSellLimits(botFresh);

      // 5. Generate Target Grid Prices across Virgin Space:
      // Rule: Exactly 1 order at bottommost virgin edge, 1 order at topmost virgin edge,
      // and remaining orders distributed evenly in between!
      double targetPrices[];
      ArrayResize(targetPrices, targetCapacity);

      double margin = MathMax(freshSpan * 0.02, 5.0 * _Point);
      double pBot = botFresh + margin;
      double pTop = topFresh - margin;

      if(targetCapacity == 1)
      {
         targetPrices[0] = NormalizeDouble((pTop + pBot) * 0.5, _Digits);
      }
      else
      {
         targetPrices[0]                  = NormalizeDouble(pBot, _Digits); // 1 at bottommost virgin edge
         targetPrices[targetCapacity - 1] = NormalizeDouble(pTop, _Digits); // 1 at topmost virgin edge

         if(targetCapacity > 2)
         {
            double innerSpan = pTop - pBot;
            double step = innerSpan / (double)(targetCapacity - 1);
            for(int m = 1; m < targetCapacity - 1; m++)
            {
               targetPrices[m] = NormalizeDouble(pBot + (m * step), _Digits);
            }
         }
      }

      // 6. Check existing orders vs target prices:
      // If an order or position already covers a target price, keep it!
      // Only place orders for missing virgin slots.
      double tolerance = MathMax((freshSpan / (double)(targetCapacity + 1)) * 0.40, 5.0 * _Point);
      string comment   = GenerateOrderComment("DBD", area.roofPeriod, area.roofDNA, area.roofStrength, area.sellExhaustionLevel);

      for(int i = 0; i < targetCapacity; i++)
      {
         double orderPrice = targetPrices[i];

         // Safety: order price must be above current Bid
         if(orderPrice <= currentBid + (10.0 * _Point)) continue;
         if(orderPrice >= topFresh) continue;

         // If already covered by existing Sell Limit or Sell Position near this price -> DO NOT REORDER
         if(IsOrderOrPositionExistingNearPrice(ORDER_TYPE_SELL_LIMIT, orderPrice, tolerance))
            continue;

         // Place Limit Order in this untouched slot
         m_trade.SellLimit(m_fixedLotSize, orderPrice, m_symbol, area.roofHardSL, area.hardTP50,
                           ORDER_TIME_GTC, 0, comment);
      }
   }

   //+------------------------------------------------------------------+
   //| Check Equilibrium Clean-up:                                      |
   //| If price reached Hard TP 50% and open positions closed,          |
   //| purge any lingering unfilled pending limit orders                |
   //+------------------------------------------------------------------+
   void CheckEquilibriumCleanUp(const SLivingTradingArea &area,
                                const double currentBid,
                                const double currentAsk)
   {
      // If price is above TP 50% and no open Buy positions, cancel stale Buy Limits
      if(currentBid >= area.hardTP50)
      {
         if(CountOpenPositionsByType(POSITION_TYPE_BUY) == 0)
         {
            CancelPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
         }
      }

      // If price is below TP 50% and no open Sell positions, cancel stale Sell Limits
      if(currentAsk <= area.hardTP50)
      {
         if(CountOpenPositionsByType(POSITION_TYPE_SELL) == 0)
         {
            CancelPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cancel all pending orders for this EA                            |
   //+------------------------------------------------------------------+
   void CancelAllPendingOrders()
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber)
         {
            m_trade.OrderDelete(ticket);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cancel pending orders of a specific type                         |
   //+------------------------------------------------------------------+
   void CancelPendingOrdersByType(const ENUM_ORDER_TYPE orderType)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == orderType)
         {
            m_trade.OrderDelete(ticket);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cancel Buy Limits that have already been touched/breached        |
   //+------------------------------------------------------------------+
   void CancelBreachedBuyLimits(const double topFreshPrice)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_LIMIT)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price >= topFreshPrice)
            {
               m_trade.OrderDelete(ticket);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Cancel Sell Limits that have already been touched/breached       |
   //+------------------------------------------------------------------+
   void CancelBreachedSellLimits(const double botFreshPrice)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_LIMIT)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(price <= botFreshPrice)
            {
               m_trade.OrderDelete(ticket);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Count open positions by type                                     |
   //+------------------------------------------------------------------+
   int CountOpenPositionsByType(const ENUM_POSITION_TYPE posType) const
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)m_magicNumber &&
            PositionGetInteger(POSITION_TYPE)  == posType)
         {
            count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Count pending orders by type                                     |
   //+------------------------------------------------------------------+
   int CountPendingOrdersByType(const ENUM_ORDER_TYPE orderType) const
   {
      int count = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == orderType)
         {
            count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Helper: Check if an order OR open position exists near price     |
   //+------------------------------------------------------------------+
   bool IsOrderOrPositionExistingNearPrice(const ENUM_ORDER_TYPE orderType,
                                           const double targetPrice,
                                           const double tolerance) const
   {
      // 1. Check pending orders
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == orderType)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(price - targetPrice) <= tolerance)
               return true;
         }
      }

      // 2. Check open positions (if already filled at this price level)
      ENUM_POSITION_TYPE posType = (orderType == ORDER_TYPE_BUY_LIMIT) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket <= 0) continue;

         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            PositionGetInteger(POSITION_MAGIC) == (long)m_magicNumber &&
            PositionGetInteger(POSITION_TYPE)  == posType)
         {
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(posPrice - targetPrice) <= tolerance)
               return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Helper: Check if an order exists near a target price             |
   //+------------------------------------------------------------------+
   bool IsOrderExistingNearPrice(const ENUM_ORDER_TYPE orderType,
                                 const double targetPrice,
                                 const double tolerance) const
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;

         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            OrderGetInteger(ORDER_MAGIC) == (long)m_magicNumber &&
            OrderGetInteger(ORDER_TYPE)  == orderType)
         {
            double price = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(price - targetPrice) <= tolerance)
               return true;
         }
      }
      return false;
   }
};
//+------------------------------------------------------------------+

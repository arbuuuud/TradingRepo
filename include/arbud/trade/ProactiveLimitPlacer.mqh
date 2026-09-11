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

public:
   CProactiveLimitPlacer() : m_magicNumber(888222),
                             m_maxPosPerSide(5),
                             m_fixedLotSize(0.01),
                             m_symbol(""),
                             m_orderDeviation(10)
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

      // 1. Check Equilibrium Clean-up:
      // If price has reached Hard TP 50% from below (for Buy) or from above (for Sell)
      CheckEquilibriumCleanUp(area, currentBid, currentAsk);

      // 2. Synchronize Buy Limit Grid on Floor Side
      SyncBuyLimitGrid(area, currentAsk);

      // 3. Synchronize Sell Limit Grid on Roof Side
      SyncSellLimitGrid(area, currentBid);
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
      // Upper bound of virgin space: deepest penetrated price if touched, else buyZoneEnd
      double topFresh = area.buyZoneEnd;
      if(area.buyMaxPenetratedPrice > 0.0 && area.buyMaxPenetratedPrice < topFresh)
      {
         topFresh = area.buyMaxPenetratedPrice;
      }

      // Lower bound of virgin space: Final Floor boundary
      double botFresh = area.buyZoneStart;
      double freshSpan = topFresh - botFresh;

      // Minimum space required to place orders safely (e.g. at least 15 points)
      if(freshSpan < (15.0 * _Point))
      {
         CancelPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
         return;
      }

      // 4. Cancel any Buy Limit orders whose price is already touched (>= topFresh)
      CancelBreachedBuyLimits(topFresh);

      // 5. Count currently active Buy positions and Buy Limit orders for this area
      int openBuyPositions = CountOpenPositionsByType(POSITION_TYPE_BUY);
      int activeBuyLimits  = CountPendingOrdersByType(ORDER_TYPE_BUY_LIMIT);
      int totalBuySlots    = openBuyPositions + activeBuyLimits;

      // If already at or above target capacity, do not place more
      if(totalBuySlots >= targetCapacity) return;

      int neededLimits = targetCapacity - totalBuySlots;
      if(neededLimits <= 0) return;

      // 6. Distribute Limit Orders evenly inside virgin depth
      double priceStep = freshSpan / (double)(neededLimits + 1);
      string comment   = GenerateOrderComment("RBR", area.floorPeriod, area.floorDNA, area.floorStrength, area.buyExhaustionLevel);

      for(int k = 1; k <= neededLimits; k++)
      {
         double orderPrice = NormalizeDouble(topFresh - (k * priceStep), _Digits);

         // Safety Check: must be strictly below current Ask and above botFresh
         if(orderPrice >= currentAsk - (10.0 * _Point)) continue;
         if(orderPrice <= botFresh) continue;

         // Check if an order already exists very close to this price (within 5 points)
         if(IsOrderExistingNearPrice(ORDER_TYPE_BUY_LIMIT, orderPrice, 5.0 * _Point)) continue;

         // Execute Order Placement
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
      // Lower bound of virgin space: deepest penetrated price if touched, else sellZoneStart
      double botFresh = area.sellZoneStart;
      if(area.sellMaxPenetratedPrice > 0.0 && area.sellMaxPenetratedPrice > botFresh)
      {
         botFresh = area.sellMaxPenetratedPrice;
      }

      // Upper bound of virgin space: Final Roof boundary
      double topFresh = area.sellZoneEnd;
      double freshSpan = topFresh - botFresh;

      // Minimum space required to place orders safely
      if(freshSpan < (15.0 * _Point))
      {
         CancelPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
         return;
      }

      // 4. Cancel any Sell Limit orders whose price is already touched (<= botFresh)
      CancelBreachedSellLimits(botFresh);

      // 5. Count currently active Sell positions and Sell Limit orders for this area
      int openSellPositions = CountOpenPositionsByType(POSITION_TYPE_SELL);
      int activeSellLimits  = CountPendingOrdersByType(ORDER_TYPE_SELL_LIMIT);
      int totalSellSlots    = openSellPositions + activeSellLimits;

      // If already at or above target capacity, do not place more
      if(totalSellSlots >= targetCapacity) return;

      int neededLimits = targetCapacity - totalSellSlots;
      if(neededLimits <= 0) return;

      // 6. Distribute Limit Orders evenly inside virgin depth
      double priceStep = freshSpan / (double)(neededLimits + 1);
      string comment   = GenerateOrderComment("DBD", area.roofPeriod, area.roofDNA, area.roofStrength, area.sellExhaustionLevel);

      for(int k = 1; k <= neededLimits; k++)
      {
         double orderPrice = NormalizeDouble(botFresh + (k * priceStep), _Digits);

         // Safety Check: must be strictly above current Bid and below topFresh
         if(orderPrice <= currentBid + (10.0 * _Point)) continue;
         if(orderPrice >= topFresh) continue;

         // Check if an order already exists very close to this price (within 5 points)
         if(IsOrderExistingNearPrice(ORDER_TYPE_SELL_LIMIT, orderPrice, 5.0 * _Point)) continue;

         // Execute Order Placement
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

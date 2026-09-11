//+------------------------------------------------------------------+
//|                                                LivingTradingArea.mqh |
//|                                           Copyright 2025, Arbud. |
//|                                             https://www.mql5.com |
//|               Living TradingArea & Exhaustion State Machine      |
//|               Dynamic Corridor, Depth Mapping & Order Validation |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arbud."
#property link      "https://www.mql5.com"
#property strict

#include "rbrdbdV1.mqh"

//+------------------------------------------------------------------+
//| Exhaustion Level Enumeration (Level 0 - 5)                       |
//+------------------------------------------------------------------+
enum ENUM_EXHAUSTION_LEVEL
{
   EXHAUSTION_L0_FRESH     = 0, // 0% penetration: 100% pristine virgin depth
   EXHAUSTION_L1_TOUCHED   = 1, // 1% - 25% penetration: early retest
   EXHAUSTION_L2_HALF      = 2, // 26% - 50% penetration: half depth consumed
   EXHAUSTION_L3_DEEP      = 3, // 51% - 75% penetration: deep penetration
   EXHAUSTION_L4_CRITICAL  = 4, // 76% - 99% penetration: high saturation risk
   EXHAUSTION_L5_EXHAUSTED = 5  // 100% penetration: fully mitigated / dead
};

//+------------------------------------------------------------------+
//| Area Boundary Source Type                                        |
//+------------------------------------------------------------------+
enum ENUM_BOUNDARY_SOURCE
{
   BOUNDARY_ORGANIC_RBRDBD = 0, // From organic RBR (Demand) or DBD (Supply)
   BOUNDARY_HTF_SWING      = 1, // Fallback from HTF (M15/H1) structural swing
   BOUNDARY_ATR_PROJECTED  = 2  // Fallback from Daily ATR projection
};

//+------------------------------------------------------------------+
//| Struct for Primary Living Trading Area                           |
//+------------------------------------------------------------------+
struct SLivingTradingArea
{
   bool                 isValid;           // True if area geometry is established
   datetime             createdTime;       // Timestamp when area was established
   int                  areaId;            // Incremental sequence ID

   // Floor Geometries (Bottom / Demand Side)
   ENUM_BOUNDARY_SOURCE floorSource;       // Organic RBR, HTF Swing, or ATR
   datetime             floorBaseStart;    // Base formation time (unique identifier)
   double               floorBoundary;     // Final Floor Price (Distal - Buffer)
   double               floorDistal;       // Raw Distal
   double               floorProximal;     // Raw Proximal
   ENUM_TIMEFRAMES      floorPeriod;       // Floor origin timeframe
   int                  floorStrength;     // Strength 0 (Weak), 1 (Mod), 2 (A+)
   int                  floorScore;        // Stars 0 - 4
   string               floorDNA;          // DNA string e.g. "TBFH"
   bool                 hasOrganicFloor;   // True if Floor is an actual RBR zone

   // Roof Geometries (Top / Supply Side)
   ENUM_BOUNDARY_SOURCE roofSource;        // Organic DBD, HTF Swing, or ATR
   datetime             roofBaseStart;     // Base formation time (unique identifier)
   double               roofBoundary;      // Final Roof Price (Distal + Buffer)
   double               roofDistal;        // Raw Distal
   double               roofProximal;      // Raw Proximal
   ENUM_TIMEFRAMES      roofPeriod;        // Roof origin timeframe
   int                  roofStrength;      // Strength 0 (Weak), 1 (Mod), 2 (A+)
   int                  roofScore;         // Stars 0 - 4
   string               roofDNA;           // DNA string e.g. "TBFH"
   bool                 hasOrganicRoof;    // True if Roof is an actual DBD zone

   // Corridor Geometry
   double               totalRange;        // Final Roof - Final Floor
   double               hardTP50;          // Equilibrium: Final Floor + 0.50 * Range
   
   // Sub-Area Transaction Boundaries
   double               buyZoneStart;      // Final Floor (0%)
   double               buyZoneEnd;        // Final Floor + 0.25 * Range (25%)
   double               floorHardSL;       // Final Floor - 0.30 * Range (-30%)

   double               sellZoneStart;     // Final Roof - 0.25 * Range (75%)
   double               sellZoneEnd;       // Final Roof (100%)
   double               roofHardSL;        // Final Roof + 0.30 * Range (+130%)

   // Exhaustion State Machine (One-Way Ratchet)
   double               buyMaxPenetrationPct;  // 0.0% to 100.0%
   double               buyMaxPenetratedPrice; // Deepest price reached inside Buy Zone
   ENUM_EXHAUSTION_LEVEL buyExhaustionLevel;

   double               sellMaxPenetrationPct; // 0.0% to 100.0%
   double               sellMaxPenetratedPrice;// Deepest price reached inside Sell Zone
   ENUM_EXHAUSTION_LEVEL sellExhaustionLevel;

   void Init()
   {
      isValid               = false;
      createdTime           = 0;
      areaId                = 0;

      floorSource           = BOUNDARY_ORGANIC_RBRDBD;
      floorBaseStart        = 0;
      floorBoundary         = 0.0;
      floorDistal           = 0.0;
      floorProximal         = 0.0;
      floorPeriod           = PERIOD_CURRENT;
      floorStrength         = 0;
      floorScore            = 0;
      floorDNA              = "----";
      hasOrganicFloor       = false;

      roofSource            = BOUNDARY_ORGANIC_RBRDBD;
      roofBaseStart         = 0;
      roofBoundary          = 0.0;
      roofDistal            = 0.0;
      roofProximal          = 0.0;
      roofPeriod            = PERIOD_CURRENT;
      roofStrength          = 0;
      roofScore             = 0;
      roofDNA               = "----";
      hasOrganicRoof        = false;

      totalRange            = 0.0;
      hardTP50              = 0.0;
      buyZoneStart          = 0.0;
      buyZoneEnd            = 0.0;
      floorHardSL           = 0.0;
      sellZoneStart         = 0.0;
      sellZoneEnd           = 0.0;
      roofHardSL            = 0.0;

      buyMaxPenetrationPct  = 0.0;
      buyMaxPenetratedPrice = 0.0;
      buyExhaustionLevel    = EXHAUSTION_L0_FRESH;

      sellMaxPenetrationPct = 0.0;
      sellMaxPenetratedPrice= 0.0;
      sellExhaustionLevel   = EXHAUSTION_L0_FRESH;
   }
};

//+------------------------------------------------------------------+
//| Class CLivingTradingAreaManager                                  |
//+------------------------------------------------------------------+
class CLivingTradingAreaManager
{
private:
   SLivingTradingArea   m_activeArea;
   int                  m_areaCounter;
   string               m_objPrefix;
   bool                 m_drawEnabled;
   ENUM_TIMEFRAMES      m_baseTF;

   // Visual colors
   color                m_clrBuyArea;
   color                m_clrSellArea;
   color                m_clrTP50;
   color                m_clrHardSL;
   color                m_clrText;

public:
   CLivingTradingAreaManager() : m_areaCounter(0),
                                 m_objPrefix("LTA_"),
                                 m_drawEnabled(true),
                                 m_baseTF(PERIOD_M1),
                                 m_clrBuyArea(C'20,60,35'),    // Dark subtle green
                                 m_clrSellArea(C'60,20,25'),   // Dark subtle maroon
                                 m_clrTP50(clrDodgerBlue),
                                 m_clrHardSL(clrDimGray),
                                 m_clrText(clrWhite)
   {
      m_activeArea.Init();
   }

   ~CLivingTradingAreaManager()
   {
      ClearChartObjects();
   }

   void SetDrawEnabled(const bool enable) { m_drawEnabled = enable; }
   void SetBaseTF(const ENUM_TIMEFRAMES tf) { m_baseTF = tf; }

   SLivingTradingArea GetActiveArea() const { return m_activeArea; }
   bool HasValidArea() const { return m_activeArea.isValid; }

   //+------------------------------------------------------------------+
   //| Core Engine: Synchronize & Update Living Trading Area            |
   //| Called on every tick or new candle                               |
   //+------------------------------------------------------------------+
   bool UpdateTradingArea(const string symbol,
                          CRBRDBDV1 &rbrdbdEngine,
                          const double currentBid,
                          const double currentAsk)
   {
      double midPrice = (currentBid + currentAsk) * 0.5;
      if(midPrice <= 0.0) return false;

      // 1. Check if a newer/closer RBR or DBD zone has formed
      bool structureShifted = false;
      if(m_activeArea.isValid)
      {
         SRBRDBDArea curNearestFloor, curNearestRoof;
         curNearestFloor.Init();
         curNearestRoof.Init();

         bool hasFloor = rbrdbdEngine.FindNearestFloor(m_baseTF, midPrice, curNearestFloor);
         bool hasRoof  = rbrdbdEngine.FindNearestRoof(m_baseTF, midPrice, curNearestRoof);

         // Check if a closer/newer Floor has formed
         if(hasFloor)
         {
            if(!m_activeArea.hasOrganicFloor || curNearestFloor.baseStart != m_activeArea.floorBaseStart)
            {
               structureShifted = true;
            }
         }

         // Check if a closer/newer Roof has formed
         if(!structureShifted && hasRoof)
         {
            if(!m_activeArea.hasOrganicRoof || curNearestRoof.baseStart != m_activeArea.roofBaseStart)
            {
               structureShifted = true;
            }
         }
      }

      // 2. If no active area, breached/invalidated, OR closer structure formed -> Rebuild
      if(!m_activeArea.isValid || IsAreaBreached(midPrice) || structureShifted)
      {
         bool rebuilt = BuildNewTradingArea(symbol, rbrdbdEngine, midPrice);
         if(!rebuilt)
         {
            // Could not build area (waiting for structure)
            if(m_drawEnabled) ClearChartObjects();
            return false;
         }
      }

      // 3. Living Exhaustion State Tracking (Ratchet on Live Price)
      UpdateExhaustionRatchet(currentBid, currentAsk);

      // 4. Render / Update visual elements
      if(m_drawEnabled)
      {
         DrawTradingAreaObjects();
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if active area has been completely breached or invalidated |
   //+------------------------------------------------------------------+
   bool IsAreaBreached(const double currentPrice)
   {
      if(!m_activeArea.isValid) return true;

      // Breached if price drops below Floor Hard SL or rises above Roof Hard SL
      if(currentPrice < m_activeArea.floorHardSL || currentPrice > m_activeArea.roofHardSL)
         return true;

      // Breached if both Buy & Sell zones are 100% exhausted
      if(m_activeArea.buyExhaustionLevel == EXHAUSTION_L5_EXHAUSTED &&
         m_activeArea.sellExhaustionLevel == EXHAUSTION_L5_EXHAUSTED)
         return true;

      return false;
   }

   //+------------------------------------------------------------------+
   //| Validation: Can Buy Order be placed in Floor area?               |
   //| - Must have organic RBR zone (hasOrganicFloor)                   |
   //| - Floor strength must be >= 1 (Strength 1 or 2)                  |
   //| - Price coordinate must be in pristine / virgin depth            |
   //+------------------------------------------------------------------+
   bool CanPlaceBuyOrder(const double orderPrice, string &rejectReason) const
   {
      if(!m_activeArea.isValid)
      {
         rejectReason = "No Active TradingArea";
         return false;
      }

      // 1. Organic RBR validation
      if(!m_activeArea.hasOrganicFloor)
      {
         rejectReason = "Floor is Synthetic/Projected (No Organic RBR)";
         return false;
      }

      // 2. Strength Validation (Must be >= 1)
      if(m_activeArea.floorStrength < 1)
      {
         rejectReason = StringFormat("Floor Strength is %d (Weak Str0)", m_activeArea.floorStrength);
         return false;
      }

      // 3. Coordinate within Buy Area (0% - 25%)
      if(orderPrice < m_activeArea.buyZoneStart || orderPrice > m_activeArea.buyZoneEnd)
      {
         rejectReason = StringFormat("Price %.2f outside BuyZone [%.2f - %.2f]",
                                     orderPrice, m_activeArea.buyZoneStart, m_activeArea.buyZoneEnd);
         return false;
      }

      // 4. Virgin / Untouched Depth Validation
      // In Buy zone: prices are entered downwards from buyZoneEnd down to buyZoneStart.
      // If price has previously penetrated down to buyMaxPenetratedPrice,
      // any order ABOVE buyMaxPenetratedPrice is already used/touched!
      if(m_activeArea.buyMaxPenetratedPrice > 0.0)
      {
         if(orderPrice >= m_activeArea.buyMaxPenetratedPrice)
         {
            rejectReason = StringFormat("Price %.2f is already touched (Deepest: %.2f)",
                                        orderPrice, m_activeArea.buyMaxPenetratedPrice);
            return false;
         }
      }

      // 5. Exhaustion Level Check
      if(m_activeArea.buyExhaustionLevel == EXHAUSTION_L5_EXHAUSTED)
      {
         rejectReason = "Buy Zone is 100% Fully Exhausted (Level 5)";
         return false;
      }

      rejectReason = "OK";
      return true;
   }

   //+------------------------------------------------------------------+
   //| Validation: Can Sell Order be placed in Roof area?               |
   //| - Must have organic DBD zone (hasOrganicRoof)                    |
   //| - Roof strength must be >= 1 (Strength 1 or 2)                   |
   //| - Price coordinate must be in pristine / virgin depth            |
   //+------------------------------------------------------------------+
   bool CanPlaceSellOrder(const double orderPrice, string &rejectReason) const
   {
      if(!m_activeArea.isValid)
      {
         rejectReason = "No Active TradingArea";
         return false;
      }

      // 1. Organic DBD validation
      if(!m_activeArea.hasOrganicRoof)
      {
         rejectReason = "Roof is Synthetic/Projected (No Organic DBD)";
         return false;
      }

      // 2. Strength Validation (Must be >= 1)
      if(m_activeArea.roofStrength < 1)
      {
         rejectReason = StringFormat("Roof Strength is %d (Weak Str0)", m_activeArea.roofStrength);
         return false;
      }

      // 3. Coordinate within Sell Area (75% - 100%)
      if(orderPrice < m_activeArea.sellZoneStart || orderPrice > m_activeArea.sellZoneEnd)
      {
         rejectReason = StringFormat("Price %.2f outside SellZone [%.2f - %.2f]",
                                     orderPrice, m_activeArea.sellZoneStart, m_activeArea.sellZoneEnd);
         return false;
      }

      // 4. Virgin / Untouched Depth Validation
      // In Sell zone: prices are entered upwards from sellZoneStart up to sellZoneEnd.
      // If price has previously penetrated up to sellMaxPenetratedPrice,
      // any order BELOW sellMaxPenetratedPrice is already used/touched!
      if(m_activeArea.sellMaxPenetratedPrice > 0.0)
      {
         if(orderPrice <= m_activeArea.sellMaxPenetratedPrice)
         {
            rejectReason = StringFormat("Price %.2f is already touched (Deepest: %.2f)",
                                        orderPrice, m_activeArea.sellMaxPenetratedPrice);
            return false;
         }
      }

      // 5. Exhaustion Level Check
      if(m_activeArea.sellExhaustionLevel == EXHAUSTION_L5_EXHAUSTED)
      {
         rejectReason = "Sell Zone is 100% Fully Exhausted (Level 5)";
         return false;
      }

      rejectReason = "OK";
      return true;
   }

   //+------------------------------------------------------------------+
   //| Clear visual objects belonging to this area                      |
   //+------------------------------------------------------------------+
   void ClearChartObjects()
   {
      ObjectsDeleteAll(0, m_objPrefix);
      ChartRedraw(0);
   }

private:
   //+------------------------------------------------------------------+
   //| Build New TradingArea from RBR/DBD engine + Fallbacks            |
   //+------------------------------------------------------------------+
   bool BuildNewTradingArea(const string symbol, CRBRDBDV1 &rbrdbdEngine, const double midPrice)
   {
      SRBRDBDArea floorZone, roofZone;
      floorZone.Init();
      roofZone.Init();

      bool hasFloor = rbrdbdEngine.FindNearestFloor(m_baseTF, midPrice, floorZone);
      bool hasRoof  = rbrdbdEngine.FindNearestRoof(m_baseTF, midPrice, roofZone);

      // If neither floor nor roof found, cannot establish corridor yet
      if(!hasFloor && !hasRoof)
      {
         m_activeArea.Init();
         return false;
      }

      // Daily ATR reference for projection fallbacks
      double dailyATR = GetDailyATR(symbol, 14);
      if(dailyATR <= 0.0) dailyATR = 2500.0 * _Point; // Safe fallback ($25.00 on Gold)

      SLivingTradingArea newArea;
      newArea.Init();
      m_areaCounter++;
      newArea.areaId      = m_areaCounter;
      newArea.createdTime = TimeCurrent();

      // --- 1. RESOLVE FLOOR GEOMETRY ---
      if(hasFloor)
      {
         newArea.hasOrganicFloor = true;
         newArea.floorSource     = BOUNDARY_ORGANIC_RBRDBD;
         newArea.floorBaseStart  = floorZone.baseStart;
         newArea.floorBoundary   = floorZone.finalBoundary;
         newArea.floorDistal     = floorZone.distal;
         newArea.floorProximal   = floorZone.proximal;
         newArea.floorPeriod     = floorZone.period;
         newArea.floorStrength   = floorZone.strengthLevel;
         newArea.floorScore      = floorZone.totalScore;
         newArea.floorDNA        = floorZone.dnaCode;
      }
      else
      {
         // Fallback Floor: Try HTF Swing Low or ATR Projection
         double htfSwingLow = FindHTFSwingLow(symbol, midPrice);
         if(htfSwingLow > 0.0 && htfSwingLow < midPrice)
         {
            newArea.hasOrganicFloor = false;
            newArea.floorSource     = BOUNDARY_HTF_SWING;
            newArea.floorBaseStart  = 0;
            newArea.floorBoundary   = htfSwingLow - (50.0 * _Point);
            newArea.floorDistal     = htfSwingLow;
            newArea.floorProximal   = htfSwingLow;
            newArea.floorPeriod     = PERIOD_M15;
            newArea.floorStrength   = 0;
            newArea.floorScore      = 0;
            newArea.floorDNA        = "----";
         }
         else
         {
            // ATR Projection downwards
            newArea.hasOrganicFloor = false;
            newArea.floorSource     = BOUNDARY_ATR_PROJECTED;
            newArea.floorBaseStart  = 0;
            newArea.floorBoundary   = NormalizeDouble(midPrice - (1.0 * dailyATR), _Digits);
            newArea.floorDistal     = newArea.floorBoundary;
            newArea.floorProximal   = newArea.floorBoundary;
            newArea.floorPeriod     = PERIOD_D1;
            newArea.floorStrength   = 0;
            newArea.floorScore      = 0;
            newArea.floorDNA        = "----";
         }
      }

      // --- 2. RESOLVE ROOF GEOMETRY ---
      if(hasRoof)
      {
         newArea.hasOrganicRoof = true;
         newArea.roofSource     = BOUNDARY_ORGANIC_RBRDBD;
         newArea.roofBaseStart  = roofZone.baseStart;
         newArea.roofBoundary   = roofZone.finalBoundary;
         newArea.roofDistal     = roofZone.distal;
         newArea.roofProximal   = roofZone.proximal;
         newArea.roofPeriod     = roofZone.period;
         newArea.roofStrength   = roofZone.strengthLevel;
         newArea.roofScore      = roofZone.totalScore;
         newArea.roofDNA        = roofZone.dnaCode;
      }
      else
      {
         // Fallback Roof: Try HTF Swing High or ATR Projection
         double htfSwingHigh = FindHTFSwingHigh(symbol, midPrice);
         if(htfSwingHigh > 0.0 && htfSwingHigh > midPrice)
         {
            newArea.hasOrganicRoof = false;
            newArea.roofSource     = BOUNDARY_HTF_SWING;
            newArea.roofBaseStart  = 0;
            newArea.roofBoundary   = htfSwingHigh + (50.0 * _Point);
            newArea.roofDistal     = htfSwingHigh;
            newArea.roofProximal   = htfSwingHigh;
            newArea.roofPeriod     = PERIOD_M15;
            newArea.roofStrength   = 0;
            newArea.roofScore      = 0;
            newArea.roofDNA        = "----";
         }
         else
         {
            // ATR Projection upwards
            newArea.hasOrganicRoof = false;
            newArea.roofSource     = BOUNDARY_ATR_PROJECTED;
            newArea.roofBaseStart  = 0;
            newArea.roofBoundary   = NormalizeDouble(midPrice + (1.0 * dailyATR), _Digits);
            newArea.roofDistal     = newArea.roofBoundary;
            newArea.roofProximal   = newArea.roofBoundary;
            newArea.roofPeriod     = PERIOD_D1;
            newArea.roofStrength   = 0;
            newArea.roofScore      = 0;
            newArea.roofDNA        = "----";
         }
      }

      // --- 3. COMPUTE GEOMETRY & LEVEL VALUES ---
      if(newArea.roofBoundary <= newArea.floorBoundary)
      {
         // Overlapping anomaly guard: ensure minimal separation
         newArea.roofBoundary = NormalizeDouble(newArea.floorBoundary + (100.0 * _Point), _Digits);
      }

      newArea.totalRange    = NormalizeDouble(newArea.roofBoundary - newArea.floorBoundary, _Digits);
      newArea.hardTP50      = NormalizeDouble(newArea.floorBoundary + (0.50 * newArea.totalRange), _Digits);

      // Buy Area (0% to 25%)
      newArea.buyZoneStart  = newArea.floorBoundary;
      newArea.buyZoneEnd    = NormalizeDouble(newArea.floorBoundary + (0.25 * newArea.totalRange), _Digits);
      newArea.floorHardSL   = NormalizeDouble(newArea.floorBoundary - (0.30 * newArea.totalRange), _Digits);

      // Sell Area (75% to 100%)
      newArea.sellZoneStart = NormalizeDouble(newArea.roofBoundary - (0.25 * newArea.totalRange), _Digits);
      newArea.sellZoneEnd   = newArea.roofBoundary;
      newArea.roofHardSL    = NormalizeDouble(newArea.roofBoundary + (0.30 * newArea.totalRange), _Digits);

      newArea.isValid = true;
      m_activeArea    = newArea;

      // Clean prior chart elements and redraw freshly
      ClearChartObjects();
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update Exhaustion State Machine using One-Way Ratchet            |
   //+------------------------------------------------------------------+
   void UpdateExhaustionRatchet(const double bid, const double ask)
   {
      if(!m_activeArea.isValid) return;

      double buySubRange  = m_activeArea.buyZoneEnd - m_activeArea.buyZoneStart;
      double sellSubRange = m_activeArea.sellZoneEnd - m_activeArea.sellZoneStart;

      // 1. Buy Area Exhaustion (Tested by Bid low downwards)
      if(buySubRange > 0.0)
      {
         if(bid <= m_activeArea.buyZoneEnd)
         {
            // Penetrated into Buy zone
            double penetration = m_activeArea.buyZoneEnd - bid;
            double pct = (penetration / buySubRange) * 100.0;

            if(pct > m_activeArea.buyMaxPenetrationPct)
            {
               m_activeArea.buyMaxPenetrationPct  = NormalizeDouble(pct, 1);
               m_activeArea.buyMaxPenetratedPrice = bid;
            }
         }

         // Map to Level 0 - 5
         if(m_activeArea.buyMaxPenetrationPct >= 100.0)
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L5_EXHAUSTED;
         else if(m_activeArea.buyMaxPenetrationPct >= 75.0)
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L4_CRITICAL;
         else if(m_activeArea.buyMaxPenetrationPct >= 50.0)
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L3_DEEP;
         else if(m_activeArea.buyMaxPenetrationPct >= 25.0)
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L2_HALF;
         else if(m_activeArea.buyMaxPenetrationPct > 0.0)
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L1_TOUCHED;
         else
            m_activeArea.buyExhaustionLevel = EXHAUSTION_L0_FRESH;
      }

      // 2. Sell Area Exhaustion (Tested by Ask high upwards)
      if(sellSubRange > 0.0)
      {
         if(ask >= m_activeArea.sellZoneStart)
         {
            // Penetrated into Sell zone
            double penetration = ask - m_activeArea.sellZoneStart;
            double pct = (penetration / sellSubRange) * 100.0;

            if(pct > m_activeArea.sellMaxPenetrationPct)
            {
               m_activeArea.sellMaxPenetrationPct  = NormalizeDouble(pct, 1);
               m_activeArea.sellMaxPenetratedPrice = ask;
            }
         }

         // Map to Level 0 - 5
         if(m_activeArea.sellMaxPenetrationPct >= 100.0)
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L5_EXHAUSTED;
         else if(m_activeArea.sellMaxPenetrationPct >= 75.0)
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L4_CRITICAL;
         else if(m_activeArea.sellMaxPenetrationPct >= 50.0)
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L3_DEEP;
         else if(m_activeArea.sellMaxPenetrationPct >= 25.0)
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L2_HALF;
         else if(m_activeArea.sellMaxPenetrationPct > 0.0)
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L1_TOUCHED;
         else
            m_activeArea.sellExhaustionLevel = EXHAUSTION_L0_FRESH;
      }
   }

   //+------------------------------------------------------------------+
   //| Draw TradingArea Visual Objects (Boxes, TP50, Hard SL lines)     |
   //+------------------------------------------------------------------+
   void DrawTradingAreaObjects()
   {
      if(!m_activeArea.isValid) return;

      datetime curTime = TimeCurrent();
      datetime tStart  = curTime - (PeriodSeconds(m_baseTF) * 20); // Pin to recent bars
      datetime tEnd    = curTime + (PeriodSeconds(m_baseTF) * 35); // Extend into immediate future

      // 1. Buy Area Rectangle (0% - 25%)
      string buyRect = m_objPrefix + "BuyZone";
      if(ObjectFind(0, buyRect) < 0)
         ObjectCreate(0, buyRect, OBJ_RECTANGLE, 0, tStart, m_activeArea.buyZoneEnd, tEnd, m_activeArea.buyZoneStart);
      else
      {
         ObjectMove(0, buyRect, 0, tStart, m_activeArea.buyZoneEnd);
         ObjectMove(0, buyRect, 1, tEnd, m_activeArea.buyZoneStart);
      }
      ObjectSetInteger(0, buyRect, OBJPROP_COLOR, m_clrBuyArea);
      ObjectSetInteger(0, buyRect, OBJPROP_FILL, true);
      ObjectSetInteger(0, buyRect, OBJPROP_BACK, true);
      ObjectSetInteger(0, buyRect, OBJPROP_STYLE, STYLE_SOLID);

      // 2. Sell Area Rectangle (75% - 100%)
      string sellRect = m_objPrefix + "SellZone";
      if(ObjectFind(0, sellRect) < 0)
         ObjectCreate(0, sellRect, OBJ_RECTANGLE, 0, tStart, m_activeArea.sellZoneEnd, tEnd, m_activeArea.sellZoneStart);
      else
      {
         ObjectMove(0, sellRect, 0, tStart, m_activeArea.sellZoneEnd);
         ObjectMove(0, sellRect, 1, tEnd, m_activeArea.sellZoneStart);
      }
      ObjectSetInteger(0, sellRect, OBJPROP_COLOR, m_clrSellArea);
      ObjectSetInteger(0, sellRect, OBJPROP_FILL, true);
      ObjectSetInteger(0, sellRect, OBJPROP_BACK, true);
      ObjectSetInteger(0, sellRect, OBJPROP_STYLE, STYLE_SOLID);

      // 3. Hard TP 50% Equilibrium Line (Dashed Dodger Blue)
      string tpLine = m_objPrefix + "TP50";
      if(ObjectFind(0, tpLine) < 0)
         ObjectCreate(0, tpLine, OBJ_TREND, 0, tStart, m_activeArea.hardTP50, tEnd, m_activeArea.hardTP50);
      else
      {
         ObjectMove(0, tpLine, 0, tStart, m_activeArea.hardTP50);
         ObjectMove(0, tpLine, 1, tEnd, m_activeArea.hardTP50);
      }
      ObjectSetInteger(0, tpLine, OBJPROP_COLOR, m_clrTP50);
      ObjectSetInteger(0, tpLine, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, tpLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, tpLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, tpLine, OBJPROP_BACK, true);

      // TP 50 Tag
      string tpTag = m_objPrefix + "TP50_Tag";
      string tpText = StringFormat("── Hard TP 50%%: %.2f (Equilibrium)", m_activeArea.hardTP50);
      if(ObjectFind(0, tpTag) < 0)
         ObjectCreate(0, tpTag, OBJ_TEXT, 0, tStart, m_activeArea.hardTP50);
      else
         ObjectMove(0, tpTag, 0, tStart, m_activeArea.hardTP50);
      ObjectSetString(0, tpTag, OBJPROP_TEXT, tpText);
      ObjectSetInteger(0, tpTag, OBJPROP_COLOR, m_clrTP50);
      ObjectSetInteger(0, tpTag, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, tpTag, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, tpTag, OBJPROP_FONT, "Arial Bold");

      // 4. Floor Hard SL Line (-30%)
      string floorSLLine = m_objPrefix + "FloorHardSL";
      if(ObjectFind(0, floorSLLine) < 0)
         ObjectCreate(0, floorSLLine, OBJ_TREND, 0, tStart, m_activeArea.floorHardSL, tEnd, m_activeArea.floorHardSL);
      else
      {
         ObjectMove(0, floorSLLine, 0, tStart, m_activeArea.floorHardSL);
         ObjectMove(0, floorSLLine, 1, tEnd, m_activeArea.floorHardSL);
      }
      ObjectSetInteger(0, floorSLLine, OBJPROP_COLOR, m_clrHardSL);
      ObjectSetInteger(0, floorSLLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, floorSLLine, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, floorSLLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, floorSLLine, OBJPROP_BACK, true);

      // 5. Roof Hard SL Line (+30%)
      string roofSLLine = m_objPrefix + "RoofHardSL";
      if(ObjectFind(0, roofSLLine) < 0)
         ObjectCreate(0, roofSLLine, OBJ_TREND, 0, tStart, m_activeArea.roofHardSL, tEnd, m_activeArea.roofHardSL);
      else
      {
         ObjectMove(0, roofSLLine, 0, tStart, m_activeArea.roofHardSL);
         ObjectMove(0, roofSLLine, 1, tEnd, m_activeArea.roofHardSL);
      }
      ObjectSetInteger(0, roofSLLine, OBJPROP_COLOR, m_clrHardSL);
      ObjectSetInteger(0, roofSLLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, roofSLLine, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, roofSLLine, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, roofSLLine, OBJPROP_BACK, true);

      // 6. Buy Exhaustion Label
      string buyTag = m_objPrefix + "BuyExhaustionTag";
      string bStatus = (m_activeArea.buyExhaustionLevel == EXHAUSTION_L0_FRESH) ? "Fresh" : StringFormat("%.1f%%", m_activeArea.buyMaxPenetrationPct);
      string bOrgStr = m_activeArea.hasOrganicFloor ? StringFormat("[Str%d|%s]", m_activeArea.floorStrength, m_activeArea.floorDNA) : "[Synthetic]";
      string buyText = StringFormat(" BUY AREA (0-25%%) | L%d (%s) %s",
                                    (int)m_activeArea.buyExhaustionLevel, bStatus, bOrgStr);
      if(ObjectFind(0, buyTag) < 0)
         ObjectCreate(0, buyTag, OBJ_TEXT, 0, tStart, m_activeArea.buyZoneEnd);
      else
         ObjectMove(0, buyTag, 0, tStart, m_activeArea.buyZoneEnd);
      ObjectSetString(0, buyTag, OBJPROP_TEXT, buyText);
      ObjectSetInteger(0, buyTag, OBJPROP_COLOR, clrMediumSeaGreen);
      ObjectSetInteger(0, buyTag, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, buyTag, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, buyTag, OBJPROP_FONT, "Arial Bold");

      // 7. Sell Exhaustion Label
      string sellTag = m_objPrefix + "SellExhaustionTag";
      string sStatus = (m_activeArea.sellExhaustionLevel == EXHAUSTION_L0_FRESH) ? "Fresh" : StringFormat("%.1f%%", m_activeArea.sellMaxPenetrationPct);
      string sOrgStr = m_activeArea.hasOrganicRoof ? StringFormat("[Str%d|%s]", m_activeArea.roofStrength, m_activeArea.roofDNA) : "[Synthetic]";
      string sellText = StringFormat(" SELL AREA (75-100%%) | L%d (%s) %s",
                                     (int)m_activeArea.sellExhaustionLevel, sStatus, sOrgStr);
      if(ObjectFind(0, sellTag) < 0)
         ObjectCreate(0, sellTag, OBJ_TEXT, 0, tStart, m_activeArea.sellZoneStart);
      else
         ObjectMove(0, sellTag, 0, tStart, m_activeArea.sellZoneStart);
      ObjectSetString(0, sellTag, OBJPROP_TEXT, sellText);
      ObjectSetInteger(0, sellTag, OBJPROP_COLOR, clrLightCoral);
      ObjectSetInteger(0, sellTag, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, sellTag, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, sellTag, OBJPROP_FONT, "Arial Bold");

      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| Helper: Get Daily ATR                                            |
   //+------------------------------------------------------------------+
   double GetDailyATR(const string symbol, const int period = 14)
   {
      MqlRates d1Rates[];
      ArraySetAsSeries(d1Rates, true);
      int copied = CopyRates(symbol, PERIOD_D1, 1, period, d1Rates);
      if(copied < 1) return 0.0;

      double sumTR = 0.0;
      for(int i = 0; i < copied; i++)
      {
         sumTR += (d1Rates[i].high - d1Rates[i].low);
      }
      return (sumTR / copied);
   }

   //+------------------------------------------------------------------+
   //| Helper: Find HTF Swing Low below current price                   |
   //+------------------------------------------------------------------+
   double FindHTFSwingLow(const string symbol, const double price)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, PERIOD_M15, 1, 30, rates);
      if(copied < 5) return 0.0;

      double bestLow = 0.0;
      double closestDist = DBL_MAX;

      for(int i = 2; i < copied - 2; i++)
      {
         bool isValley = (rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
                          rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low);
         if(isValley && rates[i].low < price)
         {
            double dist = price - rates[i].low;
            if(dist < closestDist)
            {
               closestDist = dist;
               bestLow     = rates[i].low;
            }
         }
      }
      return bestLow;
   }

   //+------------------------------------------------------------------+
   //| Helper: Find HTF Swing High above current price                  |
   //+------------------------------------------------------------------+
   double FindHTFSwingHigh(const string symbol, const double price)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(symbol, PERIOD_M15, 1, 30, rates);
      if(copied < 5) return 0.0;

      double bestHigh = 0.0;
      double closestDist = DBL_MAX;

      for(int i = 2; i < copied - 2; i++)
      {
         bool isPeak = (rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
                        rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high);
         if(isPeak && rates[i].high > price)
         {
            double dist = rates[i].high - price;
            if(dist < closestDist)
            {
               closestDist = dist;
               bestHigh    = rates[i].high;
            }
         }
      }
      return bestHigh;
   }
};
//+------------------------------------------------------------------+

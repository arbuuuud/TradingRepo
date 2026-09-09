//+------------------------------------------------------------------+
//|                                                   rbrdbdV1.mqh   |
//|                                           Copyright 2025, Arbud. |
//|                                             https://www.mql5.com |
//|      Multi-Timeframe RBR (Rally-Base-Rally) & DBD (Drop-Base-Drop)|
//|            Supply & Demand Engine with Dynamic Consumption Tracking|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arbud."
#property link      "https://www.mql5.com"
#property strict

#include "StructureV0.mqh"

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_RBRDBD_TYPE
{
   RBRDBD_NONE = 0,
   RBRDBD_RBR  = 1, // Demand: Rally - Base - Rally
   RBRDBD_DBD  = 2  // Supply: Drop - Base - Drop
};

//+------------------------------------------------------------------+
//| Struct for Individual Zone                                       |
//+------------------------------------------------------------------+
struct SRBRDBDArea
{
   ENUM_RBRDBD_TYPE  type;             // 1 = RBR, 2 = DBD
   datetime          baseStart;        // Time of first base candle
   datetime          baseEnd;          // Time of last base candle
   datetime          legOutTime;       // Time of Leg-Out candle
   double            proximal;         // Entry boundary (High for RBR, Low for DBD)
   double            distal;           // Invalidation/SL boundary (Low for RBR, High for DBD)
   double            zoneHeight;       // |Proximal - Distal|
   int               baseCandleCount;  // 1 to N base candles
   double            consumptionPct;   // 0.0% to 100.0%
   bool              isInvalid;        // True if consumption >= 100.0%
   datetime          invalidTime;      // Candle time when 100% consumption occurred
   datetime          lastCheckedTime;  // Bar time when consumption was last evaluated
   string            objName;          // Chart rectangle object name

   void Init()
   {
      type            = RBRDBD_NONE;
      baseStart       = 0;
      baseEnd         = 0;
      legOutTime      = 0;
      proximal        = 0.0;
      distal          = 0.0;
      zoneHeight      = 0.0;
      baseCandleCount = 0;
      consumptionPct  = 0.0;
      isInvalid       = false;
      invalidTime     = 0;
      lastCheckedTime = 0;
      objName         = "";
   }
};

//+------------------------------------------------------------------+
//| Struct for Roof and Floor Range Channel                          |
//+------------------------------------------------------------------+
struct SRoofFloorChannel
{
   bool              isValid;
   double            roofPrice;        // Top border of DBD base (Distal of DBD)
   double            floorPrice;       // Bottom border of RBR base (Distal of RBR)
   double            medianPrice;      // (Roof + Floor) / 2
   string            roofSource;       // "DBD", "SwingHigh (Fallback)", "ATH (Projected)"
   string            floorSource;      // "RBR", "SwingLow (Fallback)", "ATL (Projected)"
   datetime          startTime;        // Earliest relevant base start time
   datetime          endTime;          // Future projection time
   string            channelName;

   void Init()
   {
      isValid     = false;
      roofPrice   = 0.0;
      floorPrice  = 0.0;
      medianPrice = 0.0;
      roofSource  = "";
      floorSource = "";
      startTime   = 0;
      endTime     = 0;
      channelName = "";
   }
};

//+------------------------------------------------------------------+
//| Struct for Timeframe Data                                        |
//+------------------------------------------------------------------+
struct STimeframeRBRDBDData
{
   ENUM_TIMEFRAMES   tf;
   int               minBaseCandles;
   int               maxBaseCandles;
   double            minLegRatio;
   bool              drawEnabled;
   bool              drawRoofFloor;
   color             rbrColor;
   color             dbdColor;
   color             usedColor;
   color             invalidColor;
   color             roofColor;
   color             floorColor;
   color             channelBgColor;
   datetime          lastBarTime;

   SRBRDBDArea       areas[];
   SRoofFloorChannel currentChannel;

   void Init(ENUM_TIMEFRAMES period, 
             int minBase = 1, 
             int maxBase = 7, 
             double legRatio = 1.0, 
             bool draw = true,
             bool drawRF = true,
             color clrRBR = clrLimeGreen, 
             color clrDBD = clrCrimson,
             color clrUsed = clrSandyBrown,
             color clrInvalid = clrGray,
             color clrRoof = clrIndianRed,
             color clrFloor = clrMediumSeaGreen,
             color clrBg = C'20,30,45')
   {
      tf             = period;
      minBaseCandles = minBase;
      maxBaseCandles = maxBase;
      minLegRatio    = legRatio;
      drawEnabled    = draw;
      drawRoofFloor  = drawRF;
      rbrColor       = clrRBR;
      dbdColor       = clrDBD;
      usedColor      = clrUsed;
      invalidColor   = clrInvalid;
      roofColor      = clrRoof;
      floorColor     = clrFloor;
      channelBgColor = clrBg;
      lastBarTime    = 0;

      ArrayResize(areas, 0);
      currentChannel.Init();
   }
};

//+------------------------------------------------------------------+
//| Class CRBRDBDV1                                                  |
//+------------------------------------------------------------------+
class CRBRDBDV1
{
private:
   STimeframeRBRDBDData m_tfList[];
   int                  m_totalTFs;
   string               m_objPrefix;

public:
   CRBRDBDV1() : m_totalTFs(0), m_objPrefix("RBRDBD_")
   {
      ArrayResize(m_tfList, 0);
   }

   ~CRBRDBDV1()
   {
      ClearChartObjects();
      ArrayFree(m_tfList);
   }

   //+------------------------------------------------------------------+
   //| Register a specific Timeframe with customizable base limits      |
   //+------------------------------------------------------------------+
   bool RegisterTimeframe(const ENUM_TIMEFRAMES tf,
                          const int minBaseCandles = 1,
                          const int maxBaseCandles = 7,
                          const double minLegRatio = 1.0,
                          const bool drawOnChart = true,
                          const bool drawRoofFloor = true,
                          const color rbrColor = clrSeaGreen,
                          const color dbdColor = clrIndianRed,
                          const color roofColor = clrCrimson,
                          const color floorColor = clrLimeGreen)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf)
         {
            m_tfList[i].minBaseCandles = minBaseCandles;
            m_tfList[i].maxBaseCandles = maxBaseCandles;
            m_tfList[i].minLegRatio    = minLegRatio;
            m_tfList[i].drawEnabled    = drawOnChart;
            m_tfList[i].drawRoofFloor  = drawRoofFloor;
            m_tfList[i].rbrColor       = rbrColor;
            m_tfList[i].dbdColor       = dbdColor;
            m_tfList[i].roofColor      = roofColor;
            m_tfList[i].floorColor     = floorColor;
            return true;
         }
      }

      m_totalTFs++;
      if(ArrayResize(m_tfList, m_totalTFs) < m_totalTFs)
      {
         PrintFormat("[CRBRDBDV1] Failed to resize TF array for %s", EnumToString(tf));
         return false;
      }

      m_tfList[m_totalTFs - 1].Init(tf, minBaseCandles, maxBaseCandles, minLegRatio, drawOnChart, drawRoofFloor, rbrColor, dbdColor, clrSandyBrown, clrGray, roofColor, floorColor);
      PrintFormat("[CRBRDBDV1] Registered TF: %s (Base: %d~%d candles, Ratio: %.1f, RoofFloor: %s)", 
                  EnumToString(tf), minBaseCandles, maxBaseCandles, minLegRatio, drawRoofFloor ? "true" : "false");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Scan history bars from past to present and track consumption     |
   //+------------------------------------------------------------------+
   void InitHistory(const string symbol, const int maxBars = 500, CStructureV0 *structureEngine = NULL)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         InitTFHistory(symbol, m_tfList[i], maxBars, structureEngine);
      }
   }

   //+------------------------------------------------------------------+
   //| Event-Driven Update: Called in OnTick, runs when candle closes   |
   //+------------------------------------------------------------------+
   void UpdateOnCandleClose(const string symbol, CStructureV0 *structureEngine = NULL)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         ENUM_TIMEFRAMES tf = m_tfList[i].tf;
         datetime currentBarTime = iTime(symbol, tf, 0);

         if(currentBarTime != 0 && currentBarTime != m_tfList[i].lastBarTime)
         {
            m_tfList[i].lastBarTime = currentBarTime;

            // 1. Scan for newly formed RBR/DBD zone
            ScanRecentBars(symbol, m_tfList[i]);

            // 2. Evaluate consumption on completed bar 1 across all existing zones
            EvaluateClosedBarConsumption(symbol, m_tfList[i]);

            // 3. Redraw visual rectangles & labels on chart
            if(m_tfList[i].drawEnabled)
            {
               DrawAllAreas(m_tfList[i]);
            }

            // 4. Update and draw Roof & Floor Channel
            if(m_tfList[i].drawRoofFloor)
            {
               double curPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
               CalculateRoofFloorChannel(symbol, m_tfList[i], curPrice, structureEngine);
               DrawRoofFloorChannel(m_tfList[i]);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Real-time consumption evaluation from live tick (Bid/Ask)        |
   //+------------------------------------------------------------------+
   void UpdateConsumptionOnTick(const string symbol, const double bid, const double ask, CStructureV0 *structureEngine = NULL)
   {
      datetime currentTickTime = TimeCurrent();

      for(int i = 0; i < m_totalTFs; i++)
      {
         bool changed = false;
         int total = ArraySize(m_tfList[i].areas);

         for(int a = 0; a < total; a++)
         {
            if(m_tfList[i].areas[a].isInvalid) continue;

            double testPrice = (m_tfList[i].areas[a].type == RBRDBD_RBR) ? bid : ask;
            if(UpdateSingleAreaConsumption(m_tfList[i].areas[a], testPrice, testPrice, currentTickTime))
            {
               changed = true;
            }
         }

         if(changed && m_tfList[i].drawEnabled)
         {
            DrawAllAreas(m_tfList[i]);
         }

         if(m_tfList[i].drawRoofFloor)
         {
            double curPrice = (bid > 0) ? bid : ask;
            CalculateRoofFloorChannel(symbol, m_tfList[i], curPrice, structureEngine);
            DrawRoofFloorChannel(m_tfList[i]);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Clear all visual chart objects created by this engine            |
   //+------------------------------------------------------------------+
   void ClearChartObjects()
   {
      ObjectsDeleteAll(0, m_objPrefix);
   }

   //+------------------------------------------------------------------+
   //| Get count of active valid zones for a timeframe                  |
   //+------------------------------------------------------------------+
   int GetValidAreasCount(const ENUM_TIMEFRAMES tf)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return 0;

      int count = 0;
      int total = ArraySize(m_tfList[idx].areas);
      for(int i = 0; i < total; i++)
      {
         if(!m_tfList[idx].areas[i].isInvalid) count++;
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get all areas (including consumption %) for a timeframe          |
   //+------------------------------------------------------------------+
   bool GetAreas(const ENUM_TIMEFRAMES tf, SRBRDBDArea &outArray[])
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return false;

      int total = ArraySize(m_tfList[idx].areas);
      if(total <= 0) return false;

      ArrayResize(outArray, total);
      for(int i = 0; i < total; i++)
      {
         outArray[i] = m_tfList[idx].areas[i];
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get Current Roof and Floor Channel for a timeframe               |
   //+------------------------------------------------------------------+
   bool GetRoofFloorChannel(const ENUM_TIMEFRAMES tf, SRoofFloorChannel &outChannel)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return false;

      if(!m_tfList[idx].currentChannel.isValid) return false;

      outChannel = m_tfList[idx].currentChannel;
      return true;
   }

private:
   int FindTFIndex(const ENUM_TIMEFRAMES tf)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf) return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Scan history from past to present for one timeframe              |
   //+------------------------------------------------------------------+
   void InitTFHistory(const string symbol, STimeframeRBRDBDData &data, const int maxBars, CStructureV0 *structureEngine = NULL)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(symbol, data.tf, 0, maxBars + 15, rates);
      if(copied < (data.maxBaseCandles + 5)) return;

      ArrayResize(data.areas, 0);

      // Clear existing chart objects for this TF
      string tfPrefix = m_objPrefix + EnumToString(data.tf) + "_";
      ObjectsDeleteAll(0, tfPrefix);

      // Scan from oldest to newest:
      // index 'outIdx' represents the Leg-Out candle
      for(int outIdx = copied - 3; outIdx >= 1; outIdx--)
      {
         DetectPatternAtBar(rates, copied, outIdx, data);
      }

      // Track consumption sequentially from formation time up to Bar 1
      for(int a = 0; a < ArraySize(data.areas); a++)
      {
         // Find candle index of Leg-Out
         for(int b = copied - 1; b >= 1; b--)
         {
            if(rates[b].time > data.areas[a].legOutTime)
            {
               UpdateSingleAreaConsumption(data.areas[a], rates[b].low, rates[b].high, rates[b].time);
               if(data.areas[a].isInvalid) break;
            }
         }
      }

      if(data.drawEnabled)
      {
         DrawAllAreas(data);
      }

      if(data.drawRoofFloor)
      {
         double curPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
         CalculateRoofFloorChannel(symbol, data, curPrice, structureEngine);
         DrawRoofFloorChannel(data);
      }

      PrintFormat("[CRBRDBDV1] InitHistory for %s: %d zones found (%d valid/active).",
                  EnumToString(data.tf), ArraySize(data.areas), GetValidAreasCount(data.tf));
   }

   //+------------------------------------------------------------------+
   //| Scan most recent completed bars                                  |
   //+------------------------------------------------------------------+
   void ScanRecentBars(const string symbol, STimeframeRBRDBDData &data)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int needed = data.maxBaseCandles + 5;
      if(CopyRates(symbol, data.tf, 0, needed, rates) < needed) return;

      // Check if Bar 1 was a Leg-Out candle of a new RBR or DBD
      DetectPatternAtBar(rates, needed, 1, data);
   }

   //+------------------------------------------------------------------+
   //| Core Pattern Detection logic at candle index 'outIdx'            |
   //+------------------------------------------------------------------+
   void DetectPatternAtBar(const MqlRates &rates[], const int totalRates, const int outIdx, STimeframeRBRDBDData &data)
   {
      // 1. Evaluate Leg-Out Candle (Strong Extended Range Candle - ERC)
      double outBody  = MathAbs(rates[outIdx].close - rates[outIdx].open);
      double outRange = rates[outIdx].high - rates[outIdx].low;
      if(outRange <= 0.0 || (outBody / outRange) < 0.50) return; // Body must be at least 50% of range

      bool outBullish = (rates[outIdx].close > rates[outIdx].open);
      bool outBearish = (rates[outIdx].close < rates[outIdx].open);

      // Check for duplication at this leg-out time
      for(int a = 0; a < ArraySize(data.areas); a++)
      {
         if(data.areas[a].legOutTime == rates[outIdx].time) return;
      }

      // 2. Iterate base length from minBaseCandles to maxBaseCandles
      for(int baseLen = data.minBaseCandles; baseLen <= data.maxBaseCandles; baseLen++)
      {
         int baseStart = outIdx + 1;
         int baseEnd   = outIdx + baseLen;
         int legInIdx  = baseEnd + 1;

         if(legInIdx >= totalRates - 1) break;

         // Evaluate Base Candles (Boring candles, tight range)
         double baseHigh = 0.0;
         double baseLow  = DBL_MAX;
         bool baseValid  = true;

         for(int b = baseStart; b <= baseEnd; b++)
         {
            double bBody  = MathAbs(rates[b].close - rates[b].open);
            double bRange = rates[b].high - rates[b].low;

            // Boring candle rule: Body should not dominate the candle (> 60% rejected as boring)
            if(bRange > 0.0 && (bBody / bRange) > 0.65)
            {
               baseValid = false;
               break;
            }

            if(rates[b].high > baseHigh) baseHigh = rates[b].high;
            if(rates[b].low < baseLow)   baseLow  = rates[b].low;
         }

         if(!baseValid || baseHigh <= baseLow) continue;

         double baseRange = baseHigh - baseLow;
         if(baseRange <= 0.0) continue;

         // Check Leg-Out to Base Range Ratio
         if(outRange < (baseRange * data.minLegRatio)) continue;

         // 3. Evaluate Leg-In Candle (Strong ERC)
         double inBody  = MathAbs(rates[legInIdx].close - rates[legInIdx].open);
         double inRange = rates[legInIdx].high - rates[legInIdx].low;
         if(inRange <= 0.0 || (inBody / inRange) < 0.50) continue;

         bool inBullish = (rates[legInIdx].close > rates[legInIdx].open);
         bool inBearish = (rates[legInIdx].close < rates[legInIdx].open);

         // === PATTERN A: RBR (Bullish Leg-In + Base + Bullish Leg-Out breaking Base High) ===
         if(inBullish && outBullish && rates[outIdx].close > baseHigh)
         {
            RegisterNewArea(data, RBRDBD_RBR, rates[baseEnd].time, rates[baseStart].time, rates[outIdx].time,
                            baseHigh, baseLow, baseLen);
            return; // Found valid pattern for this outIdx
         }

         // === PATTERN B: DBD (Bearish Leg-In + Base + Bearish Leg-Out breaking Base Low) ===
         if(inBearish && outBearish && rates[outIdx].close < baseLow)
         {
            RegisterNewArea(data, RBRDBD_DBD, rates[baseEnd].time, rates[baseStart].time, rates[outIdx].time,
                            baseLow, baseHigh, baseLen);
            return; // Found valid pattern for this outIdx
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Register newly identified zone into areas array                  |
   //+------------------------------------------------------------------+
   void RegisterNewArea(STimeframeRBRDBDData &data,
                        const ENUM_RBRDBD_TYPE type,
                        const datetime bStart,
                        const datetime bEnd,
                        const datetime lOutTime,
                        const double prox,
                        const double dist,
                        const int baseCount)
   {
      int size = ArraySize(data.areas);
      ArrayResize(data.areas, size + 1);

      data.areas[size].Init();
      data.areas[size].type            = type;
      data.areas[size].baseStart       = bStart;
      data.areas[size].baseEnd         = bEnd;
      data.areas[size].legOutTime      = lOutTime;
      data.areas[size].proximal        = prox;
      data.areas[size].distal          = dist;
      data.areas[size].zoneHeight      = MathAbs(prox - dist);
      data.areas[size].baseCandleCount = baseCount;
      data.areas[size].consumptionPct  = 0.0;
      data.areas[size].isInvalid       = false;

      string lbl = (type == RBRDBD_RBR) ? "RBR" : "DBD";
      data.areas[size].objName = m_objPrefix + EnumToString(data.tf) + "_" + lbl + "_" + TimeToString(bStart, TIME_DATE|TIME_MINUTES);
   }

   //+------------------------------------------------------------------+
   //| Evaluate consumption on completed bar 1                          |
   //+------------------------------------------------------------------+
   void EvaluateClosedBarConsumption(const string symbol, STimeframeRBRDBDData &data)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, data.tf, 1, 1, rates) < 1) return;

      int total = ArraySize(data.areas);
      for(int a = 0; a < total; a++)
      {
         if(data.areas[a].isInvalid) continue;
         if(rates[0].time <= data.areas[a].legOutTime) continue;

         UpdateSingleAreaConsumption(data.areas[a], rates[0].low, rates[0].high, rates[0].time);
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate and update consumption percentage for a single zone    |
   //+------------------------------------------------------------------+
   bool UpdateSingleAreaConsumption(SRBRDBDArea &area, const double testLow, const double testHigh, const datetime hitTime)
   {
      if(area.isInvalid || area.zoneHeight <= 0.0) return false;

      bool updated = false;

      // --- Demand (RBR): Proximal = Top, Distal = Bottom ---
      if(area.type == RBRDBD_RBR)
      {
         // If price entered into or below proximal
         if(testLow < area.proximal)
         {
            double penetration = area.proximal - testLow;
            double currentPct  = (penetration / area.zoneHeight) * 100.0;

            if(currentPct > area.consumptionPct)
            {
               area.consumptionPct = NormalizeDouble(currentPct, 1);
               updated = true;
            }

            if(testLow <= area.distal || area.consumptionPct >= 100.0)
            {
               area.consumptionPct = 100.0;
               area.isInvalid      = true;
               area.invalidTime    = hitTime;
               updated             = true;
            }
         }
      }
      // --- Supply (DBD): Proximal = Bottom, Distal = Top ---
      else if(area.type == RBRDBD_DBD)
      {
         // If price entered into or above proximal
         if(testHigh > area.proximal)
         {
            double penetration = testHigh - area.proximal;
            double currentPct  = (penetration / area.zoneHeight) * 100.0;

            if(currentPct > area.consumptionPct)
            {
               area.consumptionPct = NormalizeDouble(currentPct, 1);
               updated = true;
            }

            if(testHigh >= area.distal || area.consumptionPct >= 100.0)
            {
               area.consumptionPct = 100.0;
               area.isInvalid      = true;
               area.invalidTime    = hitTime;
               updated             = true;
            }
         }
      }

      return updated;
   }

   //+------------------------------------------------------------------+
   //| Draw all zones and percentage labels on chart                    |
   //+------------------------------------------------------------------+
   void DrawAllAreas(STimeframeRBRDBDData &data)
   {
      int total = ArraySize(data.areas);
      if(total <= 0) return;

      datetime futureTime = TimeCurrent() + (PeriodSeconds(data.tf) * 15);

      for(int a = 0; a < total; a++)
      {
         SRBRDBDArea area = data.areas[a];
         string rectName = area.objName;
         string textName = rectName + "_lbl";

         // Select visual color based on consumption status
         color clr;
         if(area.isInvalid)
         {
            clr = data.invalidColor;
         }
         else if(area.consumptionPct > 0.0)
         {
            clr = data.usedColor;
         }
         else
         {
            clr = (area.type == RBRDBD_RBR) ? data.rbrColor : data.dbdColor;
         }

         double topPrice = MathMax(area.proximal, area.distal);
         double botPrice = MathMin(area.proximal, area.distal);

         // End time: if invalid (100% used), stop exactly at the candle that consumed it!
         datetime rectEndTime = futureTime;
         if(area.isInvalid && area.invalidTime > 0)
         {
            rectEndTime = area.invalidTime;
         }

         // Draw / Update Rectangle
         if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, area.baseStart, topPrice, rectEndTime, botPrice))
         {
            ObjectMove(0, rectName, 0, area.baseStart, topPrice);
            ObjectMove(0, rectName, 1, rectEndTime, botPrice);
         }
         ObjectSetInteger(0, rectName, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
         ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rectName, OBJPROP_STYLE, area.isInvalid ? STYLE_DOT : STYLE_SOLID);

         // Format status text
         string typeStr = (area.type == RBRDBD_RBR) ? "RBR" : "DBD";
         string statusStr;
         if(area.isInvalid)
            statusStr = StringFormat(" %s %s [%d C] (100%% Used)", EnumToString(data.tf), typeStr, area.baseCandleCount);
         else if(area.consumptionPct > 0.0)
            statusStr = StringFormat(" %s %s [%d C] (%.1f%% Used)", EnumToString(data.tf), typeStr, area.baseCandleCount, area.consumptionPct);
         else
            statusStr = StringFormat(" %s %s [%d C] (Fresh)", EnumToString(data.tf), typeStr, area.baseCandleCount);

         // Draw / Update Text (pinned to baseStart)
         if(!ObjectCreate(0, textName, OBJ_TEXT, 0, area.baseStart, topPrice))
         {
            ObjectMove(0, textName, 0, area.baseStart, topPrice);
         }
         ObjectSetString(0, textName, OBJPROP_TEXT, statusStr);
         ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, textName, OBJPROP_FONT, "Arial Bold");
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate Roof & Floor with 5-Level Priority Hierarchy           |
   //+------------------------------------------------------------------+
   void CalculateRoofFloorChannel(const string symbol, 
                                  STimeframeRBRDBDData &data, 
                                  const double currentPrice, 
                                  CStructureV0 *structureEngine = NULL)
   {
      data.currentChannel.Init();
      if(currentPrice <= 0.0) return;

      int currentTFIndex = FindTFIndex(data.tf);
      ENUM_TIMEFRAMES higherTF = GetNextHigherTF(data.tf);
      int higherTFIndex = (higherTF != PERIOD_CURRENT) ? FindTFIndex(higherTF) : -1;

      // ====================================================================
      // 1. DETERMINE ROOF (PRIORITAS 1 -> 2 -> 3 -> 4 -> INVALID)
      // ====================================================================
      double roofPrice = 0.0;
      string roofSource = "";
      datetime roofTime = 0;

      // --- Prioritas 1: DBD terdekat di TF yang sama (di atas harga) ---
      if(currentTFIndex >= 0)
      {
         double nearestDBD = DBL_MAX;
         datetime nTime = 0;
         for(int a = 0; a < ArraySize(m_tfList[currentTFIndex].areas); a++)
         {
            if(m_tfList[currentTFIndex].areas[a].isInvalid) continue;
            if(m_tfList[currentTFIndex].areas[a].type == RBRDBD_DBD)
            {
               double top = m_tfList[currentTFIndex].areas[a].distal;
               if(top >= currentPrice && top < nearestDBD)
               {
                  nearestDBD = top;
                  nTime      = m_tfList[currentTFIndex].areas[a].baseStart;
               }
            }
         }
         if(nearestDBD < DBL_MAX)
         {
            roofPrice  = nearestDBD;
            roofSource = EnumToString(data.tf) + " DBD";
            roofTime   = nTime;
         }
      }

      // --- Prioritas 2: DBD terdekat di 1 level TF di atasnya ---
      if(roofPrice <= 0.0 && higherTFIndex >= 0)
      {
         double nearestDBD = DBL_MAX;
         datetime nTime = 0;
         for(int a = 0; a < ArraySize(m_tfList[higherTFIndex].areas); a++)
         {
            if(m_tfList[higherTFIndex].areas[a].isInvalid) continue;
            if(m_tfList[higherTFIndex].areas[a].type == RBRDBD_DBD)
            {
               double top = m_tfList[higherTFIndex].areas[a].distal;
               if(top >= currentPrice && top < nearestDBD)
               {
                  nearestDBD = top;
                  nTime      = m_tfList[higherTFIndex].areas[a].baseStart;
               }
            }
         }
         if(nearestDBD < DBL_MAX)
         {
            roofPrice  = nearestDBD;
            roofSource = EnumToString(higherTF) + " DBD (Higher TF)";
            roofTime   = nTime;
         }
      }

      // --- Prioritas 3: Structure Swing High ke-2 terdekat di TF yang sama ---
      if(roofPrice <= 0.0 && structureEngine != NULL)
      {
         double sh2Price = 0.0;
         datetime sh2Time = 0;
         string sh2Label = "";
         if(FindSecondNearestSwingHigh(structureEngine, data.tf, currentPrice, sh2Price, sh2Time, sh2Label))
         {
            roofPrice  = sh2Price;
            roofSource = EnumToString(data.tf) + " Struct #2 (" + sh2Label + ")";
            roofTime   = sh2Time;
         }
      }

      // --- Prioritas 4: Structure Swing High ke-2 terdekat di 1 level TF di atasnya ---
      if(roofPrice <= 0.0 && structureEngine != NULL && higherTF != PERIOD_CURRENT)
      {
         double sh2Price = 0.0;
         datetime sh2Time = 0;
         string sh2Label = "";
         if(FindSecondNearestSwingHigh(structureEngine, higherTF, currentPrice, sh2Price, sh2Time, sh2Label))
         {
            roofPrice  = sh2Price;
            roofSource = EnumToString(higherTF) + " Struct #2 (" + sh2Label + " Higher TF)";
            roofTime   = sh2Time;
         }
      }

      // ====================================================================
      // 2. DETERMINE FLOOR (PRIORITAS 1 -> 2 -> 3 -> 4 -> INVALID)
      // ====================================================================
      double floorPrice = 0.0;
      string floorSource = "";
      datetime floorTime = 0;

      // --- Prioritas 1: RBR terdekat di TF yang sama (di bawah harga) ---
      if(currentTFIndex >= 0)
      {
         double nearestRBR = 0.0;
         datetime nTime = 0;
         for(int a = 0; a < ArraySize(m_tfList[currentTFIndex].areas); a++)
         {
            if(m_tfList[currentTFIndex].areas[a].isInvalid) continue;
            if(m_tfList[currentTFIndex].areas[a].type == RBRDBD_RBR)
            {
               double bottom = m_tfList[currentTFIndex].areas[a].distal;
               if(bottom <= currentPrice && bottom > nearestRBR)
               {
                  nearestRBR = bottom;
                  nTime      = m_tfList[currentTFIndex].areas[a].baseStart;
               }
            }
         }
         if(nearestRBR > 0.0)
         {
            floorPrice  = nearestRBR;
            floorSource = EnumToString(data.tf) + " RBR";
            floorTime   = nTime;
         }
      }

      // --- Prioritas 2: RBR terdekat di 1 level TF di atasnya ---
      if(floorPrice <= 0.0 && higherTFIndex >= 0)
      {
         double nearestRBR = 0.0;
         datetime nTime = 0;
         for(int a = 0; a < ArraySize(m_tfList[higherTFIndex].areas); a++)
         {
            if(m_tfList[higherTFIndex].areas[a].isInvalid) continue;
            if(m_tfList[higherTFIndex].areas[a].type == RBRDBD_RBR)
            {
               double bottom = m_tfList[higherTFIndex].areas[a].distal;
               if(bottom <= currentPrice && bottom > nearestRBR)
               {
                  nearestRBR = bottom;
                  nTime      = m_tfList[higherTFIndex].areas[a].baseStart;
               }
            }
         }
         if(nearestRBR > 0.0)
         {
            floorPrice  = nearestRBR;
            floorSource = EnumToString(higherTF) + " RBR (Higher TF)";
            floorTime   = nTime;
         }
      }

      // --- Prioritas 3: Structure Swing Low ke-2 terdekat di TF yang sama ---
      if(floorPrice <= 0.0 && structureEngine != NULL)
      {
         double sl2Price = 0.0;
         datetime sl2Time = 0;
         string sl2Label = "";
         if(FindSecondNearestSwingLow(structureEngine, data.tf, currentPrice, sl2Price, sl2Time, sl2Label))
         {
            floorPrice  = sl2Price;
            floorSource = EnumToString(data.tf) + " Struct #2 (" + sl2Label + ")";
            floorTime   = sl2Time;
         }
      }

      // --- Prioritas 4: Structure Swing Low ke-2 terdekat di 1 level TF di atasnya ---
      if(floorPrice <= 0.0 && structureEngine != NULL && higherTF != PERIOD_CURRENT)
      {
         double sl2Price = 0.0;
         datetime sl2Time = 0;
         string sl2Label = "";
         if(FindSecondNearestSwingLow(structureEngine, higherTF, currentPrice, sl2Price, sl2Time, sl2Label))
         {
            floorPrice  = sl2Price;
            floorSource = EnumToString(higherTF) + " Struct #2 (" + sl2Label + " Higher TF)";
            floorTime   = sl2Time;
         }
      }

      // ====================================================================
      // 3. VALIDASI AKHIR (PRIORITAS 5: JIKA TIDAK DITEMUKAN -> INVALID)
      // ====================================================================
      if(roofPrice <= 0.0 || floorPrice <= 0.0 || roofPrice <= floorPrice)
      {
         data.currentChannel.Init();
         data.currentChannel.channelName = m_objPrefix + EnumToString(data.tf) + "_RoofFloor";
         data.currentChannel.isValid = false;
         return; // Invalid channel!
      }

      // Channel Valid
      data.currentChannel.isValid     = true;
      data.currentChannel.roofPrice   = roofPrice;
      data.currentChannel.floorPrice  = floorPrice;
      data.currentChannel.roofSource  = roofSource;
      data.currentChannel.floorSource = floorSource;

      datetime tStart = (roofTime > 0 && floorTime > 0) ? MathMin(roofTime, floorTime) : MathMax(roofTime, floorTime);
      if(tStart == 0) tStart = TimeCurrent() - (PeriodSeconds(data.tf) * 20);

      data.currentChannel.startTime   = tStart;
      data.currentChannel.endTime     = TimeCurrent() + (PeriodSeconds(data.tf) * 15);
      data.currentChannel.medianPrice = (roofPrice + floorPrice) / 2.0;
      data.currentChannel.channelName = m_objPrefix + EnumToString(data.tf) + "_RoofFloor";
   }

   //+------------------------------------------------------------------+
   //| Helper: Get Next Higher Timeframe in registered ladder           |
   //+------------------------------------------------------------------+
   ENUM_TIMEFRAMES GetNextHigherTF(const ENUM_TIMEFRAMES tf)
   {
      // Known ladder: M1 -> M3 -> M15 -> H1
      if(tf == PERIOD_M1)  return PERIOD_M3;
      if(tf == PERIOD_M3)  return PERIOD_M15;
      if(tf == PERIOD_M15) return PERIOD_H1;
      return PERIOD_CURRENT; // No higher TF defined beyond H1
   }

   //+------------------------------------------------------------------+
   //| Helper: Find the 2nd nearest Swing High above current price      |
   //+------------------------------------------------------------------+
   bool FindSecondNearestSwingHigh(CStructureV0 *structureEngine,
                                  const ENUM_TIMEFRAMES tf,
                                  const double currentPrice,
                                  double &outPrice,
                                  datetime &outTime,
                                  string &outLabel)
   {
      SStructurePoint structs[];
      if(!structureEngine.GetStructures(tf, structs)) return false;

      int total = ArraySize(structs);
      if(total < 2) return false;

      // Collect all swing highs above current price
      double highs[];
      datetime times[];
      string labels[];
      ArrayResize(highs, 0);
      ArrayResize(times, 0);
      ArrayResize(labels, 0);

      for(int i = 0; i < total; i++)
      {
         string lbl = structs[i].label;
         if(lbl == "H" || lbl == "HH" || lbl == "LH")
         {
            if(structs[i].priceH > currentPrice)
            {
               int s = ArraySize(highs);
               ArrayResize(highs, s + 1);
               ArrayResize(times, s + 1);
               ArrayResize(labels, s + 1);
               highs[s]  = structs[i].priceH;
               times[s]  = structs[i].candleTime;
               labels[s] = lbl;
            }
         }
      }

      int count = ArraySize(highs);
      if(count < 2) return false; // Need at least 2 to pick the 2nd nearest!

      // Sort ascending (nearest to currentPrice first)
      for(int i = 0; i < count - 1; i++)
      {
         for(int j = i + 1; j < count; j++)
         {
            if(highs[j] < highs[i])
            {
               double tempH = highs[i];   highs[i]  = highs[j];  highs[j]  = tempH;
               datetime tempT = times[i]; times[i]  = times[j];  times[j]  = tempT;
               string tempL = labels[i];  labels[i] = labels[j]; labels[j] = tempL;
            }
         }
      }

      // Pick the 2nd nearest (index 1)
      outPrice = highs[1];
      outTime  = times[1];
      outLabel = labels[1];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Helper: Find the 2nd nearest Swing Low below current price       |
   //+------------------------------------------------------------------+
   bool FindSecondNearestSwingLow(CStructureV0 *structureEngine,
                                 const ENUM_TIMEFRAMES tf,
                                 const double currentPrice,
                                 double &outPrice,
                                 datetime &outTime,
                                 string &outLabel)
   {
      SStructurePoint structs[];
      if(!structureEngine.GetStructures(tf, structs)) return false;

      int total = ArraySize(structs);
      if(total < 2) return false;

      // Collect all swing lows below current price
      double lows[];
      datetime times[];
      string labels[];
      ArrayResize(lows, 0);
      ArrayResize(times, 0);
      ArrayResize(labels, 0);

      for(int i = 0; i < total; i++)
      {
         string lbl = structs[i].label;
         if(lbl == "L" || lbl == "LL" || lbl == "HL")
         {
            if(structs[i].priceL < currentPrice)
            {
               int s = ArraySize(lows);
               ArrayResize(lows, s + 1);
               ArrayResize(times, s + 1);
               ArrayResize(labels, s + 1);
               lows[s]  = structs[i].priceL;
               times[s]  = structs[i].candleTime;
               labels[s] = lbl;
            }
         }
      }

      int count = ArraySize(lows);
      if(count < 2) return false; // Need at least 2 to pick the 2nd nearest!

      // Sort descending (nearest to currentPrice first: e.g. 2630 before 2620)
      for(int i = 0; i < count - 1; i++)
      {
         for(int j = i + 1; j < count; j++)
         {
            if(lows[j] > lows[i])
            {
               double tempL = lows[i];    lows[i]   = lows[j];   lows[j]   = tempL;
               datetime tempT = times[i]; times[i]  = times[j];  times[j]  = tempT;
               string tempLStr = labels[i]; labels[i] = labels[j]; labels[j] = tempLStr;
            }
         }
      }

      // Pick the 2nd nearest (index 1)
      outPrice = lows[1];
      outTime  = times[1];
      outLabel = labels[1];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Draw Roof & Floor Visual Range Box & Lines                       |
   //+------------------------------------------------------------------+
   void DrawRoofFloorChannel(STimeframeRBRDBDData &data)
   {
      string baseName  = m_objPrefix + EnumToString(data.tf) + "_RoofFloor";
      string boxName   = baseName + "_Box";
      string roofLine  = baseName + "_RoofLine";
      string floorLine = baseName + "_FloorLine";
      string eqLine    = baseName + "_EqLine";
      string labelName = baseName + "_Lbl";

      // If channel is invalid (either roof or floor not found), delete all channel objects!
      if(!data.currentChannel.isValid)
      {
         ObjectDelete(0, boxName);
         ObjectDelete(0, roofLine);
         ObjectDelete(0, floorLine);
         ObjectDelete(0, eqLine);
         ObjectDelete(0, labelName);
         return;
      }

      datetime tStart = data.currentChannel.startTime;
      datetime tEnd   = data.currentChannel.endTime;
      double roofP    = data.currentChannel.roofPrice;
      double floorP   = data.currentChannel.floorPrice;
      double eqP      = data.currentChannel.medianPrice;

      // 1. Draw Range Box
      if(!ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, tStart, roofP, tEnd, floorP))
      {
         ObjectMove(0, boxName, 0, tStart, roofP);
         ObjectMove(0, boxName, 1, tEnd, floorP);
      }
      ObjectSetInteger(0, boxName, OBJPROP_COLOR, data.channelBgColor);
      ObjectSetInteger(0, boxName, OBJPROP_FILL, true);
      ObjectSetInteger(0, boxName, OBJPROP_BACK, true);
      ObjectSetInteger(0, boxName, OBJPROP_SELECTABLE, false);

      // 2. Draw Roof Line (Top Border)
      if(!ObjectCreate(0, roofLine, OBJ_TREND, 0, tStart, roofP, tEnd, roofP))
      {
         ObjectMove(0, roofLine, 0, tStart, roofP);
         ObjectMove(0, roofLine, 1, tEnd, roofP);
      }
      ObjectSetInteger(0, roofLine, OBJPROP_COLOR, data.roofColor);
      ObjectSetInteger(0, roofLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, roofLine, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, roofLine, OBJPROP_RAY_RIGHT, false);

      // 3. Draw Floor Line (Bottom Border)
      if(!ObjectCreate(0, floorLine, OBJ_TREND, 0, tStart, floorP, tEnd, floorP))
      {
         ObjectMove(0, floorLine, 0, tStart, floorP);
         ObjectMove(0, floorLine, 1, tEnd, floorP);
      }
      ObjectSetInteger(0, floorLine, OBJPROP_COLOR, data.floorColor);
      ObjectSetInteger(0, floorLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, floorLine, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, floorLine, OBJPROP_RAY_RIGHT, false);

      // 4. Draw Median Equilibrium (50%) Line
      if(!ObjectCreate(0, eqLine, OBJ_TREND, 0, tStart, eqP, tEnd, eqP))
      {
         ObjectMove(0, eqLine, 0, tStart, eqP);
         ObjectMove(0, eqLine, 1, tEnd, eqP);
      }
      ObjectSetInteger(0, eqLine, OBJPROP_COLOR, clrDarkGray);
      ObjectSetInteger(0, eqLine, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, eqLine, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, eqLine, OBJPROP_RAY_RIGHT, false);

      // 5. Draw Label Text on Top Right / Left
      if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, tStart, roofP))
      {
         ObjectMove(0, labelName, 0, tStart, roofP);
      }
      string txt = StringFormat(" [%s Range] Roof: %.5f (%s) | Floor: %.5f (%s) | Eq: %.5f",
                                EnumToString(data.tf), roofP, data.currentChannel.roofSource,
                                floorP, data.currentChannel.floorSource, eqP);
      ObjectSetString(0, labelName, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhiteSmoke);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   }
};

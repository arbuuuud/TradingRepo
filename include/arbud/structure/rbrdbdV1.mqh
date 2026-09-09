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
      lastCheckedTime = 0;
      objName         = "";
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
   color             rbrColor;
   color             dbdColor;
   color             usedColor;
   color             invalidColor;
   datetime          lastBarTime;

   SRBRDBDArea       areas[];

   void Init(ENUM_TIMEFRAMES period, 
             int minBase = 1, 
             int maxBase = 7, 
             double legRatio = 1.0, 
             bool draw = true,
             color clrRBR = clrLimeGreen, 
             color clrDBD = clrCrimson,
             color clrUsed = clrSandyBrown,
             color clrInvalid = clrGray)
   {
      tf             = period;
      minBaseCandles = minBase;
      maxBaseCandles = maxBase;
      minLegRatio    = legRatio;
      drawEnabled    = draw;
      rbrColor       = clrRBR;
      dbdColor       = clrDBD;
      usedColor      = clrUsed;
      invalidColor   = clrInvalid;
      lastBarTime    = 0;

      ArrayResize(areas, 0);
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
                          const color rbrColor = clrSeaGreen,
                          const color dbdColor = clrIndianRed)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf)
         {
            m_tfList[i].minBaseCandles = minBaseCandles;
            m_tfList[i].maxBaseCandles = maxBaseCandles;
            m_tfList[i].minLegRatio    = minLegRatio;
            m_tfList[i].drawEnabled    = drawOnChart;
            m_tfList[i].rbrColor       = rbrColor;
            m_tfList[i].dbdColor       = dbdColor;
            return true;
         }
      }

      m_totalTFs++;
      if(ArrayResize(m_tfList, m_totalTFs) < m_totalTFs)
      {
         PrintFormat("[CRBRDBDV1] Failed to resize TF array for %s", EnumToString(tf));
         return false;
      }

      m_tfList[m_totalTFs - 1].Init(tf, minBaseCandles, maxBaseCandles, minLegRatio, drawOnChart, rbrColor, dbdColor);
      PrintFormat("[CRBRDBDV1] Registered TF: %s (Base: %d~%d candles, Ratio: %.1f)", 
                  EnumToString(tf), minBaseCandles, maxBaseCandles, minLegRatio);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Scan history bars from past to present and track consumption     |
   //+------------------------------------------------------------------+
   void InitHistory(const string symbol, const int maxBars = 500)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         InitTFHistory(symbol, m_tfList[i], maxBars);
      }
   }

   //+------------------------------------------------------------------+
   //| Event-Driven Update: Called in OnTick, runs when candle closes   |
   //+------------------------------------------------------------------+
   void UpdateOnCandleClose(const string symbol)
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
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Real-time consumption evaluation from live tick (Bid/Ask)        |
   //+------------------------------------------------------------------+
   void UpdateConsumptionOnTick(const string symbol, const double bid, const double ask)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         bool changed = false;
         int total = ArraySize(m_tfList[i].areas);

         for(int a = 0; a < total; a++)
         {
            if(m_tfList[i].areas[a].isInvalid) continue;

            double testPrice = (m_tfList[i].areas[a].type == RBRDBD_RBR) ? bid : ask;
            if(UpdateSingleAreaConsumption(m_tfList[i].areas[a], testPrice, testPrice))
            {
               changed = true;
            }
         }

         if(changed && m_tfList[i].drawEnabled)
         {
            DrawAllAreas(m_tfList[i]);
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
   void InitTFHistory(const string symbol, STimeframeRBRDBDData &data, const int maxBars)
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
               UpdateSingleAreaConsumption(data.areas[a], rates[b].low, rates[b].high);
               if(data.areas[a].isInvalid) break;
            }
         }
      }

      if(data.drawEnabled)
      {
         DrawAllAreas(data);
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

         UpdateSingleAreaConsumption(data.areas[a], rates[0].low, rates[0].high);
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate and update consumption percentage for a single zone    |
   //+------------------------------------------------------------------+
   bool UpdateSingleAreaConsumption(SRBRDBDArea &area, const double testLow, const double testHigh)
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

         // Draw / Update Rectangle
         if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, area.baseStart, topPrice, futureTime, botPrice))
         {
            ObjectMove(0, rectName, 0, area.baseStart, topPrice);
            ObjectMove(0, rectName, 1, futureTime, botPrice);
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
            statusStr = StringFormat(" %s %s [%d C] (100%% Used - Invalid)", EnumToString(data.tf), typeStr, area.baseCandleCount);
         else if(area.consumptionPct > 0.0)
            statusStr = StringFormat(" %s %s [%d C] (%.1f%% Used)", EnumToString(data.tf), typeStr, area.baseCandleCount, area.consumptionPct);
         else
            statusStr = StringFormat(" %s %s [%d C] (Fresh)", EnumToString(data.tf), typeStr, area.baseCandleCount);

         // Draw / Update Text
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
};

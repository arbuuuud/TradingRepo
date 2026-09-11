//+------------------------------------------------------------------+
//|                                                   rbrdbdV1.mqh   |
//|                                           Copyright 2025, Arbud. |
//|                                             https://www.mql5.com |
//|       Pure Multi-Timeframe RBR & DBD Supply/Demand Engine        |
//|              with Dynamic Retest/Consumption Tracking            |
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
//| Struct for Individual Supply / Demand Zone                       |
//+------------------------------------------------------------------+
struct SRBRDBDArea
{
   ENUM_RBRDBD_TYPE  type;             // RBR (Demand) or DBD (Supply)
   ENUM_TIMEFRAMES   period;           // Origin timeframe (PERIOD_M1, PERIOD_M3, PERIOD_M5, etc.)
   ENUM_TIMEFRAMES   detectedTF;       // Initial scanner timeframe (e.g. PERIOD_M1)
   bool              isEscalated;      // True if escalated via MTF recursive scan
   datetime          baseStart;        // Time of first base candle
   datetime          baseEnd;          // Time of last base candle
   datetime          legOutTime;       // Time of Leg-Out breakout candle
   double            proximal;         // Entry boundary (High for RBR, Low for DBD)
   double            distal;           // Stop/Invalidation boundary (Low for RBR, High for DBD)
   double            zoneHeight;       // |Proximal - Distal|
   int               baseCandleCount;  // Base candles count on zone timeframe
   int               m1BaseCandleCount;// Base candles count in M1
   double            consumptionPct;   // 0.0% to 100.0% penetration
   bool              isInvalid;        // True if consumption >= 100.0% (fully mitigated)
   datetime          invalidTime;      // Bar time when 100% penetration occurred
   string            objName;          // Chart rectangle object name

   void Init()
   {
      type              = RBRDBD_NONE;
      period            = PERIOD_CURRENT;
      detectedTF        = PERIOD_CURRENT;
      isEscalated       = false;
      baseStart         = 0;
      baseEnd           = 0;
      legOutTime        = 0;
      proximal          = 0.0;
      distal            = 0.0;
      zoneHeight        = 0.0;
      baseCandleCount   = 0;
      m1BaseCandleCount = 0;
      consumptionPct    = 0.0;
      isInvalid         = false;
      invalidTime       = 0;
      objName           = "";
   }
};

//+------------------------------------------------------------------+
//| Struct for Registered Timeframe Configuration & State            |
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
             int maxBase = 5,
             double legRatio = 1.0,
             bool draw = true,
             color clrRBR = clrMediumSeaGreen,
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
//| Class CRBRDBDV1: Pure Supply & Demand Detection Engine           |
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
   //| Register a specific Timeframe                                    |
   //+------------------------------------------------------------------+
   bool RegisterTimeframe(const ENUM_TIMEFRAMES tf,
                          const int minBaseCandles = 1,
                          const int maxBaseCandles = 5,
                          const double minLegRatio = 1.0,
                          const bool drawOnChart = true,
                          const color rbrColor = clrMediumSeaGreen,
                          const color dbdColor = clrCrimson,
                          const color usedColor = clrSandyBrown,
                          const color invalidColor = clrGray)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf)
         {
            m_tfList[i].Init(tf, minBaseCandles, maxBaseCandles, minLegRatio, drawOnChart,
                             rbrColor, dbdColor, usedColor, invalidColor);
            return true;
         }
      }

      int newSize = m_totalTFs + 1;
      ArrayResize(m_tfList, newSize);
      m_tfList[m_totalTFs].Init(tf, minBaseCandles, maxBaseCandles, minLegRatio, drawOnChart,
                                rbrColor, dbdColor, usedColor, invalidColor);
      m_totalTFs = newSize;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Scan historical bars on initialization                           |
   //+------------------------------------------------------------------+
   void InitHistory(const string symbol, const int maxBars = 500)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         InitTFHistory(symbol, m_tfList[i], maxBars);
      }
   }

   //+------------------------------------------------------------------+
   //| Event-driven update on completed candle close                    |
   //+------------------------------------------------------------------+
   void UpdateOnCandleClose(const string symbol)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         datetime currentBarTime = iTime(symbol, m_tfList[i].tf, 0);
         if(currentBarTime == 0) continue;

         if(currentBarTime != m_tfList[i].lastBarTime)
         {
            m_tfList[i].lastBarTime = currentBarTime;

            // 1. Evaluate retest/consumption on completed bar 1
            EvaluateClosedBarConsumption(symbol, m_tfList[i]);

            // 2. Scan if bar 1 was the Leg-Out of a new RBR or DBD
            ScanRecentBars(symbol, m_tfList[i]);

            // 3. Refresh chart visuals
            if(m_tfList[i].drawEnabled)
            {
               DrawAllAreas(m_tfList[i]);
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Real-time consumption update on live price tick                  |
   //+------------------------------------------------------------------+
   void UpdateConsumptionOnTick(const string symbol, const double bid, const double ask)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         bool anyUpdated = false;
         int total = ArraySize(m_tfList[i].areas);

         for(int a = 0; a < total; a++)
         {
            if(m_tfList[i].areas[a].isInvalid) continue;

            double testPrice = (m_tfList[i].areas[a].type == RBRDBD_RBR) ? bid : ask;
            if(testPrice <= 0.0) continue;

            if(UpdateSingleAreaConsumption(m_tfList[i].areas[a], testPrice, testPrice, TimeCurrent()))
            {
               anyUpdated = true;
            }
         }

         if(anyUpdated && m_tfList[i].drawEnabled)
         {
            DrawAllAreas(m_tfList[i]);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Delete all visual chart objects created by this engine           |
   //+------------------------------------------------------------------+
   void ClearChartObjects()
   {
      ObjectsDeleteAll(0, m_objPrefix);
      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| Dynamic Garbage Collection & Memory Management                   |
   //| Removes zones that are 100% mitigated and far away, or expired   |
   //+------------------------------------------------------------------+
   int RunGarbageCollection(const string symbol,
                            const double currentPrice,
                            const int maxAgeBars = 1500,
                            const double minDistanceMultiplier = 3.0)
   {
      int purgedCount = 0;
      datetime currentTime = TimeCurrent();

      for(int i = 0; i < m_totalTFs; i++)
      {
         int tfSec = PeriodSeconds(m_tfList[i].tf);
         if(tfSec <= 0) tfSec = 60;
         datetime maxAgeSeconds = (datetime)(maxAgeBars * tfSec);

         int a = 0;
         while(a < ArraySize(m_tfList[i].areas))
         {
            bool shouldPurge = false;

            // 1. Condition A: Fully Mitigated (100%) and price has moved far away
            if(m_tfList[i].areas[a].isInvalid)
            {
               double distToZone = 0.0;
               double topEdge    = MathMax(m_tfList[i].areas[a].proximal, m_tfList[i].areas[a].distal);
               double botEdge    = MathMin(m_tfList[i].areas[a].proximal, m_tfList[i].areas[a].distal);

               if(currentPrice > topEdge)
                  distToZone = currentPrice - topEdge;
               else if(currentPrice < botEdge)
                  distToZone = botEdge - currentPrice;

               double purgeDistance = MathMax(m_tfList[i].areas[a].zoneHeight * minDistanceMultiplier, 50.0 * _Point);
               if(distToZone >= purgeDistance)
               {
                  shouldPurge = true;
               }
            }

            // 2. Condition B: Zone exceeds maximum memory age
            if(!shouldPurge && m_tfList[i].areas[a].baseStart > 0)
            {
               if((currentTime - m_tfList[i].areas[a].baseStart) > maxAgeSeconds)
               {
                  shouldPurge = true;
               }
            }

            // Execute purge if condition met
            if(shouldPurge)
            {
               // Delete chart visual objects cleanly
               ObjectDelete(0, m_tfList[i].areas[a].objName);
               ObjectDelete(0, m_tfList[i].areas[a].objName + "_lbl");

               // Shift array to remove element
               int total = ArraySize(m_tfList[i].areas);
               for(int k = a; k < total - 1; k++)
               {
                  m_tfList[i].areas[k] = m_tfList[i].areas[k + 1];
               }
               ArrayResize(m_tfList[i].areas, total - 1);
               purgedCount++;
               // do not increment 'a', inspect current index with new shifted element
            }
            else
            {
               a++;
            }
         }
      }

      if(purgedCount > 0)
      {
         ChartRedraw(0);
      }

      return purgedCount;
   }

   //+------------------------------------------------------------------+
   //| Get count of active/valid (unmitigated) areas                    |
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
   //| Get copy of areas array for a specific timeframe                 |
   //+------------------------------------------------------------------+
   bool GetAreas(const ENUM_TIMEFRAMES tf, SRBRDBDArea &outArray[])
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return false;

      int total = ArraySize(m_tfList[idx].areas);
      ArrayResize(outArray, total);
      for(int i = 0; i < total; i++)
      {
         outArray[i] = m_tfList[idx].areas[i];
      }
      return true;
   }

private:
   //+------------------------------------------------------------------+
   //| Find index of timeframe in registered list                       |
   //+------------------------------------------------------------------+
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

      // Attempt to load history, retry up to 5 times if MT5 terminal hasn't synced bars yet
      int copied = 0;
      for(int attempt = 0; attempt < 5; attempt++)
      {
         copied = CopyRates(symbol, data.tf, 0, maxBars + 25, rates);
         if(copied >= (data.maxBaseCandles + 5)) break;
         Sleep(50);
      }

      PrintFormat("[CRBRDBDV1] InitTFHistory: Requested %d bars for %s on %s -> Copied %d bars.",
                  maxBars, EnumToString(data.tf), symbol, copied);

      if(copied < (data.maxBaseCandles + 5))
      {
         PrintFormat("[CRBRDBDV1] WARNING: Insufficient bars copied (%d < %d) for %s. Waiting for next ticks.",
                     copied, (data.maxBaseCandles + 5), EnumToString(data.tf));
         return;
      }

      ArrayResize(data.areas, 0);

      // Clear existing chart objects for this TF
      string tfPrefix = m_objPrefix + EnumToString(data.tf) + "_";
      ObjectsDeleteAll(0, tfPrefix);

      // Scan from oldest to newest:
      // index 'outIdx' represents the candidate Leg-Out candle
      for(int outIdx = copied - 3; outIdx >= 1; outIdx--)
      {
         DetectPatternAtBar(symbol, rates, copied, outIdx, data);
      }

      int zonesBeforeRetest = ArraySize(data.areas);

      // Track consumption chronologically from zone formation up to Bar 1
      for(int a = 0; a < ArraySize(data.areas); a++)
      {
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

      PrintFormat("[CRBRDBDV1] InitHistory for %s: %d raw zones found (%d currently active/unmitigated).",
                  EnumToString(data.tf), zonesBeforeRetest, GetValidAreasCount(data.tf));
   }

   //+------------------------------------------------------------------+
   //| Scan recent completed bars for newly formed zones                |
   //+------------------------------------------------------------------+
   void ScanRecentBars(const string symbol, STimeframeRBRDBDData &data)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int needed = (data.tf == PERIOD_M1) ? 25 : (data.maxBaseCandles + 5);
      if(CopyRates(symbol, data.tf, 0, needed, rates) < needed) return;

      // Check if completed Bar 1 was the Leg-Out of a new RBR or DBD
      DetectPatternAtBar(symbol, rates, needed, 1, data);
   }

   //+------------------------------------------------------------------+
   //| Core Pattern Detection logic at candle index 'outIdx'            |
   //+------------------------------------------------------------------+
   void DetectPatternAtBar(const string symbol, const MqlRates &rates[], const int totalRates, const int outIdx, STimeframeRBRDBDData &data)
   {
      // 1. Evaluate Leg-Out Candle (Impulsive candle)
      double outBody  = MathAbs(rates[outIdx].close - rates[outIdx].open);
      double outRange = rates[outIdx].high - rates[outIdx].low;
      if(outRange <= 0.0) return;

      // Leg-Out body must dominate candle (>= 40% solid body for Gold M1)
      if((outBody / outRange) < 0.40) return;

      bool outBullish = (rates[outIdx].close > rates[outIdx].open);
      bool outBearish = (rates[outIdx].close < rates[outIdx].open);
      if(!outBullish && !outBearish) return;

      // Check for duplication at this leg-out time
      for(int a = 0; a < ArraySize(data.areas); a++)
      {
         if(data.areas[a].legOutTime == rates[outIdx].time) return;
      }

      // Max scan base: allow scanning up to 15 candles on M1 to enable recursive MTF escalation
      int maxScanBase = (data.tf == PERIOD_M1) ? MathMax(data.maxBaseCandles, 15) : data.maxBaseCandles;

      // 2. Iterate base length from minBaseCandles to maxScanBase
      for(int baseLen = data.minBaseCandles; baseLen <= maxScanBase; baseLen++)
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

            // Boring candle rule: Body should not be overly large (> 65% rejected as boring)
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

         // Leg-Out to Base Range Ratio check
         if(outRange < (baseRange * data.minLegRatio)) continue;

         // 3. Evaluate Leg-In Candle
         double inBody  = MathAbs(rates[legInIdx].close - rates[legInIdx].open);
         double inRange = rates[legInIdx].high - rates[legInIdx].low;
         if(inRange <= 0.0) continue;

         // Leg-In body must also be solid (>= 40%)
         if((inBody / inRange) < 0.40) continue;

         bool inBullish = (rates[legInIdx].close > rates[legInIdx].open);
         bool inBearish = (rates[legInIdx].close < rates[legInIdx].open);

         // In series array: rates[baseEnd] is the oldest candle of the base (startTime)
         // rates[baseStart] is the newest candle of the base (endTime)
         datetime bStartTime = rates[baseEnd].time;
         datetime bEndTime   = rates[baseStart].time;

         // === PATTERN A: RBR (Bullish Leg-In + Base + Bullish Leg-Out breaking Base High) ===
         if(inBullish && outBullish && rates[outIdx].close > baseHigh)
         {
            if(baseLen <= data.maxBaseCandles)
            {
               // Standard Base within limits
               RegisterNewArea(data, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                               baseHigh, baseLow, baseLen, data.tf, false, baseLen);
               return;
            }
            else if(data.tf == PERIOD_M1)
            {
               // Base > maxBaseCandles in M1: Attempt Recursive MTF Escalation to 1-3 HTF candles
               ENUM_TIMEFRAMES htf;
               int htfCount = 0;
               if(TryEscalateBaseToHTF(symbol, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                                       baseHigh, baseLow, baseLen, htf, htfCount))
               {
                  RegisterNewArea(data, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                                  baseHigh, baseLow, htfCount, htf, true, baseLen);
                  return;
               }
            }
         }

         // === PATTERN B: DBD (Bearish Leg-In + Base + Bearish Leg-Out breaking Base Low) ===
         if(inBearish && outBearish && rates[outIdx].close < baseLow)
         {
            if(baseLen <= data.maxBaseCandles)
            {
               // Standard Base within limits
               RegisterNewArea(data, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                               baseLow, baseHigh, baseLen, data.tf, false, baseLen);
               return;
            }
            else if(data.tf == PERIOD_M1)
            {
               // Base > maxBaseCandles in M1: Attempt Recursive MTF Escalation to 1-3 HTF candles
               ENUM_TIMEFRAMES htf;
               int htfCount = 0;
               if(TryEscalateBaseToHTF(symbol, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                                       baseLow, baseHigh, baseLen, htf, htfCount))
               {
                  RegisterNewArea(data, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                                  baseLow, baseHigh, htfCount, htf, true, baseLen);
                  return;
               }
            }
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
                        const int baseCount,
                        const ENUM_TIMEFRAMES originTF = PERIOD_CURRENT,
                        const bool isEscalated = false,
                        const int m1Count = 0)
   {
      int size = ArraySize(data.areas);
      ArrayResize(data.areas, size + 1);

      ENUM_TIMEFRAMES finalPeriod = (originTF == PERIOD_CURRENT) ? data.tf : originTF;

      data.areas[size].Init();
      data.areas[size].type              = type;
      data.areas[size].period            = finalPeriod;
      data.areas[size].detectedTF        = data.tf;
      data.areas[size].isEscalated       = isEscalated;
      data.areas[size].baseStart         = bStart;
      data.areas[size].baseEnd           = bEnd;
      data.areas[size].legOutTime        = lOutTime;
      data.areas[size].proximal          = prox;
      data.areas[size].distal            = dist;
      data.areas[size].zoneHeight        = MathAbs(prox - dist);
      data.areas[size].baseCandleCount   = baseCount;
      data.areas[size].m1BaseCandleCount = (m1Count > 0) ? m1Count : baseCount;
      data.areas[size].consumptionPct    = 0.0;
      data.areas[size].isInvalid         = false;

      string lbl = (type == RBRDBD_RBR) ? "RBR" : "DBD";
      data.areas[size].objName = m_objPrefix + EnumToString(finalPeriod) + "_" + lbl + "_" + TimeToString(bStart, TIME_DATE|TIME_MINUTES);
   }

   //+------------------------------------------------------------------+
   //| Recursive MTF Base Consolidation Scanner                         |
   //| If base candles are excessive in M1 (> maxBaseCandles),          |
   //| climb TF ladder to check if it compacts into 1-3 boring candles   |
   //+------------------------------------------------------------------+
   bool TryEscalateBaseToHTF(const string symbol,
                             const ENUM_RBRDBD_TYPE type,
                             const datetime bStart,
                             const datetime bEnd,
                             const datetime lOutTime,
                             const double prox,
                             const double dist,
                             const int m1BaseLen,
                             ENUM_TIMEFRAMES &outTF,
                             int &outHTFBaseCount)
   {
      // Timeframe escalation ladder
      ENUM_TIMEFRAMES ladder[4] = { PERIOD_M3, PERIOD_M5, PERIOD_M15, PERIOD_H1 };

      for(int i = 0; i < 4; i++)
      {
         ENUM_TIMEFRAMES targetTF = ladder[i];
         int tfSec = PeriodSeconds(targetTF);
         if(tfSec <= 0) continue;

         // Find bar index covering bStart and bEnd in targetTF
         int startBar = iBarShift(symbol, targetTF, bStart, false);
         int endBar   = iBarShift(symbol, targetTF, bEnd, false);

         if(startBar < 0 || endBar < 0) continue;

         // In series array, startBar >= endBar because bStart <= bEnd
         int htfCandleCount = MathAbs(startBar - endBar) + 1;

         // We seek exactly 1 to 3 candles on higher timeframe
         if(htfCandleCount >= 1 && htfCandleCount <= 3)
         {
            int oldestBar = MathMax(startBar, endBar);
            int newestBar = MathMin(startBar, endBar);

            MqlRates htfRates[];
            ArraySetAsSeries(htfRates, true);
            int copied = CopyRates(symbol, targetTF, newestBar, htfCandleCount, htfRates);
            if(copied != htfCandleCount) continue;

            bool allBoring = true;
            for(int k = 0; k < copied; k++)
            {
               double body  = MathAbs(htfRates[k].close - htfRates[k].open);
               double range = htfRates[k].high - htfRates[k].low;
               if(range > 0.0 && (body / range) > 0.65)
               {
                  allBoring = false;
                  break;
               }
            }

            if(allBoring)
            {
               outTF          = targetTF;
               outHTFBaseCount = htfCandleCount;
               return true;
            }
         }
      }

      return false; // Could not consolidate into clean 1-3 candle base on HTF
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
         ObjectSetInteger(0, rectName, OBJPROP_BACK, false);
         ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rectName, OBJPROP_STYLE, area.isInvalid ? STYLE_DOT : STYLE_SOLID);

         // Format status text
         string typeStr = (area.type == RBRDBD_RBR) ? "RBR" : "DBD";
         string tfStr   = EnumToString(area.period);
         string baseInfo;
         if(area.isEscalated)
            baseInfo = StringFormat("[%d C in %s (M1: %d C)]", area.baseCandleCount, tfStr, area.m1BaseCandleCount);
         else
            baseInfo = StringFormat("[%d C]", area.baseCandleCount);

         string statusStr;
         if(area.isInvalid)
            statusStr = StringFormat(" %s %s %s (100%% Mitigated)", tfStr, typeStr, baseInfo);
         else if(area.consumptionPct > 0.0)
            statusStr = StringFormat(" %s %s %s (%.1f%% Retested)", tfStr, typeStr, baseInfo, area.consumptionPct);
         else
            statusStr = StringFormat(" %s %s %s (Fresh)", tfStr, typeStr, baseInfo);

         // Draw / Update Text (pinned to baseStart)
         if(!ObjectCreate(0, textName, OBJ_TEXT, 0, area.baseStart, topPrice))
         {
            ObjectMove(0, textName, 0, area.baseStart, topPrice);
         }
         ObjectSetString(0, textName, OBJPROP_TEXT, statusStr);
         ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, textName, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, textName, OBJPROP_BACK, false);
      }

      ChartRedraw(0);
   }
};
//+------------------------------------------------------------------+

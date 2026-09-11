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

   // Phase 2.1: Base Tightness & MTF Reflection
   bool              passBaseTightness;// M1 base candles <= 60% body and baseRange <= 0.8 * legOutRange
   bool              passMTFReflection;// Base reflects as clean 1-3 candles in M3, M5, or M15
   ENUM_TIMEFRAMES   reflTF;           // Timeframe that confirmed clean reflection
   int               reflCandleCount;  // Number of clean candles in reflTF
   int               scorePhase2_1;    // +1 Point if both pass, 0 otherwise

   // Phase 2.2: BOS / ChoCH Wajib Body Close on Zone Origin Timeframe
   bool              passBOS;          // True if Leg-Out closed body beyond previous swing
   double            bosBrokenLevel;   // Price level of the broken swing high/low
   datetime          bosSwingTime;     // Time of the swing high/low bar
   int               scorePhase2_2;    // +1 Point if passBOS is true, 0 otherwise

   // Phase 2.3: Direct Attached FVG (Magnet Retest) on Origin Timeframe
   bool              passDirectFVG;    // True if Leg-Out forms a significant direct attached FVG
   double            fvgTopPrice;      // Upper boundary of the FVG
   double            fvgBotPrice;      // Lower boundary of the FVG
   double            fvgGapPoints;     // Width of the FVG in points
   datetime          fvgStartTime;     // Start timestamp of the FVG (Leg-Out candle)
   datetime          fvgEndTime;       // End timestamp of the FVG (Candle after Leg-Out)
   int               scorePhase2_3;    // +1 Point if passDirectFVG is true, 0 otherwise

   int               totalScore;       // Phase 2 total score accumulator (0 to 5)

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

      passBaseTightness = false;
      passMTFReflection = false;
      reflTF            = PERIOD_CURRENT;
      reflCandleCount   = 0;
      scorePhase2_1     = 0;

      passBOS           = false;
      bosBrokenLevel    = 0.0;
      bosSwingTime      = 0;
      scorePhase2_2     = 0;

      passDirectFVG     = false;
      fvgTopPrice       = 0.0;
      fvgBotPrice       = 0.0;
      fvgGapPoints      = 0.0;
      fvgStartTime      = 0;
      fvgEndTime        = 0;
      scorePhase2_3     = 0;

      totalScore        = 0;
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

   // Phase 2 Modular Test Switches (Default true)
   bool                 m_enablePhase2_1; // Base Tightness & MTF Reflection
   bool                 m_enablePhase2_2; // Origin TF BOS / ChoCH Body Close
   bool                 m_enablePhase2_3; // Origin TF Direct Attached FVG
   double               m_minFVGGapPoints;// Minimum FVG gap in points (default 50 = $0.50 on Gold)

public:
   CRBRDBDV1() : m_totalTFs(0), m_objPrefix("RBRDBD_"),
                 m_enablePhase2_1(true), m_enablePhase2_2(true),
                 m_enablePhase2_3(true), m_minFVGGapPoints(50.0)
   {
      ArrayResize(m_tfList, 0);
   }

   //+------------------------------------------------------------------+
   //| Configure Phase 2 Modular Test Switches                          |
   //+------------------------------------------------------------------+
   void SetPhase2Switches(const bool enablePhase2_1,
                          const bool enablePhase2_2,
                          const bool enablePhase2_3 = true,
                          const double minFVGGapPoints = 50.0)
   {
      m_enablePhase2_1  = enablePhase2_1;
      m_enablePhase2_2  = enablePhase2_2;
      m_enablePhase2_3  = enablePhase2_3;
      m_minFVGGapPoints = minFVGGapPoints;
   }

   bool GetPhase2_1Enabled() const { return m_enablePhase2_1; }
   bool GetPhase2_2Enabled() const { return m_enablePhase2_2; }
   bool GetPhase2_3Enabled() const { return m_enablePhase2_3; }

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
               ObjectDelete(0, m_tfList[i].areas[a].objName + "_bos");
               ObjectDelete(0, m_tfList[i].areas[a].objName + "_fvg");

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
   //| Convert ENUM_TIMEFRAMES to clean concise short name              |
   //+------------------------------------------------------------------+
   static string GetTFShortName(const ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M2:  return "M2";
         case PERIOD_M3:  return "M3";
         case PERIOD_M4:  return "M4";
         case PERIOD_M5:  return "M5";
         case PERIOD_M6:  return "M6";
         case PERIOD_M10: return "M10";
         case PERIOD_M12: return "M12";
         case PERIOD_M15: return "M15";
         case PERIOD_M20: return "M20";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H2:  return "H2";
         case PERIOD_H3:  return "H3";
         case PERIOD_H4:  return "H4";
         case PERIOD_H6:  return "H6";
         case PERIOD_H8:  return "H8";
         case PERIOD_H12: return "H12";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN";
         default:         return "TF";
      }
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
               RegisterNewArea(symbol, data, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                               baseHigh, baseLow, baseLen, data.tf, false, baseLen, outRange, baseRange);
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
                  RegisterNewArea(symbol, data, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                                  baseHigh, baseLow, htfCount, htf, true, baseLen, outRange, baseRange);
                  return;
               }
               else
               {
                  // Fallback for Strategy Tester (where HTF rates aren't synced yet) or uncompressed M1 base
                  if(baseLen <= 8)
                  {
                     RegisterNewArea(symbol, data, RBRDBD_RBR, bStartTime, bEndTime, rates[outIdx].time,
                                     baseHigh, baseLow, baseLen, data.tf, false, baseLen, outRange, baseRange);
                     return;
                  }
               }
            }
         }

         // === PATTERN B: DBD (Bearish Leg-In + Base + Bearish Leg-Out breaking Base Low) ===
         if(inBearish && outBearish && rates[outIdx].close < baseLow)
         {
            if(baseLen <= data.maxBaseCandles)
            {
               // Standard Base within limits
               RegisterNewArea(symbol, data, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                               baseLow, baseHigh, baseLen, data.tf, false, baseLen, outRange, baseRange);
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
                  RegisterNewArea(symbol, data, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                                  baseLow, baseHigh, htfCount, htf, true, baseLen, outRange, baseRange);
                  return;
               }
               else
               {
                  // Fallback for Strategy Tester (where HTF rates aren't synced yet) or uncompressed M1 base
                  if(baseLen <= 8)
                  {
                     RegisterNewArea(symbol, data, RBRDBD_DBD, bStartTime, bEndTime, rates[outIdx].time,
                                     baseLow, baseHigh, baseLen, data.tf, false, baseLen, outRange, baseRange);
                     return;
                  }
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Register newly identified zone into areas array                  |
   //+------------------------------------------------------------------+
   void RegisterNewArea(const string symbol,
                        STimeframeRBRDBDData &data,
                        const ENUM_RBRDBD_TYPE type,
                        const datetime bStart,
                        const datetime bEnd,
                        const datetime lOutTime,
                        const double prox,
                        const double dist,
                        const int baseCount,
                        const ENUM_TIMEFRAMES originTF = PERIOD_CURRENT,
                        const bool isEscalated = false,
                        const int m1Count = 0,
                        const double outRange = 0.0,
                        const double baseRange = 0.0)
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

      // --- PHASE 2.1: Base Tightness & MTF Reflection Evaluator ---
      if(m_enablePhase2_1)
         EvaluatePhase2_1_TightnessAndReflection(symbol, data.areas[size], outRange, baseRange);
      else
      {
         data.areas[size].passBaseTightness = false;
         data.areas[size].passMTFReflection = false;
         data.areas[size].scorePhase2_1     = 0;
      }

      // --- PHASE 2.2: BOS / ChoCH Wajib Body Close on Origin Timeframe ---
      if(m_enablePhase2_2)
         EvaluatePhase2_2_BOS(symbol, data.areas[size]);
      else
      {
         data.areas[size].passBOS       = false;
         data.areas[size].scorePhase2_2 = 0;
      }

      // --- PHASE 2.3: Direct Attached FVG (Magnet Retest) on Origin Timeframe ---
      if(m_enablePhase2_3)
         EvaluatePhase2_3_AttachedFVG(symbol, data.areas[size]);
      else
      {
         data.areas[size].passDirectFVG = false;
         data.areas[size].scorePhase2_3 = 0;
      }

      // Phase 2 Total Score Accumulator (Sums active modules)
      data.areas[size].totalScore = data.areas[size].scorePhase2_1 +
                                    data.areas[size].scorePhase2_2 +
                                    data.areas[size].scorePhase2_3;

      string lbl = (type == RBRDBD_RBR) ? "RBR" : "DBD";
      data.areas[size].objName = m_objPrefix + EnumToString(finalPeriod) + "_" + lbl + "_" + TimeToString(bStart, TIME_DATE|TIME_MINUTES);
   }

   //+------------------------------------------------------------------+
   //| Phase 2.1 Evaluator: M1 Base Tightness & Ladder M3->M5->M15      |
   //+------------------------------------------------------------------+
   void EvaluatePhase2_1_TightnessAndReflection(const string symbol,
                                                SRBRDBDArea &area,
                                                const double outRange,
                                                const double baseRange)
   {
      // 1. Base Tightness Check (M1)
      // BaseRange must be compact compared to Leg-Out explosion (BaseRange <= 0.80 * OutRange)
      bool tight = false;
      if(outRange > 0.0 && baseRange > 0.0)
      {
         if(baseRange <= (outRange * 0.80))
         {
            tight = true;
         }
      }
      area.passBaseTightness = tight;

      // 2. MTF Reflection Ladder: M3 -> M5 -> M15
      ENUM_TIMEFRAMES ladder[3] = { PERIOD_M3, PERIOD_M5, PERIOD_M15 };
      bool reflPass = false;

      for(int i = 0; i < 3; i++)
      {
         ENUM_TIMEFRAMES targetTF = ladder[i];
         int tfSec = PeriodSeconds(targetTF);
         if(tfSec <= 0) continue;

         int startBar = iBarShift(symbol, targetTF, area.baseStart, false);
         int endBar   = iBarShift(symbol, targetTF, area.baseEnd, false);
         if(startBar < 0 || endBar < 0) continue;

         int htfCandleCount = MathAbs(startBar - endBar) + 1;

         // On M3, we allow 1-3 candles; on M5: 1-2 candles; on M15: 1 candle
         int maxAllowed = (targetTF == PERIOD_M3) ? 3 : ((targetTF == PERIOD_M5) ? 2 : 1);

         if(htfCandleCount >= 1 && htfCandleCount <= maxAllowed)
         {
            int newestBar = MathMin(startBar, endBar);
            MqlRates htfRates[];
            ArraySetAsSeries(htfRates, true);

            int copied = CopyRates(symbol, targetTF, newestBar, htfCandleCount, htfRates);
            if(copied == htfCandleCount)
            {
               bool clean = true;
               for(int k = 0; k < copied; k++)
               {
                  double body  = MathAbs(htfRates[k].close - htfRates[k].open);
                  double range = htfRates[k].high - htfRates[k].low;
                  // Candle must not be a massive runaway candle (> 65% body rejected as consolidation)
                  if(range > 0.0 && (body / range) > 0.65)
                  {
                     clean = false;
                     break;
                  }
               }

               if(clean)
               {
                  reflPass             = true;
                  area.passMTFReflection = true;
                  area.reflTF          = targetTF;
                  area.reflCandleCount = htfCandleCount;
                  break; // Confirmed on ladder!
               }
            }
         }
      }

      // If zone was already escalated to M3/M5 in Phase 1, it naturally satisfies MTF reflection
      if(!reflPass && area.isEscalated)
      {
         area.passMTFReflection = true;
         area.reflTF          = area.period;
         area.reflCandleCount = area.baseCandleCount;
         reflPass             = true;
      }

      // Scoring: +1 Point if both Base Tightness and MTF Reflection pass
      if(area.passBaseTightness && area.passMTFReflection)
      {
         area.scorePhase2_1 = 1;
      }
      else
      {
         area.scorePhase2_1 = 0;
      }
   }

   //+------------------------------------------------------------------+
   //| Phase 2.2 Evaluator: BOS / ChoCH Wajib Body Close on Origin TF   |
   //| Evaluates swing level matching the zone's origin period          |
   //| High-Precision Engine: 5-bar structural pivot & pullback depth   |
   //| NOTE: Functional bare minimum for MVP; can be improved later     |
   //|       (e.g., adaptive multi-bar ATR clearance / dynamic zig-zag)  |
   //+------------------------------------------------------------------+
   void EvaluatePhase2_2_BOS(const string symbol, SRBRDBDArea &area)
   {
      area.passBOS        = false;
      area.bosBrokenLevel = 0.0;
      area.bosSwingTime   = 0;
      area.scorePhase2_2  = 0;

      ENUM_TIMEFRAMES tf = area.period;
      if(tf <= 0) tf = PERIOD_CURRENT;

      // Find bar shifts on origin timeframe
      int legOutBar    = iBarShift(symbol, tf, area.legOutTime, false);
      int baseStartBar = iBarShift(symbol, tf, area.baseStart, false);
      if(legOutBar < 0 || baseStartBar < 0) return;

      // Copy Leg-Out candle to verify Body Close
      MqlRates outRates[];
      ArraySetAsSeries(outRates, true);
      if(CopyRates(symbol, tf, legOutBar, 1, outRates) < 1) return;
      double legOutClose = outRates[0].close;

      // Scan prior swings with clearance:
      // Leave at least 2 bars clearance before baseStartBar to avoid measuring the Leg-In itself
      int clearanceBars  = 2;
      int startSearchBar = baseStartBar + clearanceBars;
      int lookback       = 45; // Generous window for true structural swing

      MqlRates priorRates[];
      ArraySetAsSeries(priorRates, true);
      int copied = CopyRates(symbol, tf, startSearchBar, lookback, priorRates);
      if(copied < 7) return; // Need at least 5-7 bars to detect a 5-bar pivot with clearance

      // Minimum required pullback depth between swing and base
      // At least equal to zone height, with a floor of 80 points ($0.80 on Gold)
      double minPullback = MathMax(area.zoneHeight * 1.0, 80.0 * _Point);

      if(area.type == RBRDBD_RBR)
      {
         double swingHigh = 0.0;
         datetime sTime   = 0;

         // Priority 1: High-Precision 5-Bar Structural Peak (2 left, 2 right) with Pullback Depth
         for(int i = 2; i < copied - 2; i++)
         {
            bool isPeak = (priorRates[i].high > priorRates[i - 1].high &&
                           priorRates[i].high > priorRates[i - 2].high &&
                           priorRates[i].high >= priorRates[i + 1].high &&
                           priorRates[i].high >= priorRates[i + 2].high);

            if(isPeak)
            {
               // Measure pullback valley between base start (index 0) and this peak (index i)
               double lowestInValley = priorRates[0].low;
               for(int k = 1; k < i; k++)
               {
                  if(priorRates[k].low < lowestInValley)
                     lowestInValley = priorRates[k].low;
               }

               double pullback = priorRates[i].high - lowestInValley;
               if(pullback >= minPullback)
               {
                  swingHigh = priorRates[i].high;
                  sTime     = priorRates[i].time;
                  break; // Found nearest prominent structural swing high!
               }
            }
         }

         // Priority 2 Fallback: If no 5-bar pivot with pullback found, search prominent 3-bar pivot with pullback
         if(swingHigh <= 0.0)
         {
            for(int i = 1; i < copied - 1; i++)
            {
               bool is3BarPeak = (priorRates[i].high > priorRates[i - 1].high &&
                                  priorRates[i].high >= priorRates[i + 1].high);
               if(is3BarPeak)
               {
                  double lowestInValley = priorRates[0].low;
                  for(int k = 1; k < i; k++)
                  {
                     if(priorRates[k].low < lowestInValley)
                        lowestInValley = priorRates[k].low;
                  }

                  if((priorRates[i].high - lowestInValley) >= minPullback)
                  {
                     swingHigh = priorRates[i].high;
                     sTime     = priorRates[i].time;
                     break;
                  }
               }
            }
         }

         // Priority 3 Fallback: Major Highest High in lookback that has clear clearance from base
         if(swingHigh <= 0.0)
         {
            for(int i = 2; i < copied; i++)
            {
               if(priorRates[i].high > swingHigh)
               {
                  swingHigh = priorRates[i].high;
                  sTime     = priorRates[i].time;
               }
            }
         }

         area.bosBrokenLevel = swingHigh;
         area.bosSwingTime   = sTime;

         // Validation: Wajib Body Close (Close > SwingHigh)
         // Wick sweep (High > SwingHigh but Close <= SwingHigh) rejected as fakeout!
         if(swingHigh > 0.0 && legOutClose > swingHigh)
         {
            area.passBOS       = true;
            area.scorePhase2_2 = 1;
         }
      }
      else if(area.type == RBRDBD_DBD)
      {
         double swingLow = 0.0;
         datetime sTime  = 0;

         // Priority 1: High-Precision 5-Bar Structural Trough (2 left, 2 right) with Pullback Depth
         for(int i = 2; i < copied - 2; i++)
         {
            bool isTrough = (priorRates[i].low < priorRates[i - 1].low &&
                             priorRates[i].low < priorRates[i - 2].low &&
                             priorRates[i].low <= priorRates[i + 1].low &&
                             priorRates[i].low <= priorRates[i + 2].low);

            if(isTrough)
            {
               // Measure bounce peak between base start (index 0) and this trough (index i)
               double highestInBounce = priorRates[0].high;
               for(int k = 1; k < i; k++)
               {
                  if(priorRates[k].high > highestInBounce)
                     highestInBounce = priorRates[k].high;
               }

               double bounce = highestInBounce - priorRates[i].low;
               if(bounce >= minPullback)
               {
                  swingLow = priorRates[i].low;
                  sTime    = priorRates[i].time;
                  break; // Found nearest prominent structural swing low!
               }
            }
         }

         // Priority 2 Fallback: 3-Bar Trough with Bounce Height
         if(swingLow <= 0.0)
         {
            for(int i = 1; i < copied - 1; i++)
            {
               bool is3BarTrough = (priorRates[i].low < priorRates[i - 1].low &&
                                    priorRates[i].low <= priorRates[i + 1].low);
               if(is3BarTrough)
               {
                  double highestInBounce = priorRates[0].high;
                  for(int k = 1; k < i; k++)
                  {
                     if(priorRates[k].high > highestInBounce)
                        highestInBounce = priorRates[k].high;
                  }

                  if((highestInBounce - priorRates[i].low) >= minPullback)
                  {
                     swingLow = priorRates[i].low;
                     sTime    = priorRates[i].time;
                     break;
                  }
               }
            }
         }

         // Priority 3 Fallback: Major Lowest Low in lookback with clearance
         if(swingLow <= 0.0)
         {
            swingLow = priorRates[2].low;
            sTime    = priorRates[2].time;
            for(int i = 3; i < copied; i++)
            {
               if(priorRates[i].low < swingLow)
               {
                  swingLow = priorRates[i].low;
                  sTime    = priorRates[i].time;
               }
            }
         }

         area.bosBrokenLevel = swingLow;
         area.bosSwingTime   = sTime;

         // Validation: Wajib Body Close (Close < SwingLow)
         // Wick sweep (Low < SwingLow but Close >= SwingLow) rejected as fakeout!
         if(swingLow > 0.0 && legOutClose < swingLow)
         {
            area.passBOS       = true;
            area.scorePhase2_2 = 1;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Phase 2.3 Evaluator: Direct Attached FVG on Origin Timeframe     |
   //| Validates 3-candle imbalance around Leg-Out on zone.period       |
   //| (M1 zone -> M1 FVG, M3 zone -> M3 FVG, M5 zone -> M5 FVG, etc.)  |
   //+------------------------------------------------------------------+
   void EvaluatePhase2_3_AttachedFVG(const string symbol, SRBRDBDArea &area)
   {
      area.passDirectFVG = false;
      area.fvgTopPrice   = 0.0;
      area.fvgBotPrice   = 0.0;
      area.fvgGapPoints  = 0.0;
      area.fvgStartTime  = 0;
      area.fvgEndTime    = 0;
      area.scorePhase2_3 = 0;

      ENUM_TIMEFRAMES tf = area.period;
      if(tf <= 0) tf = PERIOD_CURRENT;

      // Locate Leg-Out candle index on its origin timeframe
      int legOutBar = iBarShift(symbol, tf, area.legOutTime, false);
      if(legOutBar < 1) return; // Need at least 1 bar after legOut (legOutBar - 1)

      // Copy 3 consecutive candles around Leg-Out on origin timeframe:
      // Candle 1: Before Leg-Out (shift = legOutBar + 1)
      // Candle 2: Leg-Out candle (shift = legOutBar)
      // Candle 3: After Leg-Out  (shift = legOutBar - 1)
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, tf, legOutBar - 1, 3, rates) < 3) return;

      // When ArraySetAsSeries is true:
      // rates[0] = shift legOutBar - 1 (Candle 3: After Leg-Out)
      // rates[1] = shift legOutBar     (Candle 2: Leg-Out candle)
      // rates[2] = shift legOutBar + 1 (Candle 1: Before Leg-Out / Base end)

      double c1High = rates[2].high;
      double c1Low  = rates[2].low;
      double c3High = rates[0].high;
      double c3Low  = rates[0].low;

      double minGap = m_minFVGGapPoints * _Point;
      double maxAttachTolerance = 15.0 * _Point; // 15 points tolerance to Base proximal

      if(area.type == RBRDBD_RBR)
      {
         // Bullish FVG: Gap between Candle 1 High and Candle 3 Low
         double gap = c3Low - c1High;
         if(gap >= minGap)
         {
            // Verify Direct Attachment: Lower boundary of FVG (c1High) must touch or align near Base Proximal (roof)
            double attachDist = MathAbs(c1High - area.proximal);
            if(attachDist <= maxAttachTolerance)
            {
               area.passDirectFVG = true;
               area.fvgTopPrice   = c3Low;
               area.fvgBotPrice   = c1High;
               area.fvgGapPoints  = NormalizeDouble(gap / _Point, 1);
               area.fvgStartTime  = rates[1].time; // Leg-Out time
               area.fvgEndTime    = rates[0].time; // Candle 3 time
               area.scorePhase2_3 = 1;
            }
         }
      }
      else if(area.type == RBRDBD_DBD)
      {
         // Bearish FVG: Gap between Candle 1 Low and Candle 3 High
         double gap = c1Low - c3High;
         if(gap >= minGap)
         {
            // Verify Direct Attachment: Upper boundary of FVG (c1Low) must touch or align near Base Proximal (floor)
            double attachDist = MathAbs(c1Low - area.proximal);
            if(attachDist <= maxAttachTolerance)
            {
               area.passDirectFVG = true;
               area.fvgTopPrice   = c1Low;
               area.fvgBotPrice   = c3High;
               area.fvgGapPoints  = NormalizeDouble(gap / _Point, 1);
               area.fvgStartTime  = rates[1].time; // Leg-Out time
               area.fvgEndTime    = rates[0].time; // Candle 3 time
               area.scorePhase2_3 = 1;
            }
         }
      }
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

      datetime currentTime = TimeCurrent();
      if(currentTime <= 0) currentTime = iTime(_Symbol, data.tf, 0);
      datetime futureTime = currentTime + (PeriodSeconds(data.tf) * 15);

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
         if(ObjectFind(0, rectName) < 0)
         {
            ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, area.baseStart, topPrice, rectEndTime, botPrice);
         }
         else
         {
            ObjectMove(0, rectName, 0, area.baseStart, topPrice);
            ObjectMove(0, rectName, 1, rectEndTime, botPrice);
         }
         ObjectSetInteger(0, rectName, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rectName, OBJPROP_BACK, true); // Put rectangle in background so candlesticks and text stay on top
         ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rectName, OBJPROP_STYLE, area.isInvalid ? STYLE_DOT : STYLE_SOLID);

         // Format status text concisely
         string typeStr = (area.type == RBRDBD_RBR) ? "RBR" : "DBD";
         string tfStr   = GetTFShortName(area.period);

         // Base candle info
         string cInfo;
         if(area.isEscalated)
            cInfo = StringFormat("%dC(M1:%d)", area.baseCandleCount, area.m1BaseCandleCount);
         else
            cInfo = StringFormat("%dC", area.baseCandleCount);

         // Phase 2 Quality Score Info (Adaptive to Active Switches)
         string scoreStr = "";
         if(m_enablePhase2_3 && !m_enablePhase2_1 && !m_enablePhase2_2)
         {
            // Pure Phase 2.3 Test Mode (Isolated FVG test)
            if(area.scorePhase2_3 > 0)
               scoreStr = StringFormat("FVG(%.0fpt|+1)", area.fvgGapPoints);
            else
               scoreStr = "no-FVG (0pt)";
         }
         else if(m_enablePhase2_1 && !m_enablePhase2_2 && !m_enablePhase2_3)
         {
            // Pure Phase 2.1 Test Mode
            if(area.scorePhase2_1 > 0)
               scoreStr = StringFormat("T:%s (+1pt)", GetTFShortName(area.reflTF));
            else
               scoreStr = "no-Tight (0pt)";
         }
         else if(!m_enablePhase2_1 && m_enablePhase2_2 && !m_enablePhase2_3)
         {
            // Pure Phase 2.2 Test Mode (Isolated BOS test)
            if(area.scorePhase2_2 > 0)
               scoreStr = "BOS (+1pt)";
            else
               scoreStr = "no-BOS (0pt)";
         }
         else
         {
            // Combined Phase 2 Mode
            string qInfo = "";
            if(area.scorePhase2_1 > 0)
               qInfo += "T:" + GetTFShortName(area.reflTF) + " ";
            if(area.scorePhase2_2 > 0)
               qInfo += "BOS ";
            if(area.scorePhase2_3 > 0)
               qInfo += "FVG ";

            if(StringLen(qInfo) > 0)
               StringTrimRight(qInfo);
            else
               qInfo = "raw";

            scoreStr = StringFormat("%s|%d★", qInfo, area.totalScore);
         }

         // Retest/Status info
         string statusStr;
         if(area.isInvalid)
            statusStr = "100% Mit";
         else if(area.consumptionPct > 0.0)
            statusStr = StringFormat("%.1f%%", area.consumptionPct);
         else
            statusStr = "Fresh";

         // Combined concise label: e.g. " M1 RBR [2C|BOS (+1pt)] • Fresh"
         string finalLabel = StringFormat(" %s %s [%s|%s] • %s", tfStr, typeStr, cInfo, scoreStr, statusStr);

         // High-contrast text color & positioning
         // For RBR (Demand): place text slightly below bottom edge
         // For DBD (Supply): place text slightly above top edge
         double textPrice;
         ENUM_ANCHOR_POINT anchor;
         color labelClr = clrWhite; // High-contrast clean white

         double offset = MathMax(area.zoneHeight * 0.15, 10.0 * _Point);
         if(area.type == RBRDBD_RBR)
         {
            textPrice = botPrice - offset;
            anchor    = ANCHOR_LEFT_UPPER; // Anchor from top of text downwards
         }
         else
         {
            textPrice = topPrice + offset;
            anchor    = ANCHOR_LEFT_LOWER; // Anchor from bottom of text upwards
         }

         // Draw / Update Text
         if(ObjectFind(0, textName) < 0)
         {
            ObjectCreate(0, textName, OBJ_TEXT, 0, area.baseStart, textPrice);
         }
         else
         {
            ObjectMove(0, textName, 0, area.baseStart, textPrice);
         }
         ObjectSetString(0, textName, OBJPROP_TEXT, finalLabel);
         ObjectSetInteger(0, textName, OBJPROP_COLOR, labelClr);
         ObjectSetInteger(0, textName, OBJPROP_ANCHOR, anchor);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, textName, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, textName, OBJPROP_BACK, false); // Keep text explicitly in foreground

         // Draw / Update BOS Horizontal Swing Reference Line (if BOS is passed and enabled)
         string bosLineName = rectName + "_bos";
         if(m_enablePhase2_2 && area.passBOS && area.bosBrokenLevel > 0.0 && area.bosSwingTime > 0)
         {
            datetime bosEndTime = area.legOutTime;
            if(bosEndTime <= area.bosSwingTime) bosEndTime = area.baseEnd;

            if(ObjectFind(0, bosLineName) < 0)
            {
               ObjectCreate(0, bosLineName, OBJ_TREND, 0, area.bosSwingTime, area.bosBrokenLevel, bosEndTime, area.bosBrokenLevel);
            }
            else
            {
               ObjectMove(0, bosLineName, 0, area.bosSwingTime, area.bosBrokenLevel);
               ObjectMove(0, bosLineName, 1, bosEndTime, area.bosBrokenLevel);
            }
            ObjectSetInteger(0, bosLineName, OBJPROP_COLOR, (area.type == RBRDBD_RBR) ? clrAqua : clrOrangeRed);
            ObjectSetInteger(0, bosLineName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, bosLineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, bosLineName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, bosLineName, OBJPROP_BACK, true);
         }
         else
         {
            if(ObjectFind(0, bosLineName) >= 0)
               ObjectDelete(0, bosLineName);
         }

         // Draw / Update Direct Attached FVG Visual Box (if FVG passed and enabled)
         string fvgBoxName = rectName + "_fvg";
         if(m_enablePhase2_3 && area.passDirectFVG && area.fvgTopPrice > 0.0 && area.fvgBotPrice > 0.0)
         {
            datetime fvgStart = area.fvgStartTime;
            datetime fvgEnd   = futureTime; // Extend into future until retested or dynamic zone lifetime

            double fvgHigh = MathMax(area.fvgTopPrice, area.fvgBotPrice);
            double fvgLow  = MathMin(area.fvgTopPrice, area.fvgBotPrice);

            color fvgColor = (area.type == RBRDBD_RBR) ? clrMediumSpringGreen : clrMediumOrchid;

            if(ObjectFind(0, fvgBoxName) < 0)
            {
               ObjectCreate(0, fvgBoxName, OBJ_RECTANGLE, 0, fvgStart, fvgHigh, fvgEnd, fvgLow);
            }
            else
            {
               ObjectMove(0, fvgBoxName, 0, fvgStart, fvgHigh);
               ObjectMove(0, fvgBoxName, 1, fvgEnd, fvgLow);
            }
            ObjectSetInteger(0, fvgBoxName, OBJPROP_COLOR, fvgColor);
            ObjectSetInteger(0, fvgBoxName, OBJPROP_FILL, true);
            ObjectSetInteger(0, fvgBoxName, OBJPROP_BACK, true); // Behind candles
            ObjectSetInteger(0, fvgBoxName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, fvgBoxName, OBJPROP_STYLE, STYLE_DOT);
         }
         else
         {
            if(ObjectFind(0, fvgBoxName) >= 0)
               ObjectDelete(0, fvgBoxName);
         }
      }

      ChartRedraw(0);
   }
};
//+------------------------------------------------------------------+

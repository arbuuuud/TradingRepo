//+------------------------------------------------------------------+
//|                                         MTFStructureEngine.mqh   |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "MTFDefines.mqh"

class CMTFStructureEngine
{
private:
   STFData        m_tfData[];
   int            m_totalTFs;

public:
   CMTFStructureEngine() : m_totalTFs(0)
   {
      ArrayResize(m_tfData, 0);
   }

   ~CMTFStructureEngine()
   {
      ArrayFree(m_tfData);
   }

   //+------------------------------------------------------------------+
   //| Register a Timeframe with its designated role                    |
   //+------------------------------------------------------------------+
   bool RegisterTimeframe(const ENUM_TIMEFRAMES tf, const ENUM_TF_ROLE role)
   {
      // Check if already registered
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfData[i].tf == tf)
         {
            m_tfData[i].role = role;
            return true;
         }
      }

      m_totalTFs++;
      if(ArrayResize(m_tfData, m_totalTFs) < m_totalTFs)
      {
         PrintFormat("[MTFStructureEngine] Failed to resize TF array for %s", EnumToString(tf));
         return false;
      }

      m_tfData[m_totalTFs - 1].Init(tf, role);
      PrintFormat("[MTFStructureEngine] Registered TF: %s (Role: %d)", EnumToString(tf), role);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Event-Driven Update: called in OnTick, but only executes when a  |
   //| new bar has CLOSED on the respective registered timeframe.       |
   //+------------------------------------------------------------------+
   void UpdateOnCandleClose(const string symbol)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         ENUM_TIMEFRAMES tf = m_tfData[i].tf;
         datetime currentBarTime = iTime(symbol, tf, 0);

         if(currentBarTime != 0 && currentBarTime != m_tfData[i].lastBarTime)
         {
            m_tfData[i].lastBarTime = currentBarTime;
            // Bar has completed, perform swing and structure calculation
            CalculateStructure(symbol, i);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get Macro Bias by combining two higher timeframes (e.g. H1 + M15)|
   //+------------------------------------------------------------------+
   ENUM_SMC_TREND GetCombinedBias(const ENUM_TIMEFRAMES htf1, const ENUM_TIMEFRAMES htf2)
   {
      ENUM_SMC_TREND trend1 = GetTrend(htf1);
      ENUM_SMC_TREND trend2 = GetTrend(htf2);

      if(trend1 == TREND_BULL && trend2 == TREND_BULL)
         return TREND_BULL;
      if(trend1 == TREND_BEAR && trend2 == TREND_BEAR)
         return TREND_BEAR;

      return TREND_NONE; // Conflicting or neutral
   }

   //+------------------------------------------------------------------+
   //| Get Trend of specific registered timeframe                       |
   //+------------------------------------------------------------------+
   ENUM_SMC_TREND GetTrend(const ENUM_TIMEFRAMES tf)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return TREND_NONE;
      return m_tfData[idx].trend;
   }

   //+------------------------------------------------------------------+
   //| Get Last Main High and Low for a timeframe                       |
   //+------------------------------------------------------------------+
   bool GetMainStructureRange(const ENUM_TIMEFRAMES tf, STFStructure &outHigh, STFStructure &outLow)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return false;

      outHigh = m_tfData[idx].lastMainHigh;
      outLow  = m_tfData[idx].lastMainLow;
      return (outHigh.priceH > 0 && outLow.priceL > 0);
   }

   //+------------------------------------------------------------------+
   //| Get Equilibrium Price (50% Fibonacci level of Main Swings)       |
   //+------------------------------------------------------------------+
   double GetEquilibrium(const ENUM_TIMEFRAMES tf)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return 0.0;
      return m_tfData[idx].equilibriumPrice;
   }

private:
   int FindTFIndex(const ENUM_TIMEFRAMES tf)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfData[i].tf == tf) return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Core Algorithm: Scan completed bars for Swings & Body Breaks     |
   //+------------------------------------------------------------------+
   void CalculateStructure(const string symbol, const int tfIndex)
   {
      ENUM_TIMEFRAMES tf = m_tfData[tfIndex].tf;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      // We only need the last 50 completed bars for structure detection
      int copied = CopyRates(symbol, tf, 1, 50, rates);
      if(copied < 10) return;

      // Scan for 3-bar swing pivot on Bar 2
      // Pivot High: High[2] > High[1] and High[2] > High[3]
      // Pivot Low:  Low[2] < Low[1] and Low[2] < Low[3]
      for(int b = 2; b < copied - 1; b++)
      {
         bool isPivotHigh = (rates[b].high > rates[b - 1].high && rates[b].high > rates[b + 1].high);
         bool isPivotLow  = (rates[b].low  < rates[b - 1].low  && rates[b].low  < rates[b + 1].low);

         if(isPivotHigh)
         {
            double swingHighPrice = rates[b].high;
            datetime swingTime    = rates[b].time;

            // Check if this breaks previous Main High by body close
            if(m_tfData[tfIndex].lastMainHigh.priceH > 0 && rates[0].close > m_tfData[tfIndex].lastMainHigh.priceH)
            {
               // Confirmed BOS Bullish -> Validates new Main Higher High (HH)
               m_tfData[tfIndex].lastMainHigh.label      = "HH";
               m_tfData[tfIndex].lastMainHigh.priceH     = swingHighPrice;
               m_tfData[tfIndex].lastMainHigh.candleTime = swingTime;
               m_tfData[tfIndex].lastMainHigh.isMain     = true;
               m_tfData[tfIndex].trend                   = TREND_BULL;
            }
            else
            {
               // Sub-swing inside range -> Internal Structure High
               m_tfData[tfIndex].lastInternalHigh.label      = (m_tfData[tfIndex].lastMainHigh.priceH > 0 && swingHighPrice < m_tfData[tfIndex].lastMainHigh.priceH) ? "LH" : "H";
               m_tfData[tfIndex].lastInternalHigh.priceH     = swingHighPrice;
               m_tfData[tfIndex].lastInternalHigh.candleTime = swingTime;
               m_tfData[tfIndex].lastInternalHigh.isMain     = false;

               if(m_tfData[tfIndex].lastMainHigh.priceH == 0)
               {
                  m_tfData[tfIndex].lastMainHigh = m_tfData[tfIndex].lastInternalHigh;
                  m_tfData[tfIndex].lastMainHigh.isMain = true;
               }
            }
         }

         if(isPivotLow)
         {
            double swingLowPrice = rates[b].low;
            datetime swingTime   = rates[b].time;

            // Check if this breaks previous Main Low by body close
            if(m_tfData[tfIndex].lastMainLow.priceL > 0 && rates[0].close < m_tfData[tfIndex].lastMainLow.priceL)
            {
               // Confirmed BOS Bearish -> Validates new Main Lower Low (LL)
               m_tfData[tfIndex].lastMainLow.label      = "LL";
               m_tfData[tfIndex].lastMainLow.priceL     = swingLowPrice;
               m_tfData[tfIndex].lastMainLow.candleTime = swingTime;
               m_tfData[tfIndex].lastMainLow.isMain     = true;
               m_tfData[tfIndex].trend                  = TREND_BEAR;
            }
            else
            {
               // Sub-swing inside range -> Internal Structure Low
               m_tfData[tfIndex].lastInternalLow.label      = (m_tfData[tfIndex].lastMainLow.priceL > 0 && swingLowPrice > m_tfData[tfIndex].lastMainLow.priceL) ? "HL" : "L";
               m_tfData[tfIndex].lastInternalLow.priceL     = swingLowPrice;
               m_tfData[tfIndex].lastInternalLow.candleTime = swingTime;
               m_tfData[tfIndex].lastInternalLow.isMain     = false;

               if(m_tfData[tfIndex].lastMainLow.priceL == 0)
               {
                  m_tfData[tfIndex].lastMainLow = m_tfData[tfIndex].lastInternalLow;
                  m_tfData[tfIndex].lastMainLow.isMain = true;
               }
            }
         }
         break; // Process latest confirmed swing
      }

      // Calculate Equilibrium Price (50%)
      if(m_tfData[tfIndex].lastMainHigh.priceH > 0 && m_tfData[tfIndex].lastMainLow.priceL > 0)
      {
         m_tfData[tfIndex].equilibriumPrice = (m_tfData[tfIndex].lastMainHigh.priceH + m_tfData[tfIndex].lastMainLow.priceL) / 2.0;
      }
   }
};

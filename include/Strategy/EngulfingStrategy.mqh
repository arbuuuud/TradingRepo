//+------------------------------------------------------------------+
//|                                        EngulfingStrategy.mqh     |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "BaseEntryEngine.mqh"

enum ENUM_FIBO_SOURCE_TF
{
   FIBO_FROM_M3  = 0, // Calculate Fibonacci from M3 Structure
   FIBO_FROM_M15 = 1  // Calculate Fibonacci from M15 Structure
};

class CEngulfingStrategy : public CBaseEntryEngine
{
private:
   ENUM_TIMEFRAMES         m_htfBias1;      // H1
   ENUM_TIMEFRAMES         m_htfBias2;      // M15
   ENUM_TIMEFRAMES         m_setupTF;       // M3
   ENUM_TIMEFRAMES         m_triggerTF;     // M1
   ENUM_FIBO_SOURCE_TF     m_fiboSource;
   double                  m_fibTolerancePoints;
   double                  m_riskRewardRatio;
   datetime                m_lastM3Processed;

public:
   CEngulfingStrategy(const ulong magic = 888201) : 
      CBaseEntryEngine("Test01EngulfingEntry", PERIOD_M3, magic),
      m_htfBias1(PERIOD_H1),
      m_htfBias2(PERIOD_M15),
      m_setupTF(PERIOD_M3),
      m_triggerTF(PERIOD_M1),
      m_fiboSource(FIBO_FROM_M3),
      m_fibTolerancePoints(30.0),
      m_riskRewardRatio(2.0),
      m_lastM3Processed(0)
   {}

   ~CEngulfingStrategy() {}

   void Configure(const ENUM_FIBO_SOURCE_TF fiboSource, const double fibTolerancePoints, const double rrRatio)
   {
      m_fiboSource         = fiboSource;
      m_fibTolerancePoints = fibTolerancePoints;
      m_riskRewardRatio    = rrRatio;
   }

   //+------------------------------------------------------------------+
   //| Main Evaluation Method                                           |
   //+------------------------------------------------------------------+
   virtual bool EvaluateEntry(const string symbol, 
                              CMTFStructureEngine &structure, 
                              CSmartTradeManager &tradeManager, 
                              const double riskPercent, 
                              const double maxSpreadPoints) override
   {
      if(!m_isEnabled) return false;

      // 1. Spread Check
      long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(maxSpreadPoints > 0 && currentSpread > maxSpreadPoints)
         return false;

      // 2. Rule 2: Trend Alignment (H1 + M15 must agree)
      ENUM_SMC_TREND macroTrend = structure.GetCombinedBias(m_htfBias1, m_htfBias2);
      if(macroTrend == TREND_NONE)
         return false; // Trend not aligned

      // 3. Rule 1 & 3: Check M3 Candle on completed bar
      datetime m3BarTime = iTime(symbol, m_setupTF, 1);
      if(m3BarTime == 0 || m3BarTime == m_lastM3Processed)
         return false; // Already checked this M3 bar

      MqlRates m3Rates[];
      ArraySetAsSeries(m3Rates, true);
      if(CopyRates(symbol, m_setupTF, 1, 3, m3Rates) < 3)
         return false;

      // Detect M3 Engulfing (Bar 0 in copied array is Bar 1 on chart)
      bool m3BullEngulf = IsBullishEngulfing(m3Rates[0], m3Rates[1]);
      bool m3BearEngulf = IsBearishEngulfing(m3Rates[0], m3Rates[1]);

      if(!m3BullEngulf && !m3BearEngulf)
         return false;

      // Must align with Macro Trend
      if(m3BullEngulf && macroTrend != TREND_BULL) return false;
      if(m3BearEngulf && macroTrend != TREND_BEAR) return false;

      // 4. Rule 3: Check if M3 Engulfing touches 0.382 or 0.618 of Structure Range
      ENUM_TIMEFRAMES structureTF = (m_fiboSource == FIBO_FROM_M3) ? m_setupTF : m_htfBias2;
      STFStructure stHigh, stLow;
      if(!structure.GetMainStructureRange(structureTF, stHigh, stLow))
         return false;

      double range = stHigh.priceH - stLow.priceL;
      if(range <= 0.0) return false;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tolPrice = m_fibTolerancePoints * point;

      // In an Uptrend (Bullish): Retracement levels from High downwards
      // Level 0.382 = High - 0.382 * range
      // Level 0.618 = High - 0.618 * range
      // In a Downtrend (Bearish): Retracement levels from Low upwards
      // Level 0.382 = Low + 0.382 * range
      // Level 0.618 = Low + 0.618 * range
      double fib382 = 0.0;
      double fib618 = 0.0;

      if(macroTrend == TREND_BULL)
      {
         fib382 = stHigh.priceH - (0.382 * range);
         fib618 = stHigh.priceH - (0.618 * range);
      }
      else
      {
         fib382 = stLow.priceL + (0.382 * range);
         fib618 = stLow.priceL + (0.618 * range);
      }

      bool touchFib = (PriceTouchesLevel(m3Rates[0].low, m3Rates[0].high, fib382, tolPrice) ||
                       PriceTouchesLevel(m3Rates[0].low, m3Rates[0].high, fib618, tolPrice));

      if(!touchFib)
      {
         return false; // M3 candle did not touch 0.382 or 0.618
      }

      // 5. Rule 1: Confirmation on M1 -> Is there an Engulfing on M1?
      MqlRates m1Rates[];
      ArraySetAsSeries(m1Rates, true);
      // Check last 3 completed M1 candles
      if(CopyRates(symbol, m_triggerTF, 1, 3, m1Rates) < 3)
         return false;

      bool m1Confirmed = false;
      if(macroTrend == TREND_BULL)
      {
         m1Confirmed = IsBullishEngulfing(m1Rates[0], m1Rates[1]) || IsBullishEngulfing(m1Rates[1], m1Rates[2]);
      }
      else
      {
         m1Confirmed = IsBearishEngulfing(m1Rates[0], m1Rates[1]) || IsBearishEngulfing(m1Rates[1], m1Rates[2]);
      }

      if(!m1Confirmed)
         return false; // M1 confirmation not found yet

      // Mark this M3 setup as processed
      m_lastM3Processed = m3BarTime;

      // 6. Execute Entry with Dynamic Lot & SL/TP
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      if(macroTrend == TREND_BULL)
      {
         // Stop loss placed below M3 Engulfing Low with 10 pts buffer
         double slPrice = NormalizeDouble(m3Rates[0].low - (10 * point), digits);
         double slDist  = ask - slPrice;
         if(slDist <= 0) return false;

         double tpPrice = NormalizeDouble(ask + (slDist * m_riskRewardRatio), digits);
         double lot     = tradeManager.CalculateLot(symbol, ask, slPrice, riskPercent);

         PrintFormat("[Test01EngulfingEntry] BUY Signal! Trend=BULL, M3 & M1 Engulf confirmed at Fib, Lot: %.2f, Ask: %.5f, SL: %.5f, TP: %.5f",
                     lot, ask, slPrice, tpPrice);

         return tradeManager.OpenBuy(symbol, lot, slPrice, tpPrice, "Engulf-M3-M1-Buy");
      }
      else if(macroTrend == TREND_BEAR)
      {
         // Stop loss placed above M3 Engulfing High with 10 pts buffer
         double slPrice = NormalizeDouble(m3Rates[0].high + (10 * point), digits);
         double slDist  = slPrice - bid;
         if(slDist <= 0) return false;

         double tpPrice = NormalizeDouble(bid - (slDist * m_riskRewardRatio), digits);
         double lot     = tradeManager.CalculateLot(symbol, bid, slPrice, riskPercent);

         PrintFormat("[Test01EngulfingEntry] SELL Signal! Trend=BEAR, M3 & M1 Engulf confirmed at Fib, Lot: %.2f, Bid: %.5f, SL: %.5f, TP: %.5f",
                     lot, bid, slPrice, tpPrice);

         return tradeManager.OpenSell(symbol, lot, slPrice, tpPrice, "Engulf-M3-M1-Sell");
      }

      return false;
   }

private:
   //+------------------------------------------------------------------+
   //| Check if Candle A (newer) engulfs Candle B (older) Bullish       |
   //+------------------------------------------------------------------+
   bool IsBullishEngulfing(const MqlRates &currentBar, const MqlRates &prevBar)
   {
      // Prev bar must be bearish (or doji)
      bool prevBearish = (prevBar.close <= prevBar.open);
      // Current bar must be strong bullish
      bool currBullish = (currentBar.close > currentBar.open);

      if(!currBullish || !prevBearish) return false;

      // Body engulfing: Current body covers previous body
      bool bodyEngulf = (currentBar.close >= prevBar.open && currentBar.open <= prevBar.close);
      // Extra confirmation: Current high > prev high
      bool breakout   = (currentBar.high >= prevBar.high);

      return (bodyEngulf && breakout);
   }

   //+------------------------------------------------------------------+
   //| Check if Candle A (newer) engulfs Candle B (older) Bearish       |
   //+------------------------------------------------------------------+
   bool IsBearishEngulfing(const MqlRates &currentBar, const MqlRates &prevBar)
   {
      // Prev bar must be bullish (or doji)
      bool prevBullish = (prevBar.close >= prevBar.open);
      // Current bar must be strong bearish
      bool currBearish = (currentBar.close < currentBar.open);

      if(!currBearish || !prevBullish) return false;

      // Body engulfing: Current body covers previous body
      bool bodyEngulf = (currentBar.close <= prevBar.open && currentBar.open >= prevBar.close);
      // Extra confirmation: Current low < prev low
      bool breakdown  = (currentBar.low <= prevBar.low);

      return (bodyEngulf && breakdown);
   }

   //+------------------------------------------------------------------+
   //| Helper: Check if candle low-high range touches level +/- tolerance|
   //+------------------------------------------------------------------+
   bool PriceTouchesLevel(const double candleLow, const double candleHigh, const double level, const double tolerance)
   {
      return (candleLow <= (level + tolerance) && candleHigh >= (level - tolerance));
   }
};

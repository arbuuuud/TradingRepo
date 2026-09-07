//+------------------------------------------------------------------+
//|                                             M3SMCStrategy.mqh    |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "BaseEntryEngine.mqh"

class CM3SMCStrategy : public CBaseEntryEngine
{
private:
   ENUM_TIMEFRAMES   m_htfBias1;
   ENUM_TIMEFRAMES   m_htfBias2;
   ENUM_TIMEFRAMES   m_setupTF;
   ENUM_TIMEFRAMES   m_triggerTF;

public:
   CM3SMCStrategy(const ulong magic = 888103) : 
      CBaseEntryEngine("M3-SMC-Pullback", PERIOD_M3, magic),
      m_htfBias1(PERIOD_H1),
      m_htfBias2(PERIOD_M15),
      m_setupTF(PERIOD_M3),
      m_triggerTF(PERIOD_M1)
   {}

   ~CM3SMCStrategy() {}

   virtual bool EvaluateEntry(const string symbol, 
                              CMTFStructureEngine &structure, 
                              CSmartTradeManager &tradeManager, 
                              const double riskPercent, 
                              const double maxSpreadPoints) override
   {
      if(!m_isEnabled) return false;

      // 1. Spread filter
      long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(maxSpreadPoints > 0 && currentSpread > maxSpreadPoints)
         return false;

      // 2. Tier 1: Check Combined Macro Bias (H1 + M15)
      ENUM_SMC_TREND macroBias = structure.GetCombinedBias(m_htfBias1, m_htfBias2);
      if(macroBias == TREND_NONE) return false;

      // 3. Tier 2: Check Setup Base (M3 Structure & Equilibrium)
      STFStructure m3High, m3Low;
      if(!structure.GetMainStructureRange(m_setupTF, m3High, m3Low))
         return false;

      double eqPrice = structure.GetEquilibrium(m_setupTF);
      if(eqPrice <= 0.0) return false;

      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

      // 4. Tier 3: Trigger & Execution Check
      if(macroBias == TREND_BULL)
      {
         // Discount Zone: price must be below 50% Equilibrium
         if(ask >= eqPrice) return false;

         // Stop loss placed below last M3 Main Low
         double slPrice = m3Low.priceL;
         if(slPrice <= 0.0 || slPrice >= ask) return false;

         // Dynamic Lot
         double lot = tradeManager.CalculateLot(symbol, ask, slPrice, riskPercent);
         double tpPrice = m3High.priceH; // Target opposing main high

         PrintFormat("[M3SMCStrategy] Firing BUY Order. Lot: %.2f, Ask: %.5f, SL: %.5f, TP: %.5f", 
                     lot, ask, slPrice, tpPrice);
         return tradeManager.OpenBuy(symbol, lot, slPrice, tpPrice, "M3-SMC-Buy");
      }
      else if(macroBias == TREND_BEAR)
      {
         // Premium Zone: price must be above 50% Equilibrium
         if(bid <= eqPrice) return false;

         // Stop loss placed above last M3 Main High
         double slPrice = m3High.priceH;
         if(slPrice <= 0.0 || slPrice <= bid) return false;

         // Dynamic Lot
         double lot = tradeManager.CalculateLot(symbol, bid, slPrice, riskPercent);
         double tpPrice = m3Low.priceL; // Target opposing main low

         PrintFormat("[M3SMCStrategy] Firing SELL Order. Lot: %.2f, Bid: %.5f, SL: %.5f, TP: %.5f", 
                     lot, bid, slPrice, tpPrice);
         return tradeManager.OpenSell(symbol, lot, slPrice, tpPrice, "M3-SMC-Sell");
      }

      return false;
   }
};

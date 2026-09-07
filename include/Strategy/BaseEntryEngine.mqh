//+------------------------------------------------------------------+
//|                                            BaseEntryEngine.mqh   |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "..\MTFStructure\MTFStructureEngine.mqh"
#include "..\TradeManager\SmartTradeManager.mqh"

//+------------------------------------------------------------------+
//| Abstract / Base Entry Engine Interface                           |
//+------------------------------------------------------------------+
class CBaseEntryEngine
{
protected:
   bool              m_isEnabled;
   ulong             m_magicNumber;
   ENUM_TIMEFRAMES   m_entryTF;
   string            m_engineName;

public:
   CBaseEntryEngine(const string engineName, const ENUM_TIMEFRAMES entryTF, const ulong magic) :
      m_engineName(engineName),
      m_entryTF(entryTF),
      m_magicNumber(magic),
      m_isEnabled(true)
   {}

   virtual ~CBaseEntryEngine() {}

   virtual void SetEnabled(const bool enabled) { m_isEnabled = enabled; }
   virtual bool IsEnabled() const { return m_isEnabled; }
   virtual ulong GetMagicNumber() const { return m_magicNumber; }
   virtual string GetName() const { return m_engineName; }

   //+------------------------------------------------------------------+
   //| Evaluation logic to be overridden by specific strategies         |
   //+------------------------------------------------------------------+
   virtual bool EvaluateEntry(const string symbol, 
                              CMTFStructureEngine &structure, 
                              CSmartTradeManager &tradeManager, 
                              const double riskPercent, 
                              const double maxSpreadPoints)
   {
      // To be implemented by child classes (e.g. M1 Trigger, M3 Pullback, M15 Breakout)
      return false;
   }
};

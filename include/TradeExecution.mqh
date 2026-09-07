//+------------------------------------------------------------------+
//|                                               TradeExecution.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include <Trade\Trade.mqh>
#include "Defines.mqh"

class CTradeExecution
{
private:
   CTrade         m_trade;
   ulong          m_magicNumber;
   int            m_slippagePoints;

public:
   CTradeExecution() : m_magicNumber(123456), m_slippagePoints(10) {}
   ~CTradeExecution() {}

   //+------------------------------------------------------------------+
   //| Initialization                                                   |
   //+------------------------------------------------------------------+
   bool Init(const ulong magicNumber, const int slippagePoints)
   {
      m_magicNumber     = magicNumber;
      m_slippagePoints  = slippagePoints;

      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetTypeFillingBySymbol(_Symbol);

      PrintFormat("[TradeExecution] Initialized with Magic: %I64u, Deviation: %d points", 
                  m_magicNumber, m_slippagePoints);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Count open positions for this symbol & magic number              |
   //+------------------------------------------------------------------+
   int CountOpenPositions(const string symbol)
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
               count++;
            }
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Open Buy Position                                                |
   //+------------------------------------------------------------------+
   bool OpenBuy(const string symbol, const double lotSize, const double stopLossPoints, const double takeProfitPoints, const string comment)
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      double sl = 0.0;
      double tp = 0.0;

      if(stopLossPoints > 0)
         sl = NormalizeDouble(ask - (stopLossPoints * point), digits);
      if(takeProfitPoints > 0)
         tp = NormalizeDouble(ask + (takeProfitPoints * point), digits);

      if(!m_trade.Buy(lotSize, symbol, ask, sl, tp, comment))
      {
         PrintFormat("[TradeExecution] Buy Failed! Error: %d - %s", 
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
      }

      PrintFormat("[TradeExecution] Buy Opened successfully: Deal #%I64u, Volume: %.2f at %.5f", 
                  m_trade.ResultDeal(), lotSize, ask);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Open Sell Position                                               |
   //+------------------------------------------------------------------+
   bool OpenSell(const string symbol, const double lotSize, const double stopLossPoints, const double takeProfitPoints, const string comment)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      double sl = 0.0;
      double tp = 0.0;

      if(stopLossPoints > 0)
         sl = NormalizeDouble(bid + (stopLossPoints * point), digits);
      if(takeProfitPoints > 0)
         tp = NormalizeDouble(bid - (takeProfitPoints * point), digits);

      if(!m_trade.Sell(lotSize, symbol, bid, sl, tp, comment))
      {
         PrintFormat("[TradeExecution] Sell Failed! Error: %d - %s", 
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
      }

      PrintFormat("[TradeExecution] Sell Opened successfully: Deal #%I64u, Volume: %.2f at %.5f", 
                  m_trade.ResultDeal(), lotSize, bid);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Close all positions for this EA                                  |
   //+------------------------------------------------------------------+
   void CloseAllPositions(const string symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
               m_trade.PositionClose(ticket);
            }
         }
      }
   }
};

//+------------------------------------------------------------------+
//|                                           SmartTradeManager.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include <Trade\Trade.mqh>

struct SActivePosition
{
   ulong    ticket;
   bool     isLong;
   double   entryPrice;
   double   initialLot;
   bool     isSafeMode; // Breakeven activated
   int      currentTPLevel;

   void Init()
   {
      ticket         = 0;
      isLong         = false;
      entryPrice     = 0.0;
      initialLot     = 0.0;
      isSafeMode     = false;
      currentTPLevel = 0;
   }
};

class CSmartTradeManager
{
private:
   CTrade            m_trade;
   ulong             m_magicNumber;
   double            m_maxDailyLossPct;
   double            m_startDayEquity;
   datetime          m_lastDayChecked;
   string            m_currentSession;

   SActivePosition   m_positions[];
   int               m_totalPositions;

public:
   CSmartTradeManager() : 
      m_magicNumber(888101),
      m_maxDailyLossPct(5.0),
      m_startDayEquity(0.0),
      m_lastDayChecked(0),
      m_currentSession(""),
      m_totalPositions(0)
   {
      ArrayResize(m_positions, 0);
   }

   ~CSmartTradeManager()
   {
      ArrayFree(m_positions);
   }

   //+------------------------------------------------------------------+
   //| Init                                                             |
   //+------------------------------------------------------------------+
   bool Init(const ulong magic, const double maxDailyLossPct, const int slippagePoints)
   {
      m_magicNumber     = magic;
      m_maxDailyLossPct = maxDailyLossPct;

      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(slippagePoints);
      m_trade.SetTypeFillingBySymbol(_Symbol);

      m_startDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Dynamic Lot based on Entry and SL                      |
   //+------------------------------------------------------------------+
   double CalculateLot(const string symbol, const double entryPrice, const double slPrice, const double riskPercent)
   {
      if(entryPrice == slPrice || riskPercent <= 0)
         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmount = equity * (riskPercent / 100.0);

      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

      if(point <= 0 || tickValue <= 0 || tickSize <= 0)
         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      double distPoints    = MathAbs(entryPrice - slPrice) / point;
      double pointsPerTick = tickSize / point;
      double lossPerLot    = (distPoints / pointsPerTick) * tickValue;

      if(lossPerLot <= 0)
         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      double calculatedLot = riskAmount / lossPerLot;

      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(lotStep <= 0) lotStep = 0.01;
      double normalized = MathFloor(calculatedLot / lotStep) * lotStep;
      if(normalized < minLot) normalized = minLot;
      if(normalized > maxLot) normalized = maxLot;

      return normalized;
   }

   //+------------------------------------------------------------------+
   //| Real-Time Tick Management (Smart SL & Trailing)                  |
   //+------------------------------------------------------------------+
   void OnTickManage(const string symbol, const double tp1Points, const double beBufferPoints)
   {
      // 1. Check Maximum Daily Loss Protection
      if(!CheckDailyDrawdown())
      {
         CloseAllPositions(symbol, "Daily Drawdown Limit Exceeded");
         return;
      }

      // 2. Manage Open Positions
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double curPrice  = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

         double profitPoints = (posType == POSITION_TYPE_BUY) ? (curPrice - openPrice) / point : (openPrice - curPrice) / point;

         // Move SL to Breakeven when TP1 distance is reached
         if(tp1Points > 0 && profitPoints >= tp1Points)
         {
            double newSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(openPrice + (beBufferPoints * point), digits);
               if(currentSL < openPrice) // Haven't moved to BE yet
               {
                  m_trade.PositionModify(ticket, newSL, currentTP);
                  PrintFormat("[SmartTradeManager] BE Activated for BUY #%I64u at %.5f", ticket, newSL);
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               newSL = NormalizeDouble(openPrice - (beBufferPoints * point), digits);
               if(currentSL > openPrice || currentSL == 0.0) // Haven't moved to BE yet
               {
                  m_trade.PositionModify(ticket, newSL, currentTP);
                  PrintFormat("[SmartTradeManager] BE Activated for SELL #%I64u at %.5f", ticket, newSL);
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Periodic Housekeeping (OnTimer)                                  |
   //+------------------------------------------------------------------+
   void OnTimerHousekeeping(const string symbol)
   {
      MqlDateTime dt;
      TimeGMT(dt);

      UpdateMarketSession(dt);

      // Force Exit at 23:55 GMT before daily rollover
      if(dt.hour == 23 && dt.min >= 55)
      {
         Print("[SmartTradeManager] EOD 23:55 GMT reached. Force-closing all positions before rollover!");
         CloseAllPositions(symbol, "EOD Rollover Protection");
      }
   }

   //+------------------------------------------------------------------+
   //| Execute Buy Order                                                |
   //+------------------------------------------------------------------+
   bool OpenBuy(const string symbol, const double lot, const double slPrice, const double tpPrice, const string comment)
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      return m_trade.Buy(lot, symbol, ask, slPrice, tpPrice, comment);
   }

   //+------------------------------------------------------------------+
   //| Execute Sell Order                                               |
   //+------------------------------------------------------------------+
   bool OpenSell(const string symbol, const double lot, const double slPrice, const double tpPrice, const string comment)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      return m_trade.Sell(lot, symbol, bid, slPrice, tpPrice, comment);
   }

   //+------------------------------------------------------------------+
   //| Close all positions for this EA                                  |
   //+------------------------------------------------------------------+
   void CloseAllPositions(const string symbol, const string reason)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == symbol)
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
               m_trade.PositionClose(ticket);
               PrintFormat("[SmartTradeManager] Position #%I64u closed. Reason: %s", ticket, reason);
            }
         }
      }
   }

   string GetCurrentSession() const { return m_currentSession; }

private:
   bool CheckDailyDrawdown()
   {
      if(m_maxDailyLossPct <= 0) return true;

      MqlDateTime dt;
      TimeCurrent(dt);
      datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

      if(m_lastDayChecked != todayStart)
      {
         m_lastDayChecked = todayStart;
         m_startDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_startDayEquity > 0)
      {
         double drawdown = ((m_startDayEquity - currentEquity) / m_startDayEquity) * 100.0;
         if(drawdown >= m_maxDailyLossPct) return false;
      }
      return true;
   }

   void UpdateMarketSession(const MqlDateTime &dt)
   {
      int hour = dt.hour;
      bool isAsian  = (hour >= 0 && hour < 9);
      bool isLondon = (hour >= 8 && hour < 16);
      bool isNY     = (hour >= 13 && hour < 21);

      if(isLondon && isNY)      m_currentSession = "LN"; // London + New York overlap
      else if(isAsian && isLondon) m_currentSession = "AL"; // Asian + London overlap
      else if(isNY)             m_currentSession = "NY";
      else if(isLondon)         m_currentSession = "LO";
      else if(isAsian)          m_currentSession = "AS";
      else                      m_currentSession = "QN"; // Quiet Night
   }
};

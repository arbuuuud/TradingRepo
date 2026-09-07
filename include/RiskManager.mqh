//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "Defines.mqh"

class CRiskManager
{
private:
   double         m_startDayEquity;
   datetime       m_lastDayChecked;

public:
   CRiskManager() : m_startDayEquity(0), m_lastDayChecked(0) {}
   ~CRiskManager() {}

   //+------------------------------------------------------------------+
   //| Check if spread is within acceptable limit                      |
   //+------------------------------------------------------------------+
   bool IsSpreadAcceptable(const string symbol, const int maxSpreadPoints)
   {
      if(maxSpreadPoints <= 0) return true; // Filter disabled
      long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(currentSpread > maxSpreadPoints)
      {
         PrintFormat("[RiskManager] Spread too high: %d points (Max allowed: %d)", currentSpread, maxSpreadPoints);
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Track daily drawdown against starting equity                    |
   //+------------------------------------------------------------------+
   bool CheckDailyDrawdown(const double maxDailyLossPercent)
   {
      if(maxDailyLossPercent <= 0) return true; // Disabled

      MqlDateTime dt;
      TimeCurrent(dt);
      datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

      if(m_lastDayChecked != todayStart)
      {
         m_lastDayChecked = todayStart;
         m_startDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         PrintFormat("[RiskManager] New trading day initialized. Base Equity: %.2f", m_startDayEquity);
      }

      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_startDayEquity > 0)
      {
         double drawdownPercent = ((m_startDayEquity - currentEquity) / m_startDayEquity) * 100.0;
         if(drawdownPercent >= maxDailyLossPercent)
         {
            PrintFormat("[RiskManager] Daily drawdown limit exceeded: %.2f%% >= %.2f%%. Trading halted today!", 
                        drawdownPercent, maxDailyLossPercent);
            return false;
         }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate Lot Size based on Fixed or Risk Percentage             |
   //+------------------------------------------------------------------+
   double CalculateLotSize(const string symbol, 
                           const ENUM_LOT_MODE lotMode, 
                           const double fixedLot, 
                           const double riskPercent, 
                           const double stopLossPoints)
   {
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(lotMode == LOT_FIXED || stopLossPoints <= 0)
      {
         return NormalizeLot(fixedLot, minLot, maxLot, lotStep);
      }

      // Calculate risk amount in deposit currency
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * (riskPercent / 100.0);

      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

      if(tickSize <= 0 || tickValue <= 0 || point <= 0)
      {
         Print("[RiskManager] Warning: Invalid symbol tick specification. Using fixed lot.");
         return NormalizeLot(fixedLot, minLot, maxLot, lotStep);
      }

      // Loss per 1.0 standard lot
      double pointsPerTick = tickSize / point;
      double ticksRisked   = stopLossPoints / pointsPerTick;
      double lossPerLot    = ticksRisked * tickValue;

      if(lossPerLot <= 0)
      {
         return NormalizeLot(fixedLot, minLot, maxLot, lotStep);
      }

      double calculatedLot = riskMoney / lossPerLot;
      return NormalizeLot(calculatedLot, minLot, maxLot, lotStep);
   }

private:
   double NormalizeLot(double lot, double minLot, double maxLot, double lotStep)
   {
      if(lotStep <= 0) lotStep = 0.01;
      double normalized = MathFloor(lot / lotStep) * lotStep;
      if(normalized < minLot) normalized = minLot;
      if(normalized > maxLot) normalized = maxLot;
      return normalized;
   }
};

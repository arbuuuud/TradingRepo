//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property strict

#include "Defines.mqh"

class CSignalEngine
{
private:
   int            m_fastMaHandle;
   int            m_slowMaHandle;
   int            m_rsiHandle;
   datetime       m_lastBarTime;

public:
   CSignalEngine() : 
      m_fastMaHandle(INVALID_HANDLE), 
      m_slowMaHandle(INVALID_HANDLE), 
      m_rsiHandle(INVALID_HANDLE),
      m_lastBarTime(0) 
   {}

   ~CSignalEngine()
   {
      ReleaseHandles();
   }

   //+------------------------------------------------------------------+
   //| Initialize Indicator Handles                                     |
   //+------------------------------------------------------------------+
   bool Init(const string symbol, const ENUM_TIMEFRAMES period,
             const int fastMaPeriod, const int slowMaPeriod, const int rsiPeriod)
   {
      ReleaseHandles();

      m_fastMaHandle = iMA(symbol, period, fastMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_slowMaHandle = iMA(symbol, period, slowMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_rsiHandle    = iRSI(symbol, period, rsiPeriod, PRICE_CLOSE);

      if(m_fastMaHandle == INVALID_HANDLE || m_slowMaHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE)
      {
         PrintFormat("[SignalEngine] Failed to create indicator handles! Error: %d", GetLastError());
         return false;
      }

      PrintFormat("[SignalEngine] Handles created: FastMA(%d)=%d, SlowMA(%d)=%d, RSI(%d)=%d",
                  fastMaPeriod, m_fastMaHandle, slowMaPeriod, m_slowMaHandle, rsiPeriod, m_rsiHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if a new completed bar has appeared                        |
   //+------------------------------------------------------------------+
   bool IsNewBar(const string symbol, const ENUM_TIMEFRAMES period)
   {
      datetime currentBarTime = iTime(symbol, period, 0);
      if(currentBarTime != m_lastBarTime)
      {
         m_lastBarTime = currentBarTime;
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Generate Signal based on completed bar (Index 1 and 2)           |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_TYPE CheckSignal(const string symbol, const ENUM_TIMEFRAMES period,
                                const double rsiOverbought = 70.0, const double rsiOversold = 30.0)
   {
      if(m_fastMaHandle == INVALID_HANDLE || m_slowMaHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE)
         return SIGNAL_NONE;

      double fastMA[2], slowMA[2], rsi[1];

      // Copy buffer for Bar 1 and Bar 2 (completed bars, non-repainting)
      if(CopyBuffer(m_fastMaHandle, 0, 1, 2, fastMA) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_slowMaHandle, 0, 1, 2, slowMA) < 2) return SIGNAL_NONE;
      if(CopyBuffer(m_rsiHandle, 0, 1, 1, rsi) < 1) return SIGNAL_NONE;

      // fastMA[1] = bar 1 (most recently closed bar)
      // fastMA[0] = bar 2 (previous closed bar)
      bool bullishCross = (fastMA[0] <= slowMA[0]) && (fastMA[1] > slowMA[1]);
      bool bearishCross = (fastMA[0] >= slowMA[0]) && (fastMA[1] < slowMA[1]);

      if(bullishCross && rsi[0] > 50.0 && rsi[0] < rsiOverbought)
      {
         PrintFormat("[SignalEngine] BUY Signal confirmed! FastMA=%.5f crossed SlowMA=%.5f, RSI=%.2f",
                     fastMA[1], slowMA[1], rsi[0]);
         return SIGNAL_BUY;
      }
      else if(bearishCross && rsi[0] < 50.0 && rsi[0] > rsiOversold)
      {
         PrintFormat("[SignalEngine] SELL Signal confirmed! FastMA=%.5f crossed SlowMA=%.5f, RSI=%.2f",
                     fastMA[1], slowMA[1], rsi[0]);
         return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

private:
   void ReleaseHandles()
   {
      if(m_fastMaHandle != INVALID_HANDLE) { IndicatorRelease(m_fastMaHandle); m_fastMaHandle = INVALID_HANDLE; }
      if(m_slowMaHandle != INVALID_HANDLE) { IndicatorRelease(m_slowMaHandle); m_slowMaHandle = INVALID_HANDLE; }
      if(m_rsiHandle    != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle);    m_rsiHandle    = INVALID_HANDLE; }
   }
};

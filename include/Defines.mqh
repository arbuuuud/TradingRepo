//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property link      "https://github.com/arbuuuud/TradingRepo"
#property strict

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,   // No Signal
   SIGNAL_BUY  = 1,   // Buy Signal
   SIGNAL_SELL = -1   // Sell Signal
};

enum ENUM_LOT_MODE
{
   LOT_FIXED            = 0,  // Fixed Lot Size
   LOT_PERCENTAGE_RISK  = 1   // Risk % of Balance / Equity
};

//+------------------------------------------------------------------+
//| Structures                                                       |
//+------------------------------------------------------------------+
struct TradeSignal
{
   ENUM_SIGNAL_TYPE type;
   double           price;
   double           stopLoss;
   double           takeProfit;
   string           comment;
};

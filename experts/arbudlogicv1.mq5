//+------------------------------------------------------------------+
//|                                                arbudlogicv1.mq5  |
//|                                  Copyright 2025, TradingRepo EA  |
//|                                             https://github.com/  |
//+------------------------------------------------------------------+
#property copyright   "TradingRepo"
#property link        "https://github.com/arbuuuud/TradingRepo"
#property version     "1.00"
#property description "arbudlogicv1: Transaction Area Grid Limit (0.01 lot) with Smart TP and Stop Invalidation"

//+------------------------------------------------------------------+
//| Modular Includes                                                 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "..\include\arbud\structure\StructureV1.mqh"
#include "..\include\arbud\structure\rbrdbdV1.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ulong             InpMagicNumber       = 777101;          // Magic Number
input int               InpSlippagePoints    = 10;              // Max Slippage (Points)
input int               InpHistoryBars       = 500;             // History Bars to Scan on Init

input group "=== Grid Entry Settings ==="
input double            InpStaticLot         = 0.01;            // Static Order Volume
input int               InpMaxEntry          = 5;               // Max Grid Entry Points per Area (Default: 5)
input bool              InpEnableBuyLimit    = true;            // Enable Buy Limit Grid in Buy Area (0-25%)
input bool              InpEnableSellLimit   = true;            // Enable Sell Limit Grid in Sell Area (75-100%)
input bool              InpFilterByControlTrend = true;         // PAC: Filter Entry by M3 Structure Trend (Bull=Buy only, Bear=Sell only)
input double            InpHardSLPercent     = 30.0;            // Hard SL % from total area outside Floor/Roof (e.g. 30% = -30% / 130%)

input group "=== Smart TP & Exit Settings ==="
input bool              InpEnableSmartTP     = true;            // Enable Early TP Exit when Area Used >= 75%
input double            InpSmartTPThreshold  = 75.0;            // Threshold % to trigger Smart TP & Cancel Grid (Default 75%)
input int               InpDefaultSpreadPoints = 35;            // Default Spread Points for Smart TP buffer (Min profit = 2x spread)

input group "=== Candle Close SL Settings ==="
input bool              InpUseCandleCloseSL  = true;            // Cutloss on M3 Candle Close in 15%-30% outer zone
input double            InpCloseZoneMinPct   = 15.0;            // Min % outside Floor/Roof for M3 Close SL (Default: 15%)
input double            InpCloseZoneMaxPct   = 30.0;            // Max % outside Floor/Roof for M3 Close SL (Default: 30%)

input group "=== Equilibrium (M3 Structure) Settings ==="
input bool              InpEnableEquilibrium = true;            // Filter Buy in Discount (<50%) & Sell in Premium (>50%)
input int               InpM3Lookback        = 3;               // M3 confirmed structures lookback count (2-3)

input group "=== M3 Structure Settings ==="
input bool              InpEnableStructM3    = true;            // Enable M3 Structure Detection
input bool              InpDrawStructM3      = true;            // Draw M3 Structure on Chart
input color             InpColorStructM3     = clrDodgerBlue;   // M3 Structure Line Color
input int               InpWidthStructM3     = 1;               // M3 Structure Line Width

input group "=== M3 RBR / DBD Settings ==="
input bool              InpEnableRbrDbdM3    = true;            // Enable M3 RBR/DBD Detection
input bool              InpDrawRbrDbdM3      = true;            // Draw M3 RBR/DBD Rectangles on Chart
input bool              InpDrawRoofFloorM3   = true;            // Draw M3 Transaction Areas (Floor/Roof)
input int               InpMinBaseM3         = 1;               // M3 Min Base Candles (1~9)
input int               InpMaxBaseM3         = 5;               // M3 Max Base Candles (1~9)
input double            InpLegRatioM3        = 1.0;             // M3 Min Leg-Out vs Base Ratio

input group "=== Visual Colors ==="
input color             InpColorRBR          = clrMediumSeaGreen; // Fresh RBR (Demand)
input color             InpColorDBD          = clrCrimson;        // Fresh DBD (Supply)
input color             InpColorRoof         = clrIndianRed;      // 100% Roof Border
input color             InpColorFloor        = clrLimeGreen;      // 0% Floor Border

//+------------------------------------------------------------------+
//| Global Component Objects                                         |
//+------------------------------------------------------------------+
CTrade          ExtTrade;
CStructureV1    ExtStructure;
CRBRDBDV1       ExtRBRDBD;

// State tracking for placed grid orders
double g_placedBuyPrices[];
double g_placedSellPrices[];
double g_lastChannelRoof  = 0.0;
double g_lastChannelFloor = 0.0;
datetime g_lastM3BarTime  = 0;

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void ManageGridOrders(const string symbol, const SRoofFloorChannel &channel);
void ManageSmartTP(const string symbol, const SRoofFloorChannel &channel, const double bid, const double ask);
void CheckCandleCloseSL(const string symbol, const SRoofFloorChannel &currentChannel);
bool CalculateM3Equilibrium(const string symbol, const int lookback, double &outEq, double &outHigh, double &outLow);
void CloseAllPositionsAndOrders(const string symbol, const string reason);
void CancelAllPendingOrders(const string symbol, const string reason);
void CancelPendingOrdersByBatch(const int batchId, const string reason);
void CheckStandardTPClosedOrders();
bool IsPriceAlreadyOrdered(const double price, const double &placedArray[], const double tolerance);
void AddPlacedPrice(const double price, double &placedArray[]);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== [arbudlogicv1] Initializing EA with Grid & Smart TP (Main TF: M3) ===");

   if(InpMaxEntry < 2)
   {
      Alert("[arbudlogicv1] InpMaxEntry must be at least 2!");
      return INIT_PARAMETERS_INCORRECT;
   }

   // 1. Initialize CTrade
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippagePoints);
   ExtTrade.SetTypeFillingBySymbol(_Symbol);

   // 2. Structure Registration (M3 - Active & Drawn, M15/H1 background for fallback)
   ExtStructure.RegisterTimeframe(PERIOD_M1,  clrDarkGray,      1, false);
   ExtStructure.RegisterTimeframe(PERIOD_M3,  InpColorStructM3, InpWidthStructM3, InpDrawStructM3);
   ExtStructure.RegisterTimeframe(PERIOD_M15, clrGold,          1, false);
   ExtStructure.RegisterTimeframe(PERIOD_H1,  clrOrange,        1, false);

   // 3. RBR / DBD Registration (M3 - Active & Drawn, M15/H1 background for fallback)
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1,  1, 5, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_M3,  InpMinBaseM3, InpMaxBaseM3, InpLegRatioM3, 
                               InpDrawRbrDbdM3, InpDrawRoofFloorM3, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_M15, 1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_H1,  1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);

   // 4. Scan History on Init
   ExtStructure.InitHistory(_Symbol, InpHistoryBars);
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars, &ExtStructure);

   ArrayResize(g_placedBuyPrices, 0);
   ArrayResize(g_placedSellPrices, 0);

   PrintFormat("[arbudlogicv1] Init Succeeded on %s (Main TF: M3). Grid Size: %d", _Symbol, InpMaxEntry);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean visual objects
   ExtStructure.ClearChartObjects();
   ExtRBRDBD.ClearChartObjects();
   PrintFormat("=== [arbudlogicv1] Deinitialized. Reason: %d ===", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Event-driven update on completed candle close (M1, M3, M15, H1)
   ExtStructure.UpdateOnCandleClose(_Symbol);
   ExtRBRDBD.UpdateOnCandleClose(_Symbol, &ExtStructure);

   // 2. Real-time consumption & Transaction Area update on tick
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ExtRBRDBD.UpdateConsumptionOnTick(_Symbol, bid, ask, &ExtStructure);

   // 3. Fetch current M3 Transaction Area Channel
   SRoofFloorChannel channel;
   bool hasChannel = ExtRBRDBD.GetRoofFloorChannel(PERIOD_M3, channel);

   // Jika channel invalid (misal candle close tembus Stop Area), bersihkan pending orders
   if(!hasChannel || !channel.isValid)
   {
      CancelAllPendingOrders(_Symbol, "Channel Invalidated or Broken");
      ArrayResize(g_placedBuyPrices, 0);
      ArrayResize(g_placedSellPrices, 0);
      return;
   }

   // 4. Manage Grid Limit Orders (Buy Limit in Buy Area, Sell Limit in Sell Area)
   ManageGridOrders(_Symbol, channel);

   // 5. Anti-Fake Wick: Evaluate Cutloss on completed Candle Close outside Floor/Roof
   CheckCandleCloseSL(_Symbol, channel);

   // 6. Smart TP Check (Early exit if area was consumed >= 75%)
   if(InpEnableSmartTP)
   {
      ManageSmartTP(_Symbol, channel, bid, ask);
   }

   // 7. Check Standard TP Deal Closures: if batch already hit TP & area >= 75% used -> cancel remaining pending orders
   CheckStandardTPClosedOrders();
}

//+------------------------------------------------------------------+
//| Manage Grid Limit Orders                                         |
//+------------------------------------------------------------------+
void ManageGridOrders(const string symbol, const SRoofFloorChannel &channel)
{
   // Deteksi jika channel bergeser/berubah drastis -> reset placed grid
   if(g_lastChannelRoof != channel.roofPrice || g_lastChannelFloor != channel.floorPrice)
   {
      g_lastChannelRoof  = channel.roofPrice;
      g_lastChannelFloor = channel.floorPrice;
      ArrayResize(g_placedBuyPrices, 0);
      ArrayResize(g_placedSellPrices, 0);
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tol   = 5 * point;

   double curBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double curAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

   // ---------------------------------------------------------------
   // PAC: Cek Trend Kontrol M3 (Bullish vs Bearish)
   // ---------------------------------------------------------------
   ENUM_STR_TREND m3Trend = ExtStructure.GetTrend(PERIOD_M3);
   bool allowBuy  = InpEnableBuyLimit;
   bool allowSell = InpEnableSellLimit;

   if(InpFilterByControlTrend)
   {
      // Jika M3 Bullish Control -> Hanya boleh BUY di Floor/Demand
      if(m3Trend == STR_TREND_BULL)
      {
         allowSell = false;
      }
      // Jika M3 Bearish Control -> Hanya boleh SELL di Roof/Supply
      else if(m3Trend == STR_TREND_BEAR)
      {
         allowBuy = false;
      }
   }

   double range = channel.roofPrice - channel.floorPrice;

   // ---------------------------------------------------------------
   // Equilibrium Filter: M3 Multi-Structure Range (50%)
   // BUY harus di Discount (< 50%), SELL harus di Premium (> 50%)
   // ---------------------------------------------------------------
   double eqM3 = 0.0, highM3 = 0.0, lowM3 = 0.0;
   bool hasEq = false;
   if(InpEnableEquilibrium)
   {
      hasEq = CalculateM3Equilibrium(symbol, InpM3Lookback, eqM3, highM3, lowM3);
      if(hasEq)
      {
         // Buy Area Boundary (25% channel) harus di bawah Equilibrium M3 (Discount Zone)
         if(channel.levelBuyBoundary > eqM3)
         {
            allowBuy = false;
         }
         // Sell Area Boundary (75% channel) harus di atas Equilibrium M3 (Premium Zone)
         if(channel.levelSellBoundary < eqM3)
         {
            allowSell = false;
         }
      }
   }

   // ---------------------------------------------------------------
   // A. BUY LIMIT GRID IN BUY AREA (0% - 25%)
   // ---------------------------------------------------------------
   // Syarat: Buy diizinkan dan Buy Area belum 100% used
   if(allowBuy && channel.buyAreaUsedPct < 100.0)
   {
      double buyAreaTop = channel.levelBuyBoundary; // 25%
      double buyAreaBot = channel.floorPrice;       // 0%
      double step = (InpMaxEntry > 1) ? (buyAreaTop - buyAreaBot) / (InpMaxEntry - 1) : 0.0;

      // Hard SL Calculation (30% dari total area / range di luar Floor)
      double slPriceRaw = channel.floorPrice - (range * (InpHardSLPercent / 100.0));
      double slPrice = NormalizeDouble(slPriceRaw, digits);
      double tpPrice = NormalizeDouble(channel.levelTPBuy, digits); // 45% (Buy TP)

      for(int i = 0; i < InpMaxEntry; i++)
      {
         double gridPrice = NormalizeDouble(buyAreaTop - (i * step), digits);

         // Aturan 1: Hanya pasang jika belum pernah dipasang di titik ini
         if(IsPriceAlreadyOrdered(gridPrice, g_placedBuyPrices, tol))
            continue;

         // Aturan 2: Price saat ini harus masih berada DI ATAS gridPrice (Buy Limit valid)
         if(curAsk <= gridPrice)
            continue; // Sudah tersentuh / harga sudah di bawahnya, jangan pasang lagi!

         string comment = StringFormat("B%d_BL%d", channel.batchId, i);
         if(ExtTrade.BuyLimit(InpStaticLot, gridPrice, symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, comment))
         {
            PrintFormat("[PAC Grid] Placed Buy Limit #%d at %.5f (SL: %.5f, TP: %.5f, Trend: %d, Batch: %s)", 
                        i, gridPrice, slPrice, tpPrice, m3Trend, channel.batchCode);
            AddPlacedPrice(gridPrice, g_placedBuyPrices);
         }
      }
   }

   // ---------------------------------------------------------------
   // B. SELL LIMIT GRID IN SELL AREA (75% - 100%)
   // ---------------------------------------------------------------
   // Syarat: Sell diizinkan dan Sell Area belum 100% used
   if(allowSell && channel.sellAreaUsedPct < 100.0)
   {
      double sellAreaBot = channel.levelSellBoundary; // 75%
      double sellAreaTop = channel.roofPrice;         // 100%
      double step = (InpMaxEntry > 1) ? (sellAreaTop - sellAreaBot) / (InpMaxEntry - 1) : 0.0;

      // Hard SL Calculation (30% dari total area / range di luar Roof)
      double slPriceRaw = channel.roofPrice + (range * (InpHardSLPercent / 100.0));
      double slPrice = NormalizeDouble(slPriceRaw, digits);
      double tpPrice = NormalizeDouble(channel.levelTPSell, digits); // 55% (Sell TP)

      for(int i = 0; i < InpMaxEntry; i++)
      {
         double gridPrice = NormalizeDouble(sellAreaBot + (i * step), digits);

         // Aturan 1: Hanya pasang jika belum pernah dipasang di titik ini
         if(IsPriceAlreadyOrdered(gridPrice, g_placedSellPrices, tol))
            continue;

         // Aturan 2: Price saat ini harus masih berada DI BAWAH gridPrice (Sell Limit valid)
         if(curBid >= gridPrice)
            continue; // Sudah tersentuh / harga sudah di atasnya, jangan pasang lagi!

         string comment = StringFormat("B%d_SL%d", channel.batchId, i);
         if(ExtTrade.SellLimit(InpStaticLot, gridPrice, symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, comment))
         {
            PrintFormat("[PAC Grid] Placed Sell Limit #%d at %.5f (SL: %.5f, TP: %.5f, Trend: %d, Batch: %s)", 
                        i, gridPrice, slPrice, tpPrice, m3Trend, channel.batchCode);
            AddPlacedPrice(gridPrice, g_placedSellPrices);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Smart TP: Early Exit if area was deeply consumed (>= 75%)        |
//| Extra Logic: Old Batches are closed as soon as net profit >=     |
//|              2x spread per position AND new batch has active pos |
//+------------------------------------------------------------------+
void ManageSmartTP(const string symbol, const SRoofFloorChannel &currentChannel, const double bid, const double ask)
{
   // ---------------------------------------------------------------
   // 1. EVALUASI BATCH LAMA:
   //    Syarat A: Batch baru (currentChannel.batchId) SUDAH masuk posisi (bukan hanya pending order)
   //    Syarat B: Total profit batch lama >= 2x spread per posisi (default 35 points)
   // ---------------------------------------------------------------
   int currentBatchActivePos = 0;
   if(currentChannel.batchId > 0)
   {
      string currentBatchPrefix = StringFormat("B%d_", currentChannel.batchId);
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         string posComment = PositionGetString(POSITION_COMMENT);
         if(StringFind(posComment, currentBatchPrefix) == 0)
         {
            currentBatchActivePos++;
         }
      }
   }

   // Hanya evaluasi penutupan batch lama JIKA batch baru SUDAH ada posisi aktif terbuka
   if(currentBatchActivePos > 0)
   {
      // Identifikasi semua batch lama yang masih memiliki posisi terbuka
      int oldBatchIds[];
      ArrayResize(oldBatchIds, 0);

      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         string posComment = PositionGetString(POSITION_COMMENT);
         int posBatchId = 0;
         if(StringFind(posComment, "B") == 0)
         {
            int underscoreIdx = StringFind(posComment, "_");
            if(underscoreIdx > 1)
            {
               string idStr = StringSubstr(posComment, 1, underscoreIdx - 1);
               posBatchId = (int)StringToInteger(idStr);
            }
         }

         // Kategori Batch Lama: ID batch lebih kecil dari currentChannel.batchId
         if(posBatchId > 0 && currentChannel.batchId > 0 && posBatchId < currentChannel.batchId)
         {
            bool exists = false;
            for(int b = 0; b < ArraySize(oldBatchIds); b++)
            {
               if(oldBatchIds[b] == posBatchId) { exists = true; break; }
            }
            if(!exists)
            {
               int sz = ArraySize(oldBatchIds);
               ArrayResize(oldBatchIds, sz + 1);
               oldBatchIds[sz] = posBatchId;
            }
         }
      }

      // Hitung total profit per batch lama dan close jika profit neto >= 2x spread
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double pointValue = (tickSize > 0) ? (tickValue * (point / tickSize)) : 0.0;

      for(int b = 0; b < ArraySize(oldBatchIds); b++)
      {
         int bId = oldBatchIds[b];
         double batchNetProfit = 0.0;
         int batchPosCount = 0;
         double totalBatchVolume = 0.0;

         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

            string posComment = PositionGetString(POSITION_COMMENT);
            string bPrefix = StringFormat("B%d_", bId);
            if(StringFind(posComment, bPrefix) == 0)
            {
               batchNetProfit += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
               totalBatchVolume += PositionGetDouble(POSITION_VOLUME);
               batchPosCount++;
            }
         }

         // Target minimal profit: 2x Spread Points per lot volume (default: 2 * 35 points = 70 points)
         double requiredSpreadProfit = 0.0;
         if(pointValue > 0.0)
         {
            requiredSpreadProfit = (2.0 * InpDefaultSpreadPoints) * pointValue * (totalBatchVolume / (SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP) > 0 ? 1.0 : 1.0));
         }

         if(batchPosCount > 0 && batchNetProfit > requiredSpreadProfit)
         {
            PrintFormat("[SmartTP OldBatch] Batch B%d has %d positions (Vol: %.2f) with net profit %.2f (Req: > %.2f [2x spread=%d pts]). New batch B%d has %d active positions. Closing batch!",
                        bId, batchPosCount, totalBatchVolume, batchNetProfit, requiredSpreadProfit, InpDefaultSpreadPoints, currentChannel.batchId, currentBatchActivePos);

            // Tutup semua posisi terbuka milik batch ini
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket <= 0) continue;
               if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
               if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

               string posComment = PositionGetString(POSITION_COMMENT);
               string bPrefix = StringFormat("B%d_", bId);
               if(StringFind(posComment, bPrefix) == 0)
               {
                  ExtTrade.PositionClose(ticket);
               }
            }

            // Batalkan semua pending orders milik batch ini
            CancelPendingOrdersByBatch(bId, "Old Batch Profit >= 2x Spread & New Batch Active (Smart TP Closed)");
         }
      }
   }

   // ---------------------------------------------------------------
   // 2. SMART TP STANDAR (UNTUK CURRENT BATCH / AREA PENETRATION)
   // ---------------------------------------------------------------
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      string posComment = PositionGetString(POSITION_COMMENT);

      // Extract batchId from comment (e.g. "B1_BL0" -> batchId = 1)
      int posBatchId = 0;
      if(StringFind(posComment, "B") == 0)
      {
         int underscoreIdx = StringFind(posComment, "_");
         if(underscoreIdx > 1)
         {
            string idStr = StringSubstr(posComment, 1, underscoreIdx - 1);
            posBatchId = (int)StringToInteger(idStr);
         }
      }

      // Get the exact channel object that opened this position
      SRoofFloorChannel targetChannel;
      bool found = false;

      if(posBatchId > 0)
      {
         found = ExtRBRDBD.GetChannelByBatchId(PERIOD_M3, posBatchId, targetChannel);
      }

      // Fallback to current channel if not found in history
      if(!found)
      {
         targetChannel = currentChannel;
      }

      // --- Smart TP for BUY ---
      // Jika Buy Area pernah kemakan >= 75%, dan harga sudah naik menyentuh level Smart TP Buy (Level 24%)
      if(posType == POSITION_TYPE_BUY && targetChannel.buyAreaUsedPct >= InpSmartTPThreshold)
      {
         if(bid >= targetChannel.levelSmartTPBuy)
         {
            PrintFormat("[SmartTP] BUY #%I64u (%s) closed at %.5f (Batch %d was %.1f%% used, reached 24%% Smart TP Level %.5f)",
                        ticket, posComment, bid, targetChannel.batchId, targetChannel.buyAreaUsedPct, targetChannel.levelSmartTPBuy);
            if(ExtTrade.PositionClose(ticket))
            {
               // Hapus sisa limit order jika batch sudah TP dan area >= 75% used
               CancelPendingOrdersByBatch(targetChannel.batchId, StringFormat("Smart TP Triggered & Area >= %.1f%% Used", InpSmartTPThreshold));
            }
         }
      }
      // --- Smart TP for SELL ---
      // Jika Sell Area pernah kemakan >= 75%, dan harga sudah turun menyentuh level Smart TP Sell (Level 76%)
      else if(posType == POSITION_TYPE_SELL && targetChannel.sellAreaUsedPct >= InpSmartTPThreshold)
      {
         if(ask <= targetChannel.levelSmartTPSell)
         {
            PrintFormat("[SmartTP] SELL #%I64u (%s) closed at %.5f (Batch %d was %.1f%% used, reached 76%% Smart TP Level %.5f)",
                        ticket, posComment, ask, targetChannel.batchId, targetChannel.sellAreaUsedPct, targetChannel.levelSmartTPSell);
            if(ExtTrade.PositionClose(ticket))
            {
               // Hapus sisa limit order jika batch sudah TP dan area >= 75% used
               CancelPendingOrdersByBatch(targetChannel.batchId, StringFormat("Smart TP Triggered & Area >= %.1f%% Used", InpSmartTPThreshold));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Anti-Fake Wick: Close positions on Candle Close in 15%-30% Zone  |
//+------------------------------------------------------------------+
void CheckCandleCloseSL(const string symbol, const SRoofFloorChannel &currentChannel)
{
   if(!InpUseCandleCloseSL) return;

   // Check if a new M3 candle just opened (meaning bar 1 just completed its close)
   datetime curM3Time = iTime(symbol, PERIOD_M3, 0);
   if(curM3Time == 0 || curM3Time == g_lastM3BarTime) return;
   g_lastM3BarTime = curM3Time;

   double close1 = iClose(symbol, PERIOD_M3, 1);
   if(close1 <= 0.0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string posComment = PositionGetString(POSITION_COMMENT);

      // Extract batchId from comment
      int posBatchId = 0;
      if(StringFind(posComment, "B") == 0)
      {
         int underscoreIdx = StringFind(posComment, "_");
         if(underscoreIdx > 1)
         {
            string idStr = StringSubstr(posComment, 1, underscoreIdx - 1);
            posBatchId = (int)StringToInteger(idStr);
         }
      }

      SRoofFloorChannel targetChannel;
      bool found = false;
      if(posBatchId > 0)
         found = ExtRBRDBD.GetChannelByBatchId(PERIOD_M3, posBatchId, targetChannel);
      if(!found)
         targetChannel = currentChannel;

      double range = targetChannel.roofPrice - targetChannel.floorPrice;

      // BUY Invalidation: Candle Close 1 berada di zona luar 15% - 30% di bawah Floor
      // Level 15% luar: floorPrice - (0.15 * range)
      // Level 30% luar: floorPrice - (0.30 * range)
      if(posType == POSITION_TYPE_BUY)
      {
         double buyCloseZoneTop = targetChannel.floorPrice - (range * (InpCloseZoneMinPct / 100.0));
         double buyCloseZoneBot = targetChannel.floorPrice - (range * (InpCloseZoneMaxPct / 100.0));

         if(close1 <= buyCloseZoneTop && close1 >= buyCloseZoneBot)
         {
            PrintFormat("[CandleClose SL] BUY #%I64u (%s) closed! M3 Close[1] %.5f is in 15%%-30%% outer zone (%.5f - %.5f) [Batch %d]",
                        ticket, posComment, close1, buyCloseZoneTop, buyCloseZoneBot, targetChannel.batchId);
            ExtTrade.PositionClose(ticket);
            CancelPendingOrdersByBatch(targetChannel.batchId, "M3 Candle Closed in 15%-30% Outer Zone (SL)");
         }
      }
      // SELL Invalidation: Candle Close 1 berada di zona luar 15% - 30% di atas Roof
      // Level 15% luar: roofPrice + (0.15 * range)
      // Level 30% luar: roofPrice + (0.30 * range)
      else if(posType == POSITION_TYPE_SELL)
      {
         double sellCloseZoneBot = targetChannel.roofPrice + (range * (InpCloseZoneMinPct / 100.0));
         double sellCloseZoneTop = targetChannel.roofPrice + (range * (InpCloseZoneMaxPct / 100.0));

         if(close1 >= sellCloseZoneBot && close1 <= sellCloseZoneTop)
         {
            PrintFormat("[CandleClose SL] SELL #%I64u (%s) closed! M3 Close[1] %.5f is in 15%%-30%% outer zone (%.5f - %.5f) [Batch %d]",
                        ticket, posComment, close1, sellCloseZoneBot, sellCloseZoneTop, targetChannel.batchId);
            ExtTrade.PositionClose(ticket);
            CancelPendingOrdersByBatch(targetChannel.batchId, "M3 Candle Closed in 15%-30% Outer Zone (SL)");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate M3 Equilibrium (50% from last 2-3 confirmed structures)|
//+------------------------------------------------------------------+
bool CalculateM3Equilibrium(const string symbol, const int lookback, double &outEq, double &outHigh, double &outLow)
{
   SStructurePoint structures[];
   if(!ExtStructure.GetStructures(PERIOD_M3, structures))
   {
      // Fallback: Gunakan High/Low bar M3 ke belakang jika struktur belum cukup
      int bars = MathMax(lookback * 5, 20);
      int hBar = iHighest(symbol, PERIOD_M3, MODE_HIGH, bars, 1);
      int lBar = iLowest(symbol, PERIOD_M3, MODE_LOW, bars, 1);
      if(hBar >= 0 && lBar >= 0)
      {
         outHigh = iHigh(symbol, PERIOD_M3, hBar);
         outLow  = iLow(symbol, PERIOD_M3, lBar);
         outEq   = outLow + 0.5 * (outHigh - outLow);
         return (outHigh > outLow);
      }
      return false;
   }

   int total = ArraySize(structures);
   if(total <= 0) return false;

   int count = MathMin(lookback, total);
   outHigh = 0.0;
   outLow  = DBL_MAX;

   for(int i = total - 1; i >= total - count; i--)
   {
      double h = structures[i].priceH;
      double l = structures[i].priceL;
      if(h > outHigh) outHigh = h;
      if(l < outLow && l > 0.0) outLow = l;
   }

   if(outHigh <= outLow || outLow == DBL_MAX)
   {
      // Fallback to bar range
      int hBar = iHighest(symbol, PERIOD_M3, MODE_HIGH, 30, 1);
      int lBar = iLowest(symbol, PERIOD_M3, MODE_LOW, 30, 1);
      if(hBar >= 0 && lBar >= 0)
      {
         outHigh = iHigh(symbol, PERIOD_M3, hBar);
         outLow  = iLow(symbol, PERIOD_M3, lBar);
      }
   }

   if(outHigh > outLow)
   {
      outEq = outLow + 0.5 * (outHigh - outLow);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check closed deals: If TP hit & Area >= 75% -> Cancel Pending   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Check closed deals: If positions already hit TP & open positions|
//| are now clean (0 open pos) -> Cancel remaining pending orders    |
//+------------------------------------------------------------------+
void CheckStandardTPClosedOrders()
{
   // Query history of today / recent deals
   datetime fromTime = TimeCurrent() - (PeriodSeconds(PERIOD_D1));
   if(!HistorySelect(fromTime, TimeCurrent())) return;

   // 1. Identifikasi batch yang pernah mencetak Take Profit
   int tpBatchIds[];
   ArrayResize(tpBatchIds, 0);

   int totalDeals = HistoryDealsTotal();
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      // Only check exit deals (DEAL_ENTRY_OUT)
      ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT) continue;

      // Check if deal was closed by Take Profit
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);

      bool isTPHit = (reason == DEAL_REASON_TP) || (StringFind(comment, "tp") >= 0) || (StringFind(comment, "TP") >= 0);
      if(!isTPHit) continue;

      // Extract batchId from deal comment
      int posBatchId = 0;
      if(StringFind(comment, "B") == 0)
      {
         int underscoreIdx = StringFind(comment, "_");
         if(underscoreIdx > 1)
         {
            string idStr = StringSubstr(comment, 1, underscoreIdx - 1);
            posBatchId = (int)StringToInteger(idStr);
         }
      }

      if(posBatchId > 0)
      {
         bool exists = false;
         for(int b = 0; b < ArraySize(tpBatchIds); b++)
         {
            if(tpBatchIds[b] == posBatchId) { exists = true; break; }
         }
         if(!exists)
         {
            int sz = ArraySize(tpBatchIds);
            ArrayResize(tpBatchIds, sz + 1);
            tpBatchIds[sz] = posBatchId;
         }
      }
   }

   // 2. Untuk setiap batch yang sudah pernah TP:
   //    Jika open position sudah bersih (0 posisi terbuka), batalkan semua sisa pending limit ordernya!
   for(int b = 0; b < ArraySize(tpBatchIds); b++)
   {
      int bId = tpBatchIds[b];
      string batchPrefix = StringFormat("B%d_", bId);

      // Hitung jumlah open position yang masih aktif untuk batch ini
      int activePosCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         string posComment = PositionGetString(POSITION_COMMENT);
         if(StringFind(posComment, batchPrefix) == 0)
         {
            activePosCount++;
         }
      }

      // Hitung jumlah pending limit order yang masih aktif untuk batch ini
      int pendingOrderCount = 0;
      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket <= 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;

         string ordComment = OrderGetString(ORDER_COMMENT);
         if(StringFind(ordComment, batchPrefix) == 0)
         {
            pendingOrderCount++;
         }
      }

      // Aturan: Jika sudah ada posisi TP, posisi terbuka sudah 0 (bersih), dan masih ada pending order tersisa -> HAPUS!
      if(activePosCount == 0 && pendingOrderCount > 0)
      {
         PrintFormat("[Cleanup] Batch B%d hit TP and all positions closed (0 active). Cancelling %d remaining pending limit orders!",
                     bId, pendingOrderCount);
         CancelPendingOrdersByBatch(bId, "Batch hit TP and all open positions closed");
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel pending orders belonging to a specific batch              |
//+------------------------------------------------------------------+
void CancelPendingOrdersByBatch(const int batchId, const string reason)
{
   if(batchId <= 0) return;
   string batchPrefix = StringFormat("B%d_", batchId);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(StringFind(comment, batchPrefix) == 0)
      {
         ExtTrade.OrderDelete(ticket);
         PrintFormat("[Orders] Pending Order #%I64u (%s) cancelled. Reason: %s", ticket, comment, reason);
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                            |
//+------------------------------------------------------------------+
void CancelAllPendingOrders(const string symbol, const string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;

      ExtTrade.OrderDelete(ticket);
      PrintFormat("[Orders] Pending Order #%I64u cancelled. Reason: %s", ticket, reason);
   }
}

//+------------------------------------------------------------------+
//| Close all open positions & orders                                |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders(const string symbol, const string reason)
{
   CancelAllPendingOrders(symbol, reason);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ExtTrade.PositionClose(ticket);
      PrintFormat("[Positions] Position #%I64u closed. Reason: %s", ticket, reason);
   }
}

//+------------------------------------------------------------------+
//| Check if price level was already ordered                         |
//+------------------------------------------------------------------+
bool IsPriceAlreadyOrdered(const double price, const double &placedArray[], const double tolerance)
{
   int size = ArraySize(placedArray);
   for(int i = 0; i < size; i++)
   {
      if(MathAbs(placedArray[i] - price) <= tolerance) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add placed price to tracking array                               |
//+------------------------------------------------------------------+
void AddPlacedPrice(const double price, double &placedArray[])
{
   int size = ArraySize(placedArray);
   ArrayResize(placedArray, size + 1);
   placedArray[size] = price;
}
//+------------------------------------------------------------------+

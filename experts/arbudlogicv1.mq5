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
input int               InpMaxEntry          = 5;               // Max Grid Entry Points per Area (>= 2)
input bool              InpEnableBuyLimit    = true;            // Enable Buy Limit Grid in Buy Area (0-25%)
input bool              InpEnableSellLimit   = true;            // Enable Sell Limit Grid in Sell Area (75-100%)

input group "=== Smart TP & Exit Settings ==="
input bool              InpEnableSmartTP     = true;            // Enable Early TP Exit when Area Used >= 75%
input double            InpSmartTPThreshold  = 75.0;            // Threshold % to trigger Smart TP & Cancel Grid (Default 75%)

input group "=== M1 Structure Settings ==="
input bool              InpEnableStructM1    = true;            // Enable M1 Structure Detection
input bool              InpDrawStructM1      = true;            // Draw M1 Structure on Chart
input color             InpColorStructM1     = clrDodgerBlue;   // M1 Structure Line Color
input int               InpWidthStructM1     = 1;               // M1 Structure Line Width

input group "=== M1 RBR / DBD Settings ==="
input bool              InpEnableRbrDbdM1    = true;            // Enable M1 RBR/DBD Detection
input bool              InpDrawRbrDbdM1      = true;            // Draw M1 RBR/DBD Rectangles on Chart
input bool              InpDrawRoofFloorM1   = true;            // Draw M1 Transaction Areas (Floor/Roof)
input int               InpMinBaseM1         = 1;               // M1 Min Base Candles (1~9)
input int               InpMaxBaseM1         = 5;               // M1 Max Base Candles (1~9)
input double            InpLegRatioM1        = 1.0;             // M1 Min Leg-Out vs Base Ratio

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

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void ManageGridOrders(const string symbol, const SRoofFloorChannel &channel);
void ManageSmartTP(const string symbol, const SRoofFloorChannel &channel, const double bid, const double ask);
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
   Print("=== [arbudlogicv1] Initializing EA with Grid & Smart TP (Main TF: M1) ===");

   if(InpMaxEntry < 2)
   {
      Alert("[arbudlogicv1] InpMaxEntry must be at least 2!");
      return INIT_PARAMETERS_INCORRECT;
   }

   // 1. Initialize CTrade
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippagePoints);
   ExtTrade.SetTypeFillingBySymbol(_Symbol);

   // 2. Structure Registration (M1 - Active & Drawn, M3/M15/H1 background for fallback)
   ExtStructure.RegisterTimeframe(PERIOD_M1,  InpColorStructM1, InpWidthStructM1, InpDrawStructM1);
   ExtStructure.RegisterTimeframe(PERIOD_M3,  clrDodgerBlue,    1, false);
   ExtStructure.RegisterTimeframe(PERIOD_M15, clrGold,          1, false);
   ExtStructure.RegisterTimeframe(PERIOD_H1,  clrOrange,        1, false);

   // 3. RBR / DBD Registration (M1 - Active & Drawn, M3/M15/H1 background for fallback)
   ExtRBRDBD.RegisterTimeframe(PERIOD_M1,  InpMinBaseM1, InpMaxBaseM1, InpLegRatioM1, 
                               InpDrawRbrDbdM1, InpDrawRoofFloorM1, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_M3,  1, 5, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_M15, 1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);
   ExtRBRDBD.RegisterTimeframe(PERIOD_H1,  1, 7, 1.0, false, false, InpColorRBR, InpColorDBD, InpColorRoof, InpColorFloor);

   // 4. Scan History on Init
   ExtStructure.InitHistory(_Symbol, InpHistoryBars);
   ExtRBRDBD.InitHistory(_Symbol, InpHistoryBars, &ExtStructure);

   ArrayResize(g_placedBuyPrices, 0);
   ArrayResize(g_placedSellPrices, 0);

   PrintFormat("[arbudlogicv1] Init Succeeded on %s (Main TF: M1). Grid Size: %d", _Symbol, InpMaxEntry);
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

   // 3. Fetch current M1 Transaction Area Channel
   SRoofFloorChannel channel;
   bool hasChannel = ExtRBRDBD.GetRoofFloorChannel(PERIOD_M1, channel);

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

   // 5. Smart TP Check (Early exit if area was consumed >= 75%)
   if(InpEnableSmartTP)
   {
      ManageSmartTP(_Symbol, channel, bid, ask);
   }

   // 6. Check Standard TP Deal Closures: if batch already hit TP & area >= 75% used -> cancel remaining pending orders
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
      CancelAllPendingOrders(symbol, "Channel Realigned / Shifted");
      ArrayResize(g_placedBuyPrices, 0);
      ArrayResize(g_placedSellPrices, 0);
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tol   = 5 * point;

   double curBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double curAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

   // ---------------------------------------------------------------
   // A. BUY LIMIT GRID IN BUY AREA (0% - 25%)
   // ---------------------------------------------------------------
   // Syarat: Buy Area belum 100% used
   if(InpEnableBuyLimit && channel.buyAreaUsedPct < 100.0)
   {
      double buyAreaTop = channel.levelBuyBoundary; // 25%
      double buyAreaBot = channel.floorPrice;       // 0%
      double step = (buyAreaTop - buyAreaBot) / (InpMaxEntry - 1);

      double slPrice = NormalizeDouble(channel.levelStopBottom, digits); // -30%
      double tpPrice = NormalizeDouble(channel.levelTPBuy, digits);      // 45% (Buy TP)

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
            PrintFormat("[Grid] Placed Buy Limit #%d at %.5f (SL: %.5f, TP: %.5f, Batch: %s)", 
                        i, gridPrice, slPrice, tpPrice, channel.batchCode);
            AddPlacedPrice(gridPrice, g_placedBuyPrices);
         }
      }
   }

   // ---------------------------------------------------------------
   // B. SELL LIMIT GRID IN SELL AREA (75% - 100%)
   // ---------------------------------------------------------------
   // Syarat: Sell Area belum 100% used
   if(InpEnableSellLimit && channel.sellAreaUsedPct < 100.0)
   {
      double sellAreaBot = channel.levelSellBoundary; // 75%
      double sellAreaTop = channel.roofPrice;         // 100%
      double step = (sellAreaTop - sellAreaBot) / (InpMaxEntry - 1);

      double slPrice = NormalizeDouble(channel.levelStopTop, digits);    // 130%
      double tpPrice = NormalizeDouble(channel.levelTPSell, digits);     // 55% (Sell TP)

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
            PrintFormat("[Grid] Placed Sell Limit #%d at %.5f (SL: %.5f, TP: %.5f, Batch: %s)", 
                        i, gridPrice, slPrice, tpPrice, channel.batchCode);
            AddPlacedPrice(gridPrice, g_placedSellPrices);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Smart TP: Early Exit if area was deeply consumed (>= 75%)        |
//| Extra Logic: Old Batches are closed as soon as net profit > 0.0  |
//+------------------------------------------------------------------+
void ManageSmartTP(const string symbol, const SRoofFloorChannel &currentChannel, const double bid, const double ask)
{
   // ---------------------------------------------------------------
   // 1. EVALUASI BATCH LAMA: JIKA TOTAL PROFIT BATCH > 0 -> CLOSE ALL
   // ---------------------------------------------------------------
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

   // Hitung total profit per batch lama dan close jika profit neto > 0
   for(int b = 0; b < ArraySize(oldBatchIds); b++)
   {
      int bId = oldBatchIds[b];
      double batchNetProfit = 0.0;
      int batchPosCount = 0;

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
            batchPosCount++;
         }
      }

      if(batchPosCount > 0 && batchNetProfit > 0.0)
      {
         PrintFormat("[SmartTP OldBatch] Batch B%d has %d positions with total net profit %.2f (> 0). Closing batch!",
                     bId, batchPosCount, batchNetProfit);

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
         CancelPendingOrdersByBatch(bId, "Old Batch Net Profit > 0 (Smart TP Closed)");
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
         found = ExtRBRDBD.GetChannelByBatchId(PERIOD_M1, posBatchId, targetChannel);
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
//| Check closed deals: If TP hit & Area >= 75% -> Cancel Pending   |
//+------------------------------------------------------------------+
void CheckStandardTPClosedOrders()
{
   // Query history of today / recent deals
   datetime fromTime = TimeCurrent() - (PeriodSeconds(PERIOD_D1));
   if(!HistorySelect(fromTime, TimeCurrent())) return;

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

      // Extract batchId from deal comment or position comment
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

      if(posBatchId <= 0) continue;

      // Get channel object for this batch
      SRoofFloorChannel batchChannel;
      if(ExtRBRDBD.GetChannelByBatchId(PERIOD_M1, posBatchId, batchChannel))
      {
         ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         // Deal BUY means it closed a SELL position, Deal SELL means it closed a BUY position
         bool isBuyPos  = (dealType == DEAL_TYPE_SELL);
         bool isSellPos = (dealType == DEAL_TYPE_BUY);

         if((isBuyPos && batchChannel.buyAreaUsedPct >= InpSmartTPThreshold) ||
            (isSellPos && batchChannel.sellAreaUsedPct >= InpSmartTPThreshold))
         {
            CancelPendingOrdersByBatch(posBatchId, StringFormat("Standard TP Hit & Area >= %.1f%% Used", InpSmartTPThreshold));
         }
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

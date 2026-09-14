//+------------------------------------------------------------------+
//|                                              TradeDataLogger.mqh |
//|                                  Copyright 2025, TradingRepo     |
//|                    High-Fidelity Strategy Tester TSV Data Logger |
//+------------------------------------------------------------------+
#property copyright "TradingRepo"
#property link      ""
#property strict

#include <Trade\Trade.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
//| Struct to store parsed DNA & Deal Analytics                      |
//+------------------------------------------------------------------+
struct STradeLogRecord
{
   ulong                dealTicket;
   ulong                posId;
   string               symbol;
   string               tradeType;     // BUY / SELL
   string               zoneType;      // RBR / DBD
   string               zoneTF;        // M1 / M5 / M15 / etc.
   string               dna;           // TBFH / TB-H / ----
   int                  pillarT;       // 1 or 0
   int                  pillarB;       // 1 or 0
   int                  pillarF;       // 1 or 0
   int                  pillarH;       // 1 or 0
   int                  strength;      // 0, 1, 2
   int                  exhLevel;      // 0 to 5
   datetime             openTime;
   datetime             closeTime;
   double               openPrice;
   double               closePrice;
   double               profitUSD;
   double               profitPoints;
   string               exitReason;    // FULL_TP, BREAK_EVEN, CUT_PROFIT, HARD_SL, FORCE_EXIT
   string               rawComment;
};

//+------------------------------------------------------------------+
//| Class CTradeDataLogger                                           |
//+------------------------------------------------------------------+
class CTradeDataLogger
{
private:
   int                  m_fileHandle;
   string               m_fileName;
   string               m_symbol;
   ulong                m_magicNumber;
   int                  m_totalTradesLogged;
   bool                 m_isActive;
   bool                 m_verbose;
   CDealInfo            m_dealInfo;
   CHistoryOrderInfo    m_orderInfo;

public:
   CTradeDataLogger() : m_fileHandle(INVALID_HANDLE),
                        m_fileName(""),
                        m_symbol(""),
                        m_magicNumber(0),
                        m_totalTradesLogged(0),
                        m_isActive(false),
                        m_verbose(true)
   {
   }

   ~CTradeDataLogger()
   {
      CloseFile();
   }

   //+------------------------------------------------------------------+
   //| Initialize Logger & Create Unique TSV File in Common Folder      |
   //+------------------------------------------------------------------+
   bool Init(const string symbol, const ulong magicNumber, const ENUM_TIMEFRAMES tf, const bool verbose = true)
   {
      m_symbol            = symbol;
      m_magicNumber       = magicNumber;
      m_verbose           = verbose;
      m_totalTradesLogged = 0;

      // Generate unique file name per run using timestamp and tick count
      // Format: rbr_dbd_analytics_<SYMBOL>_<TF>_<YYYYMMDD_HHMMSS>_<TICK>.tsv
      MqlDateTime dt;
      TimeToStruct(TimeLocal(), dt);
      uint tickMs = GetTickCount();
      m_fileName = StringFormat("rbr_dbd_analytics_%s_%s_%04d%02d%02d_%02d%02d%02d_%u.tsv",
                                m_symbol,
                                EnumToString(tf),
                                dt.year, dt.mon, dt.day,
                                dt.hour, dt.min, dt.sec,
                                tickMs);

      // Open in FILE_COMMON folder so external analysis tools (Node.js/Bun) can access directly
      m_fileHandle = FileOpen(m_fileName, FILE_CSV | FILE_WRITE | FILE_READ | FILE_COMMON, '\t');
      if(m_fileHandle == INVALID_HANDLE)
      {
         PrintFormat("[TradeDataLogger] ERROR: Failed to open file '%s' in Common folder. Error code: %d",
                     m_fileName, GetLastError());
         m_isActive = false;
         return false;
      }

      // Write standard TSV header
      WriteHeader();

      m_isActive = true;
      PrintFormat("[TradeDataLogger] Initialized successfully. Output: Common/Files/%s", m_fileName);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Write TSV Header Columns                                         |
   //+------------------------------------------------------------------+
   void WriteHeader()
   {
      if(m_fileHandle == INVALID_HANDLE) return;

      FileSeek(m_fileHandle, 0, SEEK_SET);
      string header = "DealTicket\tPosID\tSymbol\tTradeType\tZoneType\tZoneTF\tDNA\t" +
                      "Pillar_T\tPillar_B\tPillar_F\tPillar_H\tStrength\tExhLevel\t" +
                      "OpenTime\tCloseTime\tOpenPrice\tClosePrice\tProfitUSD\tProfitPoints\tExitReason\tComment";
      FileWriteString(m_fileHandle, header + "\n");
      FileFlush(m_fileHandle);
   }

   //+------------------------------------------------------------------+
   //| Handler for OnTradeTransaction Event                             |
   //+------------------------------------------------------------------+
   void OnTransaction(const MqlTradeTransaction &trans,
                      const MqlTradeRequest &request,
                      const MqlTradeResult &result)
   {
      if(!m_isActive || m_fileHandle == INVALID_HANDLE) return;

      // We are strictly interested in executed closing deals (DEAL_ENTRY_OUT or DEAL_ENTRY_INOUT)
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

      ulong dealTicket = trans.deal;
      if(dealTicket <= 0) return;

      if(!HistoryDealSelect(dealTicket)) return;
      m_dealInfo.Ticket(dealTicket);

      // Filter by Magic Number & Symbol
      if(m_dealInfo.Magic() != m_magicNumber || m_dealInfo.Symbol() != m_symbol)
         return;

      ENUM_DEAL_ENTRY dealEntry = m_dealInfo.Entry();
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT)
         return;

      // Extract and log complete trade metrics
      ProcessClosingDeal(dealTicket);
   }

   //+------------------------------------------------------------------+
   //| Process Closing Deal & Append to TSV                             |
   //+------------------------------------------------------------------+
   void ProcessClosingDeal(const ulong dealTicket)
   {
      STradeLogRecord rec;
      rec.dealTicket = dealTicket;
      rec.posId      = m_dealInfo.PositionId();
      rec.symbol     = m_symbol;
      rec.tradeType  = (m_dealInfo.DealType() == DEAL_TYPE_BUY) ? "BUY" : "SELL"; // Note: Closing BUY deal means original pos was SELL
      if(m_dealInfo.DealType() == DEAL_TYPE_SELL) rec.tradeType = "BUY";           // Closing SELL deal means original pos was BUY
      else if(m_dealInfo.DealType() == DEAL_TYPE_BUY) rec.tradeType = "SELL";

      rec.closeTime   = m_dealInfo.Time();
      rec.closePrice  = m_dealInfo.Price();
      rec.profitUSD   = m_dealInfo.Profit() + m_dealInfo.Commission() + m_dealInfo.Swap();

      // Retrieve opening deal / order to extract original DNA comment & open price/time
      string originalComment = "";
      double originalOpenPrice = 0.0;
      datetime originalOpenTime = 0;

      FindOriginPositionDetails(rec.posId, originalComment, originalOpenPrice, originalOpenTime);

      rec.rawComment = originalComment;
      rec.openPrice  = (originalOpenPrice > 0.0) ? originalOpenPrice : m_dealInfo.Price();
      rec.openTime   = (originalOpenTime > 0) ? originalOpenTime : rec.closeTime;

      // Calculate profit in points
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point > 0.0)
      {
         if(rec.tradeType == "BUY")
            rec.profitPoints = (rec.closePrice - rec.openPrice) / point;
         else
            rec.profitPoints = (rec.openPrice - rec.closePrice) / point;
      }
      else
      {
         rec.profitPoints = 0.0;
      }

      // Parse DNA Comment: Format [RBR/DBD]:[TF]:[DNA]:[Str]:[Lvl]
      ParseDNAComment(originalComment, rec);

      // Determine Exit Reason with High Determinism
      rec.exitReason = DetermineExitReason(dealTicket, rec.profitPoints, rec.profitUSD);

      // Write Record to TSV File
      AppendRecordToFile(rec);

      m_totalTradesLogged++;
      if(m_verbose)
      {
         PrintFormat("[TradeDataLogger] Logged Trade #%d: Ticket %I64u | Type: %s | DNA: %s (S%d) | Points: %.1f | Profit: $%.2f | Reason: %s",
                     m_totalTradesLogged, rec.dealTicket, rec.tradeType, rec.dna, rec.strength, rec.profitPoints, rec.profitUSD, rec.exitReason);
      }
   }

   //+------------------------------------------------------------------+
   //| Parse DNA Comment: [ZoneType]:[TF]:[DNA]:[Str]:[Lvl]             |
   //| Example: RBR:M1:TBFH:S2:L0 or DBD:M15:TB--:S1:L1                 |
   //+------------------------------------------------------------------+
   void ParseDNAComment(const string comment, STradeLogRecord &rec)
   {
      // Default fallback values
      rec.zoneType = (rec.tradeType == "BUY") ? "RBR" : "DBD";
      rec.zoneTF   = "M1";
      rec.dna      = "----";
      rec.pillarT  = 0;
      rec.pillarB  = 0;
      rec.pillarF  = 0;
      rec.pillarH  = 0;
      rec.strength = 0;
      rec.exhLevel = 0;

      if(StringLen(comment) == 0) return;

      string parts[];
      int count = StringSplit(comment, ':', parts);
      if(count >= 5)
      {
         rec.zoneType = parts[0];
         rec.zoneTF   = parts[1];
         rec.dna      = parts[2];

         // Parse 4 Pillars from DNA string
         if(StringLen(rec.dna) >= 4)
         {
            rec.pillarT = (StringSubstr(rec.dna, 0, 1) == "T") ? 1 : 0;
            rec.pillarB = (StringSubstr(rec.dna, 1, 1) == "B") ? 1 : 0;
            rec.pillarF = (StringSubstr(rec.dna, 2, 1) == "F") ? 1 : 0;
            rec.pillarH = (StringSubstr(rec.dna, 3, 1) == "H") ? 1 : 0;
         }

         // Parse Strength: "S0", "S1", "S2"
         if(StringLen(parts[3]) >= 2 && StringSubstr(parts[3], 0, 1) == "S")
            rec.strength = (int)StringToInteger(StringSubstr(parts[3], 1));

         // Parse Exhaustion Level: "L0" to "L5"
         if(StringLen(parts[4]) >= 2 && StringSubstr(parts[4], 0, 1) == "L")
            rec.exhLevel = (int)StringToInteger(StringSubstr(parts[4], 1));
      }
      else
      {
         // Fallback if comment was truncated or structured differently
         int sPos = StringFind(comment, ":S");
         if(sPos >= 0 && (sPos + 2) < StringLen(comment))
            rec.strength = (int)StringToInteger(StringSubstr(comment, sPos + 2, 1));
      }
   }

   //+------------------------------------------------------------------+
   //| Determine Precise Exit Reason                                    |
   //+------------------------------------------------------------------+
   string DetermineExitReason(const ulong dealTicket, const double profitPoints, const double profitUSD)
   {
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

      if(reason == DEAL_REASON_TP)
      {
         return "FULL_TP";
      }
      else if(reason == DEAL_REASON_SL)
      {
         // In MT5, if Breakeven SL was hit with positive points (e.g. 10 to 35 pts)
         if(profitPoints >= 0.0 && profitPoints <= 40.0)
            return "BREAK_EVEN";
         else if(profitPoints > 40.0)
            return "CUT_PROFIT"; // Defensive SL lock in profit
         else
            return "HARD_SL";
      }
      else if(reason == DEAL_REASON_EXPERT || reason == DEAL_REASON_CLIENT)
      {
         if(profitPoints > 0.0)
            return "CUT_PROFIT";
         else if(profitPoints >= -10.0 && profitPoints <= 10.0)
            return "BREAK_EVEN";
         else
            return "FORCE_EXIT";
      }

      // General fallback based on points
      if(profitPoints > 100.0) return "FULL_TP";
      if(profitPoints >= 0.0 && profitPoints <= 40.0) return "BREAK_EVEN";
      if(profitPoints > 40.0) return "CUT_PROFIT";
      return "HARD_SL";
   }

   //+------------------------------------------------------------------+
   //| Retrieve Position Origin Details from History Deals / Orders     |
   //+------------------------------------------------------------------+
   void FindOriginPositionDetails(const ulong posId, string &outComment, double &outOpenPrice, datetime &outOpenTime)
   {
      outComment   = "";
      outOpenPrice = 0.0;
      outOpenTime  = 0;

      // Select full history from beginning of test
      if(!HistorySelect(0, TimeCurrent())) return;

      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_POSITION_ID) == (long)posId)
         {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN)
            {
               outComment   = HistoryDealGetString(ticket, DEAL_COMMENT);
               outOpenPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
               outOpenTime  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
               break;
            }
         }
      }

      // If deal comment was empty or overridden, search original history order
      if(StringLen(outComment) == 0)
      {
         int totalOrders = HistoryOrdersTotal();
         for(int j = 0; j < totalOrders; j++)
         {
            ulong oTicket = HistoryOrderGetTicket(j);
            if(oTicket > 0 && HistoryOrderGetInteger(oTicket, ORDER_POSITION_ID) == (long)posId)
            {
               string oComment = HistoryOrderGetString(oTicket, ORDER_COMMENT);
               if(StringLen(oComment) > 0)
               {
                  outComment = oComment;
                  break;
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Append 1 Record to File with FileFlush (Safe Live Write)         |
   //+------------------------------------------------------------------+
   void AppendRecordToFile(const STradeLogRecord &rec)
   {
      if(m_fileHandle == INVALID_HANDLE) return;

      FileSeek(m_fileHandle, 0, SEEK_END);
      string row = StringFormat("%I64u\t%I64u\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.1f\t%s\t%s",
                                rec.dealTicket,
                                rec.posId,
                                rec.symbol,
                                rec.tradeType,
                                rec.zoneType,
                                rec.zoneTF,
                                rec.dna,
                                rec.pillarT,
                                rec.pillarB,
                                rec.pillarF,
                                rec.pillarH,
                                rec.strength,
                                rec.exhLevel,
                                TimeToString(rec.openTime, TIME_DATE | TIME_SECONDS),
                                TimeToString(rec.closeTime, TIME_DATE | TIME_SECONDS),
                                rec.openPrice,
                                rec.closePrice,
                                rec.profitUSD,
                                rec.profitPoints,
                                rec.exitReason,
                                rec.rawComment);

      FileWriteString(m_fileHandle, row + "\n");
      FileFlush(m_fileHandle); // Immediate flush to prevent data loss if test is aborted
   }

   //+------------------------------------------------------------------+
   //| Close File Handle & Log Summary                                  |
   //+------------------------------------------------------------------+
   void CloseFile()
   {
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
         PrintFormat("=== [TradeDataLogger] Closed file '%s'. Total trades logged: %d ===",
                     m_fileName, m_totalTradesLogged);
      }
      m_isActive = false;
   }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   int    GetTotalTradesLogged() const { return m_totalTradesLogged; }
   string GetFileName()          const { return m_fileName; }
};

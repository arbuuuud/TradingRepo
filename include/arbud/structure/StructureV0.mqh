//+------------------------------------------------------------------+
//|                                                StructureV0.mqh   |
//|                                           Copyright 2025, Arbud. |
//|                                             https://www.mql5.com |
//|                     Independent Market Structure Detection Engine|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Arbud."
#property link      "https://www.mql5.com"
#property strict

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_STR_TREND
{
   STR_TREND_NONE = 0,
   STR_TREND_BULL = 1,
   STR_TREND_BEAR = -1
};

//+------------------------------------------------------------------+
//| Structs                                                          |
//+------------------------------------------------------------------+
struct SStructurePoint
{
   string            label;        // "HH", "HL", "LH", "LL", "H", "L"
   datetime          candleTime;   // Anchor time (bar time)
   double            priceH;       // High price
   double            priceL;       // Low price
   bool              isLiquidated; // True if swept
   bool              isMain;       // True if confirmed main structure

   void Init()
   {
      label        = "";
      candleTime   = 0;
      priceH       = 0.0;
      priceL       = 0.0;
      isLiquidated = false;
      isMain       = false;
   }
};

struct STimeframeStructureData
{
   ENUM_TIMEFRAMES   tf;
   color             lineColor;
   int               lineWidth;
   bool              drawEnabled;
   ENUM_STR_TREND    trend;
   datetime          lastBarTime;

   SStructurePoint   structures[];
   SStructurePoint   pivotStructure;

   void Init(ENUM_TIMEFRAMES period, color clr = clrDodgerBlue, int width = 1, bool draw = true)
   {
      tf          = period;
      lineColor   = clr;
      lineWidth   = width;
      drawEnabled = draw;
      trend       = STR_TREND_NONE;
      lastBarTime = 0;

      ArrayResize(structures, 0);
      pivotStructure.Init();
   }
};

//+------------------------------------------------------------------+
//| Class CStructureV0                                               |
//+------------------------------------------------------------------+
class CStructureV0
{
private:
   STimeframeStructureData m_tfList[];
   int                     m_totalTFs;
   string                  m_objPrefix;

public:
   CStructureV0() : m_totalTFs(0), m_objPrefix("STR0_")
   {
      ArrayResize(m_tfList, 0);
   }

   ~CStructureV0()
   {
      ClearChartObjects();
      ArrayFree(m_tfList);
   }

   //+------------------------------------------------------------------+
   //| Register a specific timeframe to be tracked                      |
   //+------------------------------------------------------------------+
   bool RegisterTimeframe(const ENUM_TIMEFRAMES tf, 
                          const color lineColor = clrDodgerBlue, 
                          const int lineWidth = 1, 
                          const bool drawOnChart = true)
   {
      // Check if already registered
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf)
         {
            m_tfList[i].lineColor   = lineColor;
            m_tfList[i].lineWidth   = lineWidth;
            m_tfList[i].drawEnabled = drawOnChart;
            return true;
         }
      }

      m_totalTFs++;
      if(ArrayResize(m_tfList, m_totalTFs) < m_totalTFs)
      {
         PrintFormat("[StructureV0] Failed to resize TF array for %s", EnumToString(tf));
         return false;
      }

      m_tfList[m_totalTFs - 1].Init(tf, lineColor, lineWidth, drawOnChart);
      PrintFormat("[StructureV0] Registered TF: %s (Color: %s, Width: %d, Draw: %s)",
                  EnumToString(tf), ColorToString(lineColor), lineWidth, drawOnChart ? "true" : "false");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Scan historical bars on registered timeframes and draw to chart  |
   //+------------------------------------------------------------------+
   void InitHistory(const string symbol, const int maxBars = 500)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         InitTFHistory(symbol, m_tfList[i], maxBars);
      }
   }

   //+------------------------------------------------------------------+
   //| Event-driven update: called on tick, checks candle close per TF  |
   //+------------------------------------------------------------------+
   void UpdateOnCandleClose(const string symbol)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         ENUM_TIMEFRAMES tf = m_tfList[i].tf;
         datetime currentBarTime = iTime(symbol, tf, 0);

         if(currentBarTime != 0 && currentBarTime != m_tfList[i].lastBarTime)
         {
            m_tfList[i].lastBarTime = currentBarTime;

            // Fetch last 4 bars (Bar 0 running, 1, 2, 3 completed)
            MqlRates rates[];
            ArraySetAsSeries(rates, true);
            if(CopyRates(symbol, tf, 0, 4, rates) >= 4)
            {
               // Process candle close (rates[1], rates[2], rates[3])
               ProcessStructureWithRates(m_tfList[i], rates[1], rates[2], rates[3]);

               if(m_tfList[i].drawEnabled)
               {
                  DrawStructureOnChart(m_tfList[i]);
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Clean all visual objects from chart                              |
   //+------------------------------------------------------------------+
   void ClearChartObjects()
   {
      ObjectsDeleteAll(0, m_objPrefix);
   }

   //+------------------------------------------------------------------+
   //| Getter: Get total confirmed structures count for TF              |
   //+------------------------------------------------------------------+
   int GetStructuresCount(const ENUM_TIMEFRAMES tf)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return 0;
      return ArraySize(m_tfList[idx].structures);
   }

   //+------------------------------------------------------------------+
   //| Getter: Get confirmed structures array copy                      |
   //+------------------------------------------------------------------+
   bool GetStructures(const ENUM_TIMEFRAMES tf, SStructurePoint &outArray[])
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return false;

      int total = ArraySize(m_tfList[idx].structures);
      if(total <= 0) return false;

      ArrayResize(outArray, total);
      for(int i = 0; i < total; i++)
      {
         outArray[i] = m_tfList[idx].structures[i];
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Getter: Get Current Trend for TF                                 |
   //+------------------------------------------------------------------+
   ENUM_STR_TREND GetTrend(const ENUM_TIMEFRAMES tf)
   {
      int idx = FindTFIndex(tf);
      if(idx < 0) return STR_TREND_NONE;
      return m_tfList[idx].trend;
   }

private:
   int FindTFIndex(const ENUM_TIMEFRAMES tf)
   {
      for(int i = 0; i < m_totalTFs; i++)
      {
         if(m_tfList[i].tf == tf) return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Process history for one specific timeframe                       |
   //+------------------------------------------------------------------+
   void InitTFHistory(const string symbol, STimeframeStructureData &data, const int maxBars)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(symbol, data.tf, 0, maxBars + 5, rates);
      if(copied < 4) return;

      // Reset data
      ArrayResize(data.structures, 0);
      data.pivotStructure.Init();

      // Clear existing objects for this TF
      string tfPrefix = m_objPrefix + EnumToString(data.tf) + "_";
      ObjectsDeleteAll(0, tfPrefix);

      // Loop historical bars from past to present
      for(int i = copied - 3; i >= 1; i--)
      {
         ProcessStructureWithRates(data, rates[i], rates[i + 1], rates[i + 2]);
      }

      if(data.drawEnabled)
      {
         DrawStructureOnChart(data);
      }

      PrintFormat("[StructureV0] InitHistory done for %s: %d structures identified.",
                  EnumToString(data.tf), ArraySize(data.structures));
   }

   //+------------------------------------------------------------------+
   //| Core algorithm: Process 3 candles (r0=newest, r1=middle, r2=old) |
   //+------------------------------------------------------------------+
   void ProcessStructureWithRates(STimeframeStructureData &data, 
                                  const MqlRates &r0, 
                                  const MqlRates &r1, 
                                  const MqlRates &r2)
   {
      SStructurePoint structure0;
      structure0.Init();

      int newStructure = 0;

      // Reliable 3-bar swing pivot on r1
      bool isSwingHigh = (r1.high > r0.high && r1.high > r2.high);
      bool isSwingLow  = (r1.low < r0.low && r1.low < r2.low);

      int size = ArraySize(data.structures);

      if(isSwingHigh && isSwingLow)
      {
         if(size > 1)
         {
            if(data.pivotStructure.label == "H")
            {
               if(data.pivotStructure.priceH < r1.high) structure0.label = "H";
               else structure0.label = "L";
            }
            else if(data.pivotStructure.label == "L")
            {
               if(data.pivotStructure.priceL > r1.low) structure0.label = "L";
               else structure0.label = "H";
            }
            else if(data.structures[size - 1].label == "H" || 
                    data.structures[size - 1].label == "HH" || 
                    data.structures[size - 1].label == "LH")
            {
               if(data.structures[size - 1].priceH < r1.high) structure0.label = "H";
               else structure0.label = "L";
            }
            else
            {
               if(data.structures[size - 1].priceL > r1.low) structure0.label = "L";
               else structure0.label = "H";
            }
         }
         else
         {
            if(r1.close > r1.open) structure0.label = "H";
            else structure0.label = "L";
         }

         structure0.priceH     = r1.high;
         structure0.priceL     = r1.low;
         structure0.candleTime = r1.time;
         newStructure          = 1;
      }
      else if(isSwingHigh)
      {
         structure0.label      = "H";
         structure0.priceH     = r1.high;
         structure0.priceL     = r1.low;
         structure0.candleTime = r1.time;
         newStructure          = 1;
      }
      else if(isSwingLow)
      {
         structure0.label      = "L";
         structure0.priceH     = r1.high;
         structure0.priceL     = r1.low;
         structure0.candleTime = r1.time;
         newStructure          = 1;
      }

      if(newStructure == 0) return;

      // Handle building structures array
      if(size == 0)
      {
         ArrayResize(data.structures, 1);
         data.structures[0] = structure0;
         return;
      }
      else if(size == 1)
      {
         if(data.structures[0].label != structure0.label)
         {
            ArrayResize(data.structures, 2);
            data.structures[1] = structure0;
         }
         return;
      }

      if(newStructure == 1)
      {
         int last = size - 1;
         if(data.structures[last].candleTime != structure0.candleTime)
         {
            if(data.structures[last].label == "H" || 
               data.structures[last].label == "HH" || 
               data.structures[last].label == "LH")
            {
               if(structure0.label == "H" && data.structures[last].priceH < structure0.priceH && data.pivotStructure.label == "")
               {
                  // Extend existing High
                  data.structures[last] = structure0;
               }
               else if(structure0.label == "H" && data.structures[last].priceH < structure0.priceH && data.pivotStructure.label == "L")
               {
                  // BOS confirmed: commit saved pivot L + new H
                  ArrayResize(data.structures, size + 2);
                  data.structures[size]     = data.pivotStructure;
                  data.structures[size + 1] = structure0;
                  newStructure = 2;
                  data.pivotStructure.Init();
               }
               else if(structure0.label == "L")
               {
                  if(data.structures[last - 1].priceL > structure0.priceL)
                  {
                     // Valid Low (CHoCH / Lower swing confirmed)
                     ArrayResize(data.structures, size + 1);
                     data.structures[size] = structure0;
                     data.pivotStructure.Init();
                  }
                  else
                  {
                     // Save to Pivot candidate
                     if(data.pivotStructure.label == "")
                        data.pivotStructure = structure0;
                     else if(data.pivotStructure.priceL > structure0.priceL)
                        data.pivotStructure = structure0;
                  }
               }
            }
            else // Last confirmed structure was a Low (L / LL / HL)
            {
               if(structure0.label == "L" && data.structures[last].priceL > structure0.priceL && data.pivotStructure.label == "")
               {
                  // Extend existing Low
                  data.structures[last] = structure0;
               }
               else if(structure0.label == "L" && data.structures[last].priceL > structure0.priceL && data.pivotStructure.label == "H")
               {
                  // BOS confirmed: commit saved pivot H + new L
                  ArrayResize(data.structures, size + 2);
                  data.structures[size]     = data.pivotStructure;
                  data.structures[size + 1] = structure0;
                  newStructure = 2;
                  data.pivotStructure.Init();
               }
               else if(structure0.label == "H")
               {
                  if(data.structures[last - 1].priceH < structure0.priceH)
                  {
                     // Valid High (CHoCH / Higher swing confirmed)
                     ArrayResize(data.structures, size + 1);
                     data.structures[size] = structure0;
                     data.pivotStructure.Init();
                  }
                  else
                  {
                     // Save to Pivot candidate
                     if(data.pivotStructure.label == "")
                        data.pivotStructure = structure0;
                     else if(data.pivotStructure.priceH < structure0.priceH)
                        data.pivotStructure = structure0;
                  }
               }
            }
         }
      }

      // Update structural labels (HH, HL, LH, LL) and Trend
      UpdateLabels(data, newStructure);
   }

   //+------------------------------------------------------------------+
   //| Update swing labels (HH, HL, LH, LL) and overall trend           |
   //+------------------------------------------------------------------+
   void UpdateLabels(STimeframeStructureData &data, const int depth)
   {
      int size = ArraySize(data.structures);
      if(size < 3) return;

      if(depth == 1)
      {
         int curr      = size - 1;
         int prevPivot = size - 3; // Compare with previous swing of the same type

         if(data.structures[curr].label == "L" || data.structures[curr].label == "LL" || data.structures[curr].label == "HL")
         {
            if(data.structures[curr].priceL < data.structures[prevPivot].priceL)
               data.structures[curr].label = "LL";
            else
               data.structures[curr].label = "HL";
         }
         else
         {
            if(data.structures[curr].priceH > data.structures[prevPivot].priceH)
               data.structures[curr].label = "HH";
            else
               data.structures[curr].label = "LH";
         }
      }
      else
      {
         int curr1      = size - 2;
         int prevPivot1 = size - 4;

         if(prevPivot1 >= 0)
         {
            if(data.structures[curr1].label == "L" || data.structures[curr1].label == "LL" || data.structures[curr1].label == "HL")
            {
               if(data.structures[curr1].priceL < data.structures[prevPivot1].priceL)
                  data.structures[curr1].label = "LL";
               else
                  data.structures[curr1].label = "HL";
            }
            else
            {
               if(data.structures[curr1].priceH > data.structures[prevPivot1].priceH)
                  data.structures[curr1].label = "HH";
               else
                  data.structures[curr1].label = "LH";
            }
         }

         int curr0      = size - 1;
         int prevPivot0 = size - 3;

         if(data.structures[curr0].label == "L" || data.structures[curr0].label == "LL" || data.structures[curr0].label == "HL")
         {
            if(data.structures[curr0].priceL < data.structures[prevPivot0].priceL)
               data.structures[curr0].label = "LL";
            else
               data.structures[curr0].label = "HL";
         }
         else
         {
            if(data.structures[curr0].priceH > data.structures[prevPivot0].priceH)
               data.structures[curr0].label = "HH";
            else
               data.structures[curr0].label = "LH";
         }
      }

      // Determine Trend from latest confirmed swings
      // User rule:
      // Bullish: HH-HL atau HL-HH atau tidak ada LL yang terbentuk di N swing terakhir
      // Bearish: LL-HL atau HL-LL (serta LL-LH/LH-LL) atau tidak ada HH yang terbentuk di N swing terakhir
      string s1 = data.structures[size - 1].label; // Latest
      string s2 = data.structures[size - 2].label; // Previous

      // Check N recent swings (window 4-6 swings) for presence of LL or HH
      int checkWindow = MathMin(6, size);
      bool hasRecentLL = false;
      bool hasRecentHH = false;
      for(int w = size - 1; w >= size - checkWindow; w--)
      {
         if(data.structures[w].label == "LL") hasRecentLL = true;
         if(data.structures[w].label == "HH") hasRecentHH = true;
      }

      if((s2 == "HH" && s1 == "HL") || (s2 == "HL" && s1 == "HH"))
      {
         data.trend = STR_TREND_BULL;
      }
      else if((s2 == "LL" && s1 == "HL") || (s2 == "HL" && s1 == "LL") ||
              (s2 == "LL" && s1 == "LH") || (s2 == "LH" && s1 == "LL"))
      {
         data.trend = STR_TREND_BEAR;
      }
      else if(!hasRecentLL && hasRecentHH)
      {
         data.trend = STR_TREND_BULL; // Bullish: tidak ada LL terbentuk di N swing terakhir
      }
      else if(!hasRecentHH && hasRecentLL)
      {
         data.trend = STR_TREND_BEAR; // Bearish: tidak ada HH terbentuk di N swing terakhir
      }
   }

   //+------------------------------------------------------------------+
   //| Draw confirmed structure trendlines and labels on chart          |
   //+------------------------------------------------------------------+
   void DrawStructureOnChart(STimeframeStructureData &data)
   {
      int size = ArraySize(data.structures);
      if(size < 1) return;

      string tfPrefix = m_objPrefix + EnumToString(data.tf) + "_";

      // 1. Draw confirmed lines between sequential swings
      for(int i = 1; i < size; i++)
      {
         string lineName = tfPrefix + "Line_" + IntegerToString(i);
         string textName = tfPrefix + "Text_" + IntegerToString(i);

         double prevPrice = (data.structures[i - 1].label == "HH" || 
                             data.structures[i - 1].label == "LH" || 
                             data.structures[i - 1].label == "H") ? data.structures[i - 1].priceH : data.structures[i - 1].priceL;

         double currPrice = (data.structures[i].label == "HH" || 
                             data.structures[i].label == "LH" || 
                             data.structures[i].label == "H") ? data.structures[i].priceH : data.structures[i].priceL;

         datetime prevTime = data.structures[i - 1].candleTime;
         datetime currTime = data.structures[i].candleTime;

         // Draw Trendline
         if(!ObjectCreate(0, lineName, OBJ_TREND, 0, prevTime, prevPrice, currTime, currPrice))
         {
            ObjectMove(0, lineName, 0, prevTime, prevPrice);
            ObjectMove(0, lineName, 1, currTime, currPrice);
         }
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, data.lineColor);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, data.lineWidth);

         // Draw Text Label (HH, HL, LH, LL)
         if(!ObjectCreate(0, textName, OBJ_TEXT, 0, currTime, currPrice))
         {
            ObjectMove(0, textName, 0, currTime, currPrice);
         }
         ObjectSetString(0, textName, OBJPROP_TEXT, " " + data.structures[i].label);
         ObjectSetInteger(0, textName, OBJPROP_COLOR, data.lineColor);
         ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, textName, OBJPROP_FONT, "Arial Bold");
      }

      // 2. Draw line to running Pivot candidate (Dotted)
      string pivotLineName = tfPrefix + "PivotLine";
      string pivotTextName = tfPrefix + "PivotText";

      if(data.pivotStructure.label != "")
      {
         int lastIdx = size - 1;
         double lastPrice = (data.structures[lastIdx].label == "HH" || 
                             data.structures[lastIdx].label == "LH" || 
                             data.structures[lastIdx].label == "H") ? data.structures[lastIdx].priceH : data.structures[lastIdx].priceL;

         double pivotPrice = (data.pivotStructure.label == "HH" || 
                              data.pivotStructure.label == "LH" || 
                              data.pivotStructure.label == "H") ? data.pivotStructure.priceH : data.pivotStructure.priceL;

         datetime lastTime  = data.structures[lastIdx].candleTime;
         datetime pivotTime = data.pivotStructure.candleTime;

         if(!ObjectCreate(0, pivotLineName, OBJ_TREND, 0, lastTime, lastPrice, pivotTime, pivotPrice))
         {
            ObjectMove(0, pivotLineName, 0, lastTime, lastPrice);
            ObjectMove(0, pivotLineName, 1, pivotTime, pivotPrice);
         }
         ObjectSetInteger(0, pivotLineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, pivotLineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, pivotLineName, OBJPROP_COLOR, data.lineColor);
         ObjectSetInteger(0, pivotLineName, OBJPROP_WIDTH, 1);

         if(!ObjectCreate(0, pivotTextName, OBJ_TEXT, 0, pivotTime, pivotPrice))
         {
            ObjectMove(0, pivotTextName, 0, pivotTime, pivotPrice);
         }
         ObjectSetString(0, pivotTextName, OBJPROP_TEXT, " (Pivot " + data.pivotStructure.label + ")");
         ObjectSetInteger(0, pivotTextName, OBJPROP_COLOR, data.lineColor);
         ObjectSetInteger(0, pivotTextName, OBJPROP_FONTSIZE, 8);
      }
      else
      {
         ObjectDelete(0, pivotLineName);
         ObjectDelete(0, pivotTextName);
      }
   }
};

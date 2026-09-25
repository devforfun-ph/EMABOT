//+------------------------------------------------------------------+
//|                                                     MACD_BOT.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== STRATEGY INDICATOR ==="
input ENUM_TIMEFRAMES MACDPeriod = PERIOD_M3;            // MACD Strategy TF
input ENUM_TIMEFRAMES MACDZeroLinePeriod = PERIOD_M15;   // MACD Strategy Zero Line TF
input int FastEMA       = 12;                            // Fast EMA
input int SlowEMA       = 26;                            // Slow EMA
input int SignalPeriod  = 9;                             // Signal Period


input group "=== TRADING SETTINGS ==="
input double initLotSize = 0.01;           // Initial Lot Size
input int roundSize = 2;              // Round off
input ulong magicNumber = 434437;  //Random Magic Number/Key
input bool isContinous = true; // Continue Trading if Secure Profit Hit?

input group "=== Multiplier Settings===="
input double x1 = 2.0;
input double x2 = 1.9;
input double x3 = 1.8;
input double x4 = 1.7;
input double x5 = 1.6;
input double x6 = 1.5;
input double x7 = 1.4;
input double x8 = 1.3;
input double x9 = 1.2;
input double x10 = 1.1;

input group "=== RISK MANAGEMENT ==="
input double tpMin = 2.0;                  //Minimum Profit
input double tpValueA = 5;                 //First Trailing Profit
input double tpValueB = 10;                //Second Trailing Profit
input double tpValueC = 15;                //Max Trailing Profit

// create 3 trailing percentage based on profit
input double trailPercentA = 55;                   //First Trailing Percentage
input double trailPercentB = 65;                   //Second Trailing Percentage
input double trailPercentC = 75;                   //Max Trailing Percentage



//                                     1  2  3  4  5   6   7   8   9  10  11	Server Time
//0   1  2  3  4  5  6 7 8 9 10 11 12 13 14 15 16 17  18  19  20  21  22  23 	GMT+8
//18 19 20 21 22 23  0 1 2 3  4  5  6  7  8  9 10 11  12  13  14  15  16  17	GMT+2

input group "=== TRADING HOUR ==="
input int    InpStartHourShift1 = 1;               //Shift 1 - Start Hour
input int    InpEndHourShift1 = 5;                 //Shift 1 - End Hour
input int    InpStartHourShift2 = 8;               //Shift 2 - Start Hour
input int    InpEndHourShift2 = 11;                 //Shift 2 - End Hour
input int    InpStartHourShift3 = 16;               //Shift 3 - Start Hour
input int    InpEndHourShift3 = 21;                 //Shift 3 - End Hour

input int    InpTargetGMTOffset  = 2;             // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;             // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)

input int hourBeforeClosing = 22;      //Friday No Trade After N Hour
input bool isForceCloseFriday = false;

input group "=== WITH NEWS SETTING ==="
input int    InpStartHourShift1News = 1;               //Shift 1 - Start Hour
input int    InpEndHourShift1News = 5;                 //Shift 1 - End Hour
input int    InpStartHourShift2News = 8;               //Shift 2 - Start Hour
input int    InpEndHourShift2News = 11;                 //Shift 2 - End Hour
input int    InpStartHourShift3News = 1;               //Shift 3 - Start Hour
input int    InpEndHourShift3News = 1;                 //Shift 3 - End Hour
input double newsLotSize = 0.01;                         //Lot Size w/ News

input group "=== Monthly Economic Calendar Date ==="
input int          InpNewsTradeYear   = 2026;            // Year 
input int          InpNewsTradeMonth  = 9;               // Month 
input string       InpNewsTradeDays   = "5,10,15,25";    // Days 

bool g_isNewsDay = false;
datetime g_lastDateTradeCheck = 0;
datetime lastBarTime = 0;
datetime lastZLBarTime = 0;
double lotSize = 0;

double currentLotSize = 0;

enum CurrentPosition
  {
   C_None,
   C_Buy,
   C_Sell
  };
CurrentPosition activePosition = C_None;


int macd3MHandle;
int macd15MHandle;

int macdState = 0;
int macdZLState = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
  
      //==============================================================
      // M3 MACD
      //==============================================================
      macd3MHandle = iMACD(
         _Symbol,
         MACDPeriod,
         FastEMA,
         SlowEMA,
         SignalPeriod,
         PRICE_CLOSE
      );
   
      if(macd3MHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create M3 MACD handle");
         return INIT_FAILED;
      }
   
   
      //==============================================================
      // M15 MACD
      //==============================================================
   
      macd15MHandle = iMACD(
         _Symbol,
         MACDZeroLinePeriod,
         FastEMA,
         SlowEMA,
         SignalPeriod,
         PRICE_CLOSE
      );
   
      if(macd15MHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create M15 MACD handle");
         return INIT_FAILED;
      }
      trade.SetExpertMagicNumber(magicNumber);
      return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
    if(macd3MHandle != INVALID_HANDLE)
      IndicatorRelease(macd3MHandle);

   if(macd15MHandle != INVALID_HANDLE)
      IndicatorRelease(macd15MHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  
   CheckNewsDay();
   
   if (g_isNewsDay)
      lotSize = newsLotSize;
   else
      lotSize = initLotSize;
      
   ManageTrailingStop();
   
    
   if (IsNewZLBar())
   {
      UpdateZLDStatee();
   }

   if(IsNewBar())
     {
          UpdateMACDState();
         //Clsoe all position for friday only
         if (isForceCloseFriday)
         {
            if (IsFridayLastNHours())
            {
               CloseAllPositions();
               return;
            }
         }
         
         CheckForSignal();
     }
  }
//+------------------------------------------------------------------+
void CheckForSignal()
{

   int signal = GetMACDSignal();
   
   bool hasPosition = HasOpenPositionByMagic();
   double positionLotSize = lotSize;
   
   if (!hasPosition && isContinous)
      activePosition = C_None;
      
   if(signal == 1 && activePosition != C_Buy)
   {
         if(hasPosition)
         {
            Print("EMABOT: Have existing Position...");
            positionLotSize = GetLotSize();
         }
         Print("Position Lot Size: ", positionLotSize, "| Lot Size: ", lotSize, "| Buy Signal");
         
         if(positionLotSize == lotSize)
         {     
            if (!IsInTradeSchedule())
            {
                  Print("Not in schedule");
                  activePosition = C_None;
                  return; 
            }
         } 
         
         bool tbuy = trade.Buy(positionLotSize, _Symbol);
           
         Print("EMABOT:Buy Position: " + positionLotSize);
         
         activePosition = C_Buy;
         
   }
   else if (signal == -1 && activePosition != C_Sell)
   {
         if(hasPosition)
         {
            Print("EMABOT: Have existing Position...");
            positionLotSize = GetLotSize();
         }
         Print("Position Lot Size: ", positionLotSize, "| Lot Size: ", lotSize, "| Sell Signal");
         
         if(positionLotSize == lotSize)
         {     
            if (!IsInTradeSchedule())
            {
                  Print("Not in schedule");
                  activePosition = C_None;
                  return; 
            }
         } 
         
         bool tsell = trade.Sell(positionLotSize, _Symbol);
           
         Print("EMABOT:Sell Position: " + positionLotSize);
         
         activePosition = C_Sell;
   }
}


//==================================================================
// UPDATE M3 MACD STATE
//==================================================================

void UpdateMACDState()
{
   double macd[3];
   double signal[3];

   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal, true);


   //==============================================================
   // MACD MAIN
   //==============================================================

   if(CopyBuffer(
      macd3MHandle,
      0,
      0,
      3,
      macd
   ) < 3)
   {
      Print("ERROR: Cannot read M3 MACD");
      return;
   }


   //==============================================================
   // SIGNAL LINE
   //==============================================================

   if(CopyBuffer(
      macd3MHandle,
      1,
      0,
      3,
      signal
   ) < 3)
   {
      Print("ERROR: Cannot read M3 Signal");
      return;
   }


   //==============================================================
   // BULLISH CROSS
   //
   // Previous closed candle:
   // MACD <= Signal
   //
   // Latest closed candle:
   // MACD > Signal
   //==============================================================

   bool bullishCross =
      macd[2] <= signal[2] &&
      macd[1] > signal[1];


   //==============================================================
   // BEARISH CROSS
   //==============================================================

   bool bearishCross =
      macd[2] >= signal[2] &&
      macd[1] < signal[1];


   //==============================================================
   // STORE STATE
   //==============================================================

   if(bullishCross)
   {
      macdState = 1;

      Print(
         "M3 MACD STATE = BULLISH | ",
         "MACD: ", DoubleToString(macd[1], 6),
         " | Signal: ", DoubleToString(signal[1], 6)
      );
   }


   if(bearishCross)
   {
      macdState = -1;

      Print(
         "M3 MACD STATE = BEARISH | ",
         "MACD: ", DoubleToString(macd[1], 6),
         " | Signal: ", DoubleToString(signal[1], 6)
      );
   }
}


void UpdateZLDStatee()
{
   double macd[2];

   ArraySetAsSeries(macd, true);

   if(CopyBuffer(macd15MHandle, 0, 0, 2, macd) < 2)
      return;

   //--- M15 MACD above zero
   if(macd[1] > 0)
   {
      macdZLState = 1;
   }
   //--- M15 MACD below zero
   else if(macd[1] < 0)
   {
      macdZLState = -1;
   }
}


bool IsNewZLBar()
{
   datetime barTime = iTime(
      _Symbol,
      MACDZeroLinePeriod,
      0
   );

   if(barTime == 0)
      return false;

   if(barTime != lastZLBarTime)
   {
      lastZLBarTime = barTime;
      return true;
   }

   return false;
}


/*
   1 - BUY
  -1 - SELL
   0 - Error
*/
int GetMACDSignal()
{
   //==================================================
   // BUY
   // M3 is bullish AND M15 is above zero
   //==================================================
   
   Print("MACD State: ", macdState);
   Print("MACD Zero Line State: ", macdZLState);
   
   if(macdState == 1 &&
      macdZLState == 1)
   {
      return 1;
   }


   //==================================================
   // SELL
   // M3 is bearish AND M15 is below zero
   //==================================================
   if(macdState == -1 &&
      macdZLState == -1)
   {
      return -1;
   }
   
   return 0;
}


void ManageTrailingStop()
  {
   int nPosCount = CountPositionsByMagic();
   
   if (nPosCount == 0)
      return;
   
   if(nPosCount > 1)
     {
      if(GetTotalProfitByMagic() > tpMin)
        {
         CloseAllPositions();
         activePosition = C_None;
         return; 
        }
      return;
     }
   

   for (int j = PositionsTotal() - 1; j>= 0; j--)
   {
 
      ulong ticket = PositionGetTicket(j);
   
      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
         
      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      double currentProfit = PositionGetDouble(POSITION_PROFIT);
      double trailPercent = 0;
   
      if(currentProfit < tpValueA)
         return;
   
      trailPercent = trailPercentA;
      
      if (currentProfit < tpValueB)
      {  
         trailPercent = trailPercentA;
      }
      else if (currentProfit < tpValueC)
      {
         trailPercent = trailPercentB;
      }
      else
      {
         trailPercent = trailPercentC;
      }
      
      
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
   
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
      double lockedProfit =
         currentProfit * (trailPercent / 100.0);
   
      double profitToGiveBack =
         currentProfit - lockedProfit;
   
      double priceDistance =
         (profitToGiveBack / (tickValue * volume)) * tickSize;
   
      double newSL;
   
      if(type == POSITION_TYPE_BUY)
        {
         newSL = bid - priceDistance;
   
         if(currentSL == 0 || newSL > currentSL)
           {
            trade.PositionModify(ticket, newSL, tp);
           }
        }
      else
         if(type == POSITION_TYPE_SELL)
           {
            newSL = ask + priceDistance;
   
            if(currentSL == 0 || newSL < currentSL)
              {
               trade.PositionModify(ticket, newSL, tp);
              }
           }
   }
  }

//+------------------------------------------------------------------+
//|Count only positions belongs to EA MagicNumber                    |
//+------------------------------------------------------------------+

int CountPositionsByMagic()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//|Total Profit for all positions belongs to EA MagicNumber          |
//+------------------------------------------------------------------+
double GetTotalProfitByMagic()
{
   double totalProfit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
      {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }

   return totalProfit;
}

//+------------------------------------------------------------------+
//|Close all positions belongs to EA MagicNumber                     |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
 
      if(IsMyPosition(ticket))
        {
         trade.PositionClose(ticket);
        }
     }
 }
 
//+------------------------------------------------------------------+
//| Returns true only if a position on _Symbol belonging to this EA  |
//| (matching magicNumber) is currently selected                     |
//+------------------------------------------------------------------+
bool SelectMyPosition()
  {
   if(!PositionSelect(_Symbol))
      return false;
   return (PositionGetInteger(POSITION_MAGIC) == (long)magicNumber);
  }
 
//+------------------------------------------------------------------+
//| Returns true only if the position at the given ticket belongs    |
//| to this EA (matching magicNumber) on this symbol                 |
//+------------------------------------------------------------------+
bool IsMyPosition(ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   return (PositionGetInteger(POSITION_MAGIC) == (long)magicNumber &&
           PositionGetString(POSITION_SYMBOL) == _Symbol);
  }
  
bool HasOpenPositionByMagic()
  {
   int totalPositions = PositionsTotal();

   for(int i = 0; i < totalPositions; i++)
     {
      ulong ticket = PositionGetTicket(i);

      if(IsMyPosition(ticket))
         return true;
     }

   return false;
  }
  
double GetBiggestLotSizeByMagic()
{
   double biggestLot = lotSize;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      // Check magic number
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;

      double lSize = PositionGetDouble(POSITION_VOLUME);

      if(lSize > biggestLot)
         biggestLot = lSize;
   }

   return biggestLot;
}

double GetMultiplier(int nPosCount)
{
   double dMultiplier = x10;
   switch (nPosCount)
   {
      case 1:
         dMultiplier = x1;
         break;
      case 2:
         dMultiplier = x2;
         break;
      case 3:
         dMultiplier = x3;
         break;
      case 4:
         dMultiplier = x4;
         break;
      case 5:
         dMultiplier = x5;
         break;
      case 6:
         dMultiplier = x6;
         break;
      case 7:
         dMultiplier = x7;
         break;
      case 8:
         dMultiplier = x8;
         break;
      case 9:
         dMultiplier = x9;
         break;
      default:
         dMultiplier = x10;
         break;
   }
   return dMultiplier;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetLotSize()
  {
   double dLotSize = lotSize;
   double multiplier = x10;
   double currentPnL = 0;
   int nPositionCount = CountPositionsByMagic();

   if(nPositionCount > 0)
     {
      currentPnL = GetTotalProfitByMagic();
      // close if positive position
      if(currentPnL > 0)
        {
         CloseAllPositions();
         dLotSize = lotSize;
        }

      else
        {
         // to ensure if position still exits
         currentLotSize = GetBiggestLotSizeByMagic();
         multiplier = GetMultiplier(nPositionCount);
         dLotSize = NormalizeDouble(currentLotSize * multiplier, roundSize);  
          
         Print("EMABOT R: Current Running PnL: " + currentPnL);
        }
     }
   Print("Position Lot Size: " + dLotSize);
   return dLotSize;
  }
  
//+------------------------------------------------------------------+
//|Process only if theres a new bar based on current time frame      |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBar = iTime(_Symbol, MACDPeriod, 0);
   if(currentBar != lastBarTime)
     {
      lastBarTime = currentBar;
      return true;
     }
   return false;
  }
  
//+------------------------------------------------------------------+
//FOR FORCE CLOSE ALL POSITION ON FRIDAY
//+------------------------------------------------------------------+
bool IsFridayLastNHours()
{
   datetime now = TimeTradeServer();

   MqlDateTime tm;
   TimeToStruct(now, tm);

   // 5 = Friday
   if(tm.day_of_week != 5)
      return false;

   // Example: force close starting at 22:00 server time
   if(tm.hour >= hourBeforeClosing)
      return true;

   return false;
}


//+------------------------------------------------------------------+
//CHECK TRADER SCHEDULE
//+------------------------------------------------------------------+
bool IsInTradeSchedule()
{
   //will ignore checking if start and end are equal
   bool isInSched = false;
   if (g_isNewsDay)
   {
      if (InpStartHourShift1News != InpEndHourShift1News)
         if(IsInTradeWindow(InpStartHourShift1News, InpEndHourShift1News))
         {
            isInSched = true;
            Print("Shift 1 Schedule News");
         }
      if (InpStartHourShift2News != InpEndHourShift2News)
         if(IsInTradeWindow(InpStartHourShift2News, InpEndHourShift2News))
         {
            isInSched = true;
            Print("Shift 2 Schedule News");
         }
      
      if (InpStartHourShift3News != InpEndHourShift3News)
         if(IsInTradeWindow(InpStartHourShift3News, InpEndHourShift3News))
         {
            isInSched = true;
            Print("Shift 3 Schedule News");
         }
   }
   else
   {
      if (InpStartHourShift1 != InpEndHourShift1)
         if(IsInTradeWindow(InpStartHourShift1, InpEndHourShift1))
         {
            isInSched = true;
            Print("Shift 1 Schedule");
         }
      if (InpStartHourShift2 != InpEndHourShift2)
         if(IsInTradeWindow(InpStartHourShift2, InpEndHourShift2))
         {
            isInSched = true;
            Print("Shift 2 Schedule");
         }
      
      if (InpStartHourShift3 != InpEndHourShift3)
         if(IsInTradeWindow(InpStartHourShift3, InpEndHourShift3))
         {
            isInSched = true;
            Print("Shift 3 Schedule");
         }
   }
   return isInSched;
}
bool IsInTradeWindow(int iTradeStart, int iTradeEnd)
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);

// Convert broker server hour -> target timezone hour (e.g. GMT+8)
   int hour = dt.hour + (InpTargetGMTOffset - InpBrokerGMTOffset);
   hour = ((hour % 24) + 24) % 24; // normalize into 0-23

   // will consider 24/7 if tradestart and tradeend is equal
   if(iTradeStart == iTradeEnd)
      return true; 
      
   if(iTradeStart < iTradeEnd)
      return (hour >= iTradeStart && hour < iTradeEnd);
   else
      // window wraps past midnight, e.g. 22 -> 2
      return (hour >= iTradeStart || hour < iTradeEnd);
  }



/************************************
CHECK IF CURRENT DAY HAS NEWS SETTING
************************************/
void CheckNewsDay()
{
   datetime currentTime = TimeCurrent();

   // Get the beginning of the current 15-minute period
   datetime currentPeriod = currentTime - (currentTime % 900);

   // Already checked this 15-minute period
   if(currentPeriod == g_lastDateTradeCheck)
      return;

   // Store the period that was checked
   g_lastDateTradeCheck = currentPeriod;
   
   g_isNewsDay = IsNewsDay();
   
   Print("News Day: ", g_isNewsDay);
}

bool IsNewsDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Check year
   if(dt.year != InpNewsTradeYear)
      return false;

   // Check month
   if(dt.mon != InpNewsTradeMonth)
      return false;

   // Split comma-separated days
   string dayList[];
   int count = StringSplit(InpNewsTradeDays, ',', dayList);

   if(count <= 0)
      return false;

   // Check if today's day is in the list
   for(int i = 0; i < count; i++)
   {
      string dayString = dayList[i];
      StringTrimLeft(dayString);
      StringTrimRight(dayString);

      int noTradeDay = (int)StringToInteger(dayString);

      if(dt.day == noTradeDay)
         return true;
   }

   return false;
}

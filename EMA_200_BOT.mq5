#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade/Trade.mqh>
CTrade trade;


input group "=== Version: 23 Oct 2026  12:08pm ==="

input group "=== STRATEGY INDICATOR ==="
input ENUM_TIMEFRAMES EMAFastPeriod = PERIOD_M3;               //EMA TF
input int emaFast=200;                                         //EMA Length

input group "=== STRATEGY INDICATOR FILTER ==="
input bool checkEMACross = false;                              //Check EMA Cross
input int emaCrossSlow=9;                                      //Slow EMA
input int emaCrossFast=21;                                     //Fast EMA
input ENUM_TIMEFRAMES EMACrossPeriod = PERIOD_M3;              //EMA Cross TF

input bool checkMACD = true;                                   //Check MACD
input int FastEMA       = 12;                                  //MACD Fast EMA
input int SlowEMA       = 26;                                  //MACD Slow EMA
input int SignalPeriod  = 9;                                   //MACD Signal Period
input ENUM_TIMEFRAMES MACDPeriod = PERIOD_M3;                  //MACD TF

input group "=== TRADING SETTINGS ==="
input double initLotSize = 0.01;                               // Initial Lot Size
input ulong magicNumber = 2026;                                // Magic Number

input group "=== RISK MANAGEMENT ==="
input bool hasSL = false;                                      //Force Stop-Loss
input double slValue = 15;                                     // Stop-Loss Value
input double tpValueA = 6;                                    //First Trailing Profit
input double tpValueB = 12;                                    //Second Trailing Profit
input double tpValueC = 18;                                    //Max Trailing Profit

// create 3 trailing percentage based on profit
input double trailPercentA = 55;                               //First Trailing Percentage
input double trailPercentB = 65;                               //Second Trailing Percentage
input double trailPercentC = 75;                               //Max Trailing Percentage


input group "=== TRADING HOUR ==="
input int    InpStartHourShift1 = 1;                           //Shift 1 - Start Hour
input int    InpEndHourShift1 = 5;                             //Shift 1 - End Hour
input int    InpStartHourShift2 = 8;                           //Shift 2 - Start Hour
input int    InpEndHourShift2 = 11;                            //Shift 2 - End Hour
input int    InpStartHourShift3 = 16;                          //Shift 3 - Start Hour
input int    InpEndHourShift3 = 21;                            //Shift 3 - End Hour

input int    InpTargetGMTOffset  = 2;                          // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;                          // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)
   
input int hourBeforeClosing = 22;                              //Friday No Trade After N Hour
input bool isForceCloseFriday = true;

input group "=== WITH NEWS SETTING ==="
input int    InpStartHourShift1News = 1;                       //Shift 1 - Start Hour
input int    InpEndHourShift1News = 5;                         //Shift 1 - End Hour
input int    InpStartHourShift2News = 8;                       //Shift 2 - Start Hour
input int    InpEndHourShift2News = 11;                        //Shift 2 - End Hour
input int    InpStartHourShift3News = 1;                       //Shift 3 - Start Hour
input int    InpEndHourShift3News = 1;                         //Shift 3 - End Hour
input double newsLotSize = 0.01;                               //Lot Size w/ News

input group "=== News Date ==="
input int          InpNewsTradeYear   = 2025;                  //Year A
input int          InpNewsTradeMonth  = 9;                     //Month A
input string       InpNewsTradeDays   = "5,10,15,25";          //Days Month A

input int          InpNewsTradeYearB  = 2025;                  //Year B
input int          InpNewsTradeMonthB  = 1;                    //Month B
input string       InpNewsTradeDaysB   = "1";                  //Days of Month B

int emaFastHandle;
int emaCrossSlowHandle;
int emaCrossFastHandle;
int macdHandle;


bool g_isNewsDay = false;
datetime g_lastDateTradeCheck = 0;
datetime lastBarTime = 0;
double lotSize = 0;


// 1: buy | -1: sell
int macdState = 0;         
int emaState = 0;    
int emaCrossState = 0;

enum CurrentPosition
  {
   C_None,
   C_Buy,
   C_Sell
  };
CurrentPosition activePosition = C_None;

int OnInit()
  {
   emaFastHandle = iMA(_Symbol, EMAFastPeriod, emaFast, 0, MODE_EMA, PRICE_CLOSE);
   emaCrossSlowHandle = iMA(_Symbol, EMACrossPeriod, emaCrossSlow, 0, MODE_EMA, PRICE_CLOSE);
   emaCrossFastHandle = iMA(_Symbol, EMACrossPeriod, emaCrossFast, 0, MODE_EMA, PRICE_CLOSE);
   macdHandle = iMACD(_Symbol, MACDPeriod, FastEMA, SlowEMA, SignalPeriod, PRICE_CLOSE);
  
   if(emaFastHandle == INVALID_HANDLE || emaCrossSlowHandle == INVALID_HANDLE || emaCrossFastHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE)
     {
      LogMessage("Failed to create EMA/MACD handles");
      return(INIT_FAILED);
     }

   
   Print("Local Time : ", TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   Print("GMT Time   : ", TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
   Print("Server Time: ", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   
   trade.SetExpertMagicNumber(magicNumber);
   
   return(INIT_SUCCEEDED);

  }
  
void OnDeinit(const int reason)
  {
   if(emaFastHandle != INVALID_HANDLE)
      IndicatorRelease(emaFastHandle);
   if(emaCrossSlowHandle != INVALID_HANDLE)
      IndicatorRelease(emaCrossSlowHandle);
   if(emaCrossFastHandle != INVALID_HANDLE)
      IndicatorRelease(emaCrossFastHandle);
   if(macdHandle != INVALID_HANDLE)
      IndicatorRelease(macdHandle);
  }

void UpdateEMACrossState()
  {
   emaCrossState = 0;
   
   if (!checkEMACross)
      return;
      
   double fastEMA[3];
   double slowEMA[3];

   //ema 21
   if(CopyBuffer(emaCrossFastHandle, 0, 0, 3, fastEMA) < 0)
      return;
      
   //ema 9
   if(CopyBuffer(emaCrossSlowHandle, 0, 0, 3, slowEMA) < 0)
      return;

   emaCrossState = 0;
   
   if (slowEMA[0] > fastEMA[0])
   {
      emaCrossState = 1;
   }
   else if (slowEMA[0] < fastEMA[0])
   {  
      emaCrossState = -1;
   }
  }  
  
void UpdateMACDState()
{
   macdState = 0;
   
   if (!checkMACD)
      return;
      
   if(macdHandle == INVALID_HANDLE)
      return;
      
   double macd[3];
   double signal[3];

   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal, true);


   //==============================================================
   // MACD MAIN
   //==============================================================

   if(CopyBuffer(macdHandle,0,0,3,macd) < 3)
   {
      LogMessage("ERROR: Cannot read MACD main line");
      return;
   }


   //==============================================================
   // SIGNAL LINE
   //==============================================================

   if(CopyBuffer(macdHandle,1,0,3,signal) < 3)
   {
      LogMessage("ERROR: Cannot read Signal line");
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
   
   bool bullishCross = macd[1] > signal[1];
      

   //==============================================================
   // BEARISH CROSS
   //==============================================================

   bool bearishCross = macd[1] < signal[1];
      
   //==============================================================
   // STORE STATE
   //==============================================================

   if(bullishCross)
   {
      macdState = 1;
   }

   if(bearishCross)
   {
      macdState = -1;
   }   
}

void UpdateEMAState()
  {

   emaState = 0;
   if(emaFastHandle == INVALID_HANDLE)
      return;


   double f[3];

   ArraySetAsSeries(f, true);


   if(CopyBuffer(emaFastHandle, 0, 1, 3, f) < 3)
   {
      LogMessage("ERROR: Cannot read EMA Fast line");
      return;
   }

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if (askPrice > f[0])
   {
      emaState = 1;
   }
   if (bidPrice < f[0])
   {
      emaState = -1;
   }
  }
  
  void LogMessage(string message)
  {
      Print("--------------------");
      Print("BOT: ", message);
      Print("--------------------");
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
//+------------------------------------------------------------------+
//|Process only if theres a new bar based on current time frame      |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
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


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   int nPosCount = CountPositionsByMagic();
   
   if (nPosCount == 0)
      return;
   
   // IF Stop Loss is implemented
   if (hasSL)
   {
      if (GetTotalProfitByMagic() <= (slValue * -1))
         {
            CloseAllPositions();
            return;
         }
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
  
  
  void OnTick()
  {
   
   CheckNewsDay();
   
   if (g_isNewsDay)
      lotSize = newsLotSize;
   else
      lotSize = initLotSize;
      
   ManageTrailingStop();

   if(IsNewBar())
     {
         //Clsoe all position for friday only
         if (isForceCloseFriday)
         {
            if (IsFridayLastNHours())
            {
               CloseAllPositions();
               return;
            }
         }
         UpdateEMACrossState();
         UpdateMACDState();
         UpdateEMAState();
         
         CheckForSignal();
     }
  }
  
void CheckForSignal()
  {
   
   bool hasPosition = HasOpenPositionByMagic();
   
   bool isBuy = false;
   bool isSell = false;
   
   if (emaState == 1) isBuy = true;
   if (emaState == -1) isSell = true;
   
   if (checkEMACross)
   {
      if (emaCrossState != 1 && isBuy) isBuy = false;
      if (emaCrossState != -1 && isSell) isSell = false;
   }
   if (checkMACD)
   {
      if (macdState != 1 && isBuy) isBuy = false;
      if (macdState != -1 && isSell) isSell = false;
   }
      
   
      
   if (!hasPosition) activePosition = C_None;
   
   if (isBuy && activePosition != C_Buy)
   {
      if (hasPosition)
      {
         CloseAllPositions();
      }
      if (!IsInTradeSchedule())
      {
         activePosition = C_None;
         return;
      }
      bool tbuy = trade.Buy(lotSize, _Symbol);
      activePosition = C_Buy;
      
      if (!HasOpenPositionByMagic())
      {
         activePosition = C_None; 
         LogMessage("Error creating buy order");
      }  

   }
   else if (isSell && activePosition != C_Sell)
   {
      if (hasPosition)
      {
         CloseAllPositions();
      }
      if (!IsInTradeSchedule())
      {
            activePosition = C_None;
            return;
      }
      bool tbuy = trade.Sell(lotSize, _Symbol);
      activePosition = C_Sell;
      
      if (!HasOpenPositionByMagic())
      {
         activePosition = C_None; 
         LogMessage("Error creating sell order");
      }  
   }
   
  }
  
  

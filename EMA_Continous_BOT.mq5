//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade/Trade.mqh>

CTrade trade;

// Indicator Handles
int ema9Handle;
int ema21Handle;
int emaLongHandle;

input group "===STRATEGY INDICATOR==="
input int ema9 = 9;                    // Fast EMA (9)
input int ema21 = 21;                  // Slow EMA (21)

input group "===ADDITIONAL FILTER INDICATOR==="
input bool includeEMAFilter = false;   // Consider Filter?
input int emaLong = 50;                // Additional Filter EMA(50 min)
input double rangeFilter = 20;          //Range Filter +/-

input group "===TRADING SETTINGS==="
input double lotSize = 0.01;           // Initial Lot Size
input ulong magicNumber = 3197230;     // Magic Number


input group "===RISK MANAGEMENT==="
input double tp5 = 4.0;                // Minimum Secure Profit
input double tp15 = 8.0;              // First Trailing Profit
input double tp25 = 25.0;              // Second Trailing Profit
input double tp35 = 35.0;              // Max Trailing Profit
input double trail50 = 50.0;           // First Trailing Percentage
input double trail65 = 70.0;           // Second Trailing Percentage
input double trail75 = 75.0;           // Third Trailing Percentage
input double trailfix = 80;            // Max Trailing Percentage

input group "===TIME MANAGEMENT==="
input int    InpStartHourShift1 = 1;               //Shift 1 - Start Hour
input int    InpEndHourShift1 = 1;                 //Shift 1 - End Hour
input int    InpStartHourShift2 = 1;               //Shift 2 - Start Hour
input int    InpEndHourShift2 = 1;                 //Shift 2 - End Hour
input int    InpStartHourShift3 = 1;               //Shift 3 - Start Hour
input int    InpEndHourShift3 = 1;                 //Shift 3 - End Hour

//input int    InpNoTradeStartHour = 14;            // Asian/London No-Trade Window Start Hour (in Target GMT Offset below)//
//input int    InpNoTradeEndHour   = 14;            // Asian/London No-Trade Window End Hour (in Target GMT Offset
//input int    InpNoTradeStartHourNY = 14;          // NY No-Trade Window Start Hour (in Target GMT Offset below)
//input int    InpNoTradeEndHourNY   = 14;          // NY No-Trade Window End Hour (in Target GMT Offset
input int    InpTargetGMTOffset  = 8;             // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;             // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)
input int hourBeforeClosing = 22;      //Friday No Trade After N Hour
input bool isForceCloseFriday = false;

int InpLotSizeDiffStartHour = 4;            // Start Hour Increment Lot Size
int InpLotSizeDiffEndHour = 1;              // End Hour Increment Lot Size
double multiplierDiffLotSize = 1.0;          // Increment Lot Size Multiplier

datetime lastBarTime = 0;

enum CurrentPosition
  {
   None,
   Buy,
   Sell
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   ema9Handle = iMA(_Symbol, PERIOD_CURRENT, ema9, 0, MODE_EMA, PRICE_CLOSE);
   ema21Handle = iMA(_Symbol, PERIOD_CURRENT, ema21, 0, MODE_EMA, PRICE_CLOSE);
   emaLongHandle = iMA(_Symbol, PERIOD_CURRENT, emaLong, 0, MODE_EMA, PRICE_CLOSE);

   if(ema9Handle == INVALID_HANDLE || ema21Handle == INVALID_HANDLE || emaLongHandle == INVALID_HANDLE)
     {
      Print("Failed to create EMA handles");
      return(INIT_FAILED);
     }

   Print("Create EMA handles");

   trade.SetExpertMagicNumber(magicNumber);

   return(INIT_SUCCEEDED);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema9Handle);
   IndicatorRelease(ema21Handle);
   IndicatorRelease(emaLongHandle);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   
   if (isForceCloseFriday)
   {
      if (IsFridayLastNHours())
      {
         if (HasOpenPositionByMagic())
         {
            CloseAllPositions();
         }
         return;
      }
   }

   ManageTrailingStop();

   if(IsNewBar())
     {
      CheckForSignal();
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckForSignal()
  {

   double fastEMA[3];
   double slowEMA[3];
   double longEMA[3];

   if(CopyBuffer(ema9Handle, 0, 0, 3, fastEMA) < 0)
      return;

   if(CopyBuffer(ema21Handle, 0, 0, 3, slowEMA) < 0)
      return;
      
   if(CopyBuffer(emaLongHandle, 0, 0, 3, longEMA) < 0)
      return;

   bool buySignal = fastEMA[0] > slowEMA[0];
   bool sellSignal = fastEMA[0] < slowEMA[0];
   
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   bool isBuyBias = false;
   bool isSellBias = false;
   
   
   
   if (buySignal)
   {
      isBuyBias = askPrice - longEMA[0] < rangeFilter && askPrice > longEMA[0]; 
   }
   if (sellSignal)
   {

      isSellBias = longEMA[0] - bidPrice < rangeFilter && bidPrice < longEMA[0];
   }
   
   /*** log mode***/
   Print("-----------------------------");
   Print("BuySignal: " + buySignal);
   Print("sellSignal: " + sellSignal);
   Print("isBuyBias: " + isBuyBias);
   Print("isSellBias: " + isSellBias);
   PrintFormat("ask=%.2f | bid=%.2f | LongEMA=%.2f", askPrice, bidPrice, longEMA[0]);
   Print("-----------------------------");
 

   if (!includeEMAFilter)
   {
      isBuyBias = true;
      isSellBias = true;
   }
   
   double positionLotSize = GetLotSize(InpLotSizeDiffStartHour, InpLotSizeDiffEndHour);


// BUY Signal
   if(buySignal)
     {
      if(HasOpenPositionByMagic())
        {
         long posType = PositionGetInteger(POSITION_TYPE);

         if(posType == POSITION_TYPE_SELL)
           {
            Print("Position P/L: " + PositionGetDouble(POSITION_PROFIT));
            trade.PositionClose(_Symbol);
            Sleep(1000);
           }
         else
           {
            return;
           }
        }
        
      if (!IsInTradeSchedule())
         return;
      
      if (!isBuyBias)
         return;
      
      bool buy =  trade.Buy(positionLotSize, _Symbol);

      PrintFormat(
         "BUY EXECUTED | Ticket=%I64u | Symbol=%s | Volume=%.2f | Price=%.5f",
         trade.ResultOrder(),
         _Symbol,
         positionLotSize,
         trade.ResultPrice()
      );

     }

// SELL Signal
   if(sellSignal)
     {
      if(HasOpenPositionByMagic())
        {
         long posType = PositionGetInteger(POSITION_TYPE);

         if(posType == POSITION_TYPE_BUY)
           {
            trade.PositionClose(_Symbol);
            Sleep(1000);
           }
         else
           {
            return;
           }
        }
        
      if (!IsInTradeSchedule())
         return;

      if (!isSellBias)
         return;

      bool sell = trade.Sell(positionLotSize, _Symbol);

      PrintFormat(
         "Sell EXECUTED | Ticket=%I64u | Symbol=%s | Volume=%.2f | Price=%.5f",
         trade.ResultOrder(),
         _Symbol,
         positionLotSize,
         trade.ResultPrice()
      );

     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   if(!HasOpenPositionByMagic())
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   ulong ticket = PositionGetInteger(POSITION_TICKET);

   double volume = PositionGetDouble(POSITION_VOLUME);
   double currentProfit = PositionGetDouble(POSITION_PROFIT);

   if(currentProfit < tp5)
      return;

   double trailPercent;

   if(currentProfit < tp15)
     {
      trailPercent = trail50;
     }
   else
      if(currentProfit < tp25)
        {
         trailPercent = trail65;
        }
      else
         if(currentProfit < tp35)
           {
            trailPercent = trail75;
           }
         else
           {
            trailPercent = trailfix;
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

bool IsInTradeSchedule()
{
   //will ignore checking if start and end are equal
   bool isInSched = false;
   
   if (InpStartHourShift1 != InpEndHourShift1)
      if(IsInTradeWindow(InpStartHourShift1, InpEndHourShift1))
         isInSched = true;

   if (InpStartHourShift2 != InpEndHourShift2)
      if(!IsInTradeWindow(InpStartHourShift2, InpEndHourShift2))
         isInSched = true;
   
   if (InpStartHourShift3 != InpEndHourShift3)
      if(!IsInTradeWindow(InpStartHourShift3, InpEndHourShift3))
         isInSched = true;
      
   return isInSched;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/*
bool IsInNoTradeWindow(int iNoTradeStart, int iNoTradeEnd)
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);

   // Convert broker server hour -> target timezone hour (e.g. GMT+8)
   int hour = dt.hour + (InpTargetGMTOffset - InpBrokerGMTOffset);
   hour = ((hour % 24) + 24) % 24; // normalize into 0-23

   if(iNoTradeStart == iNoTradeEnd)
      return false; // zero-width window = disabled

   if(iNoTradeStart < iNoTradeEnd)
      return (hour >= iNoTradeStart && hour < iNoTradeEnd);
   else
      // window wraps past midnight, e.g. 22 -> 2
      return (hour >= iNoTradeStart || hour < iNoTradeEnd);
  }
*/

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
      return (hour >= iTradeStart && hour <= iTradeEnd);
   else
      // window wraps past midnight, e.g. 22 -> 2
      return (hour >= iTradeStart || hour <= iTradeEnd);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetLotSize(int iStart, int iEnd)
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);

   int hour = dt.hour + (InpTargetGMTOffset - InpBrokerGMTOffset);
   hour = ((hour % 24) + 24) % 24;

   if(iStart == iEnd)
      return lotSize; // just return default lot size

   if(iStart < iEnd)
     {
      if(hour >= iStart && hour < iEnd)
         return multiplierDiffLotSize * lotSize;
     }
   else
      if(hour >= iStart || hour < iEnd)
         return multiplierDiffLotSize * lotSize;

   return lotSize;

  }

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

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

/* initial parameter */
input int ema9 = 9;                    // Fast EMA (9)
input int ema21 = 21;                  // Slow EMA (21)
input int emaLong = 50;                // Additional Filter EMA(50 min)
input bool includeEMAFilter = false;
input int hourBeforeClosing = 22;      //Friday No Trade After N Hour

input double lotSize = 0.01;           // Initial Lot Size
int trailingStopPoints = 500;

input double tp5 = 4.0;                // Minimum Secure Profit
input double trail50 = 50.0;           // Trailing Stop (50%)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double tp15 = 8.0;              // Secure Profit (15)
input double trail65 = 70.0;           // Trailing Stop (65%)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double tp25 = 25.0;              // Secure Profit (25)
input double trail75 = 75.0;           // Trailing Stop (75%)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double tp35 = 35.0;              // Secure Profit (35)
input double trailfix = 80;            // Trailing Stop Max(80%)

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
input int    InpNoTradeStartHour = 14;            // Asian/London No-Trade Window Start Hour (in Target GMT Offset below)
input int    InpNoTradeEndHour   = 14;            // Asian/London No-Trade Window End Hour (in Target GMT Offset

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input int    InpNoTradeStartHourNY = 14;          // NY No-Trade Window Start Hour (in Target GMT Offset below)
input int    InpNoTradeEndHourNY   = 14;          // NY No-Trade Window End Hour (in Target GMT Offset

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input int    InpTargetGMTOffset  = 8;             // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;             // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)

input int InpLotSizeDiffStartHour = 4;            // Start Hour Increment Lot Size
input int InpLotSizeDiffEndHour = 10;              // End Hour Increment Lot Size
input double multiplierDiffLotSize = 2.0;          // Increment Lot Size Multiplier

input ulong magicNumber = 3197230;  //Random Magic Number/Key

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
   
   if (IsFridayLastNHours())
   {
      if (HasOpenPositionByMagic())
      {
         CloseAllPositions();
      }
      return;
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
   bool isBuyBias = fastEMA[0] > longEMA[0];
   bool isSellBias = longEMA[0] > slowEMA[0];
  
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

      if(IsInNoTradeWindow(InpNoTradeStartHour, InpNoTradeEndHour))
         return;


      if(IsInNoTradeWindow(InpNoTradeStartHourNY, InpNoTradeEndHourNY))
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

      if(IsInNoTradeWindow(InpNoTradeStartHour, InpNoTradeEndHour))
         return;

      if(IsInNoTradeWindow(InpNoTradeStartHourNY, InpNoTradeEndHourNY))
         return;
      
      if (isBuyBias)
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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
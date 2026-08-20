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


//--- input parameters (Indicator)
input group "=== STRATEGY INDICATOR ==="
input int emaSlow=9;              //Slow EMA
input int emaFast=21;             //Fast EMA

input group "=== ADDITIONAL FILTER INDICATOR ==="
//add on filter for consideration
input bool includeEMAFilter = false;   // Consider Filter?
input int emaLong = 50;                // Additional Filter EMA(50 min)
input int rangeFilter = 20;      //Range/Zone +/- for Filter

input group "=== TRADING SETTINGS ==="
input double lotSize = 0.1;           // Initial Lot Size
input int roundSize = 1;              // Round off
input string multiplierList = "2,1.9,1.8,1.7,1.6,1.5,1.4,1.3,1.2,1";         //Multiplier List
input bool isContinous = false; // Continue Trading if Secure Profit Hit?
input ulong magicNumber = 2047913;  //Random Magic Number/Key

input group "=== RISK MANAGEMENT ==="
input double tpMin = 2.0;                  //Minimum Profit
input double tpValueA = 5;                 //First Trailing Profit
input double tpValueB = 10;                //Second Trailing Profit
input double tpValueC = 15;                //Max Trailing Profit

// create 3 trailing percentage based on profit
input double trailPercentA = 50;                   //First Trailing Percentage
input double trailPercentB = 75;                   //Second Trailing Percentage
input double trailPercentC = 80;                   //Max Trailing Percentage


input group "=== TRADING HOUR ==="
input int    InpNoTradeStartHour = 19;            // Asian/London No-Trade Start Hour (in Target GMT Offset below)
input int    InpNoTradeEndHour   = 6;            // Asian/London No-Trade End Hour (in Target GMT Offset
input int    InpNoTradeStartHourNY = 19;          // NY No-Trade Start Hour (in Target GMT Offset below)
input int    InpNoTradeEndHourNY   = 6;          // NY No-Trade End Hour (in Target GMT Offset
input int    InpTargetGMTOffset  = 8;             // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;             // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)

input int hourBeforeClosing = 22;      //Friday No Trade After N Hour
input bool isForceCloseFriday = false;



// Indicator Handles
int ema9Handle;
int ema21Handle;
int emaLongHandle;

datetime lastBarTime = 0;

int positionCounter = 0;
int lenMultiplier = 0;
double arrMultiplier[];
double lastMultiplier;
double currentLotSize = 0;
int maxPosition = 0;

double maxMargin = 0;

enum CurrentPosition
  {
   C_None,
   C_Buy,
   C_Sell
  };
CurrentPosition activePosition = C_None;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   ema9Handle = iMA(_Symbol, PERIOD_CURRENT, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
   ema21Handle = iMA(_Symbol, PERIOD_CURRENT, emaFast, 0, MODE_EMA, PRICE_CLOSE);
   emaLongHandle = iMA(_Symbol, PERIOD_CURRENT, emaLong, 0, MODE_EMA, PRICE_CLOSE);

   if(ema9Handle == INVALID_HANDLE || ema21Handle == INVALID_HANDLE || emaLongHandle == INVALID_HANDLE)
     {
      Print("Failed to create EMA handles");
      return(INIT_FAILED);
     }

   string values[];
   int lenMultiplier = StringSplit(multiplierList, ',', values);

   ArrayResize(arrMultiplier, lenMultiplier);

   for(int i=0; i<lenMultiplier; i++)
      arrMultiplier[i] = StringToDouble(values[i]);

   lastMultiplier = arrMultiplier[lenMultiplier-1];

   Print("EMABOT: Last Mutliplier :" + lastMultiplier);

   Print("Local Time : ", TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   Print("GMT Time   : ", TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
   Print("Server Time: ", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   
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
void ManageTrailingStop()
  {
   if(!HasOpenPositionByMagic())
      return;

   if(positionCounter > 1)
     {
      if(GetTotalProfitByMagic() > tpMin)
        {
         CloseAllPositions();

         // reset position to 1
         if(IsInNoTradeWindow(InpNoTradeStartHour, InpNoTradeEndHour))
            return;

         if(IsInNoTradeWindow(InpNoTradeStartHourNY, InpNoTradeEndHourNY))
            return;

         if(activePosition == C_Buy)
           {
            if(trade.Buy(lotSize, _Symbol))
              {
               Print("EMABOT: Reset position BUY");
              }
           }
         else
           {
            if(trade.Sell(lotSize, _Symbol))
              {
               Print("EMABOT: Reset position SELL");
              }
           }

         positionCounter = 1;
         currentLotSize = lotSize;
        }
      return;
     }
   
   long type = PositionGetInteger(POSITION_TYPE);
   ulong ticket = PositionGetInteger(POSITION_TICKET);

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
  

//continous
bool GetEmaCrossC(bool &bullishCross, bool &bearishCross, bool &buyBias, bool &sellBias)
  {
   bullishCross = false;
   bearishCross = false;
   buyBias = true;
   sellBias = true;
   
   double fastEMA[3];
   double slowEMA[3];
   double longEMA[3];

   if(CopyBuffer(ema9Handle, 0, 0, 3, fastEMA) < 0)
      return false;

   if(CopyBuffer(ema21Handle, 0, 0, 3, slowEMA) < 0)
      return false;

   if(CopyBuffer(emaLongHandle, 0, 0, 3, longEMA) < 0)
      return false;

   bullishCross = fastEMA[0] > slowEMA[0];

   bearishCross = fastEMA[0] < slowEMA[0];
   
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if (bullishCross)
   {
      buyBias = askPrice - longEMA[0] < rangeFilter && askPrice > longEMA[0]; 
   }
   if (bearishCross)
   {

      sellBias = longEMA[0] - bidPrice < rangeFilter && bidPrice < longEMA[0];
   }
   
    /*** log mode***/
   Print("-----------------------------");
   Print("BuySignal: " + bullishCross);
   Print("sellSignal: " + bearishCross);
   Print("isBuyBias: " + buyBias);
   Print("isSellBias: " + sellBias);
   PrintFormat("buyPrice=%.2f | sellPrice=%.2f | LongEMA=%.2f", askPrice, bidPrice, longEMA[0]);
   Print("-----------------------------");
      
   
   if (!includeEMAFilter)
   {
      buyBias = true;
      sellBias = true;
   }
   
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckForSignal()
  {

   bool buySignal = false;
   bool sellSignal = false;
   bool isBuyBias = true;
   bool isSellBias = true;
   double usedMargin = 0;
   
   if(!GetEmaCrossC(buySignal, sellSignal, isBuyBias, isSellBias))
      return;

   double positionLotSize = lotSize;
   
   // if hit by secure profit double check activePosition
   /*if (positionCounter == 1 && !PositionSelect(_Symbol))
   {
         activePosition = C_None;
   }*/
   bool hasPosition = HasOpenPositionByMagic();
   
   if (isContinous && !hasPosition)
   {
      activePosition = C_None;
   }
   
   Print("------------");
   Print ("Has Position: " + hasPosition);
   Print("Active Position: " + activePosition);
   Print("BuySignal: " + buySignal);
   Print("BuyBias: " + isBuyBias);
   Print("SellSignal: " + sellSignal);
   Print("SellBias: " + isSellBias);
   Print("------------");
   // BUY Signal
   if(buySignal && activePosition != C_Buy && isBuyBias)
     {
      if(hasPosition)
        {
         Print("EMABOT: Have existing Position(sell...)");
         positionLotSize = GetLotSize();
        }

      if(positionLotSize == lotSize)
      {
         
         positionCounter = 0;
         
         if(IsInNoTradeWindow(InpNoTradeStartHour, InpNoTradeEndHour))
            return;


         if(IsInNoTradeWindow(InpNoTradeStartHourNY, InpNoTradeEndHourNY))
            return;
      }
      
      
      bool tbuy = trade.Buy(positionLotSize, _Symbol);
        
      Print("EMABOT:Buy Position: " + positionLotSize);

      currentLotSize = positionLotSize;
      positionCounter++;

      activePosition = C_Buy;

      Print("EMABOT:Increase Position Counter: " + positionCounter);
        
     }

   // SELL Signal
   if(sellSignal && activePosition != C_Sell && isSellBias)
     {

      if(hasPosition)
        {
         Print("EMABOT: Have existing Position(buy...)");
         positionLotSize = GetLotSize();
        }

      if(positionLotSize == lotSize)
        {
         positionCounter = 0;

         if(IsInNoTradeWindow(InpNoTradeStartHour, InpNoTradeEndHour))
            return;


         if(IsInNoTradeWindow(InpNoTradeStartHourNY, InpNoTradeEndHourNY))
            return;
        }

      bool tsell = trade.Sell(positionLotSize, _Symbol);
        
      Print("EMABOT:Sell Position: " + positionLotSize);

      currentLotSize = positionLotSize;
      positionCounter++;
      activePosition = C_Sell;

      Print("EMABOT:Increase Position Counter: " + positionCounter);
     
     }
   
   if(positionCounter > maxPosition)
     {
      maxPosition = positionCounter;
      Print("EMABOT M: New Max Position: " + maxPosition);
      
      usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
      
      if (usedMargin > maxMargin)
      {
         maxMargin = usedMargin;
         Print("EMABOT M: Max Margin: " + maxMargin);
      }
     }
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool GetEmaCross(bool &bullishCross, bool &bearishCross)
  {

   bullishCross = false;
   bearishCross = false;

   if(ema9Handle == INVALID_HANDLE || ema21Handle == INVALID_HANDLE)
      return false;


   double f[3], s[3];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);

   if(CopyBuffer(ema9Handle, 0, 1, 3, f) < 3)
      return false;

   if(CopyBuffer(ema21Handle, 0, 1, 3, s) < 3)
      return false;



   double fastCurrent = f[0];
   double fastPrev    = f[1];
   double slowCurrent = s[0];
   double slowPrev    = s[1];


   bullishCross = (fastCurrent > slowCurrent) && (fastPrev <= slowPrev);
   bearishCross = (fastCurrent < slowCurrent) && (fastPrev >= slowPrev);

   return true;

  }

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
//|                                                                  |
//+------------------------------------------------------------------+
double GetTotalProfit()
  {
   double totalProfit = 0.0;

   int totalPositions = CountPositionsByMagic();

   for(int i = 0; i < totalPositions; i++)
     {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
        {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
        }
     }

   return totalProfit;
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
double GetLotSize()
  {
   double dLotSize = lotSize;
   double multiplier = lastMultiplier;
   double currentPnL = 0;

   if(positionCounter > 0)
     {
      currentPnL = GetTotalProfitByMagic();
      // close if positive position
      if(currentPnL > 0)
        {
         CloseAllPositions();

         dLotSize = lotSize;
         positionCounter = 0;

         Print("EMABOT:Close Position, remaining counter: " + positionCounter);
        }

      else
        {
         if(positionCounter <= ArraySize(arrMultiplier))
           {
            multiplier =  arrMultiplier[positionCounter-1];
            Print("EMABOT:Position Counter: " + positionCounter);
            Print("EMABOT:Position Multiplier: " + multiplier);

            dLotSize = NormalizeDouble(currentLotSize * multiplier, roundSize);
           }
         else
           {
            multiplier = lastMultiplier;
            dLotSize = NormalizeDouble(currentLotSize * multiplier, roundSize);

           }
         Print("EMABOT R: Current Running PnL: " + currentPnL);
        }
     }
   Print("Position Lot Size: " + dLotSize);
   return dLotSize;
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
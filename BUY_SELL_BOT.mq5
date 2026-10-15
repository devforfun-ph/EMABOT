#include <Trade/Trade.mqh>
CTrade trade;

enum PositionDirection
{
   BUY_LONG,
   SELL_SHORT
};
input group "=== Version: 13 Oct 2026  ==="
input group "=== TRADING SETTINGS ==="
input double lotSize = 0.1;           // Initial Lot Size
input ulong magicNumber = 1;  //Random Magic Number/Key

input group "==== EMA ENTRY STRATEGY ===="
input bool useEMA = false;                      // Use EMA on Cross
input int emaSlow=9;                            //Slow EMA
input int emaFast=21;                           //Fast EMA
input ENUM_TIMEFRAMES EMAPeriod = PERIOD_H4;    // EMA Period
input bool includeEMAFilter = false;            // Consider Filter?
input int emaLong = 100;                        // Additional Filter EMA(50 min)
input int rangeFilter = 5;                      //Range/Zone +/- for Filter
input bool closeOnCross = false;                // Close on Cross

// Indicator Handles 
int ema9Handle;
int ema21Handle;
int emaLongHandle;


input group "=== TRADING STRATEGY ==="
input double dcaLotSize = 0.1;                     //DCA Cover
input double lossThreshold = 50;                   //Loss Threshold
input PositionDirection pDirection = SELL_SHORT;   //Position Direction
input double priceThreshold = 0;                   // Price Threshold (if buy below price else above price)


input group "=== DCA Setting ==="
input bool useDefineDCA = false;    //Use Define DCA
input double dcaLotSize1 = 0.02;    //DCA Cover 1
input double dcaLotSize2 = 0.03;    //DCA Cover 2
input double dcaLotSize3 = 0.04;    //DCA Cover 3
input double dcaLotSize4 = 0.05;    //DCA Cover 4
input double dcaLotSize5 = 0.06;    //DCA Cover 5   


input double lossThreshold1 = 10;   //Loss Threshold 1
input double lossThreshold2 = 20;   //Loss Threshold 2
input double lossThreshold3 = 30;   //Loss Threshold 3
input double lossThreshold4 = 40;   //Loss Threshold 4
input double lossThreshold5 = 50;   //Loss Threshold 5


input group "=== RISK MANAGEMENT ==="
input double tpMin = 2.0;                  //Minimum Profit
input double tpValueA = 5;                 //First Trailing Profit
input double tpValueB = 10;                //Second Trailing Profit
input double tpValueC = 15;                //Max Trailing Profit

// create 3 trailing percentage based on profit
input double trailPercentA = 55;                   //First Trailing Percentage
input double trailPercentB = 65;                   //Second Trailing Percentage
input double trailPercentC = 75;                   //Max Trailing Percentage

datetime lastBarTime = 0;
int positionCounter = 0;
string currentSymbol = "NONE";
bool isIndex = false;

double g_newDCALotSize = 0.01;
double g_negativeProfit = 10;


int OnInit()
{  
   if (currentSymbol == "NONE")
   {   
      currentSymbol = Symbol();
      
      StringToUpper(currentSymbol);
      
      if (currentSymbol == "US100" || currentSymbol == "US500")
         isIndex = true;
     
      Print("Symbols: ", currentSymbol, " | IsIndex: ", isIndex);
       
   }
   
   if (useEMA)
   {
      ema9Handle = iMA(_Symbol, EMAPeriod, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
      ema21Handle = iMA(_Symbol, EMAPeriod, emaFast, 0, MODE_EMA, PRICE_CLOSE);
      emaLongHandle = iMA(_Symbol, EMAPeriod, emaLong, 0, MODE_EMA, PRICE_CLOSE);
   
      if(ema9Handle == INVALID_HANDLE || ema21Handle == INVALID_HANDLE || emaLongHandle == INVALID_HANDLE)
        {
         LogMessage("Failed to create EMA handles");
         return(INIT_FAILED);
        }  
   }
   
   trade.SetExpertMagicNumber(magicNumber);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if (useEMA)
   {
      IndicatorRelease(ema9Handle);
      IndicatorRelease(ema21Handle);
      IndicatorRelease(emaLongHandle);
   }
  }


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
  

void SetDCACover()
{
   g_negativeProfit = lossThreshold;
   g_newDCALotSize = dcaLotSize;
   
   if (useDefineDCA)
   {
      int countPosition = CountPositionsByMagic();
      switch(countPosition)
      {
         case 1:
            g_negativeProfit = lossThreshold1;
            g_newDCALotSize = dcaLotSize1;
            break;
         case 2:
            g_negativeProfit = lossThreshold2;
            g_newDCALotSize = dcaLotSize2;
            break;
         case 3:
            g_negativeProfit = lossThreshold3;
            g_newDCALotSize = dcaLotSize3;
            break;
         case 4:
            g_negativeProfit = lossThreshold4;
            g_newDCALotSize = dcaLotSize4;
            break;
         default:
            g_negativeProfit = lossThreshold5;
            g_newDCALotSize = dcaLotSize5;
            break;
            
      }
   }
   
   g_negativeProfit = g_negativeProfit * -1;
}

bool AddDCA()
{
   double profit = 0.0;
   bool isLatestLossThreshold = true;
   
   SetDCACover();
   
   int ctr = 0;
   string logProfit = "= ";
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
      {
         profit = PositionGetDouble(POSITION_PROFIT);       
         ctr++;
         logProfit = logProfit + profit + ", =";
         if (profit >= g_negativeProfit)
         {
            isLatestLossThreshold = false;
         }
      }
   }
   
   if (isLatestLossThreshold)
   {
      if (pDirection == BUY_LONG)
         bool tbuy = trade.Buy(g_newDCALotSize, _Symbol);  
      else
         bool tsell = trade.Sell(g_newDCALotSize, _Symbol); 
         
      LogMessage("Created DCA Position at Price: " + trade.ResultPrice() + "| Last Profit Detected: "  + logProfit);
      
      return true;
   }
   return false;
   
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


void ManageTrailingStop()
  {
   if(!HasOpenPositionByMagic())
      return;
      
   positionCounter = CountPositionsByMagic();
   double profitByMagic = GetTotalProfitByMagic();
   
   if(positionCounter > 1)
     {
      if(profitByMagic > tpMin)
        {
         CloseAllPositions();

         if(pDirection == BUY_LONG)
           {
            if(trade.Buy(lotSize, _Symbol))
              {
               LogMessage("Reset position BUY");
              }
           }
         else
           {
            if(trade.Sell(lotSize, _Symbol))
              {
               LogMessage("Reset position SELL");
              }
           }

         positionCounter = 1;
        }
       else
       {
         AddDCA();
       }
      return;
     }
    
   if (profitByMagic < tpMin)
   {
       if (AddDCA())
         {
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
         
         if (isIndex)
            priceDistance = profitToGiveBack / volume;
         
            
        // LogMessage ("Magic Number:" + magicNumber + " Profit:"+ currentProfit+ " TV: "+ tickValue + " Vol: " +
        //    volume + " TS: " + tickSize + " profitToGiveBack: " + profitToGiveBack + " priceDistance: " + priceDistance);
         
         
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
  
  void CheckEntry()
  {
   
   if(HasOpenPositionByMagic())
      return;
  
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if (useEMA)
   {
      if (!AllowEntryByEMA())
         return;
   }
   
   if (pDirection == SELL_SHORT && bidPrice > priceThreshold)
   {
      trade.Sell(lotSize, _Symbol);
   }
   else if (pDirection == BUY_LONG && askPrice < priceThreshold)
   {
      trade.Buy(lotSize, _Symbol);
   }
  }
  
  
  void OnTick()
  {
      ManageTrailingStop();
      if(IsNewBar())
        {
         CheckEntry();
        }
  }
  
  
  bool AllowEntryByEMA()
  {
      bool buySignal = false;
      bool sellSignal = false;
      bool isBuyBias = true;
      bool isSellBias = true;
      bool inRange = false;

      if(!GetEmaCross(buySignal, sellSignal, isBuyBias, isSellBias, inRange))
         return false;
   
      
      if(buySignal && pDirection == BUY_LONG && isBuyBias)
      {
         if (!inRange)
            return false;
         
         return true;
      }
      
      if(sellSignal && pDirection == SELL_SHORT && isSellBias)
      {
         if (!inRange)
            return false;
         
         return true;
      }
      
      return false;
  }
  
  
  
  bool GetEmaCross(bool &bullishCross, bool &bearishCross, bool &buyBias, bool &sellBias, bool &inRange)
  {
   bullishCross = false;
   bearishCross = false;
   buyBias = true;
   sellBias = true;
   inRange = false;
   
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
      buyBias = askPrice > longEMA[0]; 
      inRange = askPrice - longEMA[0] < rangeFilter;
   }
   if (bearishCross)
   {

      sellBias = bidPrice < longEMA[0];
      inRange = longEMA[0] - bidPrice < rangeFilter;
   }
   
   if (pDirection == BUY_LONG)
      {
         LogMessage("Buy Signal: " + bullishCross + "| Buy Bias: " + buyBias + "| InRange: " + inRange);
      }
   else
      {
         LogMessage("Sell Signal: " + bearishCross + "| Sell Bias: " + sellBias + "| InRange: " + inRange);   
      }
   
   if (!includeEMAFilter)
   {
      buyBias = true;
      sellBias = true;
      inRange = true;
   }
   
   return true;
  }

  void LogMessage(string msg)
  {
   Print("-----------------------------");
   Print("BOT: ", msg);
   Print("-----------------------------");
  }

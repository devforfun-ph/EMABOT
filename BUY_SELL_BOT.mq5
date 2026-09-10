#include <Trade/Trade.mqh>
CTrade trade;

enum PositionDirection
{
   BUY_LONG,
   SELL_SHORT
};

input group "=== TRADING SETTINGS ==="
input double lotSize = 0.1;           // Initial Lot Size
input ulong magicNumber = 126301;  //Random Magic Number/Key

input group "=== TRADING STRATEGY ==="
input double dcaLotSize = 0.1;      //DCA Cover
input double lossThreashold = 50;   //Loss Threshold
input PositionDirection pDirection = SELL_SHORT;  //Position Direction
input double priceThreshold = 0;    // Price Threshold (if buy below price else above price)

input group "=== RISK MANAGEMENT ==="
input double tpMin = 2.0;                  //Minimum Profit
input double tpValueA = 5;                 //First Trailing Profit
input double tpValueB = 10;                //Second Trailing Profit
input double tpValueC = 15;                //Max Trailing Profit

// create 3 trailing percentage based on profit
input double trailPercentA = 50;                   //First Trailing Percentage
input double trailPercentB = 75;                   //Second Trailing Percentage
input double trailPercentC = 80;                   //Max Trailing Percentage

datetime lastBarTime = 0;
int positionCounter = 0;
string currentSymbol = "NONE";
bool isIndex = false;
bool isJPY = false;

int OnInit()
{  
   if (currentSymbol == "NONE")
   {   
      currentSymbol = Symbol();
      
      StringToUpper(currentSymbol);
      
      if (currentSymbol == "US100" || currentSymbol == "US500")
         isIndex = true;
     
      if(StringFind(currentSymbol, "JPY") >= 0)
         isJPY = true;
         
      Print("Symbols: ", currentSymbol, " | IsIndex: ", isIndex);
       
   }
   trade.SetExpertMagicNumber(magicNumber);
   
   return(INIT_SUCCEEDED);
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
  
bool AddDCA()
{
   double profit = 0.0;
   bool isLatestLossThreshold = true;
   double lossProfit = lossThreashold * -1;
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
         if (profit >= lossProfit)
         {
            isLatestLossThreshold = false;
         }
      }
   }
   
   if (isLatestLossThreshold)
   {
      if (pDirection == BUY_LONG)
         bool tbuy = trade.Buy(dcaLotSize, _Symbol);  
      else
         bool tsell = trade.Sell(dcaLotSize, _Symbol); 
         
      Print("LOG: Created DCA Position at Price: ", trade.ResultPrice(), "| Last Profit Detected: ", logProfit);
      
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
         

            
         Print ("Magic Number:", magicNumber, " Profit:", currentProfit, " TV: ", tickValue, " Vol: ", volume, " TS: ", tickSize, " profitToGiveBack: ", profitToGiveBack, " priceDistance: ", priceDistance);
         
         
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

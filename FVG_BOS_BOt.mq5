/*
1. Find Swing High/Low
2. Detect BOS
3. When BOS Confirmed, Find FVG
4. WHen FVG Cofirmed, wait for retracement
5. Price enters FVG Zone, (Buy mode only)
*/

#include <Trade/Trade.mqh>
CTrade trade;

//Input Parameters

input group "=== TRADING SETTINGS ==="
input double lotSize = 0.2;               // Initial Lot Size
input ulong magicNumber = 98765;          //Random Magic Number/Key

input group "=== DCA SETTINGS ==="
input double addLotSize = 0.1;              // DCA Cover 
input bool useLotSize = false;                    // Use DCA Setting Lot Size
input double lostProfitThreshold = 50;     // Profit Threshold


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
input int    InpStartHourShift1 = 1;               //Shift 1 - Start Hour
input int    InpEndHourShift1 = 1;                 //Shift 1 - End Hour
input int    InpStartHourShift2 = 1;               //Shift 2 - Start Hour
input int    InpEndHourShift2 = 1;                 //Shift 2 - End Hour
input int    InpStartHourShift3 = 1;               //Shift 3 - Start Hour
input int    InpEndHourShift3 = 1;                 //Shift 3 - End Hour

input int    InpTargetGMTOffset  = 8;             // Target Timezone GMT Offset (e.g. 8 = GMT+8)
input int    InpBrokerGMTOffset  = 3;             // Broker Server GMT Offset (yours = GMT+3, confirmed from server clock; may shift ±1hr with DST)


//+------------------------------------------------------------------+
//| FVG + BOS Detection Module                                      |
//+------------------------------------------------------------------+
input group "==== FVG SETTING ==="
input ENUM_TIMEFRAMES StructureTF = PERIOD_M15; //TF Structure
input int SwingStrength = 2;                    //Candle (min 2)
input int LookbackBars  = 100;                  //Lookback Bars
input double MinFVGPoints = 100;                //Min FVG Gap Price
input bool DrawBOS = true;                      //Check BOS
input bool withRetracement = true;              //With Retracement
//-------------------------------------------------------------------
// Market structure
//-------------------------------------------------------------------

double LastSwingHigh = 0;
double LastSwingLow  = 0;
datetime LastSwingHighTime = 0;
datetime LastSwingLowTime  = 0;
//-------------------------------------------------------------------
// FVG
//-------------------------------------------------------------------
struct FVGData
{
   bool     valid;
   bool     bullish;

   double   high;
   double   low;

   datetime time;
};
FVGData CurrentFVG;

//-------------------------------------------------------------------
// BOS
//-------------------------------------------------------------------
bool BullishBOSDetected = false;
bool BearishBOSDetected = false;
datetime LastBOSTime = 0;


enum SetupState
{
   SETUP_NONE,
   WAIT_FVG_BULLISH,
   WAIT_FVG_BEARISH,
   WAIT_RETRACEMENT_BULLISH,
   WAIT_RETRACEMENT_BEARISH
};

SetupState CurrentSetup = SETUP_NONE;

double FVG_High = 0.0;
double FVG_Low  = 0.0;

datetime BOS_Time = 0;
datetime FVG_Time = 0;

bool EntryTriggered = false;

//+------------------------------------------------------------------+
//| Check Swing High                                                 |
//+------------------------------------------------------------------+

bool IsSwingHigh(MqlRates &rates[], int index, int strength)
{
   for(int i = 1; i <= strength; i++)
   {
      if(rates[index].high <= rates[index-i].high)
         return false;

      if(rates[index].high <= rates[index+i].high)
         return false;
   }

   return true;
}


//+------------------------------------------------------------------+
//| Check Swing Low                                                  |
//+------------------------------------------------------------------+

bool IsSwingLow(MqlRates &rates[], int index, int strength)
{
   for(int i = 1; i <= strength; i++)
   {
      if(rates[index].low >= rates[index-i].low)
         return false;

      if(rates[index].low >= rates[index+i].low)
         return false;
   }

   return true;
}


//+------------------------------------------------------------------+
//| Find latest swing structure                                      |
//+------------------------------------------------------------------+

void FindMarketStructure()
{
   MqlRates rates[];

   int barsNeeded = LookbackBars + SwingStrength + 10;

   ArraySetAsSeries(rates, false);

   int copied = CopyRates(
      _Symbol,
      StructureTF,
      0,
      barsNeeded,
      rates
   );

   if(copied <= SwingStrength * 2)
      return;


   // Search from newest to oldest
   for(int i = copied - SwingStrength - 1;
       i >= SwingStrength;
       i--)
   {
      if(LastSwingHigh == 0 &&
         IsSwingHigh(rates, i, SwingStrength))
      {
         LastSwingHigh     = rates[i].high;
         LastSwingHighTime = rates[i].time;
      }


      if(LastSwingLow == 0 &&
         IsSwingLow(rates, i, SwingStrength))
      {
         LastSwingLow     = rates[i].low;
         LastSwingLowTime = rates[i].time;
      }


      if(LastSwingHigh != 0 &&
         LastSwingLow != 0)
      {
         break;
      }
   }
}


bool FindBullishFVG(FVGData &fvg)
{
   MqlRates rates[];

   ArraySetAsSeries(rates, false);

   if(CopyRates(
      _Symbol,
      StructureTF,
      1,
      3,
      rates) != 3)
   {
      return false;
   }


   // rates[0] = oldest
   // rates[1] = middle
   // rates[2] = newest


   // Bullish FVG:
   //
   // Candle 3 High
   //       |
   //       |       FVG
   //       |<------------>
   //       |
   // Candle 1 Low
   //
   // Newest candle low > oldest candle high

   if(rates[2].low > rates[0].high)
   {
      double gapSize =
         rates[2].low - rates[0].high;

      if(gapSize >= MinFVGPoints * _Point)
      {
         fvg.valid   = true;
         fvg.bullish = true;

         fvg.high = rates[2].low;
         fvg.low  = rates[0].high;

         fvg.time = rates[1].time;

         return true;
      }
   }

   return false;
}


//+------------------------------------------------------------------+
//| Detect Bearish FVG                                                |
//+------------------------------------------------------------------+

bool FindBearishFVG(FVGData &fvg)
{
   MqlRates rates[];

   ArraySetAsSeries(rates, false);

   if(CopyRates(
      _Symbol,
      StructureTF,
      1,
      3,
      rates) != 3)
   {
      return false;
   }


   // Bearish FVG:
   //
   // Newest candle high < oldest candle low

   if(rates[2].high < rates[0].low)
   {
      double gapSize =
         rates[0].low - rates[2].high;

      if(gapSize >= MinFVGPoints * _Point)
      {
         fvg.valid   = true;
         fvg.bullish = false;

         fvg.high = rates[0].low;
         fvg.low  = rates[2].high;

         fvg.time = rates[1].time;

         return true;
      }
   }

   return false;
}


//+------------------------------------------------------------------+
//| Check if price entered FVG                                       |
//+------------------------------------------------------------------+

bool PriceEnteredFVG()
{
   if(!CurrentFVG.valid)
      return false;


   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );


   // ---------------------------------------------------------------
   // Bullish FVG
   // ---------------------------------------------------------------

   if(CurrentFVG.bullish)
   {
      if(bid >= CurrentFVG.low &&
         bid <= CurrentFVG.high)
      {
         return true;
      }
   }


   // ---------------------------------------------------------------
   // Bearish FVG
   // ---------------------------------------------------------------

   if(!CurrentFVG.bullish)
   {
      if(ask >= CurrentFVG.low &&
         ask <= CurrentFVG.high)
      {
         return true;
      }
   }


   return false;
}


//+------------------------------------------------------------------+
//| Process FVG after BOS                                            |
//+------------------------------------------------------------------+

void CheckBOS()
{
   MqlRates rates[2];

   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, StructureTF, 0, 2, rates) != 2)
      return;

   // rates[0] = current candle
   // rates[1] = last CLOSED candle

   MqlRates candle = rates[1];

   // ------------------------------------------------------------
   // Bullish BOS
   // ------------------------------------------------------------

   if(LastSwingHigh > 0 &&
      candle.close > LastSwingHigh &&
      candle.time > LastSwingHighTime)
   {
      CurrentSetup = WAIT_FVG_BULLISH;

      BOS_Time = candle.time;

      FVG_High = 0;
      FVG_Low  = 0;

      EntryTriggered = false;

      //Print("BULLISH BOS"," | Close=", candle.close," | Broken High=", LastSwingHigh);

      return;
   }


   // ------------------------------------------------------------
   // Bearish BOS
   // ------------------------------------------------------------

   if(LastSwingLow > 0 &&
      candle.close < LastSwingLow &&
      candle.time > LastSwingLowTime)
   {
      CurrentSetup = WAIT_FVG_BEARISH;

      BOS_Time = candle.time;

      FVG_High = 0;
      FVG_Low  = 0;

      EntryTriggered = false;

      //Print("BEARISH BOS"," | Close=", candle.close," | Broken Low=", LastSwingLow);

      return;
   }
}


bool FindBullishFVGAfterBOS()
{
   MqlRates rates[3];

   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, StructureTF, 1, 3, rates) != 3)
      return false;

   // rates[0] = most recent CLOSED candle
   // rates[1] = middle candle
   // rates[2] = oldest candle

   if (DrawBOS)
      // FVG must occur after BOS
      if(rates[1].time <= BOS_Time)
         return false;


   // Bullish FVG
   //
   // Old candle HIGH
   //        |
   //        |<---- FVG ---->
   //        |
   // New candle LOW
   //
   // newest LOW > oldest HIGH

   if(rates[0].low > rates[2].high)
   {
      double gapSize =
         rates[0].low - rates[2].high;

      if(gapSize < MinFVGPoints * _Point)
         return false;


      FVG_High = rates[0].low;
      FVG_Low  = rates[2].high;

      FVG_Time = rates[1].time;

      //Print("BULLISH FVG detected"," | High=", FVG_High," | Low=", FVG_Low);

      return true;
   }

   return false;
}

bool FindBearishFVGAfterBOS()
{
   MqlRates rates[3];

   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, StructureTF, 1, 3, rates) != 3)
      return false;


   if(rates[1].time <= BOS_Time)
      return false;


   // Bearish FVG
   //
   // newest HIGH < oldest LOW

   if(rates[0].high < rates[2].low)
   {
      double gapSize =
         rates[2].low - rates[0].high;

      if(gapSize < MinFVGPoints * _Point)
         return false;


      FVG_High = rates[2].low;
      FVG_Low  = rates[0].high;

      FVG_Time = rates[1].time;

      //Print("BEARISH FVG detected"," | High=", FVG_High," | Low=", FVG_Low);

      return true;
   }

   return false;
}

void ProcessSetup()
{
   // ------------------------------------------------------------
   // BOS → WAIT FOR BULLISH FVG
   // ------------------------------------------------------------
   if (DrawBOS)
   {
      if(CurrentSetup == SETUP_NONE)
      {
         if(FindBullishFVGAfterBOS())
         {
            CurrentSetup = WAIT_RETRACEMENT_BULLISH;
   
            Print("BULLISH FVG confirmed."," Waiting for retracement.");
         }
      }
   }
   else
   {
      if(CurrentSetup == SETUP_NONE)
      {
         if(FindBullishFVGAfterBOS())
         {
            CurrentSetup = WAIT_RETRACEMENT_BULLISH;
   
            Print("BULLISH FVG confirmed."," Waiting for retracement.");
         }
      }
   }

}

bool PriceRetracedIntoFVG()
{
   if(FVG_High <= 0 || FVG_Low <= 0)
      return false;


   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );


   // ------------------------------------------------------------
   // Bullish FVG
   // ------------------------------------------------------------

   if(CurrentSetup == WAIT_RETRACEMENT_BULLISH)
   {
      if(bid >= FVG_Low &&
         bid <= FVG_High)
      {
         return true;
      }
   }


   // ------------------------------------------------------------
   // Bearish FVG
   // ------------------------------------------------------------

   if(CurrentSetup == WAIT_RETRACEMENT_BEARISH)
   {
      if(ask >= FVG_Low &&
         ask <= FVG_High)
      {
         return true;
      }
   }


   return false;
}


bool IsInTradeSchedule()
{
   //will ignore checking if start and end are equal
   bool isInSched = false;
   
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
  
int OnInit()
  {
   Print("Local Time : ", TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   Print("GMT Time   : ", TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
   Print("Server Time: ", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS));
   
   CurrentFVG.valid = false;

   LastSwingHigh = 0;
   LastSwingLow  = 0;

   FindMarketStructure();
      
   trade.SetExpertMagicNumber(magicNumber);
 
   return(INIT_SUCCEEDED);

  }
  
void CheckEntry()
{
   if(EntryTriggered)
      return;
   
   if (withRetracement)
      if(!PriceRetracedIntoFVG())
         return;

   if(HasOpenPositionByMagic())
      return;
      
   if (!IsInTradeSchedule())
      return;
   // ------------------------------------------------------------
   // BULLISH
   // ------------------------------------------------------------

   if(CurrentSetup == WAIT_RETRACEMENT_BULLISH)
   {

      bool tbuy = trade.Buy(lotSize, _Symbol);
      
      Print("LOG: BUY ENTRY SIGNAL"," | Price retraced into Bullish FVG"," | FVG Low=", FVG_Low," | FVG High=", FVG_High," | Created Price=", trade.ResultPrice());
      
      EntryTriggered = true;

      CurrentSetup = SETUP_NONE;
   }


   // ------------------------------------------------------------
   // BEARISH
   // ------------------------------------------------------------
   return;
   
   //ignore sell
   
   if(CurrentSetup == WAIT_RETRACEMENT_BEARISH)
   {
      Print(
         "SELL ENTRY SIGNAL",
         " | Price retraced into Bearish FVG",
         " | FVG Low=", FVG_Low,
         " | FVG High=", FVG_High
      );


      // =========================================================
      // YOUR trade.Sell() GOES HERE
      // =========================================================

      // Example:
      //
      // trade.Sell(
      //    LotSize,
      //    _Symbol,
      //    0,
      //    StopLoss,
      //    TakeProfit
      // );


      EntryTriggered = true;

      CurrentSetup = SETUP_NONE;
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


void AddNewPosition()
{
   double profit = 0.0;
   bool isLatestLossThreshold = true;
   double lossProfit = lostProfitThreshold * -1;
   int ctr = 0;
   double newLotSize = lotSize;
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
   
      newLotSize = newLotSize * (ctr +1);
      if (useLotSize) 
      {
         newLotSize = addLotSize;
      }
      bool tbuy = trade.Buy(newLotSize, _Symbol);
      
      Print("LOG: Created DCA Position at Price: ", trade.ResultPrice(), "| Last Profit Detected: ", logProfit);
   }
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
 
void ManageTrailingStop()
  {
   if(!HasOpenPositionByMagic())
      return;

   int positionCounter = CountPositionsByMagic();
   
   double totalProfit = GetTotalProfitByMagic();
   
   if (positionCounter > 1 && totalProfit > tpMin)
   {
      // close all position and wait for next entry
      CloseAllPositions();
      bool tbuy = trade.Buy(lotSize, _Symbol);
      Print("LOG: BUY ENTRY SIGNAL FOR BREAKEVEN: ", trade.ResultPrice());
   }
   else if (totalProfit < tpMin)
   {
         AddNewPosition();
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
      
   Print ("TV: ", tickValue, " Vol: ", volume, " TS: ", tickSize, " profitToGiveBack: ", profitToGiveBack, " priceDistance: ", priceDistance);
   
   priceDistance = profitToGiveBack / volume;
   
   Print ("TV: ", tickValue, " Vol: ", volume, " TS: ", tickSize, " profitToGiveBack: ", profitToGiveBack, " priceDistance: ", priceDistance);
   
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
  


void OnTick()
{
   static datetime LastBarTime = 0;

   datetime CurrentBarTime =
      iTime(
         _Symbol,
         StructureTF,
         0
      );


   // ============================================================
   // NEW CANDLE
   // ============================================================

   if(CurrentBarTime != LastBarTime)
   {
      LastBarTime = CurrentBarTime;


      // ---------------------------------------------------------
      // Update market structure
      // ---------------------------------------------------------

      LastSwingHigh = 0;
      LastSwingLow  = 0;

      FindMarketStructure();


      // ---------------------------------------------------------
      // Check BOS
      // ---------------------------------------------------------
      if (DrawBOS)
         CheckBOS();


      // ---------------------------------------------------------
      // BOS → FVG
      // ---------------------------------------------------------

      ProcessSetup();
   }
   
   ManageTrailingStop();

   // ============================================================
   // FVG → RETRACEMENT → ENTRY
   // ============================================================
   
   CheckEntry();
}


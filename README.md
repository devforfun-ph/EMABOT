1. Strategy Indicators
    Fast EMA: 9
    Slow EMA: 21
    Additional Filter (Optional)
    Long EMA: 100
    Range/Zone Difference for Additional Filter: 1000 pips (Gold Setting); choose a range for your preference.
     
2.  Logic
      Entry Position:
      a. With no existing position
          Enter with initial lot size when
          LONG: if Fast EMA > Slow EMA
                Additional filter: AND if ask price >  long EMA and difference of ask price and Long EMA is within range specified
          SHORT: if Slow EMA > Fast EMA
                Additional filter: AND if bid price < long EMA and difference of bid price and Long EMA is within range specified
      b. With existing Position (positive profit)
          If EMA Crosses and current position have a total unrealized pnl is > 0, then close all positions and follow procedure a.
      c. With existing Position (negative profit)
          Based on the multiplier list (martingale setting), get the previous lot size and multiply by the current martingale multiplier

3.  Stop Loss / Take Profit Logic
      Exit Entry
      a. IF have existing position,Close all positions  when EMA Crosses and total profit is > 0
      b.  IF multiple positions,
          close all positions if the total profit is greater than or equal to the minimum profit specified on the setting, then create new entry with lot size reset to initial volume

      Trailing Stop
      a. For single position only, use the setting to set what profit percentage you want to secure when profit reached on your specified preferred setting:
         if First Trailing Profit  set First Trailing Percentage
         if Second Trailing Profit set Second Trailing Percentage
         if Max Trailing Profit set Max Trailing Percentage

    
5.  Time Setting
    Make sure to get the current gmt and broker gmt
    Set Target Time Zone: Machine GMT
    Broker Server GMT: Your broker server GMT

    
7. No Trade Rule
   a. You can specify when your bot will stop during specified time
   b. Option to close all position when trading day is friday (configurable)
       IsForceCloseFriday : will trigger the feature if set to true
       Friday No Trade After N Hour: Trader Server Time (UTC+0), will stop if N Hours before 24hour

TRADE AT YOUR OWN RISK
1. On how to setup this EA, search in google, how to run EA in MT5

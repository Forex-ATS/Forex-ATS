
//+------------------------------------------------------------------+
//|                                                   PA_Break2_Optimized_1pct.mq5 |
//|   Price Action: Break of 2 candles + D1 & H4 trend (Optimized)    |
//|                                                                  |
//|   This Expert Advisor implements a simple price‑action breakout   |
//|   strategy. The system looks for the close of the last completed  |
//|   H1 candle to break above (or below) the highs (or lows) of the  |
//|   two preceding candles. Trades are taken only in the direction   |
//|   of the dominant daily (D1) and 4‑hour (H4) trends.              |
//|                                                                  |
//|   Parameters are tuned for a 1% risk per trade, a reward‑to‑risk  |
//|   ratio of 1.3, a range filter factor of 1.5, and a trading      |
//|   session from 06:00 to 19:00 server time. Trading on Fridays     |
//|   is disabled. The code is designed for MT5 and uses the CTrade   |
//|   class for order execution.                                      |
//|                                                                  |
//|   © 2025 Open Source Project (MIT License)                        |
//+------------------------------------------------------------------+

#property strict
#include <Trade/Trade.mqh>

// Create a trade object
CTrade trade;

// Input parameters
input ENUM_TIMEFRAMES SignalTF      = PERIOD_H1; // Signal timeframe
input double          RiskPercent   = 1.0;       // Percent of account balance to risk per trade
input double          RR_Target     = 1.3;       // Reward‑to‑risk ratio (target = RR_Target × stop size)
input int             SL_BufferPips = 5;         // Stop‑loss buffer in pips
input double          RangeFactor   = 1.5;       // Range filter: current range must be >= RangeFactor × median range
input int             SessionStartHour = 6;      // Trading session start hour (server time)
input int             SessionEndHour   = 19;     // Trading session end hour (server time)
input bool            Trade_Mon    = true;       // Trade on Monday
input bool            Trade_Tue    = true;       // Trade on Tuesday
input bool            Trade_Wed    = true;       // Trade on Wednesday
input bool            Trade_Thu    = true;       // Trade on Thursday
input bool            Trade_Fri    = false;      // Trade on Friday (disabled)
input ulong           MagicNumber  = 20250810;   // Magic number for trade identification
input bool            AllowLong    = true;       // Enable long positions
input bool            AllowShort   = true;       // Enable short positions

// Global state
datetime lastSignalBarTime = 0; // Prevent re‑entry on the same signal bar

// Ensure sufficient bars are available on a given timeframe
bool BarsReady(ENUM_TIMEFRAMES tf, int required_bars=100)
{
   return (Bars(_Symbol, tf) >= required_bars);
}

// Load rates into an MqlRates array
bool LoadRates(ENUM_TIMEFRAMES tf, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, 300, rates);
   return (copied > 50);
}

// Median of the ranges of 'count' candles starting from startIndex
double MedianRange(const MqlRates &r[], int startIndex, int count)
{
   if(count <= 0) return 0.0;
   double tmp[];
   ArrayResize(tmp, count);
   for(int i=0; i<count; i++)
   {
      int idx = startIndex + i;
      tmp[i] = r[idx].high - r[idx].low;
   }
   ArraySort(tmp);
   int mid = count / 2;
   if((count % 2) == 1) return tmp[mid];
   else return (tmp[mid-1] + tmp[mid]) / 2.0;
}

// Check if the current bar time is within the allowed session and day
bool SessionAllowed(datetime t)
{
   MqlDateTime mt; TimeToStruct(t, mt);
   // day_of_week: 0=Sunday, 1=Monday, ..., 6=Saturday
   bool day_ok =
      (mt.day_of_week==1 && Trade_Mon) ||
      (mt.day_of_week==2 && Trade_Tue) ||
      (mt.day_of_week==3 && Trade_Wed) ||
      (mt.day_of_week==4 && Trade_Thu) ||
      (mt.day_of_week==5 && Trade_Fri);
   if(!day_ok) return false;
   if(mt.hour < SessionStartHour || mt.hour > SessionEndHour) return false;
   return true;
}

// Determine the bias of the last closed candle on a given timeframe
int LastClosedCandleBias(ENUM_TIMEFRAMES tf)
{
   double o[1], c[1];
   if(CopyOpen(_Symbol, tf, 1, 1, o) != 1)  return 0;
   if(CopyClose(_Symbol, tf, 1, 1, c) != 1) return 0;
   if(c[0] > o[0]) return 1;
   if(c[0] < o[0]) return -1;
   return 0;
}

// Retrieve tick size and tick value for the current symbol
bool GetTickInfo(double &tick_value, double &tick_size)
{
   if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tick_value)) return false;
   if(!SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE,  tick_size))  return false;
   return true;
}

// Normalize lot size to the nearest allowed step
double NormalizeLot(double lots)
{
   double minLot=0, maxLot=0, step=0;
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN,  minLot);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX,  maxLot);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, step);
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   if(step > 0) lots = MathFloor(lots/step)*step;
   return lots;
}

// Check if there is already an open position for this symbol and magic number
bool HasOpenPosition()
{
   int total = PositionsTotal();
   for(int idx=0; idx<total; idx++)
   {
      ulong ticket = PositionGetTicket(idx);
      if(ticket==0) continue;
      if(PositionSelectByTicket(ticket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         long   mg  = (long)PositionGetInteger(POSITION_MAGIC);
         if(sym == _Symbol && (ulong)mg == MagicNumber)
            return true;
      }
   }
   return false;
}

int OnInit(){ return(INIT_SUCCEEDED); }
void OnDeinit(const int reason){}

// Main function: called on every tick
void OnTick()
{
   // Ensure sufficient history on required timeframes
   if(!BarsReady(SignalTF, 50) || !BarsReady(PERIOD_H4, 50) || !BarsReady(PERIOD_D1, 50))
      return;

   // Only one position at a time
   if(HasOpenPosition()) return;

   // Load H1 data
   MqlRates h1[];
   if(!LoadRates(SignalTF, h1)) return;
   if(ArraySize(h1) < 25) return;

   // Last closed bar (signal bar) index is 1 (current bar = 0)
   int iSig = 1;
   datetime sigCloseTime = h1[iSig].time;

   // Prevent duplicate signals on the same bar
   if(sigCloseTime == lastSignalBarTime) return;

   // Ensure current bar is within trading session
   if(!SessionAllowed(h1[0].time)) return;

   // Determine trends on D1 and H4
   int d1_bias = LastClosedCandleBias(PERIOD_D1);
   int h4_bias = LastClosedCandleBias(PERIOD_H4);

   if(iSig + 2 >= ArraySize(h1)) return;

   // Candle direction on H1
   bool bullSig = (h1[iSig].close > h1[iSig].open);
   bool bearSig = (h1[iSig].close < h1[iSig].open);

   // Previous highs and lows
   double prevHigh1 = h1[iSig+1].high;
   double prevLow1  = h1[iSig+1].low;
   double prevHigh2 = h1[iSig+2].high;
   double prevLow2  = h1[iSig+2].low;

   // Check breakout of the two previous candles
   bool breakUp   = (h1[iSig].close > prevHigh1 && h1[iSig].close > prevHigh2);
   bool breakDown = (h1[iSig].close < prevLow1  && h1[iSig].close < prevLow2);

   // Range filter: median range of the last 20 candles
   int medianCount = 20;
   if(iSig + medianCount >= ArraySize(h1)) return;
   double currentRange = h1[iSig].high - h1[iSig].low;
   double median20 = MedianRange(h1, iSig+1, medianCount);
   bool rangeOK = (currentRange > 0 && median20 > 0 && currentRange >= RangeFactor * median20);

   // Determine buy and sell conditions
   bool buySignal  = AllowLong  && (d1_bias == 1) && (h4_bias == 1) && bullSig && breakUp   && rangeOK;
   bool sellSignal = AllowShort && (d1_bias == -1)&& (h4_bias == -1)&& bearSig && breakDown && rangeOK;
   if(!buySignal && !sellSignal) return;

   // Compute entry price at open of current bar
   double entry = h1[0].open;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = _Point;
   double pip   = (digits==3 || digits==5) ? (10.0 * point) : point;
   double sl_buffer = SL_BufferPips * pip;

   double sl = 0.0, tp = 0.0;
   if(buySignal)
   {
      sl = h1[iSig].low - sl_buffer;
      if(sl >= entry) return;
      double risk_price = entry - sl;
      tp = entry + RR_Target * risk_price;
   }
   else
   {
      sl = h1[iSig].high + sl_buffer;
      if(sl <= entry) return;
      double risk_price = sl - entry;
      tp = entry - RR_Target * risk_price;
   }

   // Retrieve tick info for lot calculation
   double tick_value, tick_size;
   if(!GetTickInfo(tick_value, tick_size)) return;

   double risk_price = MathAbs(entry - sl);
   if(risk_price <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0) return;

   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double loss_per_lot = (risk_price / tick_size) * tick_value;
   if(loss_per_lot <= 0.0) return;

   double lots = NormalizeLot(risk_amount / loss_per_lot);
   if(lots <= 0.0) return;

   // Normalize price levels
   entry = NormalizeDouble(entry, digits);
   sl    = NormalizeDouble(sl,    digits);
   tp    = NormalizeDouble(tp,    digits);

   // Place the order
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetAsyncMode(false);

   bool sent = false;
   if(buySignal)
      sent = trade.Buy(lots, _Symbol, entry, sl, tp, "PA Break2 Buy");
   if(sellSignal)
      sent = trade.Sell(lots, _Symbol, entry, sl, tp, "PA Break2 Sell");

   // Record the time of the signal bar to avoid repeat entries
   if(sent)
      lastSignalBarTime = sigCloseTime;
}
//+------------------------------------------------------------------+

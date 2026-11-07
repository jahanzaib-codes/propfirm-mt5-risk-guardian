//+------------------------------------------------------------------+
//|                                                RiskGuardian.mq5  |
//|                    Copyright 2026, Jahanzaib (@jahanzaib-codes)  |
//|               https://github.com/jahanzaib-codes                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Jahanzaib (@jahanzaib-codes)"
#property link      "https://github.com/jahanzaib-codes"
#property version   "1.00"
#property description "Automated Prop Firm Risk Manager & Equity Drawdown Guard for MT5"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input group "=== Prop Firm Drawdown Limits ==="
input double   InpMaxDailyDrawdownPercent = 4.0;    // Max Daily Loss % (e.g. 4% for FTMO)
input double   InpMaxTotalDrawdownPercent = 8.0;    // Max Overall Account Loss %
input bool     InpClosePendingOrders     = true;   // Close Pending Orders on Breach
input bool     InpDisableTradingAfterBreach = true; // Lock Trading Terminal for Day

input group "=== Trailing Stop & Breakeven ==="
input bool     InpEnableTrailingStop     = true;   // Enable Trailing Stop
input int      InpTrailingStopPoints     = 250;    // Trailing Distance (Points)
input int      InpTrailingStepPoints     = 50;     // Trailing Step (Points)
input bool     InpEnableBreakeven        = true;   // Enable Auto Breakeven
input int      InpBreakevenTriggerPoints = 200;    // Trigger Distance (Points)
input int      InpBreakevenLockPoints    = 20;     // Profit Locked (Points)

input group "=== Notifications ==="
input bool     InpSendPushNotification   = true;   // Send MT5 Mobile Push Alert
input bool     InpPlaySoundAlert         = true;   // Play Terminal Alert Sound

//--- Global State Variables
datetime g_lastResetDay = 0;
double   g_dailyStartEquity = 0.0;
double   g_initialAccountBalance = 0.0;
bool     g_breachedToday = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_initialAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastResetDay = TimeCurrent() / 86400;
   g_breachedToday = false;

   Print("🛡️ [RiskGuardian] Initialized. Daily Starting Equity: $", DoubleToString(g_dailyStartEquity, 2));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Midnight Daily Reset Check
   datetime currentDay = TimeCurrent() / 86400;
   if(currentDay != g_lastResetDay)
   {
      g_lastResetDay = currentDay;
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_breachedToday = false;
      Print("🔄 [RiskGuardian] New Trading Day. Resetting Daily Baseline to $", DoubleToString(g_dailyStartEquity, 2));
   }

   // If locked today, do not process further
   if(g_breachedToday && InpDisableTradingAfterBreach)
      return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // 2. Check Daily Drawdown Violation
   if(g_dailyStartEquity > 0.0)
   {
      double dailyLossPercent = ((g_dailyStartEquity - currentEquity) / g_dailyStartEquity) * 100.0;
      if(dailyLossPercent >= InpMaxDailyDrawdownPercent)
      {
         TriggerEmergencyCutoff("DAILY DRAWDOWN BREACHED (" + DoubleToString(dailyLossPercent, 2) + "%)");
         return;
      }
   }

   // 3. Check Overall Total Drawdown Violation
   if(g_initialAccountBalance > 0.0)
   {
      double totalLossPercent = ((g_initialAccountBalance - currentEquity) / g_initialAccountBalance) * 100.0;
      if(totalLossPercent >= InpMaxTotalDrawdownPercent)
      {
         TriggerEmergencyCutoff("MAX TOTAL DRAWDOWN BREACHED (" + DoubleToString(totalLossPercent, 2) + "%)");
         return;
      }
   }

   // 4. Trailing Stop & Breakeven Management
   ManageTrailingAndBreakeven();
}

//+------------------------------------------------------------------+
//| Emergency Close All Positions & Orders                           |
//+------------------------------------------------------------------+
void TriggerEmergencyCutoff(string reason)
{
   Print("🚨 [RiskGuardian] EMERGENCY TRIGGER: ", reason);
   g_breachedToday = true;

   // Close all market positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         trade.PositionClose(ticket);
         Print("❌ Closed Position Ticket #", ticket);
      }
   }

   // Close pending orders if enabled
   if(InpClosePendingOrders)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong orderTicket = OrderGetTicket(i);
         if(orderTicket > 0)
         {
            trade.OrderDelete(orderTicket);
            Print("❌ Deleted Pending Order #", orderTicket);
         }
      }
   }

   if(InpSendPushNotification)
      SendNotification("🚨 [RiskGuardian] Prop Firm Protection Triggered! " + reason);

   if(InpPlaySoundAlert)
      Alert("🚨 RiskGuardian: Drawdown limit hit! All orders closed.");
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop & Breakeven logic                           |
//+------------------------------------------------------------------+
void ManageTrailingAndBreakeven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      long posType = PositionGetInteger(POSITION_TYPE);

      double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);

      // BUY Positions
      if(posType == POSITION_TYPE_BUY)
      {
         double profitPoints = (currentBid - openPrice) / point;

         // Breakeven check
         if(InpEnableBreakeven && profitPoints >= InpBreakevenTriggerPoints)
         {
            double newSL = openPrice + (InpBreakevenLockPoints * point);
            if(currentSL < newSL)
            {
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         }

         // Trailing Stop check
         if(InpEnableTrailingStop && profitPoints >= InpTrailingStopPoints)
         {
            double newSL = currentBid - (InpTrailingStopPoints * point);
            if(newSL > currentSL + (InpTrailingStepPoints * point))
            {
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}

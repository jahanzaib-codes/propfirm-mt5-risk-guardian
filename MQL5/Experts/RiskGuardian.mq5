//+------------------------------------------------------------------+
//|                                                RiskGuardian.mq5  |
//|                    Copyright 2026, Jahanzaib (@jahanzaib-codes)  |
//|               https://github.com/jahanzaib-codes                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Jahanzaib (@jahanzaib-codes)"
#property link      "https://github.com/jahanzaib-codes"
#property version   "1.20"
#property description "Prop Firm Automated Risk Manager & On-Chart GUI Dashboard for MT5"

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

input group "=== GUI Dashboard Display ==="
input bool     InpShowOnChartDashboard   = true;   // Display On-Chart GUI Dashboard
input int      InpDashboardX             = 20;     // Panel X Coordinate
input int      InpDashboardY             = 40;     // Panel Y Coordinate

input group "=== Notifications ==="
input bool     InpSendPushNotification   = true;   // Send MT5 Mobile Push Alert
input bool     InpPlaySoundAlert         = true;   // Play Terminal Alert Sound

//--- Global State Variables
datetime g_lastResetDay = 0;
double   g_dailyStartEquity = 0.0;
double   g_initialAccountBalance = 0.0;
bool     g_breachedToday = false;

//--- GUI Object Names
const string PREFIX = "RG_GUI_";
const string PANEL_BG = PREFIX + "BG";
const string TITLE_LBL = PREFIX + "TITLE";
const string EQUITY_LBL = PREFIX + "EQUITY";
const string DAILY_PL_LBL = PREFIX + "DAILY_PL";
const string BUFFER_LBL = PREFIX + "BUFFER";
const string STATUS_LBL = PREFIX + "STATUS";
const string CLOSE_BTN = PREFIX + "PANIC_BTN";

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

   if(InpShowOnChartDashboard)
      InitDashboard();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupDashboard();
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

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPercent = 0.0;

   // 2. Check Daily Drawdown Violation
   if(g_dailyStartEquity > 0.0)
   {
      dailyLossPercent = ((g_dailyStartEquity - currentEquity) / g_dailyStartEquity) * 100.0;
      if(!g_breachedToday && dailyLossPercent >= InpMaxDailyDrawdownPercent)
      {
         TriggerEmergencyCutoff("DAILY DRAWDOWN BREACHED (" + DoubleToString(dailyLossPercent, 2) + "%)");
         return;
      }
   }

   // 3. Check Overall Total Drawdown Violation
   if(g_initialAccountBalance > 0.0)
   {
      double totalLossPercent = ((g_initialAccountBalance - currentEquity) / g_initialAccountBalance) * 100.0;
      if(!g_breachedToday && totalLossPercent >= InpMaxTotalDrawdownPercent)
      {
         TriggerEmergencyCutoff("MAX TOTAL DRAWDOWN BREACHED (" + DoubleToString(totalLossPercent, 2) + "%)");
         return;
      }
   }

   // 4. Update GUI Dashboard
   if(InpShowOnChartDashboard)
      UpdateDashboard(currentEquity, dailyLossPercent);

   // If locked today, do not process trailing stops
   if(g_breachedToday && InpDisableTradingAfterBreach)
      return;

   // 5. Trailing Stop & Breakeven Management
   ManageTrailingAndBreakeven();
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Button Clicks)                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == CLOSE_BTN)
      {
         Print("⚠️ [RiskGuardian] PANIC CLOSE BUTTON CLICKED BY USER");
         TriggerEmergencyCutoff("MANUAL PANIC CLOSE ALL TRADES");
         ObjectSetInteger(0, CLOSE_BTN, OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Emergency Close All Positions & Orders                           |
//+------------------------------------------------------------------+
void TriggerEmergencyCutoff(string reason)
{
   Print("🚨 [RiskGuardian] EMERGENCY TRIGGER: ", reason);
   g_breachedToday = true;

   // Close all open market positions
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

   if(InpShowOnChartDashboard)
      UpdateDashboard(AccountInfoDouble(ACCOUNT_EQUITY), 0.0);
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

//+------------------------------------------------------------------+
//| GUI Dashboard Initialization                                     |
//+------------------------------------------------------------------+
void InitDashboard()
{
   int x = InpDashboardX;
   int y = InpDashboardY;

   // 1. Panel Background
   ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, 260);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, 210);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, C'15,23,42');
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, C'51,65,85');
   ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   // 2. Title Label
   CreateLabel(TITLE_LBL, x + 14, y + 12, "🛡️ RISK GUARDIAN PRO", C'56,189,248', 11, true);

   // 3. Stats Labels
   CreateLabel(EQUITY_LBL, x + 14, y + 42, "Live Equity: $---", clrWhite, 9, false);
   CreateLabel(DAILY_PL_LBL, x + 14, y + 68, "Daily P&L: $---", clrWhite, 9, false);
   CreateLabel(BUFFER_LBL, x + 14, y + 94, "Daily Buffer: $---", C'148,163,184', 9, false);
   CreateLabel(STATUS_LBL, x + 14, y + 120, "Status: 🟢 SAFE", C'74,222,128', 9, true);

   // 4. Panic Button
   ObjectCreate(0, CLOSE_BTN, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_XDISTANCE, x + 14);
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_YDISTANCE, y + 155);
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_XSIZE, 232);
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_YSIZE, 34);
   ObjectSetString(0, CLOSE_BTN, OBJPROP_TEXT, "🚨 CLOSE ALL TRADES");
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, CLOSE_BTN, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_BGCOLOR, C'225,29,72');
   ObjectSetInteger(0, CLOSE_BTN, OBJPROP_BORDER_COLOR, C'244,63,94');

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Update Dashboard Values on Tick                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(double currentEquity, double dailyLossPercent)
{
   double dailyPL = currentEquity - g_dailyStartEquity;
   double maxDailyAllowedLoss = g_dailyStartEquity * (InpMaxDailyDrawdownPercent / 100.0);
   double remainingBuffer = maxDailyAllowedLoss + dailyPL;
   if(remainingBuffer < 0) remainingBuffer = 0.0;

   // Equity
   ObjectSetString(0, EQUITY_LBL, OBJPROP_TEXT, "Live Equity: $" + DoubleToString(currentEquity, 2));

   // Daily P&L
   string plPrefix = (dailyPL >= 0) ? "+$" : "-$";
   color plColor = (dailyPL >= 0) ? C'74,222,128' : C'248,113,113';
   ObjectSetString(0, DAILY_PL_LBL, OBJPROP_TEXT, "Daily P&L: " + plPrefix + DoubleToString(MathAbs(dailyPL), 2));
   ObjectSetInteger(0, DAILY_PL_LBL, OBJPROP_COLOR, plColor);

   // Daily Buffer
   ObjectSetString(0, BUFFER_LBL, OBJPROP_TEXT, "Loss Buffer: $" + DoubleToString(remainingBuffer, 2));

   // Status
   if(g_breachedToday)
   {
      ObjectSetString(0, STATUS_LBL, OBJPROP_TEXT, "Status: 🚨 LOCKED (BREACHED)");
      ObjectSetInteger(0, STATUS_LBL, OBJPROP_COLOR, C'239,68,68');
   }
   else if(dailyLossPercent > (InpMaxDailyDrawdownPercent * 0.75))
   {
      ObjectSetString(0, STATUS_LBL, OBJPROP_TEXT, "Status: ⚠️ HIGH RISK LEVEL");
      ObjectSetInteger(0, STATUS_LBL, OBJPROP_COLOR, C'250,204,21');
   }
   else
   {
      ObjectSetString(0, STATUS_LBL, OBJPROP_TEXT, "Status: 🟢 SAFE THRESHOLD");
      ObjectSetInteger(0, STATUS_LBL, OBJPROP_COLOR, C'74,222,128');
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper to create labels                                          |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int size, bool bold)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Cleanup Dashboard Objects on Unload                              |
//+------------------------------------------------------------------+
void CleanupDashboard()
{
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//|                                                   SwapTrader.mq4 |
//|                                                  A.Lopatin© 2018 |
//|                                              diver.stv@gmail.com |
//+------------------------------------------------------------------+
#property copyright " A.Lopatin© 2018"
#property link      "diver.stv@gmail.com"
#property version   "1.03"
#property strict

/* Error levels for a logging */
#define LOG_LEVEL_ERR 1
#define LOG_LEVEL_WARN 2
#define LOG_LEVEL_INFO 3
#define LOG_LEVEL_DBG 4

#include <stdlib.mqh>
#include <stderror.mqh>

/* input options of the EA */
input string  EntryTime                         = "23:50";
input int     TimeForEntry                      = 4;
input bool    UseMoneyManagement                = false;
input double  RiskPercent                       = 30.0;
input double  Lots                              = 0.1;
input bool    UseExitTime                       = true;
input string  ExitTime                          = "00:00";
input int     TimeForExit                       = 5;
input bool    CloseByTotalProfit                = false;
input double  TotalProfitToClose                = 0.0;
input int     StopLoss                          = 30;
input int     TakeProfit                        = 0;
input double  SpreadLimit                       = 5.0;
input double  MinimumSwap                       = 0.0;
input int     MagicNumber                       = 8022018;
input int     Slippage                          = 3;
input bool    ShowInformation                   = true;
input bool    UseDayManagement                  = false;
input bool    TradeMonday                       = true;
input bool    TradeTuesday                      = true;
input bool    TradeWednesday                    = true;
input bool    TradeThursday                     = true;
input bool    TradeFriday                       = true;

int retry_attempts=10;                          //attempts count for opening of the order
double sleep_time       = 4.0;                  //pause in seconds between atempts
double sleep_maximum    = 25.0;                 //in seconds
static int ErrorLevel    = LOG_LEVEL_ERR;       //level of error logging
static int _OR_err       = 0;                   // error code
//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
void OnInit()
  {

  }
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   string comment_str;
   string symbol=Symbol();
   comment_str="SYMBOL|SPREAD|LONG SWAP|SHORT SWAP\n";

   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double coef=1.0;
   if(digits==3 || digits==5)
      coef=0.1;
   double swap = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   comment_str = StringConcatenate(comment_str, symbol," | ", DoubleToString(SymbolInfoInteger(symbol, SYMBOL_SPREAD)*coef, 0), " ");
   comment_str = StringConcatenate(comment_str, "| ", DoubleToString(swap, 2), " ");
   swap=SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT);
   comment_str = StringConcatenate(comment_str,"| ",DoubleToString(swap,2)," ");
   comment_str+= "\n";
   DoTrade(symbol);
   if(ShowInformation)
      Comment(comment_str);
   DoCloseAllOrders();
  }
//+------------------------------------------------------------------+
//| CheckEntrySignal - function for a trade signal checking          |
//|   input: int index - index of bar for checking                   |
//|   return value - (int) a order type for opening                  |
//+------------------------------------------------------------------+

int CheckEntrySignal(const string symbol)
  {
   double swap=SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG);
   if(swap>=MinimumSwap)
      return(OP_BUY);
   swap=SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT);
   if(swap>=MinimumSwap)
      return(OP_SELL);

   return -1;
  }
//+------------------------------------------------------------------+
//|      DoTrade - the main function for trading                     |
//+------------------------------------------------------------------+
void DoTrade(string symbol)
  {
   int total_orders=OrdersCount(symbol,MagicNumber);//count of opening orders
   double point=XGetPoint(symbol);//get point value
   int signal=-1;
   RefreshRates(); // refresh  a price quotes

   if(total_orders<1 && CheckTradeConditions(symbol))
     {
      signal=CheckEntrySignal(symbol);//check a trade signal
      if(signal==OP_BUY)
        {
         if(OpenTrade(symbol,OP_BUY,CalculateVolume(symbol),SymbolInfoDouble(symbol,SYMBOL_ASK),Slippage,StopLoss,TakeProfit,"",MagicNumber)>0)
            return;
        }

      if(signal==OP_SELL)
        {
         if(OpenTrade(symbol,OP_SELL,CalculateVolume(symbol),SymbolInfoDouble(symbol,SYMBOL_BID),Slippage,StopLoss,TakeProfit,"",MagicNumber)>0)
            return;
        }
     }
  }
//+------------------------------------------------------------------+
//|  DoCloseAllOrders() - close order by time or profit conditions   |
//+------------------------------------------------------------------+
void DoCloseAllOrders()
  {
   bool closeByProfit=false;
   bool closeByTime=false;

   if(CloseByTotalProfit)
     {
      if(UseExitTime)
        {
         closeByProfit=TotalProfit(MagicNumber)>=TotalProfitToClose && IsTimeToTrade(ExitTime,TimeForExit);
        }
      else
         closeByProfit=TotalProfit(MagicNumber)>=TotalProfitToClose;
     }
   if(UseExitTime)
      closeByTime=IsTimeToTrade(ExitTime,TimeForExit);
   if(closeByProfit || closeByTime)
      CloseAllOrders(MagicNumber,-1);
  }
//+------------------------------------------------------------------+
//| CheckTradeConditions - check trade conditons: time, day,         |
//| spread limit                                                     |
//| Argument:                                                        |
//|   symbol - symbol of checked instrument                          |
//| Return value                                                     |
//|   true - trade is allowed                                        |
//|   false - trade is denied                                        |
//+------------------------------------------------------------------+
bool CheckTradeConditions(string symbol)
  {
   bool result= false;
   double ask = SymbolInfoDouble(symbol,SYMBOL_ASK),bid = SymbolInfoDouble(symbol,SYMBOL_BID),
   point=XGetPoint(symbol);
   datetime startTime=StringToTime(EntryTime),endTime=startTime+60*TimeForEntry,currentTime=TimeCurrent();
   if(IsTimeToTrade(EntryTime,TimeForEntry) && CheckDayOfWeek() && ask-bid<=SpreadLimit*point)
      result=true;

   return result;
  }
//+------------------------------------------------------------------+
//|  CheckDayOfWeek() - returns true if trade is allowed in this     |
//|   day of week, else - returns false                              |
//+------------------------------------------------------------------+
bool CheckDayOfWeek()
  {
   bool result=false;

   if(!UseDayManagement)
      result=true;
   else
     {
      int day_week=DayOfWeek();

      if(TradeMonday && day_week==1)
         result=true;
      if(TradeTuesday && day_week==2)
         result=true;
      if(TradeWednesday && day_week==3)
         result=true;
      if(TradeThursday && day_week==4)
         result=true;
      if(TradeFriday && day_week==5)
         result=true;
     }

   return(result);
  }
//+------------------------------------------------------------------+
//|  IsTimeToTrade - checks time for trading                         |
//|  Arguments:                                                      |
//|   time - start time in format "hh:mm"                            |
//|   tradeTime - period for trading in minutes                      |
//|  Return value:                                                   |
//|      true - trade is allowed                                     |
//|      false - trade is not allowed                                |
//+------------------------------------------------------------------+
bool IsTimeToTrade(const string time,const int tradeTime)
  {
   datetime startTime=StringToTime(time),endTime=startTime+60*tradeTime,
   currentTime=TimeCurrent();
   return currentTime >= startTime && currentTime <= endTime;
  }
//+------------------------------------------------------------------+
//|  OrdersCount - counts orders for symbol and magic number         |
//|  Arguments:                                                      |
//|   symbol - instrument of orders                                  |
//|   magic - Magic Number ID for orders                             |
//|  Return value - orders count                                     |
//+------------------------------------------------------------------+
/* the function returns count of opened  orders by EA
arguments: magic - magic number of orders */
int OrdersCount(const string symbol,const int magic)
  {
   int orders_total=OrdersTotal(),count=0;

   for(int i=0; i<orders_total; i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderSymbol()!=symbol)
            continue;
         if(OrderMagicNumber()!=magic)
            continue;

         count++;
        }
     }

   return(count);
  }
//+------------------------------------------------------------------+
//|  OpenTrade - checks input values and opens orders                |
//|  Arguments:                                                      |
//|   symbol - instrument of order                                   |
//|   type - type of order: buy, sell, sell stop, sell limit etc.    |
//|   lots - volume of order                                         |
//|   price - price of order                                         |
//|   slippage - slippage in points                                  |
//|   stoploss - stoploss value in pips                              |
//|   takeprofit - takeprofit value in pips                          |
//|   takeprofit - takeprofit value in pips                          |
//|   comment - text comment for order                               |
//|   magic - magic number of order                                  |
//|   expiration - expiration time for pending order                 |
//|   arrow_color - color of arrow on the chart for order            |
//|  Return value - order ticket if order has been opened            |
//|                 -1 - if error occurs                             |
//+------------------------------------------------------------------+
/* The function for opening new order for current symbol. If successed returns ticket of opened order, if failed -1 */
int OpenTrade(string symbol,int type,double lots,double price,int slippage,int stoploss,int takeprofit,string comment,int magic,datetime expiration=0,color arrow_color=CLR_NONE)
  {
   double tp=0.0,sl=0.0,point=XGetPoint(symbol);
   int retn_ticket=-1,digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);

   if(!IsVolumeValid(symbol,lots))
      return retn_ticket;

   if(!IsNewOrderAllowed())
      return retn_ticket;

   if(!CheckMoneyForTrade(symbol,lots,type))
      return retn_ticket;

   if(!IsStopsValid(symbol,takeprofit,stoploss))
      return retn_ticket;

   price=NormalizeDouble(price,digits);

   if(takeprofit>0)
     {
      if(type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT)
         tp=NormalizeDouble(price+takeprofit*point,digits);
      if(type==OP_SELL || type==OP_SELLSTOP || type==OP_SELLLIMIT)
         tp=NormalizeDouble(price-takeprofit*point,digits);
     }

   if(stoploss>0)
     {
      if(type==OP_BUY || type==OP_BUYSTOP || type==OP_BUYLIMIT)
         sl=NormalizeDouble(price-stoploss*point,digits);
      if(type==OP_SELL || type==OP_SELLSTOP || type==OP_SELLLIMIT)
         sl=NormalizeDouble(price+stoploss*point,digits);
     }

   retn_ticket=XOrderSend(symbol,type,lots,price,slippage,sl,tp,comment,magic,expiration,arrow_color);

   return retn_ticket;
  }
//+------------------------------------------------------------------+
//|  IsStopsValid - checks takeprofit and stoploss for stop level    |
//|  Arguments:                                                      |
//|   symbol - instrument symbol                                     |
//|   tp - takeprofit in pips                                        |
//|   sl - stoploss in pips                                          |
//|  Return value:                                                   |
//|      true - if takeprofit and stoploss have correct values       |
//|      else false                                                  |
//+------------------------------------------------------------------+
bool IsStopsValid(string symbol,int tp,int sl)
  {
   int stop_level=(int)MarketInfo(symbol,MODE_STOPLEVEL);

   if(tp>0 && stop_level>tp)
     {
      Print("Take profit "+DoubleToString(tp,0)+" is lesser stop level: "+DoubleToString(stop_level, 0));
      return false;
     }

   if(sl>0 && stop_level>sl)
     {
      Print("Stop loss "+DoubleToString(sl,0)+" is lesser stop level: "+DoubleToString(stop_level, 0));
      return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
//|  TotalProfit calculates total profit for opened orders           |
//|  Arguments:                                                      |
//|   magic - magic number of orders                                 |
//|  Return value - total profit for all orders with magic           |
//+------------------------------------------------------------------+
double TotalProfit(const int magic)
  {
   int orders_total=OrdersTotal();
   double profit=0.0;

   for(int i=0; i<orders_total; i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         if(OrderMagicNumber()!=magic)
            continue;
         if(OrderType()==OP_BUY || OrderType()==OP_SELL)
            profit+=(OrderProfit()+OrderSwap()+OrderCommission());
        }
     }

   return profit;
  }
//+------------------------------------------------------------------+
//|  IsVolumeValid - checks volume of order                          |
//|  Arguments:                                                      |
//|   symbol - instrument symbol                                     |
//|   volume - trade volume in lots                                  |
//|   sl - stoploss in pips                                          |
//|  Return value:                                                   |
//|      true - volume is valid                                      |
//|      false - volume is invalid                                   |
//+------------------------------------------------------------------+
bool IsVolumeValid(string symbol,double volume)
  {
   bool result=true;
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(min_volume>volume)
     {
      Print("Volume "+DoubleToStr(volume,3)+" is lesser than minimum allowed volume: "+DoubleToStr(min_volume,3));
      result=false;
     }
   if(max_volume<volume)
     {
      Print("Volume "+DoubleToStr(volume,3)+" is greater than maximum allowed volume: "+DoubleToStr(max_volume,3));
      result=false;
     }

   return result;
  }
//+------------------------------------------------------------------+
//|  CheckMoneyForTrade - account balance for opening new trade      |
//|  Arguments:                                                      |
//|   symbol - instrument symbol                                     |
//|   lots - trade volume in lots                                    |
//|   type - type of order                                           |
//|  Return value:                                                   |
//|      true - balance allows new trade                             |
//|      false - balans doesn't allow new trade                      |
//+------------------------------------------------------------------+
bool CheckMoneyForTrade(string symbol,double lots,int type)
  {
   double free_margin=AccountFreeMarginCheck(symbol,type,lots);
//-- if there is not enough money
   if(free_margin<0)
     {
      string oper=(type==OP_BUY) ? "Buy": "Sell";
      XPrint(LOG_LEVEL_INFO,StringConcatenate("Not enough money for ",oper," ",lots," ",symbol," Error code = ",GetLastError()),true);
      return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
//|  CloseAllOrders - closes all orders for defined type and magic   |
//|  Arguments:                                                      |
//|   magic - magic number of orders                                 |
//|   type - type of order                                           |
//|  Return value - count of closed orders                           |
//+------------------------------------------------------------------+
int CloseAllOrders(const int magic,const int type=-1)
  {
   int orders_count=OrdersTotal();
   int ord_type=-1,n=0;

   for(int i=orders_count-1; i>=0; i--)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==magic
         && OrderSymbol()==Symbol())
        {
         ord_type= OrderType();
         if(type == -1|| type == ord_type)
           {
            if(ord_type==OP_BUY)
              {
               if(XOrderClose(OrderTicket(),OrderLots(),SymbolInfoDouble(OrderSymbol(),SYMBOL_BID),Slippage))
                  n++;
               continue;
              }

            if(ord_type==OP_SELL)
              {
               if(XOrderClose(OrderTicket(),OrderLots(),SymbolInfoDouble(OrderSymbol(),SYMBOL_ASK),Slippage))
                  n++;
               continue;
              }

           }
        }
     }

   return(n);
  }
//+------------------------------------------------------------------+
//|  CalculateVolume - calculates trade volume                       |
//|  Arguments:                                                      |
//|   symbol - order symbol                                          |
//|  Return value - trade volume in lots                             |
//+------------------------------------------------------------------+
/*The function for calculation the trade volume, returns lot size*/
double CalculateVolume(string symbol)
  {
   double result=Lots;
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(UseMoneyManagement && RiskPercent>0.0)
     {
      double lotsize=MarketInfo(symbol,MODE_LOTSIZE);
      if(lotsize>0.0)
         result=NormalizeVolume(symbol,AccountInfoInteger(ACCOUNT_LEVERAGE)*AccountBalance()*RiskPercent/100.0/lotsize);
     }
   result = MathMax(min_volume, result);
   result = MathMin(max_volume, result);

   return(result);
  }
//+------------------------------------------------------------------+
//|  NormalizeVolume - normalizes volume                             |
//|  Arguments:                                                      |
//|   symbol - order symbol                                          |
//|   volume - lots for trading                                      |
//|  Return value - normalized volume in lots                        |
//+------------------------------------------------------------------+
double NormalizeVolume(const string symbol,const double volume)
  {
   int dig=1;
   double min_lot=NormalizeDouble(MarketInfo(symbol,MODE_LOTSTEP),2);
   if(min_lot==0.01)
      dig=2;
   if(min_lot==0.001)
      dig=3;
   return NormalizeDouble(volume, dig);
  }
//+------------------------------------------------------------------+
//| Check if another order can be placed                             |
//|  Return value:                                                   |
//|      true - opening new order is allowed                         |
//|      false - opening new order is not allowed                    |
//+------------------------------------------------------------------+
bool IsNewOrderAllowed()
  {
//--- get the number of pending orders allowed on the account
   int max_allowed_orders=(int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);

//--- if there is no limitation, return true; you can send an order
   if(max_allowed_orders==0)
      return true;

//--- if we passed to this line, then there is a limitation; find out how many orders are already placed
   int orders=OrdersTotal();

//--- return the result of comparing
   return(orders < max_allowed_orders);
  }
//+-------------------------------------------------------------------+
//|  XPrint  - function-wrapper for Print() function                  |
//|  Arguments:                                                       |
//|   log_level - level for logging                                   |
//|   text - text of the message                                      |
//|   is_show_comments - show message in comments, by default disabled|
//+-------------------------------------------------------------------+
/* The 
inputs: log_level - level for logging
        text - text of the message
        is_show_comments - show message in comments, by default disabled*/
void XPrint(int log_level,string text,bool is_show_comments=false)
  {
   string prefix,message;

   if(log_level>ErrorLevel)
      return;

   switch(log_level)
     {
      case LOG_LEVEL_ERR:
         prefix="Error";
         break;
      case LOG_LEVEL_WARN:
         prefix="Warning";
         break;
      case LOG_LEVEL_INFO:
         prefix="Info";
         break;
      case LOG_LEVEL_DBG:
         prefix="Debug";
         break;
     }

   message=StringConcatenate(prefix,": ",text);

   if(is_show_comments)
      Comment(message);

   Print(message);
  }
//+------------------------------------------------------------------+
//|    The function-wrapper for OrderSend() function                 |
//+------------------------------------------------------------------+
int XOrderSend(string symbol,int cmd,double volume,double price,
               int slippage,double stoploss,double takeprofit,
               string comment,int magic,datetime expiration=0,
               color arrow_color=CLR_NONE)
  {

   int digits;

   XPrint(LOG_LEVEL_INFO,StringConcatenate("Attempted ",XCommandString(cmd)," ",volume,
          " lots @",price," sl:",stoploss," tp:",takeprofit));

   if(IsStopped())
     {
      XPrint(LOG_LEVEL_WARN,"Expert was stopped while processing order. Order was canceled.");
      _OR_err=ERR_COMMON_ERROR;
      return(-1);
     }

   int cnt=0;
   while(!IsTradeAllowed() && cnt<retry_attempts)
     {
      XSleepRandomTime(sleep_time,sleep_maximum);
      cnt++;
     }

   if(!IsTradeAllowed())
     {
      XPrint(LOG_LEVEL_WARN,"No operation possible because Trading not allowed for this Expert, even after retries.");
      _OR_err=ERR_TRADE_CONTEXT_BUSY;

      return(-1);
     }

   digits=(int)MarketInfo(symbol,MODE_DIGITS);

   if(price==0)
     {
      RefreshRates();
      if(cmd==OP_BUY)
        {
         price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
      if(cmd==OP_SELL)
        {
         price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }
     }

   if(digits>0)
     {
      price=NormalizeDouble(price,digits);
      stoploss=NormalizeDouble(stoploss,digits);
      takeprofit=NormalizeDouble(takeprofit,digits);
     }

   if(stoploss!=0)
      XEnsureValidStop(symbol,price,stoploss);

   int err=GetLastError(); // clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   bool limit_to_market=false;

// limit/stop order. 
   int ticket=-1;

   if((cmd==OP_BUYSTOP) || (cmd==OP_SELLSTOP) || (cmd==OP_BUYLIMIT) || (cmd==OP_SELLLIMIT))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,stoploss,takeprofit,comment,magic,expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
              } else {
            cnt++;
           }

         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

               // retryable errors
            case ERR_SERVER_BUSY:
               break;
            case ERR_NO_CONNECTION:
               break;
            case ERR_INVALID_PRICE:
               break;
            case ERR_OFF_QUOTES:
               break;
            case ERR_BROKER_BUSY:
               break;
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++;
               break;

            case ERR_PRICE_CHANGED:
               break;
            case ERR_REQUOTE:
               RefreshRates();
               continue;   // we can apparently retry immediately according to MT docs.

            case ERR_INVALID_STOPS:
              {
               double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*XGetPoint(symbol);
               if(cmd==OP_BUYSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(SymbolInfoDouble(symbol,SYMBOL_ASK)-price)<=servers_min_stop)
                     limit_to_market=true;

                 }
               else if(cmd==OP_SELLSTOP)
                 {
                  // If we are too close to put in a limit/stop order so go to market.
                  if(MathAbs(SymbolInfoDouble(symbol,SYMBOL_BID)-price)<=servers_min_stop)
                     limit_to_market=true;
                 }
               exit_loop=true;
               break;
              }
            default:
               // an apparently serious error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               XPrint(LOG_LEVEL_ERR,"Non-retryable error - "+XErrorDescription(err));
              }
            if(cnt>retry_attempts)
              {
               XPrint(LOG_LEVEL_INFO,StringConcatenate("Retry attempts maxed at ",retry_attempts));
              }
           }

         if(!exit_loop)
           {
            XPrint(LOG_LEVEL_DBG,StringConcatenate("Retryable error (",cnt,"/",retry_attempts,
                   "): ",XErrorDescription(err)));
            XSleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }
        }

      // We have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         XPrint(LOG_LEVEL_INFO,"apparently successful order placed.");
         return(ticket); // SUCCESS! 
        }
      if(!limit_to_market)
        {
         XPrint(LOG_LEVEL_ERR,StringConcatenate("failed to execute stop or limit order after ",cnt," retries"));
         XPrint(LOG_LEVEL_INFO,StringConcatenate("failed trade: ",XCommandString(cmd)," ",symbol,
                "@",price," tp@",takeprofit," sl@",stoploss));
         XPrint(LOG_LEVEL_INFO,StringConcatenate("last error: ",XErrorDescription(err)));
         return(-1);
        }
     }  // end	  

   if(limit_to_market)
     {
      XPrint(LOG_LEVEL_DBG,"going from limit order to market order because market is too close.");
      RefreshRates();
      if((cmd==OP_BUYSTOP) || (cmd==OP_BUYLIMIT))
        {
         cmd=OP_BUY;
         price=Ask;
        }
      else if((cmd==OP_SELLSTOP) || (cmd==OP_SELLLIMIT))
        {
         cmd=OP_SELL;
         price=Bid;
        }
     }

// we now have a market order.
   err=GetLastError(); // so we clear the global variable.  
   err= 0;
   _OR_err= 0;
   ticket = -1;

   if((cmd==OP_BUY) || (cmd==OP_SELL))
     {
      cnt=0;
      while(!exit_loop)
        {
         if(IsTradeAllowed())
           {
            ticket=OrderSend(symbol,cmd,volume,price,slippage,stoploss,takeprofit,comment,magic,expiration,arrow_color);
            err=GetLastError();
            _OR_err=err;
              } else {
            cnt++;
           }
         switch(err)
           {
            case ERR_NO_ERROR:
               exit_loop=true;
               break;

            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_INVALID_PRICE:
            case ERR_OFF_QUOTES:
            case ERR_BROKER_BUSY:
            case ERR_TRADE_CONTEXT_BUSY:
               cnt++; // a retryable error
               break;

            case ERR_PRICE_CHANGED:
            case ERR_REQUOTE:
               RefreshRates();
               continue; // we can apparently retry immediately according to MT docs.

            default:
               // an apparently serious, unretryable error.
               exit_loop=true;
               break;

           }  // end switch 

         if(cnt>retry_attempts)
            exit_loop=true;

         if(!exit_loop)
           {
            XPrint(LOG_LEVEL_DBG,StringConcatenate("retryable error (",cnt,"/",
                   retry_attempts,"): ",XErrorDescription(err)));
            XSleepRandomTime(sleep_time,sleep_maximum);
            RefreshRates();
           }

         if(exit_loop)
           {
            if(err!=ERR_NO_ERROR)
              {
               XPrint(LOG_LEVEL_ERR,StringConcatenate("non-retryable error: ",XErrorDescription(err)));
              }
            if(cnt>retry_attempts)
              {
               XPrint(LOG_LEVEL_INFO,StringConcatenate("retry attempts maxed at ",retry_attempts));
              }
           }
        }

      // we have now exited from loop. 
      if(err==ERR_NO_ERROR)
        {
         XPrint(LOG_LEVEL_INFO,"apparently successful order placed, details follow.");
         //			OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES); 
         //			OrderPrint(); 
         return(ticket); // SUCCESS! 
        }
      XPrint(LOG_LEVEL_ERR,StringConcatenate("failed to execute OP_BUY/OP_SELL, after ",cnt," retries"));
      XPrint(LOG_LEVEL_INFO,StringConcatenate("failed trade: ",XCommandString(cmd)," ",symbol,
             "@",price," tp@",takeprofit," sl@",stoploss));
      XPrint(LOG_LEVEL_INFO,StringConcatenate("last error: ",XErrorDescription(err)));
      return(-1);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
//|   XCommandString function converts type order into string        |                                     
//|  Arguments:                                                      |
//|   cmd - order type                                               |
//|  Return value - string representation order type                 |
//+------------------------------------------------------------------+
string XCommandString(int cmd)
  {
   if(cmd==OP_BUY)
      return("BUY");

   if(cmd==OP_SELL)
      return("SELL");

   if(cmd==OP_BUYSTOP)
      return("BUY STOP");

   if(cmd==OP_SELLSTOP)
      return("SELL STOP");

   if(cmd==OP_BUYLIMIT)
      return("BUY LIMIT");

   if(cmd==OP_SELLLIMIT)
      return("SELL LIMIT");

   return(StringConcatenate("(" , cmd , ")"));
  }
//+------------------------------------------------------------------+
//|  XEnsureValidStop calculate valid stoploss for the order.        |
//|  Arguments:                                                      |
//|   symbol - currency symbol                                       |
//|        price - open price of a order                             |
//|        sl - output the price of the stoploss                     |
//+------------------------------------------------------------------+
void XEnsureValidStop(string symbol,double price,double &sl)
  {
// Return if no S/L
   if(sl==0)
      return;

   double servers_min_stop=MarketInfo(symbol,MODE_STOPLEVEL)*XGetPoint(symbol);

   if(MathAbs(price-sl)<=servers_min_stop)
     {
      // we have to adjust the stop.
      if(price>sl)
         sl=price-servers_min_stop;   // we are long

      else if(price<sl)
         sl=price+servers_min_stop;   // we are short			
      else
         XPrint(LOG_LEVEL_WARN,"Passed Stoploss which equal to price");

      sl=NormalizeDouble(sl,(int)MarketInfo(symbol,MODE_DIGITS));
     }
  }
//+------------------------------------------------------------------+
//|   XGetPoint calculates pip value for currency (symbol)           |
//|  Arguments:                                                      |
//|   symbol - currency symbol                                       |
//|  Return value - pip value                                        |
//+------------------------------------------------------------------+
/* The function returns point value for currency (symbol).
   Multiplies the point value for 10 for 3-5 digits brokers.*/
double XGetPoint(string symbol)
  {
   double point;

   point=MarketInfo(symbol,MODE_POINT);
   double digits=NormalizeDouble(MarketInfo(symbol,MODE_DIGITS),0);

   if(digits==3 || digits==5)
     {
      return(point*10.0);
     }

   return(point);
  }
//+------------------------------------------------------------------+
//|   XSleepRandomTime function-wrapper for Sleep()                  |
//|  Arguments:                                                      |
//|   mean_time - mean time for sleep                                |
//|   max_time - maximum allowed time for sleeping                   |
//+------------------------------------------------------------------+
void XSleepRandomTime(double mean_time,double max_time)
  {
   if(IsTesting())
      return;    // return immediately if backtesting.

   double tenths=MathCeil(mean_time/0.1);
   if(tenths<=0)
      return;

   int maxtenths=(int)MathRound(max_time/0.1);
   double p=1.0-1.0/tenths;

   Sleep(100);    // one tenth of a second PREVIOUS VERSIONS WERE STUPID HERE. 

   for(int i=0; i<maxtenths; i++)
     {
      if(MathRand()>p*32768)
         break;

      // MathRand() returns in 0..32767
      Sleep(100);
     }
  }
//+------------------------------------------------------------------+
//|   XErrorDescription function-wrapper for ErrorDescription()      |
//+------------------------------------------------------------------+
/* The function-wrapper for ErrorDescription()*/
string XErrorDescription(int err)
  {
   return(ErrorDescription(err));
  }
//+------------------------------------------------------------------+
//|      XOrderModify function-wrapper for OrderModify()             |
//+------------------------------------------------------------------+
bool XOrderModify(int ticket,double price,double stoploss,
                  double takeprofit,datetime expiration,
                  color arrow_color=CLR_NONE)
  {

   XPrint(LOG_LEVEL_INFO,StringConcatenate(" attempted modify of #",ticket," price:",price," sl:",stoploss," tp:",takeprofit));

   if(IsStopped())
     {
      XPrint(LOG_LEVEL_WARN,"Expert was stopped while processing order. Order was canceled.");
      return(false);
     }

   int cnt=0;
   while(!IsTradeAllowed() && cnt<retry_attempts)
     {
      XSleepRandomTime(sleep_time,sleep_maximum);
      cnt++;
     }
   if(!IsTradeAllowed())
     {
      XPrint(LOG_LEVEL_WARN,"No operation possible because Trading not allowed for this Expert, even after retries.");
      _OR_err=ERR_TRADE_CONTEXT_BUSY;
      return(false);
     }

   int err=GetLastError(); // so we clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   cnt=0;
   bool result=false;

   while(!exit_loop)
     {
      if(IsTradeAllowed())
        {
         result=OrderModify(ticket,price,stoploss,takeprofit,expiration,arrow_color);
         err=GetLastError();
         _OR_err=err;
        }
      else
         cnt++;

      if(result==true)
         exit_loop=true;

      switch(err)
        {
         case ERR_NO_ERROR:
            exit_loop=true;
            break;

         case ERR_NO_RESULT:
            // modification without changing a parameter. 
            // if you get this then you may want to change the code.
            exit_loop=true;
            break;

         case ERR_SERVER_BUSY:
         case ERR_NO_CONNECTION:
         case ERR_INVALID_PRICE:
         case ERR_OFF_QUOTES:
         case ERR_BROKER_BUSY:
         case ERR_TRADE_CONTEXT_BUSY:
         case ERR_TRADE_TIMEOUT:      // for modify this is a retryable error, I hope. 
            cnt++;    // a retryable error
            break;

         case ERR_PRICE_CHANGED:
         case ERR_REQUOTE:
            RefreshRates();
            continue;    // we can apparently retry immediately according to MT docs.

         default:
            // an apparently serious, unretryable error.
            exit_loop=true;
            break;

        }  // end switch 

      if(cnt>retry_attempts)
         exit_loop=true;

      if(!exit_loop)
        {
         XPrint(LOG_LEVEL_DBG,StringConcatenate("retryable error (",cnt,"/",retry_attempts,"): ",XErrorDescription(err)));
         XSleepRandomTime(sleep_time,sleep_maximum);
         RefreshRates();
        }

      if(exit_loop)
        {
         if((err!=ERR_NO_ERROR) && (err!=ERR_NO_RESULT))
            XPrint(LOG_LEVEL_ERR,StringConcatenate("non-retryable error: ",XErrorDescription(err)));

         if(cnt>retry_attempts)
            XPrint(LOG_LEVEL_INFO,StringConcatenate("retry attempts maxed at ",retry_attempts));
        }
     }

// we have now exited from loop. 
   if((result==true) || (err==ERR_NO_ERROR))
     {
      XPrint(LOG_LEVEL_INFO,"apparently successful modification order.");
      return(true); // SUCCESS! 
     }

   if(err==ERR_NO_RESULT)
     {
      XPrint(LOG_LEVEL_WARN,"Server reported modify order did not actually change parameters.");
      return(true);
     }

   XPrint(LOG_LEVEL_ERR,StringConcatenate("failed to execute modify after ",cnt," retries"));
   XPrint(LOG_LEVEL_INFO,StringConcatenate("failed modification: ",ticket," @",price," tp@",takeprofit," sl@",stoploss));
   XPrint(LOG_LEVEL_INFO,StringConcatenate("last error: ",XErrorDescription(err)));

   return(false);
  }
//+------------------------------------------------------------------+
//|    XOrderClose - function-wrapper for OrderClose()               |
//+------------------------------------------------------------------+
bool XOrderClose(int ticket,double lots,double price,int slippage,color arrow_color=CLR_NONE)
  {
   int nOrderType;
   string strSymbol;

   XPrint(LOG_LEVEL_INFO,StringConcatenate(" attempted close of #",ticket," price:",price," lots:",lots," slippage:",slippage));

// collect details of order so that we can use GetMarketInfo later if needed
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
     {
      _OR_err=GetLastError();
      XPrint(LOG_LEVEL_ERR,XErrorDescription(_OR_err));
      return(false);
        } else {
      nOrderType= OrderType();
      strSymbol = Symbol();
     }

   if(nOrderType!=OP_BUY && nOrderType!=OP_SELL)
     {
      _OR_err=ERR_INVALID_TICKET;
      XPrint(LOG_LEVEL_WARN,StringConcatenate("trying to close ticket #",ticket,", which is ",XCommandString(nOrderType),", not BUY or SELL"));
      return(false);
     }

   if(IsStopped())
     {
      XPrint(LOG_LEVEL_WARN,"Expert was stopped while processing order. Order processing was canceled.");
      return(false);
     }

   int cnt=0;
   int err=GetLastError(); // so we clear the global variable.  
   err=0;
   _OR_err=0;
   bool exit_loop=false;
   cnt=0;
   bool result=false;

   if(lots== 0)
      lots= OrderLots();

   if(price==0)
     {
      RefreshRates();
      if(nOrderType==OP_BUY)
         price=NormalizeDouble(MarketInfo(strSymbol,MODE_BID),(int)MarketInfo(strSymbol,MODE_DIGITS));
      if(nOrderType==OP_SELL)
         price=NormalizeDouble(MarketInfo(strSymbol,MODE_ASK),(int)MarketInfo(strSymbol,MODE_DIGITS));
     }

   while(!exit_loop)
     {
      if(IsTradeAllowed())
        {
         result=OrderClose(ticket,lots,price,slippage,arrow_color);
         err=GetLastError();
         _OR_err=err;
        }
      else
         cnt++;

      if(result==true)
         exit_loop=true;

      switch(err)
        {
         case ERR_NO_ERROR:
            exit_loop=true;
            break;

         case ERR_SERVER_BUSY:
         case ERR_NO_CONNECTION:
         case ERR_INVALID_PRICE:
         case ERR_OFF_QUOTES:
         case ERR_BROKER_BUSY:
         case ERR_TRADE_CONTEXT_BUSY:
         case ERR_TRADE_TIMEOUT:      // for modify this is a retryable error, I hope. 
            cnt++;    // a retryable error
            break;

         case ERR_PRICE_CHANGED:
         case ERR_REQUOTE:
            continue;    // we can apparently retry immediately according to MT docs.

         default:
            // an apparently serious, unretryable error.
            exit_loop=true;
            break;

        }  // end switch 

      if(cnt>retry_attempts)
         exit_loop=true;

      if(!exit_loop)
        {
         XPrint(LOG_LEVEL_DBG,StringConcatenate("retryable error (",cnt,"/",retry_attempts,"): ",XErrorDescription(err)));
         XSleepRandomTime(sleep_time,sleep_maximum);

         // Added by Paul Hampton-Smith to ensure that price is updated for each retry
         if(nOrderType==OP_BUY)
            price=NormalizeDouble(MarketInfo(strSymbol,MODE_BID),(int)MarketInfo(strSymbol,MODE_DIGITS));
         if(nOrderType==OP_SELL)
            price=NormalizeDouble(MarketInfo(strSymbol,MODE_ASK),(int)MarketInfo(strSymbol,MODE_DIGITS));
        }

      if(exit_loop)
        {
         if((err!=ERR_NO_ERROR) && (err!=ERR_NO_RESULT))
            XPrint(LOG_LEVEL_ERR,StringConcatenate("non-retryable error: ",XErrorDescription(err)));

         if(cnt>retry_attempts)
            XPrint(LOG_LEVEL_INFO,StringConcatenate("retry attempts maxed at ",retry_attempts));
        }
     }

// we have now exited from loop. 
   if((result==true) || (err==ERR_NO_ERROR))
     {
      XPrint(LOG_LEVEL_INFO,"apparently successful close order.");
      return(true); // SUCCESS! 
     }

   XPrint(LOG_LEVEL_ERR,StringConcatenate("failed to execute close after ",cnt," retries"));
   XPrint(LOG_LEVEL_INFO,StringConcatenate("failed close: Ticket #",ticket,", Price: ",price,", Slippage: ",slippage));
   XPrint(LOG_LEVEL_INFO,StringConcatenate("last error: ",XErrorDescription(err)));

   return(false);
  }
//+------------------------------------------------------------------+

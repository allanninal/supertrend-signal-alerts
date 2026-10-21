//+------------------------------------------------------------------+
//|                                       SuperTrendSignalAlerts.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| SuperTrend: bands at hl2 -/+ multiplier x ATR that only ratchet  |
//| in the direction of the trend. The trend flips when the close    |
//| breaks the opposite band. ATR is Wilder's (RMA, as ta.atr) or an |
//| SMA of the true range. Optional filters on the arrows and alerts:|
//| EMA trend and RSI side.                                          |
//| Arrows and alerts come from closed bars only, so a signal never  |
//| appears and then disappears. The line moves on the live bar.     |
//+------------------------------------------------------------------+
// Licence: Mozilla Public License 2.0. This Source Code Form is subject
// to the terms of the MPL, v. 2.0. If a copy of the MPL was not
// distributed with this file, You can obtain one at
// https://mozilla.org/MPL/2.0/
// Origin: the SuperTrend method (ATR bands that only ratchet with the trend) is by
// Olivier Seban; the TradingView "SuperTrend" script is by KivancOzbilgic. This file is
// an independent MQL implementation of that published method.
// SPDX-License-Identifier: MPL-2.0
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property description "SuperTrend line with buy/sell arrows on closed bars, optional EMA and RSI filters."
#property description "Alerts: pop-up, sound, push, e-mail. Non-repainting: signals only on closed bars."
#property indicator_chart_window
#property indicator_buffers 13
#property indicator_plots   4
#property indicator_label1  "SuperTrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrTomato
#property indicator_width1  2
#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrTomato
#property indicator_width3  2
#property indicator_label4  "Trend EMA"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGoldenrod
#property indicator_style4  STYLE_DOT

enum ENUM_ST_ATR
  {
   ST_ATR_RMA=0,   // RMA / Wilder (same as ta.atr)
   ST_ATR_SMA=1    // SMA of the true range
  };

input group "SuperTrend"
input int           InpATR     = 10;          // ATR period
input double        InpMult    = 3.0;         // ATR multiplier
input ENUM_ST_ATR   InpMethod  = ST_ATR_RMA;  // ATR method
input group "Trend filter"
input bool   InpUseEMA  = false;   // Only signals with the EMA trend
input int    InpEMA     = 200;     // EMA period
input bool   InpShowEMA = true;    // Draw the EMA (when the filter is on)
input group "RSI filter"
input bool   InpUseRSI  = false;   // Buy only RSI above 50, sell only below
input int    InpRSI     = 14;      // RSI period
input group "Display"
input bool   InpShowLine = true;   // Draw the SuperTrend line
input int    InpArrowGap = 12;     // Arrow distance from the candle, pixels

#include "SignalAlerts.mqh"

double g_line[],g_clr[],g_buy[],g_sell[],g_ema_draw[];
double g_up[],g_dn[],g_trend[],g_atr[],g_ema[],g_rsi[],g_gain[],g_loss[];
const string PRODUCT="SuperTrend";

int OnInit()
  {
   if(InpATR<1 || InpMult<=0 || InpEMA<1 || InpRSI<1)
     {
      Print("SuperTrend: ATR period, multiplier, EMA period and RSI period must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   SetIndexBuffer(0,g_line,INDICATOR_DATA);
   SetIndexBuffer(1,g_clr,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,g_buy,INDICATOR_DATA);
   SetIndexBuffer(3,g_sell,INDICATOR_DATA);
   SetIndexBuffer(4,g_ema_draw,INDICATOR_DATA);
   SetIndexBuffer(5,g_up,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,g_dn,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,g_trend,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,g_atr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,g_ema,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,g_rsi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,g_gain,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,g_loss,INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(1,PLOT_ARROW,233);
   PlotIndexSetInteger(2,PLOT_ARROW,234);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,InpArrowGap);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-InpArrowGap);
   for(int p=0; p<4; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,InpShowLine ? DRAW_COLOR_LINE : DRAW_NONE);
   PlotIndexSetInteger(3,PLOT_DRAW_TYPE,(InpUseEMA && InpShowEMA) ? DRAW_LINE : DRAW_NONE);
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("SuperTrend (%d, %.1f)",InpATR,InpMult));
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return(INIT_SUCCEEDED);
  }

//--- true range of bar k
//--- strict a>b / a<b that ignore floating-point noise: a band can tie a close exactly in real arithmetic
//--- (e.g. 0.00728/14*2+hl2 = 1.10704) and a last-bit difference would otherwise decide the trend flip
bool Above(const double a,const double b) { return(a-b>1e-10*MathAbs(b)); }
bool Below(const double a,const double b) { return(b-a>1e-10*MathAbs(b)); }

double TrueRange(const int k,const double &high[],const double &low[],const double &close[])
  {
   if(k==0)
      return(high[k]-low[k]);
   return(MathMax(high[k]-low[k],MathMax(MathAbs(high[k]-close[k-1]),MathAbs(low[k]-close[k-1]))));
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   for(int i=start; i<rates_total; i++)
     {
      double tr=TrueRange(i,high,low,close);
      //--- ATR: Wilder's RMA seeded with the SMA of the first InpATR values, or a plain SMA
      g_atr[i]=EMPTY_VALUE;
      if(i>=InpATR-1)
        {
         if(InpMethod==ST_ATR_SMA || i==InpATR-1)
           {
            double s=0;
            for(int k=i-InpATR+1; k<=i; k++)
               s+=TrueRange(k,high,low,close);
            g_atr[i]=s/InpATR;
           }
         else
            g_atr[i]=(g_atr[i-1]*(InpATR-1)+tr)/InpATR;
        }
      //--- EMA of the close, seeded with the SMA of the first InpEMA closes
      if(i<InpEMA-1)
         g_ema[i]=EMPTY_VALUE;
      else
         if(i==InpEMA-1)
           {
            double s=0;
            for(int k=0; k<InpEMA; k++)
               s+=close[k];
            g_ema[i]=s/InpEMA;
           }
         else
            g_ema[i]=g_ema[i-1]+2.0/(InpEMA+1)*(close[i]-g_ema[i-1]);
      g_ema_draw[i]=g_ema[i];
      //--- RSI (Wilder): RMA of gains and losses seeded with the SMA of the first InpRSI changes
      g_rsi[i]=EMPTY_VALUE;
      g_gain[i]=EMPTY_VALUE;
      g_loss[i]=EMPTY_VALUE;
      if(i>=InpRSI)
        {
         if(i==InpRSI)
           {
            double sg=0,sl=0;
            for(int k=1; k<=InpRSI; k++)
              {
               double ch=close[k]-close[k-1];
               sg+=MathMax(ch,0.0);
               sl+=MathMax(-ch,0.0);
              }
            g_gain[i]=sg/InpRSI;
            g_loss[i]=sl/InpRSI;
           }
         else
           {
            double ch=close[i]-close[i-1];
            g_gain[i]=(g_gain[i-1]*(InpRSI-1)+MathMax(ch,0.0))/InpRSI;
            g_loss[i]=(g_loss[i-1]*(InpRSI-1)+MathMax(-ch,0.0))/InpRSI;
           }
         if(g_loss[i]==0.0)
            g_rsi[i]=100.0;
         else
            if(g_gain[i]==0.0)
               g_rsi[i]=0.0;
            else
               g_rsi[i]=100.0-100.0/(1.0+g_gain[i]/g_loss[i]);
        }
      //--- SuperTrend bands and trend
      g_buy[i]=EMPTY_VALUE;
      g_sell[i]=EMPTY_VALUE;
      if(g_atr[i]==EMPTY_VALUE)
        {
         g_up[i]=EMPTY_VALUE;
         g_dn[i]=EMPTY_VALUE;
         g_trend[i]=EMPTY_VALUE;
         g_line[i]=EMPTY_VALUE;
         g_clr[i]=0;
         continue;
        }
      double src=(high[i]+low[i])/2.0;
      double up=src-InpMult*g_atr[i];
      double dn=src+InpMult*g_atr[i];
      bool first=(i==0 || g_up[i-1]==EMPTY_VALUE);
      double up1=(first ? up : g_up[i-1]);
      double dn1=(first ? dn : g_dn[i-1]);
      if(i>0 && Above(close[i-1],up1))
         up=MathMax(up,up1);
      if(i>0 && Below(close[i-1],dn1))
         dn=MathMin(dn,dn1);
      double trend=(first ? 1.0 : g_trend[i-1]);
      if(trend==-1.0 && Above(close[i],dn1))
         trend=1.0;
      else
         if(trend==1.0 && Below(close[i],up1))
            trend=-1.0;
      g_up[i]=up;
      g_dn[i]=dn;
      g_trend[i]=trend;
      g_line[i]=(trend==1.0 ? up : dn);
      g_clr[i]=(trend==1.0 ? 0 : 1);
      //--- signals: the trend flips; only on closed bars
      if(first || i>rates_total-2)
         continue;
      bool buy=(trend==1.0 && g_trend[i-1]==-1.0);
      bool sell=(trend==-1.0 && g_trend[i-1]==1.0);
      if(InpUseEMA)
        {
         buy=buy && g_ema[i]!=EMPTY_VALUE && close[i]>g_ema[i];
         sell=sell && g_ema[i]!=EMPTY_VALUE && close[i]<g_ema[i];
        }
      if(InpUseRSI)
        {
         buy=buy && g_rsi[i]!=EMPTY_VALUE && g_rsi[i]>50.0;
         sell=sell && g_rsi[i]!=EMPTY_VALUE && g_rsi[i]<50.0;
        }
      if(buy)
        {
         g_buy[i]=low[i];
         if(i==rates_total-2)
            SignalAlert(PRODUCT,"BUY, trend up from "+DoubleToString(close[i],_Digits),time[i],prev_calculated>0);
        }
      if(sell)
        {
         g_sell[i]=high[i];
         if(i==rates_total-2)
            SignalAlert(PRODUCT,"SELL, trend down from "+DoubleToString(close[i],_Digits),time[i],prev_calculated>0);
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+

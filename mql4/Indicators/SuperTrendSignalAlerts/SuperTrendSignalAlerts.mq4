//+------------------------------------------------------------------+
//|                                       SuperTrendSignalAlerts.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| MT4 edition of SuperTrend Signal Alerts: the same calculation as |
//| the MT5 indicator (bands at hl2 -/+ multiplier x ATR that only   |
//| ratchet in the direction of the trend; the trend flips when the  |
//| close breaks the opposite band; ATR is Wilder's RMA, as ta.atr,  |
//| or an SMA of the true range; optional EMA and RSI filters on the |
//| arrows and alerts).                                              |
//| Arrows and alerts come from closed bars only, so a signal never  |
//| appears and then disappears. The line moves on the live bar.     |
//| MT4 differences: the line is two buffers (blue/red), and the     |
//| arrow gap is a fraction of ATR (MT4 has no pixel shift).         |
//| Buffers for iCustom match MT5: 0 line, 2 buy, 3 sell.            |
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
#property strict
#property description "SuperTrend line with buy/sell arrows on closed bars, optional EMA and RSI filters."
#property description "Alerts: pop-up, sound, push, e-mail. Non-repainting: signals only on closed bars."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1  clrNONE
#property indicator_color2  clrDodgerBlue
#property indicator_width2  2
#property indicator_color3  clrDodgerBlue
#property indicator_width3  2
#property indicator_color4  clrTomato
#property indicator_width4  2
#property indicator_color5  clrTomato
#property indicator_width5  2
#property indicator_color6  clrGoldenrod

enum ENUM_ST_ATR
  {
   ST_ATR_RMA=0,   // RMA / Wilder (same as ta.atr)
   ST_ATR_SMA=1    // SMA of the true range
  };

input int         InpATR      = 10;          // ATR period
input double      InpMult     = 3.0;         // ATR multiplier
input ENUM_ST_ATR InpMethod   = ST_ATR_RMA;  // ATR method
input bool        InpUseEMA   = false;       // Only signals with the EMA trend
input int         InpEMA      = 200;         // EMA period
input bool        InpShowEMA  = true;        // Draw the EMA (when the filter is on)
input bool        InpUseRSI   = false;       // Buy only RSI above 50, sell only below
input int         InpRSI      = 14;          // RSI period
input bool        InpShowLine = true;        // Draw the SuperTrend line
input double      InpArrowGap = 0.3;         // Arrow distance from the candle (x ATR)

#include "SignalAlerts.mqh"

//--- series-indexed (0 = live bar), as every MT4 buffer
double g_line[],g_upl[],g_buy[],g_sell[],g_dnl[],g_ema_draw[];
double g_up[],g_dn[],g_trend[],g_atr[],g_ema[],g_rsi[],g_gain[],g_loss[];
const string PRODUCT="SuperTrend";

int OnInit()
  {
   if(InpATR<1 || InpMult<=0 || InpEMA<1 || InpRSI<1 || InpArrowGap<0)
     {
      Print("SuperTrend: ATR period, multiplier, EMA period and RSI period must be positive");
      return(INIT_PARAMETERS_INCORRECT);
     }
   IndicatorBuffers(14);
   SetIndexBuffer(0,g_line);
   SetIndexBuffer(1,g_upl);
   SetIndexBuffer(2,g_buy);
   SetIndexBuffer(3,g_sell);
   SetIndexBuffer(4,g_dnl);
   SetIndexBuffer(5,g_ema_draw);
   SetIndexBuffer(6,g_up,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,g_dn,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,g_trend,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,g_atr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,g_ema,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,g_rsi,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,g_gain,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,g_loss,INDICATOR_CALCULATIONS);
   SetIndexStyle(0,DRAW_NONE);
   SetIndexStyle(1,InpShowLine ? DRAW_LINE : DRAW_NONE);
   SetIndexStyle(4,InpShowLine ? DRAW_LINE : DRAW_NONE);
   SetIndexStyle(2,DRAW_ARROW);
   SetIndexStyle(3,DRAW_ARROW);
   SetIndexArrow(2,233);
   SetIndexArrow(3,234);
   SetIndexStyle(5,(InpUseEMA && InpShowEMA) ? DRAW_LINE : DRAW_NONE,STYLE_DOT);
   SetIndexLabel(0,"SuperTrend");
   SetIndexLabel(1,NULL);
   SetIndexLabel(2,"Buy");
   SetIndexLabel(3,"Sell");
   SetIndexLabel(4,NULL);
   SetIndexLabel(5,InpUseEMA ? "Trend EMA" : NULL);
   for(int b=0; b<14; b++)
      SetIndexEmptyValue(b,EMPTY_VALUE);
   IndicatorShortName(StringFormat("SuperTrend (%d, %.1f)",InpATR,InpMult));
   IndicatorDigits(_Digits);
   return(INIT_SUCCEEDED);
  }

//--- strict a>b / a<b that ignore floating-point noise: a band can tie a close exactly in real arithmetic
//--- (e.g. 0.00728/14*2+hl2 = 1.10704) and a last-bit difference would otherwise decide the trend flip
bool Above(const double a,const double b) { return(a-b>1e-10*MathAbs(b)); }
bool Below(const double a,const double b) { return(b-a>1e-10*MathAbs(b)); }

//--- true range of the bar at series index s (n = bars in total; the oldest bar has no previous close)
double TrueRange(const int s,const int n,const double &high[],const double &low[],const double &close[])
  {
   if(s==n-1)
      return(high[s]-low[s]);
   return(MathMax(high[s]-low[s],MathMax(MathAbs(high[s]-close[s+1]),MathAbs(low[s]-close[s+1]))));
  }

//--- the two coloured halves of the line at series index s, joined to the bar before when the trend flips
void Segments(const int s,const int n)
  {
   g_upl[s]=EMPTY_VALUE;
   g_dnl[s]=EMPTY_VALUE;
   if(g_line[s]==EMPTY_VALUE)
      return;
   bool up=(g_trend[s]==1.0);
   if(up)
      g_upl[s]=g_line[s];
   else
      g_dnl[s]=g_line[s];
   if(s+1>=n || g_line[s+1]==EMPTY_VALUE)
      return;
   //--- the older bar back to its own colour (a join from an earlier tick of this bar may be stale), then the join
   bool was_up=(g_trend[s+1]==1.0);
   g_upl[s+1]=(was_up ? g_line[s+1] : EMPTY_VALUE);
   g_dnl[s+1]=(was_up ? EMPTY_VALUE : g_line[s+1]);
   if(was_up!=up)
     {
      if(up)
         g_upl[s+1]=g_line[s+1];
      else
         g_dnl[s+1]=g_line[s+1];
     }
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<2)
      return(0);
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   int n=rates_total;
   //--- oldest bar first: i counts from the oldest bar (as in the MT5 code), s is the series index
   int first=(prev_calculated>0 ? n-prev_calculated : n-1);
   if(first>=n-1)
      first=n-1;
   for(int s=first; s>=0; s--)
     {
      int i=n-1-s;
      double tr=TrueRange(s,n,high,low,close);
      //--- ATR: Wilder's RMA seeded with the SMA of the first InpATR values, or a plain SMA
      g_atr[s]=EMPTY_VALUE;
      if(i>=InpATR-1)
        {
         if(InpMethod==ST_ATR_SMA || i==InpATR-1)
           {
            double sum=0;
            for(int k=s; k<s+InpATR; k++)
               sum+=TrueRange(k,n,high,low,close);
            g_atr[s]=sum/InpATR;
           }
         else
            g_atr[s]=(g_atr[s+1]*(InpATR-1)+tr)/InpATR;
        }
      //--- EMA of the close, seeded with the SMA of the first InpEMA closes
      if(i<InpEMA-1)
         g_ema[s]=EMPTY_VALUE;
      else
         if(i==InpEMA-1)
           {
            double sum=0;
            for(int k=0; k<InpEMA; k++)
               sum+=close[n-1-k];
            g_ema[s]=sum/InpEMA;
           }
         else
            g_ema[s]=g_ema[s+1]+2.0/(InpEMA+1)*(close[s]-g_ema[s+1]);
      g_ema_draw[s]=g_ema[s];
      //--- RSI (Wilder): RMA of gains and losses seeded with the SMA of the first InpRSI changes
      g_rsi[s]=EMPTY_VALUE;
      g_gain[s]=EMPTY_VALUE;
      g_loss[s]=EMPTY_VALUE;
      if(i>=InpRSI)
        {
         if(i==InpRSI)
           {
            double sg=0,sl=0;
            for(int k=1; k<=InpRSI; k++)
              {
               double ch=close[n-1-k]-close[n-k];
               sg+=MathMax(ch,0.0);
               sl+=MathMax(-ch,0.0);
              }
            g_gain[s]=sg/InpRSI;
            g_loss[s]=sl/InpRSI;
           }
         else
           {
            double ch=close[s]-close[s+1];
            g_gain[s]=(g_gain[s+1]*(InpRSI-1)+MathMax(ch,0.0))/InpRSI;
            g_loss[s]=(g_loss[s+1]*(InpRSI-1)+MathMax(-ch,0.0))/InpRSI;
           }
         if(g_loss[s]==0.0)
            g_rsi[s]=100.0;
         else
            if(g_gain[s]==0.0)
               g_rsi[s]=0.0;
            else
               g_rsi[s]=100.0-100.0/(1.0+g_gain[s]/g_loss[s]);
        }
      //--- SuperTrend bands and trend
      g_buy[s]=EMPTY_VALUE;
      g_sell[s]=EMPTY_VALUE;
      if(g_atr[s]==EMPTY_VALUE)
        {
         g_up[s]=EMPTY_VALUE;
         g_dn[s]=EMPTY_VALUE;
         g_trend[s]=EMPTY_VALUE;
         g_line[s]=EMPTY_VALUE;
         Segments(s,n);
         continue;
        }
      double src=(high[s]+low[s])/2.0;
      double up=src-InpMult*g_atr[s];
      double dn=src+InpMult*g_atr[s];
      bool fresh=(i==0 || g_up[s+1]==EMPTY_VALUE);
      double up1=(fresh ? up : g_up[s+1]);
      double dn1=(fresh ? dn : g_dn[s+1]);
      if(i>0 && Above(close[s+1],up1))
         up=MathMax(up,up1);
      if(i>0 && Below(close[s+1],dn1))
         dn=MathMin(dn,dn1);
      double trend=(fresh ? 1.0 : g_trend[s+1]);
      if(trend==-1.0 && Above(close[s],dn1))
         trend=1.0;
      else
         if(trend==1.0 && Below(close[s],up1))
            trend=-1.0;
      g_up[s]=up;
      g_dn[s]=dn;
      g_trend[s]=trend;
      g_line[s]=(trend==1.0 ? up : dn);
      Segments(s,n);
      //--- signals: the trend flips; only on closed bars (s>=1)
      if(fresh || s<1)
         continue;
      bool buy=(trend==1.0 && g_trend[s+1]==-1.0);
      bool sell=(trend==-1.0 && g_trend[s+1]==1.0);
      if(InpUseEMA)
        {
         buy=buy && g_ema[s]!=EMPTY_VALUE && close[s]>g_ema[s];
         sell=sell && g_ema[s]!=EMPTY_VALUE && close[s]<g_ema[s];
        }
      if(InpUseRSI)
        {
         buy=buy && g_rsi[s]!=EMPTY_VALUE && g_rsi[s]>50.0;
         sell=sell && g_rsi[s]!=EMPTY_VALUE && g_rsi[s]<50.0;
        }
      if(buy)
        {
         g_buy[s]=low[s]-InpArrowGap*g_atr[s];
         if(s==1)
            SignalAlert(PRODUCT,"BUY, trend up from "+DoubleToString(close[s],_Digits),time[s],prev_calculated>0);
        }
      if(sell)
        {
         g_sell[s]=high[s]+InpArrowGap*g_atr[s];
         if(s==1)
            SignalAlert(PRODUCT,"SELL, trend down from "+DoubleToString(close[s],_Digits),time[s],prev_calculated>0);
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+

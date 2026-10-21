//+------------------------------------------------------------------+
//|                                               SuperTrendDump.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped): dumps the MT4 SuperTrend buffers and      |
//| checks repainting in the Strategy Tester, via IndTest4/Dump4.mqh.|
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

input int    InpATR    = 10;
input double InpMult   = 3.0;
input int    InpMethod = 0;
input bool   InpUseEMA = false;
input int    InpEMA    = 200;
input bool   InpUseRSI = false;
input int    InpRSI    = 14;

double IndValue(const int buf,const int shift)
  {
   return(iCustom(NULL,0,"SuperTrendSignalAlerts\\SuperTrendSignalAlerts",InpATR,InpMult,InpMethod,InpUseEMA,InpEMA,true,
                  InpUseRSI,InpRSI,true,0.3,false,false,"alert.wav",false,false,buf,shift));
  }

#include <IndTest4/Dump4.mqh>
//+------------------------------------------------------------------+

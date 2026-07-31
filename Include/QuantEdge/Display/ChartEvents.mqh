//+------------------------------------------------------------------+
//|                                            ChartEvents.mqh         |
//|                         QuantEdge - Chart Event Handling         |
//+------------------------------------------------------------------+
#ifndef QE_CHARTEVENTS_MQH
#define QE_CHARTEVENTS_MQH

#include "../Core/Config.mqh"
#include "../Core/Globals.mqh"
#include "../Core/MathUtils.mqh"
#include "../Engine/SignalEngine.mqh"
#include "../Engine/MTFEngine.mqh"
#include "../Engine/ProbabilityEngine.mqh"
#include "PanelDrawing.mqh"
#include "LineDrawing.mqh"

//+------------------------------------------------------------------+
void HandleChartEvent(const int id, const long &lparam,
                      const double &dparam, const string &sparam)
{
   // Arrow click
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, PREFIX_ARROW) == 0)
      {
         int sigIdx = FindSignalByArrowName(sparam);
         if(sigIdx >= 0)
         {
            if(g_activeSignalIndex == sigIdx && g_userSelectedSignal)
            {
               DeleteObjectsByPrefix(PREFIX_PANEL);
               DeleteObjectsByPrefix(PREFIX_LINE);
               DeleteObjectsByPrefix(PREFIX_PROB);
               DeleteObjectsByPrefix(PREFIX_ZONE);
               g_activeSignalIndex = g_signalCount - 1;
               g_userSelectedSignal = false;
            }
            else
            {
               g_activeSignalIndex = sigIdx;
               g_userSelectedSignal = true;
               if(InpShowMTF) RefreshMTFData();
               if(InpShowProbability) CalculateProbability(sigIdx, BufferOrange, BufferBBUpper, BufferBBLower);
               DrawInfoPanel(sigIdx);
               DrawSLTPLines(sigIdx);
               if(InpShowProbability) DrawProbabilityLabels();
            }
         }
         return;
      }
   }

   // Panel drag
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      if(!InpShowPanel || g_activeSignalIndex < 0) return;
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseFlags = (int)StringToInteger(sparam);
      bool leftDown = ((mouseFlags & 1) == 1);

      if(g_panelDragging)
      {
         if(leftDown)
         {
            int newX = mouseX - g_dragOffsetX;
            int newY = mouseY - g_dragOffsetY;
            if(newX < 0) newX = 0;
            if(newY < 0) newY = 0;
            if(newX != g_panelPosX || newY != g_panelPosY)
            {
               g_panelPosX = newX;
               g_panelPosY = newY;
               static uint s_lastDrag = 0;
               uint now = GetTickCount();
               if(now - s_lastDrag > 40)
               {
                  s_lastDrag = now;
                  DrawInfoPanel(g_activeSignalIndex);
               }
            }
         }         
         else
         {
            g_panelDragging = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            SavePanelPosition();
            g_panelUserMoved = true;  // ← THÊM DÒNG NÀY
            DrawInfoPanel(g_activeSignalIndex);
         }
      }
      else if(leftDown)
      {
         int titleH = InpPanelFontSize + 14;
         if(mouseX >= g_panelPosX && mouseX <= g_panelPosX + InpPanelWidth &&
            mouseY >= g_panelPosY && mouseY <= g_panelPosY + titleH)
         {
            g_panelDragging = true;
            g_dragOffsetX = mouseX - g_panelPosX;
            g_dragOffsetY = mouseY - g_panelPosY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
      }
      if(!g_panelDragging && !leftDown)
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   }
}

#endif
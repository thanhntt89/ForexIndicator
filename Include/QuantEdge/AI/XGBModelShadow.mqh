//+------------------------------------------------------------------+
//| XGBModelShadow.mqh - Shadow (candidate) model loader/evaluator    |
//| Sprint 4: A/B shadow mode. Duplicates XGBModel.mqh's binary       |
//| loader/tree evaluator under shadow-specific names so the live     |
//| champion path (XGBModel.mqh) stays byte-for-byte untouched.       |
//|                                                                    |
//| Binary file: Common/Files/QuantEdge_RSI/XGBModels_shadow.bin      |
//| Auto-reload: every 5 minutes via CheckXGBShadowReload()           |
//| Gated by InpEnableXGBShadow — zero cost when disabled.            |
//+------------------------------------------------------------------+
#ifndef QE_XGBMODELSHADOW_MQH
#define QE_XGBMODELSHADOW_MQH

#define XGB_SHADOW_MODEL_FILE     "QuantEdge_RSI\\XGBModels_shadow.bin"
#define XGB_SHADOW_RELOAD_SECONDS 300

//+------------------------------------------------------------------+
//| Structs (mirrors XGBNode / XGBTreeMeta / XGBModelMeta)             |
//+------------------------------------------------------------------+
struct XGBShadowNode
{
   int    featureIndex;
   double threshold;
   int    leftChild;
   int    rightChild;
   double leafValue;
};

struct XGBShadowTreeMeta
{
   int nodeStartIdx;
   int nodeCount;
};

struct XGBShadowModelMeta
{
   string symbol;
   int    period;
   int    treeStartIdx;
   int    treeCount;
   int    nFeatures;
   double oosBrier;
   double oosAuc;
};

//+------------------------------------------------------------------+
//| Globals (mirrors g_xgbNodes / g_xgbTrees / g_xgbModels)             |
//+------------------------------------------------------------------+
XGBShadowNode      g_xgbShadowNodes[];
int                g_xgbShadowNodeCount  = 0;

XGBShadowTreeMeta  g_xgbShadowTrees[];
int                g_xgbShadowTreeCount  = 0;

XGBShadowModelMeta g_xgbShadowModels[];
int                g_xgbShadowModelCount = 0;

bool               g_xgbShadowLoaded        = false;
int                g_xgbShadowFileTimestamp = 0;
double             g_xgbShadowBestBrier     = 0.25;
datetime           g_xgbShadowLastCheck     = 0;

//+------------------------------------------------------------------+
//| LoadXGBShadowModel — read shadow binary model file                |
//+------------------------------------------------------------------+
bool LoadXGBShadowModel()
{
   int fh = FileOpen(XGB_SHADOW_MODEL_FILE, FILE_COMMON | FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      if(!g_xgbShadowLoaded)
         Print("[XGB-SHADOW] Model file not found: ", XGB_SHADOW_MODEL_FILE);
      return(false);
   }

   long fileSize = FileSize(fh);
   if(fileSize < 28)
   {
      Print("[XGB-SHADOW] File too small: ", fileSize, " bytes");
      FileClose(fh);
      return(false);
   }

   int magic   = FileReadInteger(fh, INT_VALUE);
   int version = FileReadInteger(fh, INT_VALUE);
   int nModels = FileReadInteger(fh, INT_VALUE);
   int ts      = FileReadInteger(fh, INT_VALUE);
   int nFeat   = FileReadInteger(fh, INT_VALUE);
   double reserved = FileReadDouble(fh);

   if(magic != XGB_BIN_MAGIC)
   {
      Print("[XGB-SHADOW] Bad magic: 0x", IntegerToString(magic, 8, '0'));
      FileClose(fh);
      return(false);
   }
   if(version != XGB_BIN_VERSION)
   {
      Print("[XGB-SHADOW] Unsupported version: ", version);
      FileClose(fh);
      return(false);
   }
   if(nModels < 1 || nModels > XGB_MAX_MODELS)
   {
      Print("[XGB-SHADOW] Invalid model_count: ", nModels);
      FileClose(fh);
      return(false);
   }

   XGBShadowNode      tmpNodes[];
   XGBShadowTreeMeta  tmpTrees[];
   XGBShadowModelMeta tmpModels[];
   int tmpNodeCount = 0;
   int tmpTreeCount = 0;

   ArrayResize(tmpModels, nModels);
   ArrayResize(tmpTrees, 0);
   ArrayResize(tmpNodes, 0);

   for(int m = 0; m < nModels; m++)
   {
      if(FileIsEnding(fh)) { Print("[XGB-SHADOW] Unexpected EOF at model ", m); FileClose(fh); return(false); }

      string sym  = ReadFixedString(fh, 16);
      int period  = FileReadInteger(fh, INT_VALUE);
      int nTrees  = FileReadInteger(fh, INT_VALUE);
      int mFeat   = FileReadInteger(fh, INT_VALUE);
      double brier = FileReadDouble(fh);
      double auc   = FileReadDouble(fh);

      if(nTrees < 1 || nTrees > 500)
      {
         Print("[XGB-SHADOW] Model ", m, " (", sym, ") invalid n_trees: ", nTrees);
         FileClose(fh);
         return(false);
      }

      tmpModels[m].symbol       = sym;
      tmpModels[m].period       = period;
      tmpModels[m].treeStartIdx = tmpTreeCount;
      tmpModels[m].treeCount    = nTrees;
      tmpModels[m].nFeatures    = mFeat;
      tmpModels[m].oosBrier     = brier;
      tmpModels[m].oosAuc       = auc;

      for(int t = 0; t < nTrees; t++)
      {
         if(FileIsEnding(fh)) { Print("[XGB-SHADOW] Unexpected EOF at tree ", t); FileClose(fh); return(false); }

         int nNodes = FileReadInteger(fh, INT_VALUE);
         if(nNodes < 1 || nNodes > 1000)
         {
            Print("[XGB-SHADOW] Model ", m, " tree ", t, " invalid n_nodes: ", nNodes);
            FileClose(fh);
            return(false);
         }

         int treeIdx = tmpTreeCount;
         tmpTreeCount++;
         ArrayResize(tmpTrees, tmpTreeCount);
         tmpTrees[treeIdx].nodeStartIdx = tmpNodeCount;
         tmpTrees[treeIdx].nodeCount    = nNodes;

         int oldNodeCount = tmpNodeCount;
         tmpNodeCount += nNodes;
         ArrayResize(tmpNodes, tmpNodeCount);

         for(int n = 0; n < nNodes; n++)
         {
            if(FileIsEnding(fh)) { Print("[XGB-SHADOW] Unexpected EOF at node ", n); FileClose(fh); return(false); }

            int absIdx = oldNodeCount + n;
            tmpNodes[absIdx].featureIndex = FileReadInteger(fh, INT_VALUE);
            tmpNodes[absIdx].threshold    = FileReadDouble(fh);
            tmpNodes[absIdx].leftChild    = FileReadInteger(fh, INT_VALUE);
            tmpNodes[absIdx].rightChild   = FileReadInteger(fh, INT_VALUE);
            tmpNodes[absIdx].leafValue    = FileReadDouble(fh);
         }
      }
   }

   FileClose(fh);

   // Success — swap into globals
   g_xgbShadowModelCount = nModels;
   ArrayResize(g_xgbShadowModels, nModels);
   for(int i = 0; i < nModels; i++)
   {
      g_xgbShadowModels[i].symbol       = tmpModels[i].symbol;
      g_xgbShadowModels[i].period       = tmpModels[i].period;
      g_xgbShadowModels[i].treeStartIdx = tmpModels[i].treeStartIdx;
      g_xgbShadowModels[i].treeCount    = tmpModels[i].treeCount;
      g_xgbShadowModels[i].nFeatures    = tmpModels[i].nFeatures;
      g_xgbShadowModels[i].oosBrier     = tmpModels[i].oosBrier;
      g_xgbShadowModels[i].oosAuc       = tmpModels[i].oosAuc;
   }

   g_xgbShadowTreeCount = tmpTreeCount;
   ArrayResize(g_xgbShadowTrees, tmpTreeCount);
   for(int i = 0; i < tmpTreeCount; i++)
   {
      g_xgbShadowTrees[i].nodeStartIdx = tmpTrees[i].nodeStartIdx;
      g_xgbShadowTrees[i].nodeCount    = tmpTrees[i].nodeCount;
   }

   g_xgbShadowNodeCount = tmpNodeCount;
   ArrayResize(g_xgbShadowNodes, tmpNodeCount);
   for(int i = 0; i < tmpNodeCount; i++)
   {
      g_xgbShadowNodes[i].featureIndex = tmpNodes[i].featureIndex;
      g_xgbShadowNodes[i].threshold    = tmpNodes[i].threshold;
      g_xgbShadowNodes[i].leftChild    = tmpNodes[i].leftChild;
      g_xgbShadowNodes[i].rightChild   = tmpNodes[i].rightChild;
      g_xgbShadowNodes[i].leafValue    = tmpNodes[i].leafValue;
   }

   g_xgbShadowFileTimestamp = ts;
   g_xgbShadowLoaded        = true;

   double bestBrier = 1.0;
   for(int i = 0; i < nModels; i++)
      if(g_xgbShadowModels[i].oosBrier < bestBrier)
         bestBrier = g_xgbShadowModels[i].oosBrier;
   g_xgbShadowBestBrier = bestBrier;

   Print("[XGB-SHADOW] Loaded ", nModels, " models, ",
         tmpTreeCount, " trees, ", tmpNodeCount, " nodes (ts=", ts, ")");

   return(true);
}

//+------------------------------------------------------------------+
//| CheckXGBShadowReload — periodic file change detection             |
//+------------------------------------------------------------------+
void CheckXGBShadowReload()
{
   datetime now = TimeCurrent();
   if(now - g_xgbShadowLastCheck < XGB_SHADOW_RELOAD_SECONDS) return;
   g_xgbShadowLastCheck = now;

   int fh = FileOpen(XGB_SHADOW_MODEL_FILE, FILE_COMMON | FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) return;

   long fileSize = FileSize(fh);
   if(fileSize < 28) { FileClose(fh); return; }

   FileReadInteger(fh, INT_VALUE);  // magic
   FileReadInteger(fh, INT_VALUE);  // version
   FileReadInteger(fh, INT_VALUE);  // model_count
   int fileTs = FileReadInteger(fh, INT_VALUE);
   FileClose(fh);

   if(fileTs == g_xgbShadowFileTimestamp) return;

   Print("[XGB-SHADOW] Model file updated (ts=", fileTs, ") — reloading...");
   LoadXGBShadowModel();
}

//+------------------------------------------------------------------+
//| XGBFindShadowModel — find shadow model index for symbol+period    |
//+------------------------------------------------------------------+
int XGBFindShadowModel(string symbol, int period)
{
   if(!g_xgbShadowLoaded) return(-1);

   for(int i = 0; i < g_xgbShadowModelCount; i++)
   {
      if(g_xgbShadowModels[i].symbol == symbol && g_xgbShadowModels[i].period == period)
         return(i);
   }
   // Suffix tolerance: XAUUSDc, XAUUSD.a match XAUUSD
   for(int i = 0; i < g_xgbShadowModelCount; i++)
   {
      if(StringFind(symbol, g_xgbShadowModels[i].symbol) == 0 && g_xgbShadowModels[i].period == period)
         return(i);
   }
   return(-1);
}

//+------------------------------------------------------------------+
//| EvalShadowTree — iterative tree traversal (shadow model)          |
//+------------------------------------------------------------------+
double EvalShadowTree(int treeIdx, const double &features[])
{
   int nodeStart = g_xgbShadowTrees[treeIdx].nodeStartIdx;
   int nodeIdx   = 0;

   for(int iter = 0; iter < 64; iter++)
   {
      int absIdx = nodeStart + nodeIdx;
      if(absIdx < 0 || absIdx >= g_xgbShadowNodeCount) return(0.0);

      if(g_xgbShadowNodes[absIdx].featureIndex < 0)
         return(g_xgbShadowNodes[absIdx].leafValue);

      int fi = g_xgbShadowNodes[absIdx].featureIndex;
      if(fi >= ArraySize(features)) return(0.0);

      if(features[fi] < g_xgbShadowNodes[absIdx].threshold)
         nodeIdx = g_xgbShadowNodes[absIdx].leftChild;
      else
         nodeIdx = g_xgbShadowNodes[absIdx].rightChild;
   }
   return(0.0);
}

//+------------------------------------------------------------------+
//| XGBPredictShadow — shadow entry point (SAME 19-param signature    |
//| as XGBPredict() so XGBGetShadowPrediction() can mirror            |
//| XGBGetPrediction() call-for-call)                                  |
//+------------------------------------------------------------------+
double XGBPredictShadow(
   double rsiAtSignal,
   double angleZ,
   double atrRatio,
   double slDistATR,
   double tp1DistATR,
   double rrRatio,
   double spreadPips,
   double timeInSessionMin,
   int    caseNum,
   int    dir,
   int    session,
   int    hour,
   int    dow,
   int    d1Trend,
   int    mtfAgreePct,
   double spreadRatio,
   int    wfRobust,
   int    h4Trend,
   int    h1Trend)
{
   if(!g_xgbShadowLoaded) return(50.0);

   int modelIdx = XGBFindShadowModel(Symbol(), Period());
   if(modelIdx < 0) return(50.0);

   double features[22];
   features[0]  = rsiAtSignal;
   features[1]  = angleZ;
   features[2]  = atrRatio;
   features[3]  = slDistATR;
   features[4]  = tp1DistATR;
   features[5]  = rrRatio;
   features[6]  = spreadPips;
   features[7]  = timeInSessionMin;
   features[8]  = (double)mtfAgreePct;
   features[9]  = spreadRatio;
   features[10] = (double)wfRobust;
   features[11] = (double)h4Trend;
   features[12] = (double)h1Trend;
   features[13] = (double)d1Trend;
   features[14] = (double)caseNum;
   features[15] = (double)dir;
   features[16] = (double)session;
   features[17] = MathSin(2.0 * M_PI * hour / 24.0);
   features[18] = MathCos(2.0 * M_PI * hour / 24.0);
   features[19] = MathSin(2.0 * M_PI * dow / 5.0);
   features[20] = MathCos(2.0 * M_PI * dow / 5.0);

   double logit = 0.0;
   int treeStart = g_xgbShadowModels[modelIdx].treeStartIdx;
   int treeEnd   = treeStart + g_xgbShadowModels[modelIdx].treeCount;

   for(int t = treeStart; t < treeEnd; t++)
      logit += EvalShadowTree(t, features);

   double prob = 1.0 / (1.0 + MathExp(-logit));
   return(prob * 100.0);
}

#endif

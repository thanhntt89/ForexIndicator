//+------------------------------------------------------------------+
//| XGBModel.mqh - Runtime binary loader + array-based tree evaluator|
//| V12.2: Loads XGBoost model from binary file at runtime.          |
//| No recompile needed when model is updated by xgb_service.py.     |
//|                                                                    |
//| Binary file: Common/Files/QuantEdge_RSI/XGBModels.bin             |
//| Auto-reload: every 5 minutes via CheckXGBReload()                 |
//+------------------------------------------------------------------+
#ifndef QE_XGBMODEL_MQH
#define QE_XGBMODEL_MQH

#define XGB_BIN_MAGIC         0x58474231
#define XGB_BIN_VERSION       1
#define XGB_MAX_MODELS        20
#define XGB_MAX_TREES_TOTAL   2000
#define XGB_MAX_NODES_TOTAL   100000
#define XGB_NUM_FEATURES      26
#define XGB_MODEL_FILE        "QuantEdge_RSI\\XGBModels.bin"
#define XGB_RELOAD_SECONDS    300

//+------------------------------------------------------------------+
//| Structs                                                           |
//+------------------------------------------------------------------+
struct XGBNode
{
   int    featureIndex;
   double threshold;
   int    leftChild;
   int    rightChild;
   double leafValue;
};

struct XGBTreeMeta
{
   int nodeStartIdx;
   int nodeCount;
};

struct XGBModelMeta
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
//| Globals                                                           |
//+------------------------------------------------------------------+
XGBNode      g_xgbNodes[];
int          g_xgbNodeCount     = 0;

XGBTreeMeta  g_xgbTrees[];
int          g_xgbTreeCount     = 0;

XGBModelMeta g_xgbModels[];
int          g_xgbModelCount    = 0;

bool         g_xgbLoaded        = false;
int          g_xgbFileTimestamp  = 0;
double       g_xgbBestBrier     = 0.25;
datetime     g_xgbLastCheck     = 0;

#define XGB_MODEL_TRAINED    g_xgbFileTimestamp
#define XGB_MODEL_OOS_BRIER  g_xgbBestBrier
#define XGB_MODEL_TREES      g_xgbTreeCount
#define XGB_MODEL_DEPTH      4

//+------------------------------------------------------------------+
//| ReadFixedString — read N bytes as string (MQL4/5 compatible)      |
//+------------------------------------------------------------------+
string ReadFixedString(int fh, int len)
{
   string result = "";
   for(int i = 0; i < len; i++)
   {
      int ch = (int)FileReadInteger(fh, CHAR_VALUE);
      if(ch > 0) result += CharToString((uchar)ch);
   }
   return(result);
}

//+------------------------------------------------------------------+
//| LoadXGBModels — read binary model file from Common/Files          |
//+------------------------------------------------------------------+
bool LoadXGBModels()
{
   int fh = FileOpen(XGB_MODEL_FILE, FILE_COMMON | FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE)
   {
      if(!g_xgbLoaded)
         Print("[XGB] Model file not found: ", XGB_MODEL_FILE);
      return(false);
   }

   long fileSize = FileSize(fh);
   if(fileSize < 28)
   {
      Print("[XGB] File too small: ", fileSize, " bytes");
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
      Print("[XGB] Bad magic: 0x", IntegerToString(magic, 8, '0'));
      FileClose(fh);
      return(false);
   }
   if(version != XGB_BIN_VERSION)
   {
      Print("[XGB] Unsupported version: ", version);
      FileClose(fh);
      return(false);
   }
   if(nModels < 1 || nModels > XGB_MAX_MODELS)
   {
      Print("[XGB] Invalid model_count: ", nModels);
      FileClose(fh);
      return(false);
   }

   XGBNode      tmpNodes[];
   XGBTreeMeta  tmpTrees[];
   XGBModelMeta tmpModels[];
   int tmpNodeCount = 0;
   int tmpTreeCount = 0;

   ArrayResize(tmpModels, nModels);
   ArrayResize(tmpTrees, 0);
   ArrayResize(tmpNodes, 0);

   for(int m = 0; m < nModels; m++)
   {
      if(FileIsEnding(fh)) { Print("[XGB] Unexpected EOF at model ", m); FileClose(fh); return(false); }

      string sym  = ReadFixedString(fh, 16);
      int period  = FileReadInteger(fh, INT_VALUE);
      int nTrees  = FileReadInteger(fh, INT_VALUE);
      int mFeat   = FileReadInteger(fh, INT_VALUE);
      double brier = FileReadDouble(fh);
      double auc   = FileReadDouble(fh);

      if(nTrees < 1 || nTrees > 500)
      {
         Print("[XGB] Model ", m, " (", sym, ") invalid n_trees: ", nTrees);
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
         if(FileIsEnding(fh)) { Print("[XGB] Unexpected EOF at tree ", t); FileClose(fh); return(false); }

         int nNodes = FileReadInteger(fh, INT_VALUE);
         if(nNodes < 1 || nNodes > 1000)
         {
            Print("[XGB] Model ", m, " tree ", t, " invalid n_nodes: ", nNodes);
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
            if(FileIsEnding(fh)) { Print("[XGB] Unexpected EOF at node ", n); FileClose(fh); return(false); }

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
   g_xgbModelCount = nModels;
   ArrayResize(g_xgbModels, nModels);
   for(int i = 0; i < nModels; i++)
   {
      g_xgbModels[i].symbol       = tmpModels[i].symbol;
      g_xgbModels[i].period       = tmpModels[i].period;
      g_xgbModels[i].treeStartIdx = tmpModels[i].treeStartIdx;
      g_xgbModels[i].treeCount    = tmpModels[i].treeCount;
      g_xgbModels[i].nFeatures    = tmpModels[i].nFeatures;
      g_xgbModels[i].oosBrier     = tmpModels[i].oosBrier;
      g_xgbModels[i].oosAuc       = tmpModels[i].oosAuc;
   }

   g_xgbTreeCount = tmpTreeCount;
   ArrayResize(g_xgbTrees, tmpTreeCount);
   for(int i = 0; i < tmpTreeCount; i++)
   {
      g_xgbTrees[i].nodeStartIdx = tmpTrees[i].nodeStartIdx;
      g_xgbTrees[i].nodeCount    = tmpTrees[i].nodeCount;
   }

   g_xgbNodeCount = tmpNodeCount;
   ArrayResize(g_xgbNodes, tmpNodeCount);
   for(int i = 0; i < tmpNodeCount; i++)
   {
      g_xgbNodes[i].featureIndex = tmpNodes[i].featureIndex;
      g_xgbNodes[i].threshold    = tmpNodes[i].threshold;
      g_xgbNodes[i].leftChild    = tmpNodes[i].leftChild;
      g_xgbNodes[i].rightChild   = tmpNodes[i].rightChild;
      g_xgbNodes[i].leafValue    = tmpNodes[i].leafValue;
   }

   g_xgbFileTimestamp = ts;
   g_xgbLoaded        = true;

   double bestBrier = 1.0;
   for(int i = 0; i < nModels; i++)
      if(g_xgbModels[i].oosBrier < bestBrier)
         bestBrier = g_xgbModels[i].oosBrier;
   g_xgbBestBrier = bestBrier;

   Print("[XGB] Loaded ", nModels, " models, ",
         tmpTreeCount, " trees, ", tmpNodeCount, " nodes (ts=", ts, ")");

   return(true);
}

//+------------------------------------------------------------------+
//| CheckXGBReload — periodic file change detection                   |
//+------------------------------------------------------------------+
void CheckXGBReload()
{
   datetime now = TimeCurrent();
   if(now - g_xgbLastCheck < XGB_RELOAD_SECONDS) return;
   g_xgbLastCheck = now;

   int fh = FileOpen(XGB_MODEL_FILE, FILE_COMMON | FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE) return;

   long fileSize = FileSize(fh);
   if(fileSize < 28) { FileClose(fh); return; }

   FileReadInteger(fh, INT_VALUE);  // magic
   FileReadInteger(fh, INT_VALUE);  // version
   FileReadInteger(fh, INT_VALUE);  // model_count
   int fileTs = FileReadInteger(fh, INT_VALUE);
   FileClose(fh);

   if(fileTs == g_xgbFileTimestamp) return;

   Print("[XGB] Model file updated (ts=", fileTs, ") — reloading...");
   LoadXGBModels();
}

//+------------------------------------------------------------------+
//| XGBFindModel — find model index for symbol+period                 |
//+------------------------------------------------------------------+
int XGBFindModel(string symbol, int period)
{
   if(!g_xgbLoaded) return(-1);

   for(int i = 0; i < g_xgbModelCount; i++)
   {
      if(g_xgbModels[i].symbol == symbol && g_xgbModels[i].period == period)
         return(i);
   }
   // Suffix tolerance: XAUUSDc, XAUUSD.a match XAUUSD
   for(int i = 0; i < g_xgbModelCount; i++)
   {
      if(StringFind(symbol, g_xgbModels[i].symbol) == 0 && g_xgbModels[i].period == period)
         return(i);
   }
   return(-1);
}

//+------------------------------------------------------------------+
//| EvalTree — iterative tree traversal                               |
//+------------------------------------------------------------------+
double EvalTree(int treeIdx, const double &features[])
{
   int nodeStart = g_xgbTrees[treeIdx].nodeStartIdx;
   int nodeIdx   = 0;

   for(int iter = 0; iter < 64; iter++)
   {
      int absIdx = nodeStart + nodeIdx;
      if(absIdx < 0 || absIdx >= g_xgbNodeCount) return(0.0);

      if(g_xgbNodes[absIdx].featureIndex < 0)
         return(g_xgbNodes[absIdx].leafValue);

      int fi = g_xgbNodes[absIdx].featureIndex;
      if(fi >= ArraySize(features)) return(0.0);

      if(features[fi] < g_xgbNodes[absIdx].threshold)
         nodeIdx = g_xgbNodes[absIdx].leftChild;
      else
         nodeIdx = g_xgbNodes[absIdx].rightChild;
   }
   return(0.0);
}

//+------------------------------------------------------------------+
//| XGBPredict — main entry point (SIGNATURE UNCHANGED from V12.0)    |
//+------------------------------------------------------------------+
double XGBPredict(
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
   int    h1Trend,
   // P2 additions (Advanced Features: ADX/MACD/US10Y). Default 0 keeps
   // any pre-existing call site source-compatible and behaviorally
   // identical (old model binaries never reference indices 21-25).
   double adxValue = 0.0,
   double macdHistogram = 0.0,
   double macdSlope = 0.0,
   double us10yTrend = 0.0)
{
   if(!g_xgbLoaded) return(50.0);

   int modelIdx = XGBFindModel(Symbol(), Period());
   if(modelIdx < 0) return(50.0);

   double features[26];
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
   features[21] = adxValue;
   features[22] = macdHistogram;
   features[23] = macdSlope;
   features[24] = us10yTrend;

   double logit = 0.0;
   int treeStart = g_xgbModels[modelIdx].treeStartIdx;
   int treeEnd   = treeStart + g_xgbModels[modelIdx].treeCount;

   for(int t = treeStart; t < treeEnd; t++)
      logit += EvalTree(t, features);

   double prob = 1.0 / (1.0 + MathExp(-logit));
   return(prob * 100.0);
}

#endif

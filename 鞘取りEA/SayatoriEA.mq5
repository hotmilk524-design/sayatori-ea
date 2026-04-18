//+------------------------------------------------------------------+
//| SayatoriEA.mq5 - 鞘取りEA (統計的裁定取引)                       |
//| EURUSD/GBPUSDの価格差をZスコアで監視し平均回帰を狙う              |
//+------------------------------------------------------------------+
#property copyright "EA開発プロジェクト"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "Include\Logger.mqh"
#include "Include\SpreadCalc.mqh"

//--- 入力パラメータ ---
input group "--- ペア設定 ---"
input string   Sym1          = "EURUSD";  // シンボル1
input string   Sym2          = "GBPUSD";  // シンボル2
input int      LookBack      = 100;       // Zスコア計算期間（バー数）

input group "--- エントリー/決済条件 ---"
input double   EntryZ        = 2.0;       // エントリーZスコア閾値
input double   ExitZ         = 0.3;       // 決済Zスコア閾値（平均回帰）
input double   StopZ         = 4.0;       // 損切りZスコア閾値（トレンド判定）

input group "--- ロット設定 ---"
input double   LotSize       = 0.01;      // ロットサイズ
input int      MagicNumber   = 20240101;  // マジックナンバー

input group "--- フィルター ---"
input bool     UseTimeFilter = false;     // 時間フィルター使用
input int      StartHour     = 9;         // 開始時間（GMT）
input int      EndHour       = 17;        // 終了時間（GMT）
input int      MaxSpreadPts  = 30;        // 最大許容スプレッド（ポイント）

//--- 内部状態（グローバル変数はバグの原因になるため最小限に抑える）
static double g_mean   = 0;
static double g_stddev = 0;
static int    g_lastBar = -1;

CTrade trade;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   SymbolSelect(Sym1, true);
   SymbolSelect(Sym2, true);
   LogInfo("初期化完了 ペア=" + Sym1 + "/" + Sym2 +
           " LookBack=" + IntegerToString(LookBack) +
           " EntryZ="   + DoubleToString(EntryZ, 1));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogInfo("終了 reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
// 時間フィルター判定
bool IsTimeOK()
{
   if(!UseTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour >= StartHour && dt.hour < EndHour;
}

//+------------------------------------------------------------------+
// 両シンボルのスプレッドが許容範囲内か確認
bool IsSpreadOK()
{
   int sp1 = (int)SymbolInfoInteger(Sym1, SYMBOL_SPREAD);
   int sp2 = (int)SymbolInfoInteger(Sym2, SYMBOL_SPREAD);
   return sp1 <= MaxSpreadPts && sp2 <= MaxSpreadPts;
}

//+------------------------------------------------------------------+
// 自分のポジション（MagicNumber一致）を取得
bool GetMyPositions(ulong &ticket1, ulong &ticket2)
{
   ticket1 = 0;
   ticket2 = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym == Sym1) ticket1 = tk;
      if(sym == Sym2) ticket2 = tk;
   }
   return ticket1 > 0 && ticket2 > 0;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // 新しいバーが確定したときだけ統計を再計算（処理負荷を下げる）
   int curBar = (int)(TimeCurrent() / PeriodSeconds(PERIOD_CURRENT));
   if(curBar != g_lastBar)
   {
      if(!CalcSpreadStats(Sym1, Sym2, PERIOD_CURRENT, LookBack, g_mean, g_stddev))
      {
         LogError("統計計算失敗 データ不足の可能性");
         return;
      }
      g_lastBar = curBar;
      LogDebug(StringFormat("統計更新 mean=%.5f stddev=%.5f", g_mean, g_stddev));
   }

   if(g_stddev <= 0) return;
   if(!IsTimeOK() || !IsSpreadOK()) return;

   double z = CalcZScore(Sym1, Sym2, g_mean, g_stddev);
   LogDebug(StringFormat("Z=%.3f", z));

   ulong ticket1 = 0, ticket2 = 0;
   bool hasPos = GetMyPositions(ticket1, ticket2);

   // 決済ロジック
   if(hasPos)
   {
      if(MathAbs(z) <= ExitZ)
      {
         // 平均回帰で利確
         LogInfo(StringFormat("利確(平均回帰) Z=%.3f", z));
         trade.PositionClose(ticket1);
         trade.PositionClose(ticket2);
         return;
      }
      if(MathAbs(z) >= StopZ)
      {
         // Zスコアが拡大し続けたらトレンドと判定して損切り
         LogInfo(StringFormat("損切り(トレンド判定) Z=%.3f", z));
         trade.PositionClose(ticket1);
         trade.PositionClose(ticket2);
         return;
      }
      return;  // 保有中は追加エントリーしない
   }

   // エントリーロジック
   if(z > EntryZ)
   {
      // Sym1が割高 → Sym1売り・Sym2買い
      double bid1 = SymbolInfoDouble(Sym1, SYMBOL_BID);
      double ask2 = SymbolInfoDouble(Sym2, SYMBOL_ASK);
      LogInfo(StringFormat("エントリー SELL %s / BUY %s  Z=%.3f", Sym1, Sym2, z));
      trade.Sell(LotSize, Sym1, bid1, 0, 0, "SayatoriSELL");
      trade.Buy (LotSize, Sym2, ask2, 0, 0, "SayatoriBUY");
   }
   else if(z < -EntryZ)
   {
      // Sym1が割安 → Sym1買い・Sym2売り
      double ask1 = SymbolInfoDouble(Sym1, SYMBOL_ASK);
      double bid2 = SymbolInfoDouble(Sym2, SYMBOL_BID);
      LogInfo(StringFormat("エントリー BUY %s / SELL %s  Z=%.3f", Sym1, Sym2, z));
      trade.Buy (LotSize, Sym1, ask1, 0, 0, "SayatoriBUY");
      trade.Sell(LotSize, Sym2, bid2, 0, 0, "SayatoriSELL");
   }
}
//+------------------------------------------------------------------+

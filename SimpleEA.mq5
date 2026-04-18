//+------------------------------------------------------------------+
//|                                                 SimpleEA.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

CTrade trade;

//--- 入力パラメータ ---
input group "--- 鞘取り設定 ---"
input string Symbol1 = "EURUSD";  // シンボル1
input string Symbol2 = "GBPUSD";  // シンボル2
input int    LookBackPeriod = 100; // 平均計算期間
input double SpreadThreshold = 0.001; // スプレッド閾値 (価格差)
input double RiskPercent = 1.0;   // リスクパーセント
input int    StopLoss = 50;       // ストップロス (ポイント)
input int    TakeProfit = 100;    // テイクプロフィット (ポイント)
input bool   UseTimeFilter = true; // 時間フィルター
input int    StartHour = 9;       // 開始時間 (GMT)
input int    EndHour = 17;        // 終了時間 (GMT)
input int    MaxSpread = 30;      // 最大スプレッド (ポイント)

//--- グローバル変数 ---
double lotSize = 0.01;
double avgSpread = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   // ロットサイズを計算 (リスクベース)
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   double stopLossPoints = StopLoss * _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   lotSize = riskAmount / (stopLossPoints * tickValue);
   
   // 最小ロットサイズをチェック
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if (lotSize < minLot) lotSize = minLot;
   
   // 最大ロットサイズをチェック
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (lotSize > maxLot) lotSize = maxLot;
   
   // 平均スプレッドを計算
   avgSpread = 0.0;
   for (int i = 0; i < LookBackPeriod; i++)
     {
      double price1 = iClose(Symbol1, _Period, i);
      double price2 = iClose(Symbol2, _Period, i);
      if (price1 > 0 && price2 > 0)
        {
         avgSpread += MathAbs(price1 - price2);
        }
     }
   avgSpread /= LookBackPeriod;
   
   Print("初期ロットサイズ: ", lotSize);
   Print("平均スプレッド: ", avgSpread);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   // バックテスト結果を取得してログに出力
   if (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
     {
      double profit = TesterStatistics(STAT_PROFIT);
      double total_trades = TesterStatistics(STAT_TRADES);
      double win_trades = TesterStatistics(STAT_WON_TRADES);
      double loss_trades = TesterStatistics(STAT_LOST_TRADES);
      double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
      double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
      double max_drawdown = TesterStatistics(STAT_BALANCE_DD);
      
      Print("=== バックテスト結果 ===");
      Print("総利益: ", profit);
      Print("総トレード数: ", total_trades);
      Print("勝ちトレード: ", win_trades);
      Print("負けトレード: ", loss_trades);
      if (total_trades > 0)
        Print("勝率: ", (win_trades / total_trades) * 100, "%");
      Print("プロフィットファクター: ", profit_factor);
      Print("期待値: ", expected_payoff);
      Print("最大ドローダウン: ", max_drawdown);
     }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   // 時間フィルター
   if (UseTimeFilter)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int currentHour = dt.hour;
      if (currentHour < StartHour || currentHour >= EndHour) return;
     }
   
   // スプレッドチェック (両方のシンボル)
   int spread1 = (int)SymbolInfoInteger(Symbol1, SYMBOL_SPREAD);
   int spread2 = (int)SymbolInfoInteger(Symbol2, SYMBOL_SPREAD);
   if (spread1 > MaxSpread || spread2 > MaxSpread) return;
   
   // 現在の価格を取得
   double price1 = SymbolInfoDouble(Symbol1, SYMBOL_BID);
   double price2 = SymbolInfoDouble(Symbol2, SYMBOL_BID);
   if (price1 == 0 || price2 == 0) return;
   
   // 現在のスプレッドを計算
   double currentSpread = MathAbs(price1 - price2);
   
   // ポジション管理
   int posCount = 0;
   ulong ticket1 = 0, ticket2 = 0;
   for (int i = 0; i < PositionsTotal(); i++)
     {
      if (PositionGetSymbol(i) == Symbol1) { ticket1 = PositionGetTicket(i); posCount++; }
      if (PositionGetSymbol(i) == Symbol2) { ticket2 = PositionGetTicket(i); posCount++; }
     }
   
   // 両方のポジションがある場合、価格差が平均に戻ったら両方を決済
   if (posCount == 2)
     {
      if (currentSpread <= avgSpread)
        {
         trade.PositionClose(ticket1);
         trade.PositionClose(ticket2);
         return;
        }
     }
   
   // エントリー条件
   if (posCount == 0)
     {
      // スプレッドが平均より閾値以上広がったらエントリー
      if (currentSpread > avgSpread + SpreadThreshold)
        {
         // price1 > price2 の場合、price1売り price2買い (差を縮める)
         if (price1 > price2)
           {
            double ask1 = SymbolInfoDouble(Symbol1, SYMBOL_ASK);
            double bid2 = SymbolInfoDouble(Symbol2, SYMBOL_BID);
            double sl1 = ask1 + StopLoss * _Point;
            double tp1 = ask1 - TakeProfit * _Point;
            double sl2 = bid2 - StopLoss * _Point;
            double tp2 = bid2 + TakeProfit * _Point;
            
            trade.Sell(lotSize, Symbol1, ask1, sl1, tp1, "鞘取り Sell " + Symbol1);
            trade.Buy(lotSize, Symbol2, bid2, sl2, tp2, "鞘取り Buy " + Symbol2);
           }
         else
           {
            double bid1 = SymbolInfoDouble(Symbol1, SYMBOL_BID);
            double ask2 = SymbolInfoDouble(Symbol2, SYMBOL_ASK);
            double sl1 = bid1 - StopLoss * _Point;
            double tp1 = bid1 + TakeProfit * _Point;
            double sl2 = ask2 + StopLoss * _Point;
            double tp2 = ask2 - TakeProfit * _Point;
            
            trade.Buy(lotSize, Symbol1, bid1, sl1, tp1, "鞘取り Buy " + Symbol1);
            trade.Sell(lotSize, Symbol2, ask2, sl2, tp2, "鞘取り Sell " + Symbol2);
           }
        }
     }
//---
  }
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   // バックテスト結果を取得してログに出力
   double profit = TesterStatistics(STAT_PROFIT);
   double total_trades = TesterStatistics(STAT_TRADES);
   double win_trades = TesterStatistics(STAT_WON_TRADES);
   double loss_trades = TesterStatistics(STAT_LOST_TRADES);
   double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double max_drawdown = TesterStatistics(STAT_BALANCE_DD);
   
   Print("=== バックテスト結果 ===");
   Print("総利益: ", profit);
   Print("総トレード数: ", total_trades);
   Print("勝ちトレード: ", win_trades);
   Print("負けトレード: ", loss_trades);
   Print("勝率: ", (win_trades / total_trades) * 100, "%");
   Print("プロフィットファクター: ", profit_factor);
   Print("期待値: ", expected_payoff);
   Print("最大ドローダウン: ", max_drawdown);
   
   // 最適化時はプロフィットファクターを返す
   return(profit_factor);
  }
//+------------------------------------------------------------------+
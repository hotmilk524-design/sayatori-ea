//+------------------------------------------------------------------+
//| SpreadCalc.mqh - スプレッド・Zスコア計算                          |
//+------------------------------------------------------------------+
#ifndef SPREADCALC_MQH
#define SPREADCALC_MQH

// lookback期間の価格差の平均・標準偏差を計算する
bool CalcSpreadStats(string sym1, string sym2, ENUM_TIMEFRAMES tf,
                     int period, double &mean, double &stddev)
{
   double sum = 0.0, sum2 = 0.0;
   int count = 0;
   for(int i = 0; i < period; i++)
   {
      double p1 = iClose(sym1, tf, i);
      double p2 = iClose(sym2, tf, i);
      if(p1 <= 0 || p2 <= 0) continue;
      double s = p1 - p2;
      sum  += s;
      sum2 += s * s;
      count++;
   }
   if(count < 10) { mean = 0; stddev = 0; return false; }
   mean = sum / count;
   double variance = sum2 / count - mean * mean;
   stddev = (variance > 0) ? MathSqrt(variance) : 0.0;
   return stddev > 0;
}

// 現在の価格と統計からZスコアを返す
double CalcZScore(string sym1, string sym2, double mean, double stddev)
{
   double p1 = SymbolInfoDouble(sym1, SYMBOL_BID);
   double p2 = SymbolInfoDouble(sym2, SYMBOL_BID);
   if(p1 <= 0 || p2 <= 0 || stddev <= 0) return 0.0;
   return (p1 - p2 - mean) / stddev;
}

#endif

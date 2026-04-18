#property indicator_chart_window

//--- パラメータ ---
input group "--- 表示設定 ---"
input int    表示日数   = 3;
input color  東京色     = clrAqua;
input color  ロンドン色 = clrOrange;
input color  NY色       = clrPaleVioletRed;
input double キリ番間隔 = 100.0;
input bool   スマホ通知 = true;

//--- 内部変数 ---
double TodayTokyoHi=0, TodayTokyoLo=0, TodayLondonHi=0, TodayLondonLo=0;
int lastCalcMin = -1;

int OnInit() { 
   EventSetTimer(1); 
   UpdateAll(); 
   return(INIT_SUCCEEDED); 
}

void OnDeinit(const int r) { 
   ObjectsDeleteAll(0,"BOX_"); 
   ObjectsDeleteAll(0,"Rnd_"); 
   ObjectDelete(0,"Z_Label"); 
}

// MQL5にはiBarShiftが存在しないため自前実装
int iBarShift(string symbol, ENUM_TIMEFRAMES tf, datetime dt) {
   if(dt <= 0) return -1;
   datetime barTimes[], recentTime[];
   if(CopyTime(symbol, tf, dt, 1, barTimes) != 1) return -1;
   if(CopyTime(symbol, tf, 0, 1, recentTime) != 1) return -1;
   return Bars(symbol, tf, barTimes[0], recentTime[0]) - 1;
}

// 範囲取得（データがなければ直近の足で代用する安全版）
bool GetRangeSafe(datetime s, datetime e, double &hi, double &lo) {
   int iS = iBarShift(_Symbol, PERIOD_M1, s);
   int iE = iBarShift(_Symbol, PERIOD_M1, e);
   if(iS < 0 || iE < 0 || iS <= iE) {
      // 1分足がない場合は現在の足の値を仮に入れる
      hi = iHigh(_Symbol, _Period, 0); lo = iLow(_Symbol, _Period, 0);
      return false; 
   }
   hi = iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, iS-iE+1, iE));
   lo = iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, iS-iE+1, iE));
   return true;
}

void DrawBox(string n, datetime s, datetime e, double h, double l, color c) {
   ObjectDelete(0,n);
   ObjectCreate(0,n,OBJ_RECTANGLE,0,s,h,e,l);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c); 
   ObjectSetInteger(0,n,OBJPROP_FILL,true); 
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
}

void UpdateAll() {
   ObjectsDeleteAll(0,"BOX_");
   int off = (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
   for(int d=0; d<表示日数; d++) {
      datetime base = TimeCurrent() - d*86400;
      MqlDateTime t; TimeToStruct(base, t);
      t.hour=0; t.min=0; t.sec=0;
      datetime dayStart = StructToTime(t);
      
      double th, tl, lh, ll, nh, nl;
      // 東京
      if(GetRangeSafe(dayStart+(9-(9-off))*3600, dayStart+(15-(9-off))*3600, th, tl))
         DrawBox("BOX_T_"+(string)d, dayStart+(9-(9-off))*3600, dayStart+(15-(9-off))*3600, th, tl, 東京色);
      // ロンドン (冬時間基準 16-24)
      if(GetRangeSafe(dayStart+(16-(9-off))*3600, dayStart+(24-(9-off))*3600, lh, ll))
         DrawBox("BOX_L_"+(string)d, dayStart+(16-(9-off))*3600, dayStart+(24-(9-off))*3600, lh, ll, ロンドン色);
      // NY (22-30)
      if(GetRangeSafe(dayStart+(22-(9-off))*3600, dayStart+(30-(9-off))*3600, nh, nl))
         DrawBox("BOX_NY_"+(string)d, dayStart+(22-(9-off))*3600, dayStart+(30-(9-off))*3600, nh, nl, NY色);

      if(d==0) { TodayTokyoHi=th; TodayTokyoLo=tl; TodayLondonHi=lh; TodayLondonLo=ll; }
   }
   // キリ番
   ObjectsDeleteAll(0,"Rnd_");
   double mid = SymbolInfoDouble(_Symbol, SYMBOL_BID) > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : iClose(_Symbol, _Period, 0);
   for(int i=-5; i<=5; i++) {
      double p = (MathFloor(mid/キリ番間隔)+i)*キリ番間隔;
      string n = "Rnd_"+(string)i;
      ObjectCreate(0,n,OBJ_HLINE,0,0,p);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrSlateGray);
      ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
   }
}

void OnTimer() {
   int off = (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
   datetime jst = TimeCurrent()+(9-off)*3600;
   MqlDateTime dt_jst;
   TimeToStruct(jst, dt_jst);
   string txt = StringFormat("日本時間 %02d:%02d\n(GMT+%d)", dt_jst.hour, dt_jst.min, off);
   string nm = "Z_Label";
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,1);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,20);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clrWhite);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[]) {
   return rates_total;
}

void OnTick() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.min != lastCalcMin) { UpdateAll(); lastCalcMin = dt.min; }
   
   // 通知ロジック
   static datetime lastAlert = 0;
   if(lastAlert != iTime(_Symbol, _Period, 0)) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(TodayLondonHi > 0 && bid > TodayLondonHi) { 
         Alert("LDN上抜け"); if(スマホ通知) SendNotification("LDN上抜け"); lastAlert = iTime(_Symbol, _Period, 0); 
      }
      if(TodayLondonLo > 0 && bid < TodayLondonLo) { 
         Alert("LDN下抜け"); if(スマホ通知) SendNotification("LDN下抜け"); lastAlert = iTime(_Symbol, _Period, 0); 
      }
   }
}

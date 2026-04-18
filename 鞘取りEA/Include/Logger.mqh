//+------------------------------------------------------------------+
//| Logger.mqh - ログ出力ユーティリティ                               |
//+------------------------------------------------------------------+
#ifndef LOGGER_MQH
#define LOGGER_MQH

// #define DEBUG をつけるとデバッグログが有効になる
#ifdef DEBUG
void LogDebug(string msg) { Print("[DEBUG] ", msg); }
#else
void LogDebug(string msg) {}
#endif

void LogInfo(string msg)  { Print("[INFO]  ", msg); }
void LogError(string msg) { Print("[ERROR] ", msg); }

#endif

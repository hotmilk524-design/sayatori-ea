import struct
import os
from datetime import datetime, timedelta

def read_hst_file(filepath):
    """MT5の.hstファイルを読み取ってOHLCデータを返す"""
    data = []
    try:
        with open(filepath, 'rb') as f:
            # HSTファイルヘッダーを読み飛ばす (148バイト)
            header = f.read(148)

            # バー数を読み取る
            bar_count = struct.unpack('<I', f.read(4))[0]

            # 各バーを読み取る
            for _ in range(bar_count):
                bar_data = f.read(60)  # 各バーは60バイト
                if len(bar_data) < 60:
                    break

                # バー構造体をアンパック
                ctm, open_price, high_price, low_price, close_price, tick_volume, spread, real_volume = struct.unpack('<QddddIIQ', bar_data)

                # タイムスタンプを変換
                dt = datetime(1970, 1, 1) + timedelta(seconds=ctm)

                data.append({
                    'datetime': dt,
                    'open': open_price,
                    'high': high_price,
                    'low': low_price,
                    'close': close_price,
                    'volume': tick_volume
                })

    except Exception as e:
        print(f"Error reading HST file: {e}")

    return data

def simple_ea_backtest(data, initial_balance=1000000):
    """SimpleEAのロジックでバックテストを実行"""
    balance = initial_balance
    position = None
    trades = []
    equity_curve = []

    # 移動平均を計算
    closes = [bar['close'] for bar in data]
    ma5 = []
    ma10 = []

    for i in range(len(closes)):
        if i >= 4:
            ma5.append(sum(closes[i-4:i+1]) / 5)
        else:
            ma5.append(closes[i])

        if i >= 9:
            ma10.append(sum(closes[i-9:i+1]) / 10)
        else:
            ma10.append(closes[i])

    # バックテスト実行
    for i in range(10, len(data)):  # MA10が計算可能になるまで待つ
        current_bar = data[i]
        prev_ma5 = ma5[i-1]
        prev_ma10 = ma10[i-1]

        # ポジションがない場合
        if position is None:
            # MA5 > MA10 で買い
            if prev_ma5 > prev_ma10:
                position = {
                    'type': 'buy',
                    'entry_price': current_bar['open'],
                    'entry_time': current_bar['datetime'],
                    'lot': 0.01
                }

        # ポジションがある場合
        else:
            # 簡易決済: 次のバーで決済
            exit_price = current_bar['open']
            pnl = (exit_price - position['entry_price']) * position['lot'] * 100000 if position['type'] == 'buy' else (position['entry_price'] - exit_price) * position['lot'] * 100000

            balance += pnl

            trades.append({
                'entry_time': position['entry_time'],
                'exit_time': current_bar['datetime'],
                'type': position['type'],
                'entry_price': position['entry_price'],
                'exit_price': exit_price,
                'pnl': pnl,
                'balance': balance
            })

            position = None

        equity_curve.append({
            'datetime': current_bar['datetime'],
            'balance': balance
        })

    return trades, equity_curve, balance

# メイン実行
if __name__ == "__main__":
    # XAUUSDのHSTファイルを探す
    tester_dir = r"C:\Users\katuo\AppData\Roaming\MetaQuotes\Terminal\F616FF6485373AA333BF40A7ED4E50D8\Tester"

    hst_files = []
    for root, dirs, files in os.walk(tester_dir):
        for file in files:
            if file.endswith('.hst') and 'XAUUSD' in file:
                hst_files.append(os.path.join(root, file))

    if not hst_files:
        print("XAUUSDのHSTファイルが見つかりません")
        exit()

    # 最新のファイルを読み取る
    hst_file = max(hst_files, key=os.path.getmtime)
    print(f"使用するHSTファイル: {hst_file}")

    data = read_hst_file(hst_file)
    print(f"読み取ったバー数: {len(data)}")

    if len(data) < 100:
        print("データが不足しています")
        exit()

    # 2025年1月1日から2026年4月18日までのデータをフィルタリング
    start_date = datetime(2025, 1, 1)
    end_date = datetime(2026, 4, 18)

    filtered_data = [bar for bar in data if start_date <= bar['datetime'] <= end_date]
    print(f"フィルタリング後のバー数: {len(filtered_data)}")

    # バックテスト実行
    trades, equity_curve, final_balance = simple_ea_backtest(filtered_data)

    # 結果表示
    print("
=== バックテスト結果 ===")
    print(f"初期資金: 1,000,000円")
    print(f"最終資金: {final_balance:.2f}円")
    print(f"総損益: {final_balance - 1000000:.2f}円")
    print(f"総トレード数: {len(trades)}")

    if trades:
        winning_trades = [t for t in trades if t['pnl'] > 0]
        losing_trades = [t for t in trades if t['pnl'] <= 0]

        print(f"勝ちトレード: {len(winning_trades)}")
        print(f"負けトレード: {len(losing_trades)}")
        print(f"勝率: {len(winning_trades)/len(trades)*100:.1f}%")

        if winning_trades:
            avg_win = sum(t['pnl'] for t in winning_trades) / len(winning_trades)
            print(f"平均勝ち額: {avg_win:.2f}円")

        if losing_trades:
            avg_loss = sum(t['pnl'] for t in losing_trades) / len(losing_trades)
            print(f"平均負け額: {avg_loss:.2f}円")

    # 詳細トレードを表示（最初の10件）
    print("
=== 最初の10トレード ===")
    for i, trade in enumerate(trades[:10]):
        print(f"{i+1}. {trade['entry_time']} - {trade['exit_time']} | {trade['type']} | エントリー: {trade['entry_price']:.2f} | イグジット: {trade['exit_price']:.2f} | P&L: {trade['pnl']:.2f}円")
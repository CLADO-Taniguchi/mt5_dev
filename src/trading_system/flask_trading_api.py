import sys
import os

# 現在のディレクトリをパスに追加
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

from flask import Flask, request, jsonify
import pandas as pd
import numpy as np
import json
import logging
from datetime import datetime
import threading
import time
from pathlib import Path

# 機械学習システムのインポート（エラーハンドリング付き）
try:
    from ml_trading_system import TradingMLSystem
    ML_SYSTEM_AVAILABLE = True
except ImportError as e:
    print(f"警告: ml_trading_system のインポートに失敗しました: {e}")
    print("基本的なAPIサーバーとして動作します")
    ML_SYSTEM_AVAILABLE = False
    # ダミークラスを定義
    class TradingMLSystem:
        def __init__(self):
            pass
        def load_model(self, path):
            return False
        def generate_signal(self, df, price):
            return "HOLD", 0.0, None, "ML system not available"

# ログ設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('trading_api.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)

app = Flask(__name__)

class SymbolDataManager:
    """通貨ペア別データ管理クラス"""
    
    def __init__(self, base_dir, symbol, max_buffer_size=1000):
        self.symbol = symbol
        self.base_dir = Path(base_dir)
        self.max_buffer_size = max_buffer_size
        
        # シンボル専用ディレクトリ作成
        self.symbol_dir = self.base_dir / "data" / symbol
        self.symbol_dir.mkdir(parents=True, exist_ok=True)
        
        # ファイルパス設定
        self.current_file = self.symbol_dir / f"{symbol}_current.csv"
        self.archive_dir = self.symbol_dir / "archive"
        self.archive_dir.mkdir(exist_ok=True)
        
        # メモリバッファ
        self.data_buffer = []
        self.last_backup_time = datetime.now()
        self.backup_interval = 300  # 5分
        
        # 起動時にデータ読み込み
        self.load_current_data()
    
    def save_data(self):
        """現在のデータを保存"""
        try:
            if len(self.data_buffer) == 0:
                return
            
            df = pd.DataFrame(self.data_buffer)
            
            # datetime列を文字列に変換
            if 'datetime' in df.columns:
                df['datetime'] = pd.to_datetime(df['datetime']).dt.strftime('%Y-%m-%d %H:%M:%S')
            
            # symbolカラムを追加
            df['symbol'] = self.symbol
            
            df.to_csv(self.current_file, index=False, encoding='utf-8')
            logging.info(f"[{self.symbol}] データ保存: {len(self.data_buffer)}件 -> {self.current_file}")
            self.last_backup_time = datetime.now()
            
        except Exception as e:
            logging.error(f"[{self.symbol}] データ保存エラー: {e}")
    
    def load_current_data(self):
        """現在のデータを読み込み"""
        try:
            if not self.current_file.exists():
                logging.info(f"[{self.symbol}] バックアップファイルが見つかりません")
                return
            
            df = pd.read_csv(self.current_file, encoding='utf-8')
            
            if len(df) == 0:
                return
            
            # datetime列を復元
            if 'datetime' in df.columns:
                df['datetime'] = pd.to_datetime(df['datetime'])
            
            # symbolカラムを除去してバッファに復元
            if 'symbol' in df.columns:
                df = df.drop('symbol', axis=1)
            
            self.data_buffer = df.to_dict('records')
            
            # バッファサイズ制限
            if len(self.data_buffer) > self.max_buffer_size:
                self.data_buffer = self.data_buffer[-self.max_buffer_size:]
            
            logging.info(f"[{self.symbol}] データ復元: {len(self.data_buffer)}件")
            
        except Exception as e:
            logging.error(f"[{self.symbol}] データ読み込みエラー: {e}")
            self.data_buffer = []
    
    def add_data(self, tick_data):
        """ティックデータを追加"""
        try:
            # データ検証
            required_fields = ['datetime', 'open', 'high', 'low', 'close', 'volume']
            for field in required_fields:
                if field not in tick_data:
                    raise ValueError(f"必須フィールドが不足: {field}")
            
            # タイムスタンプの正規化
            if isinstance(tick_data['datetime'], str):
                tick_data['datetime'] = pd.to_datetime(tick_data['datetime'])
            
            # バッファに追加
            self.data_buffer.append(tick_data)
            
            # バッファサイズ制限とアーカイブ処理
            if len(self.data_buffer) > self.max_buffer_size:
                self.archive_old_data()
                self.data_buffer = self.data_buffer[-self.max_buffer_size:]
            
            # 自動バックアップチェック
            self.auto_backup_check()
            
            return True
            
        except Exception as e:
            logging.error(f"[{self.symbol}] データ追加エラー: {e}")
            return False
    
    def archive_old_data(self):
        """古いデータをアーカイブ"""
        try:
            if len(self.data_buffer) <= self.max_buffer_size:
                return
            
            # アーカイブ対象データ（古い500件）
            archive_data = self.data_buffer[:-self.max_buffer_size]
            archive_df = pd.DataFrame(archive_data)
            
            if len(archive_df) == 0:
                return
            
            # アーカイブファイル名（日付ベース）
            first_date = pd.to_datetime(archive_df['datetime'].iloc[0]).strftime('%Y%m%d')
            last_date = pd.to_datetime(archive_df['datetime'].iloc[-1]).strftime('%Y%m%d')
            archive_filename = f"{self.symbol}_{first_date}_{last_date}.csv"
            archive_path = self.archive_dir / archive_filename
            
            # datetime列を文字列に変換してアーカイブ
            archive_df['datetime'] = pd.to_datetime(archive_df['datetime']).dt.strftime('%Y-%m-%d %H:%M:%S')
            archive_df['symbol'] = self.symbol
            archive_df.to_csv(archive_path, index=False, encoding='utf-8')
            
            logging.info(f"[{self.symbol}] 古いデータをアーカイブ: {len(archive_data)}件 -> {archive_filename}")
            
        except Exception as e:
            logging.error(f"[{self.symbol}] アーカイブエラー: {e}")
    
    def auto_backup_check(self):
        """自動バックアップチェック"""
        current_time = datetime.now()
        time_diff = (current_time - self.last_backup_time).total_seconds()
        
        if time_diff >= self.backup_interval:
            self.save_data()
    
    def get_recent_dataframe(self, periods=200):
        """最近のデータをDataFrameで取得"""
        if len(self.data_buffer) < periods:
            periods = len(self.data_buffer)
        
        if periods == 0:
            return None
        
        recent_data = self.data_buffer[-periods:]
        df = pd.DataFrame(recent_data)
        df['datetime'] = pd.to_datetime(df['datetime'])
        df = df.sort_values('datetime').reset_index(drop=True)
        
        return df
    
    def get_symbol_stats(self):
        """シンボル統計情報"""
        current_size = len(self.data_buffer)
        archive_files = list(self.archive_dir.glob(f"{self.symbol}_*.csv"))
        archive_count = len(archive_files)
        
        total_archived = 0
        for archive_file in archive_files:
            try:
                df = pd.read_csv(archive_file)
                total_archived += len(df)
            except:
                pass
        
        return {
            'symbol': self.symbol,
            'current_buffer_size': current_size,
            'archive_files': archive_count,
            'total_archived_records': total_archived,
            'total_records': current_size + total_archived,
            'last_backup': self.last_backup_time.isoformat()
        }

class TradingAPIServer:
    def __init__(self):
        if ML_SYSTEM_AVAILABLE:
            self.ml_system = TradingMLSystem()
        else:
            self.ml_system = None
            
        # シンボル別データマネージャー
        self.symbol_managers = {}
        self.data_base_dir = current_dir
        self.max_buffer_size = 1000
        
        # システム状態
        self.last_signal = {}  # シンボル別
        self.last_confidence = {}  # シンボル別
        self.last_prediction = {}  # シンボル別
        self.model_loaded = {}  # シンボル別
        
        # エラー管理
        self.error_count = 0
        self.last_error_time = None
        self.connection_errors = 0
        self.last_successful_request = datetime.now()
        
        # モデルの自動読み込み
        if ML_SYSTEM_AVAILABLE:
            self.load_existing_models()
        
        # バックグラウンドでの定期処理開始
        self.start_background_tasks()
    
    def get_symbol_manager(self, symbol):
        """シンボル別データマネージャーを取得"""
        if symbol not in self.symbol_managers:
            self.symbol_managers[symbol] = SymbolDataManager(
                self.data_base_dir, symbol, self.max_buffer_size
            )
            # 新しいシンボルの初期状態設定
            self.last_signal[symbol] = "HOLD"
            self.last_confidence[symbol] = 0.0
            self.last_prediction[symbol] = None
            self.model_loaded[symbol] = False
            
        return self.symbol_managers[symbol]
    
    def load_existing_models(self):
        """既存のモデルを読み込み"""
        if not ML_SYSTEM_AVAILABLE:
            return
        
        # シンボル別モデルファイルを探索
        model_pattern = "trading_model_*.pkl"
        model_files = list(Path(current_dir).glob(model_pattern))
        
        for model_file in model_files:
            symbol = model_file.stem.replace('trading_model_', '')
            try:
                if self.ml_system.load_model(str(model_file)):
                    self.model_loaded[symbol] = True
                    logging.info(f"[{symbol}] モデル読み込み成功: {model_file}")
                else:
                    logging.info(f"[{symbol}] モデルファイルが見つかりません: {model_file}")
            except Exception as e:
                logging.error(f"[{symbol}] モデル読み込みエラー: {e}")
    
    def add_tick_data(self, tick_data, symbol):
        """ティックデータを追加"""
        manager = self.get_symbol_manager(symbol)
        success = manager.add_data(tick_data)
        
        if success:
            logging.info(f"[{symbol}] ティックデータ追加: {tick_data['datetime']}, Close: {tick_data['close']}")
        
        return success
    
    def generate_trading_signal(self, symbol):
        """取引シグナルを生成"""
        try:
            if symbol not in self.model_loaded or not self.model_loaded[symbol]:
                return "HOLD", 0.0, None, f"Model not loaded for {symbol}"
            
            manager = self.get_symbol_manager(symbol)
            df = manager.get_recent_dataframe(200)
            
            if df is None or len(df) < 100:
                return "HOLD", 0.0, None, f"Insufficient data for {symbol}"
            
            current_price = df['close'].iloc[-1]
            signal, confidence, predicted_price = self.ml_system.generate_signal(df, current_price)
            
            # シンボル別状態更新
            self.last_signal[symbol] = signal
            self.last_confidence[symbol] = confidence
            self.last_prediction[symbol] = predicted_price
            
            logging.info(f"[{symbol}] シグナル生成: {signal}, 信頼度: {confidence:.3f}")
            return signal, confidence, predicted_price, "Success"
            
        except Exception as e:
            error_msg = f"[{symbol}] シグナル生成エラー: {e}"
            logging.error(error_msg)
            return "HOLD", 0.0, None, error_msg
    
    def retrain_model(self, symbol):
        """モデルの再訓練"""
        try:
            manager = self.get_symbol_manager(symbol)
            df = manager.get_recent_dataframe()
            
            if df is None or len(df) < 500:
                return False, f"Insufficient data for training {symbol} (minimum 500 required)"
            
            logging.info(f"[{symbol}] モデル再訓練開始...")
            self.ml_system.train_model(df)
            
            # シンボル別モデルファイル名
            model_file = f"trading_model_{symbol}.pkl"
            self.ml_system.save_model(model_file)
            self.model_loaded[symbol] = True
            
            # 再訓練完了時にデータを保存
            manager.save_data()
            
            logging.info(f"[{symbol}] モデル再訓練完了")
            return True, f"Model retrained successfully for {symbol}"
            
        except Exception as e:
            error_msg = f"[{symbol}] モデル再訓練エラー: {e}"
            logging.error(error_msg)
            return False, error_msg
    
    def start_background_tasks(self):
        """バックグラウンドタスクを開始"""
        def background_worker():
            while True:
                try:
                    # 各シンボルのモデル再訓練チェック
                    for symbol, manager in self.symbol_managers.items():
                        buffer_size = len(manager.data_buffer)
                        if buffer_size >= 500 and buffer_size % 100 == 0:
                            logging.info(f"[{symbol}] バックグラウンドでモデル更新中...")
                            self.retrain_model(symbol)
                        
                        # 定期バックアップ
                        manager.auto_backup_check()
                    
                    time.sleep(300)  # 5分ごとにチェック
                    
                except Exception as e:
                    logging.error(f"バックグラウンドタスクエラー: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=background_worker, daemon=True)
        thread.start()
    
    def get_all_symbols_stats(self):
        """全シンボルの統計情報"""
        stats = {}
        for symbol, manager in self.symbol_managers.items():
            stats[symbol] = manager.get_symbol_stats()
            stats[symbol]['model_loaded'] = self.model_loaded.get(symbol, False)
            stats[symbol]['last_signal'] = self.last_signal.get(symbol, "HOLD")
            stats[symbol]['last_confidence'] = self.last_confidence.get(symbol, 0.0)
        
        return stats

# グローバルAPIサーバーインスタンス
api_server = TradingAPIServer()

@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    total_data_points = sum(len(manager.data_buffer) for manager in api_server.symbol_managers.values())
    
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'active_symbols': list(api_server.symbol_managers.keys()),
        'total_data_points': total_data_points,
        'symbols_with_models': len([s for s, loaded in api_server.model_loaded.items() if loaded])
    })

@app.route('/tick', methods=['POST'])
def receive_tick():
    """ティックデータ受信（シンボル対応）"""
    try:
        data = request.get_json()
        
        if not data:
            api_server.connection_errors += 1
            return jsonify({'error': 'No data provided'}), 400
        
        # シンボル情報取得
        symbol = data.get('symbol', 'UNKNOWN')
        if symbol == 'UNKNOWN':
            return jsonify({'error': 'Symbol not specified'}), 400
        
        # シンボル情報を除去してティックデータを抽出
        tick_data = {k: v for k, v in data.items() if k != 'symbol'}
        
        # データ追加
        success = api_server.add_tick_data(tick_data, symbol)
        
        if success:
            api_server.connection_errors = 0
            api_server.last_successful_request = datetime.now()
            manager = api_server.get_symbol_manager(symbol)
            
            return jsonify({
                'status': 'success',
                'message': f'Tick data received for {symbol}',
                'symbol': symbol,
                'buffer_size': len(manager.data_buffer),
                'timestamp': datetime.now().isoformat()
            })
        else:
            api_server.connection_errors += 1
            return jsonify({
                'error': f'Failed to add tick data for {symbol}',
                'error_count': api_server.connection_errors
            }), 400
            
    except Exception as e:
        api_server.connection_errors += 1
        logging.error(f"Tick reception error: {e}")
        return jsonify({
            'error': str(e),
            'error_count': api_server.connection_errors,
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/signal/<symbol>', methods=['GET'])
def get_signal(symbol):
    """取引シグナル取得（シンボル指定）"""
    try:
        signal, confidence, predicted_price, message = api_server.generate_trading_signal(symbol)
        
        current_price = None
        manager = api_server.get_symbol_manager(symbol)
        if len(manager.data_buffer) > 0:
            current_price = manager.data_buffer[-1]['close']
        
        return jsonify({
            'symbol': symbol,
            'signal': signal,
            'confidence': round(confidence, 3),
            'predicted_price': round(predicted_price, 5) if predicted_price else None,
            'current_price': round(current_price, 5) if current_price else None,
            'message': message,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"シグナル取得エラー [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/retrain/<symbol>', methods=['POST'])
def manual_retrain(symbol):
    """手動モデル再訓練（シンボル指定）"""
    try:
        success, message = api_server.retrain_model(symbol)
        
        if success:
            manager = api_server.get_symbol_manager(symbol)
            return jsonify({
                'status': 'success',
                'symbol': symbol,
                'message': message,
                'data_points_used': len(manager.data_buffer)
            })
        else:
            return jsonify({
                'status': 'error',
                'symbol': symbol,
                'message': message
            }), 400
            
    except Exception as e:
        logging.error(f"手動再訓練エラー [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status', methods=['GET'])
def get_status():
    """システム状態取得（全シンボル）"""
    try:
        return jsonify({
            'symbols': api_server.get_all_symbols_stats(),
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"状態取得エラー: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status/<symbol>', methods=['GET'])
def get_symbol_status(symbol):
    """シンボル別状態取得"""
    try:
        manager = api_server.get_symbol_manager(symbol)
        stats = manager.get_symbol_stats()
        stats['model_loaded'] = api_server.model_loaded.get(symbol, False)
        stats['last_signal'] = api_server.last_signal.get(symbol, "HOLD")
        stats['last_confidence'] = round(api_server.last_confidence.get(symbol, 0.0), 3)
        stats['last_prediction'] = round(api_server.last_prediction.get(symbol, 0.0), 5) if api_server.last_prediction.get(symbol) else None
        
        return jsonify(stats)
        
    except Exception as e:
        logging.error(f"シンボル状態取得エラー [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/data/<symbol>/latest', methods=['GET'])
def get_latest_data(symbol):
    """最新データ取得（シンボル指定）"""
    try:
        count = request.args.get('count', 10, type=int)
        count = min(count, 100)  # 最大100件
        
        manager = api_server.get_symbol_manager(symbol)
        
        if len(manager.data_buffer) == 0:
            return jsonify({'symbol': symbol, 'data': [], 'count': 0})
        
        latest_data = manager.data_buffer[-count:]
        
        # datetime を文字列に変換
        formatted_data = []
        for item in latest_data:
            formatted_item = item.copy()
            if isinstance(formatted_item['datetime'], pd.Timestamp):
                formatted_item['datetime'] = formatted_item['datetime'].isoformat()
            formatted_data.append(formatted_item)
        
        return jsonify({
            'symbol': symbol,
            'data': formatted_data,
            'count': len(formatted_data)
        })
        
    except Exception as e:
        logging.error(f"最新データ取得エラー [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/backup/<symbol>', methods=['POST'])
def manual_backup(symbol):
    """手動データバックアップ（シンボル指定）"""
    try:
        manager = api_server.get_symbol_manager(symbol)
        manager.save_data()
        
        return jsonify({
            'status': 'success',
            'symbol': symbol,
            'message': f'Data backup completed for {symbol}',
            'file_path': str(manager.current_file),
            'data_points': len(manager.data_buffer),
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logging.error(f"手動バックアップエラー [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/backup/all', methods=['POST'])
def backup_all_symbols():
    """全シンボルのデータバックアップ"""
    try:
        results = {}
        for symbol, manager in api_server.symbol_managers.items():
            manager.save_data()
            results[symbol] = {
                'file_path': str(manager.current_file),
                'data_points': len(manager.data_buffer)
            }
        
        return jsonify({
            'status': 'success',
            'message': 'All symbols backed up',
            'results': results,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logging.error(f"全シンボルバックアップエラー: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    logging.info("Flask Trading API Server starting...")
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
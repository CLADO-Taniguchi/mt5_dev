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

class TradingAPIServer:
    def __init__(self):
        if ML_SYSTEM_AVAILABLE:
            self.ml_system = TradingMLSystem()
        else:
            self.ml_system = None
        self.data_buffer = []  # 受信データのバッファ
        self.last_signal = "HOLD"
        self.last_confidence = 0.0
        self.last_prediction = None
        self.model_loaded = False
        
        # エラー管理
        self.error_count = 0
        self.last_error_time = None
        
        # 接続状態管理
        self.connection_errors = 0
        self.last_successful_request = datetime.now()
        
        # データバッファの最大サイズ
        self.max_buffer_size = 1000
        
        # モデルの自動読み込み
        if ML_SYSTEM_AVAILABLE:
            self.load_existing_model()
        
        # バックグラウンドでの定期処理開始
        self.start_background_tasks()
    
    def load_existing_model(self):
        """既存のモデルを読み込み"""
        if not ML_SYSTEM_AVAILABLE:
            logging.info("ML system not available")
            return
            
        try:
            if self.ml_system.load_model("trading_model.pkl"):
                self.model_loaded = True
                logging.info("Existing model loaded successfully")
            else:
                logging.info("No existing model found. Training needed with new data")
        except Exception as e:
            logging.error(f"Model loading error: {e}")
    
    def add_tick_data(self, tick_data):
        """ティックデータをバッファに追加"""
        try:
            # データ検証
            required_fields = ['datetime', 'open', 'high', 'low', 'close', 'volume']
            for field in required_fields:
                if field not in tick_data:
                    raise ValueError(f"必須フィールドが不足: {field}")
            
            # タイムスタンプの正規化
            if isinstance(tick_data['datetime'], str):
                tick_data['datetime'] = pd.to_datetime(tick_data['datetime'])
            
            # データバッファに追加
            self.data_buffer.append(tick_data)
            
            # バッファサイズ制限
            if len(self.data_buffer) > self.max_buffer_size:
                self.data_buffer = self.data_buffer[-self.max_buffer_size:]
            
            logging.info(f"ティックデータ追加: {tick_data['datetime']}, Close: {tick_data['close']}")
            return True
            
        except Exception as e:
            logging.error(f"データ追加エラー: {e}")
            return False
    
    def get_recent_dataframe(self, periods=200):
        """最近のデータをDataFrameとして取得"""
        if len(self.data_buffer) < periods:
            periods = len(self.data_buffer)
        
        if periods == 0:
            return None
        
        recent_data = self.data_buffer[-periods:]
        df = pd.DataFrame(recent_data)
        df['datetime'] = pd.to_datetime(df['datetime'])
        df = df.sort_values('datetime').reset_index(drop=True)
        
        return df
    
    def generate_trading_signal(self):
        """取引シグナルを生成"""
        try:
            if not self.model_loaded:
                return "HOLD", 0.0, None, "Model not loaded"
            
            df = self.get_recent_dataframe(200)
            if df is None or len(df) < 100:
                return "HOLD", 0.0, None, "Insufficient data"
            
            current_price = df['close'].iloc[-1]
            signal, confidence, predicted_price = self.ml_system.generate_signal(df, current_price)
            
            self.last_signal = signal
            self.last_confidence = confidence
            self.last_prediction = predicted_price
            
            logging.info(f"シグナル生成: {signal}, 信頼度: {confidence:.3f}, 予測価格: {predicted_price:.5f}")
            return signal, confidence, predicted_price, "Success"
            
        except Exception as e:
            error_msg = f"シグナル生成エラー: {e}"
            logging.error(error_msg)
            return "HOLD", 0.0, None, error_msg
    
    def retrain_model(self):
        """モデルの再訓練"""
        try:
            df = self.get_recent_dataframe()
            if df is None or len(df) < 500:
                return False, "Insufficient data for training (minimum 500 required)"
            
            logging.info("モデル再訓練開始...")
            self.ml_system.train_model(df)
            self.ml_system.save_model("trading_model.pkl")
            self.model_loaded = True
            
            logging.info("モデル再訓練完了")
            return True, "Model retrained successfully"
            
        except Exception as e:
            error_msg = f"モデル再訓練エラー: {e}"
            logging.error(error_msg)
            return False, error_msg
    
    def start_background_tasks(self):
        """バックグラウンドタスクを開始"""
        def background_worker():
            while True:
                try:
                    # 1時間ごとにモデル再訓練をチェック
                    if len(self.data_buffer) >= 500 and len(self.data_buffer) % 100 == 0:
                        logging.info("バックグラウンドでモデル更新中...")
                        self.retrain_model()
                    
                    time.sleep(300)  # 5分ごとにチェック
                    
                except Exception as e:
                    logging.error(f"バックグラウンドタスクエラー: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=background_worker, daemon=True)
        thread.start()
    def check_economic_calendar(self):
        """重要経済指標をチェック"""
        try:
            # 簡易版：事前定義された時間帯での停止
            now = datetime.now()
            
            # 重要指標発表時間（例：毎月第1金曜 21:30 NFP）
            high_impact_times = [
                # NFP (毎月第1金曜 21:30 JST)
                {'day': 'friday', 'week': 1, 'hour': 21, 'minute': 30, 'name': 'NFP'},
                # FOMC (年8回程度、事前に設定)
                # ECB政策金利発表
                # その他重要指標
            ]
            
            # 現在時刻が重要時間帯の30分前後かチェック
            for event_time in high_impact_times:
                # 簡易判定ロジック（実際はより詳細な実装が必要）
                if self.is_within_event_window(now, event_time):
                    return True, event_time['name']
            
            return False, None
            
        except Exception as e:
            logging.error(f"Economic calendar check error: {e}")
            return False, None
    
    def is_within_event_window(self, current_time, event_time, window_minutes=30):
        """イベント時間の前後30分以内かチェック"""
        # 簡易実装：実際はより複雑な日付計算が必要
        return False

# グローバルAPIサーバーインスタンス
api_server = TradingAPIServer()

@app.route('/health', methods=['GET'])
def health_check():
    """ヘルスチェック"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'model_loaded': api_server.model_loaded,
        'data_points': len(api_server.data_buffer)
    })

@app.route('/tick', methods=['POST'])
def receive_tick():
    """ティックデータ受信（エラーハンドリング強化）"""
    try:
        data = request.get_json()
        
        if not data:
            api_server.connection_errors += 1
            return jsonify({'error': 'No data provided'}), 400
        
        # データ追加
        success = api_server.add_tick_data(data)
        
        if success:
            api_server.connection_errors = 0  # エラーカウントリセット
            api_server.last_successful_request = datetime.now()
            return jsonify({
                'status': 'success',
                'message': 'Tick data received',
                'buffer_size': len(api_server.data_buffer),
                'timestamp': datetime.now().isoformat()
            })
        else:
            api_server.connection_errors += 1
            return jsonify({
                'error': 'Failed to add tick data',
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

@app.route('/signal', methods=['GET'])
def get_signal():
    """取引シグナル取得"""
    try:
        signal, confidence, predicted_price, message = api_server.generate_trading_signal()
        
        current_price = None
        if len(api_server.data_buffer) > 0:
            current_price = api_server.data_buffer[-1]['close']
        
        return jsonify({
            'signal': signal,
            'confidence': round(confidence, 3),
            'predicted_price': round(predicted_price, 5) if predicted_price else None,
            'current_price': round(current_price, 5) if current_price else None,
            'message': message,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"シグナル取得エラー: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/retrain', methods=['POST'])
def manual_retrain():
    """手動モデル再訓練"""
    try:
        success, message = api_server.retrain_model()
        
        if success:
            return jsonify({
                'status': 'success',
                'message': message,
                'data_points_used': len(api_server.data_buffer)
            })
        else:
            return jsonify({
                'status': 'error',
                'message': message
            }), 400
            
    except Exception as e:
        logging.error(f"手動再訓練エラー: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status', methods=['GET'])
def get_status():
    """システム状態取得"""
    try:
        return jsonify({
            'model_loaded': api_server.model_loaded,
            'data_buffer_size': len(api_server.data_buffer),
            'last_signal': api_server.last_signal,
            'last_confidence': round(api_server.last_confidence, 3),
            'last_prediction': round(api_server.last_prediction, 5) if api_server.last_prediction else None,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"状態取得エラー: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/data/latest', methods=['GET'])
def get_latest_data():
    """最新データ取得"""
    try:
        count = request.args.get('count', 10, type=int)
        count = min(count, 100)  # 最大100件
        
        if len(api_server.data_buffer) == 0:
            return jsonify({'data': [], 'count': 0})
        
        latest_data = api_server.data_buffer[-count:]
        
        # datetime を文字列に変換
        formatted_data = []
        for item in latest_data:
            formatted_item = item.copy()
            if isinstance(formatted_item['datetime'], pd.Timestamp):
                formatted_item['datetime'] = formatted_item['datetime'].isoformat()
            formatted_data.append(formatted_item)
        
        return jsonify({
            'data': formatted_data,
            'count': len(formatted_data)
        })
        
    except Exception as e:
        logging.error(f"最新データ取得エラー: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/predict', methods=['POST'])
def predict_price():
    """価格予測（単発）"""
    try:
        data = request.get_json()
        periods = data.get('periods', 1)  # 予測期間
        
        df = api_server.get_recent_dataframe(200)
        if df is None or len(df) < 100:
            return jsonify({'error': 'Insufficient data for prediction'}), 400
        
        current_price = df['close'].iloc[-1]
        predicted_price, confidence = api_server.ml_system.predict_next_price(df)
        
        if predicted_price is None:
            return jsonify({'error': 'Prediction failed'}), 500
        
        return jsonify({
            'current_price': round(current_price, 5),
            'predicted_price': round(predicted_price, 5),
            'price_change': round(predicted_price - current_price, 5),
            'price_change_pct': round((predicted_price - current_price) / current_price * 100, 2),
            'confidence': round(confidence, 3),
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"価格予測エラー: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    logging.info("Flask Trading API Server starting...")
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)  # ポート5000に戻す
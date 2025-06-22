import numpy as np
import pandas as pd
import joblib
from datetime import datetime, timedelta
import warnings
warnings.filterwarnings('ignore')

# 機械学習ライブラリ
from sklearn.preprocessing import StandardScaler, MinMaxScaler
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error

# TensorFlow/Keras for LSTM
import tensorflow as tf
from tensorflow import keras

# 必要なKerasコンポーネントを明示的にインポート
Sequential = keras.Sequential
LSTM = keras.layers.LSTM
Dense = keras.layers.Dense
Dropout = keras.layers.Dropout
Input = keras.layers.Input
concatenate = keras.layers.concatenate
Adam = keras.optimizers.Adam
EarlyStopping = keras.callbacks.EarlyStopping

# Technical Analysis
import talib

class TechnicalIndicators:
    """テクニカル指標計算クラス"""
    
    @staticmethod
    def calculate_indicators(df):
        """各種テクニカル指標を計算"""
        high = df['high'].values
        low = df['low'].values
        close = df['close'].values
        volume = df['volume'].values
        
        indicators = pd.DataFrame()
        
        # 移動平均
        indicators['sma_5'] = talib.SMA(close, timeperiod=5)
        indicators['sma_10'] = talib.SMA(close, timeperiod=10)
        indicators['sma_20'] = talib.SMA(close, timeperiod=20)
        indicators['ema_12'] = talib.EMA(close, timeperiod=12)
        indicators['ema_26'] = talib.EMA(close, timeperiod=26)
        
        # MACD
        macd, macd_signal, macd_hist = talib.MACD(close)
        indicators['macd'] = macd
        indicators['macd_signal'] = macd_signal
        indicators['macd_hist'] = macd_hist
        
        # RSI
        indicators['rsi'] = talib.RSI(close, timeperiod=14)
        
        # ボリンジャーバンド
        bb_upper, bb_middle, bb_lower = talib.BBANDS(close)
        indicators['bb_upper'] = bb_upper
        indicators['bb_middle'] = bb_middle
        indicators['bb_lower'] = bb_lower
        indicators['bb_width'] = (bb_upper - bb_lower) / bb_middle
        
        # ストキャスティクス
        slowk, slowd = talib.STOCH(high, low, close)
        indicators['stoch_k'] = slowk
        indicators['stoch_d'] = slowd
        
        # ATR (Average True Range)
        indicators['atr'] = talib.ATR(high, low, close, timeperiod=14)
        
        # ADX (Average Directional Index)
        indicators['adx'] = talib.ADX(high, low, close, timeperiod=14)
        
        # 出来高関連
        indicators['volume_sma'] = talib.SMA(volume.astype(float), timeperiod=20)
        
        return indicators

class FeatureEngineering:
    """特徴量エンジニアリングクラス"""
    
    @staticmethod
    def create_price_features(df):
        """価格ベースの特徴量を作成"""
        features = pd.DataFrame()
        
        # 価格変化率
        features['price_change'] = df['close'].pct_change()
        features['price_change_5'] = df['close'].pct_change(5)
        features['price_change_10'] = df['close'].pct_change(10)
        
        # 高値・安値関係
        features['hl_ratio'] = (df['high'] - df['low']) / df['close']
        features['oc_ratio'] = (df['open'] - df['close']) / df['close']
        
        # ローソク足パターン
        features['body_size'] = abs(df['open'] - df['close']) / df['close']
        features['upper_shadow'] = (df['high'] - np.maximum(df['open'], df['close'])) / df['close']
        features['lower_shadow'] = (np.minimum(df['open'], df['close']) - df['low']) / df['close']
        
        return features
    
    @staticmethod
    def create_lag_features(df, target_col='close', lags=[1, 2, 3, 5, 10]):
        """ラグ特徴量を作成"""
        features = pd.DataFrame()
        
        for lag in lags:
            features[f'{target_col}_lag_{lag}'] = df[target_col].shift(lag)
            features[f'{target_col}_pct_lag_{lag}'] = df[target_col].pct_change(lag)
        
        return features
    
    @staticmethod
    def create_rolling_features(df, windows=[5, 10, 20]):
        """移動平均系特徴量を作成"""
        features = pd.DataFrame()
        
        for window in windows:
            features[f'close_mean_{window}'] = df['close'].rolling(window).mean()
            features[f'close_std_{window}'] = df['close'].rolling(window).std()
            features[f'volume_mean_{window}'] = df['volume'].rolling(window).mean()
        
        return features

class LSTMModel:
    """LSTM予測モデルクラス"""
    
    def __init__(self, sequence_length=60, n_features=None):
        self.sequence_length = sequence_length
        self.n_features = n_features
        self.model = None
        self.scaler = MinMaxScaler()
        
    def build_model(self):
        """LSTMモデルを構築"""
        model = Sequential([
            LSTM(128, return_sequences=True, input_shape=(self.sequence_length, self.n_features)),
            Dropout(0.2),
            LSTM(64, return_sequences=True),
            Dropout(0.2),
            LSTM(32, return_sequences=False),
            Dropout(0.2),
            Dense(25),
            Dense(1)
        ])
        
        model.compile(optimizer=Adam(learning_rate=0.001), loss='mse', metrics=['mae'])
        return model
    
    def prepare_sequences(self, data):
        """時系列データをLSTM用のシーケンスに変換"""
        sequences = []
        targets = []
        
        for i in range(self.sequence_length, len(data)):
            sequences.append(data[i-self.sequence_length:i])
            targets.append(data[i, 0])  # close価格を予測
        
        return np.array(sequences), np.array(targets)
    
    def train(self, X_train, y_train, X_val=None, y_val=None, epochs=100, batch_size=32):
        """モデルを訓練"""
        self.model = self.build_model()
        
        callbacks = [
            EarlyStopping(monitor='val_loss', patience=10, restore_best_weights=True)
        ]
        
        validation_data = (X_val, y_val) if X_val is not None else None
        
        history = self.model.fit(
            X_train, y_train,
            validation_data=validation_data,
            epochs=epochs,
            batch_size=batch_size,
            callbacks=callbacks,
            verbose=1
        )
        
        return history
    
    def predict(self, X):
        """予測を実行"""
        if self.model is None:
            raise ValueError("Model not trained yet")
        return self.model.predict(X)

class EnsembleModel:
    """アンサンブル予測モデルクラス"""
    
    def __init__(self):
        self.lstm_model = None
        self.rf_model = RandomForestRegressor(n_estimators=100, random_state=42)
        self.gb_model = GradientBoostingRegressor(n_estimators=100, random_state=42)
        self.meta_model = None
        self.feature_scaler = StandardScaler()
        
    def train(self, X_lstm, y_lstm, X_traditional, y_traditional):
        """アンサンブルモデルを訓練"""
        # LSTMモデルの訓練
        self.lstm_model = LSTMModel(sequence_length=60, n_features=X_lstm.shape[2])
        X_train_lstm, X_val_lstm, y_train_lstm, y_val_lstm = train_test_split(
            X_lstm, y_lstm, test_size=0.2, random_state=42
        )
        self.lstm_model.train(X_train_lstm, y_train_lstm, X_val_lstm, y_val_lstm)
        
        # 従来のMLモデルの訓練
        X_scaled = self.feature_scaler.fit_transform(X_traditional)
        X_train_trad, X_val_trad, y_train_trad, y_val_trad = train_test_split(
            X_scaled, y_traditional, test_size=0.2, random_state=42
        )
        
        self.rf_model.fit(X_train_trad, y_train_trad)
        self.gb_model.fit(X_train_trad, y_train_trad)
        
        # メタモデル（アンサンブル）の訓練
        lstm_pred = self.lstm_model.predict(X_val_lstm)
        rf_pred = self.rf_model.predict(X_val_trad)
        gb_pred = self.gb_model.predict(X_val_trad)
        
        meta_features = np.column_stack([lstm_pred.flatten(), rf_pred, gb_pred])
        self.meta_model = RandomForestRegressor(n_estimators=50, random_state=42)
        self.meta_model.fit(meta_features, y_val_trad)
        
    def predict(self, X_lstm, X_traditional):
        """アンサンブル予測を実行"""
        lstm_pred = self.lstm_model.predict(X_lstm)
        X_scaled = self.feature_scaler.transform(X_traditional)
        rf_pred = self.rf_model.predict(X_scaled)
        gb_pred = self.gb_model.predict(X_scaled)
        
        meta_features = np.column_stack([
            lstm_pred.flatten()[:len(rf_pred)], 
            rf_pred, 
            gb_pred
        ])
        
        ensemble_pred = self.meta_model.predict(meta_features)
        return ensemble_pred

class MLTradingSystem:
    """メイン取引機械学習システムクラス"""
    
    def __init__(self):
        self.ensemble_model = EnsembleModel()
        self.tech_indicators = TechnicalIndicators()
        self.feature_engineering = FeatureEngineering()
        self.last_prediction = None
        self.last_confidence = 0.0
        
    def prepare_data(self, df):
        """データ前処理とFeatue Engineering"""
        # テクニカル指標計算
        tech_features = self.tech_indicators.calculate_indicators(df)
        
        # 価格特徴量
        price_features = self.feature_engineering.create_price_features(df)
        
        # ラグ特徴量
        lag_features = self.feature_engineering.create_lag_features(df)
        
        # 移動平均特徴量
        rolling_features = self.feature_engineering.create_rolling_features(df)
        
        # 全特徴量を結合
        all_features = pd.concat([
            df[['open', 'high', 'low', 'close', 'volume']],
            tech_features,
            price_features,
            lag_features,
            rolling_features
        ], axis=1)
        
        # NaN値を除去
        all_features = all_features.dropna()
        
        return all_features
    
    def train_model(self, df):
        """モデル全体を訓練"""
        print("データ前処理中...")
        features = self.prepare_data(df)
        
        if len(features) < 100:
            raise ValueError("十分なデータがありません（最低100行必要）")
        
        # ターゲット変数（次の終値）
        target = features['close'].shift(-1).dropna()
        features = features[:-1]  # 最後の行を削除
        
        print("LSTM用データ準備中...")
        # LSTM用データ準備
        lstm_features = features[['close', 'volume']].values
        lstm_scaler = MinMaxScaler()
        lstm_scaled = lstm_scaler.fit_transform(lstm_features)
        
        sequence_length = 60
        X_lstm, y_lstm = [], []
        for i in range(sequence_length, len(lstm_scaled)):
            X_lstm.append(lstm_scaled[i-sequence_length:i])
            y_lstm.append(target.iloc[i])
        
        X_lstm = np.array(X_lstm)
        y_lstm = np.array(y_lstm)
        
        # 従来のML用データ準備
        traditional_features = features.iloc[sequence_length:].values
        traditional_target = target.iloc[sequence_length:].values
        
        print("モデル訓練中...")
        self.ensemble_model.train(X_lstm, y_lstm, traditional_features, traditional_target)
        
        # スケーラーを保存
        self.lstm_scaler = lstm_scaler
        
        print("モデル訓練完了！")
    
    def predict_next_price(self, recent_data):
        """次の価格を予測"""
        try:
            features = self.prepare_data(recent_data)
            
            if len(features) < 60:
                return None, 0.0
            
            # LSTM用データ準備
            lstm_data = features[['close', 'volume']].tail(60).values
            lstm_scaled = self.lstm_scaler.transform(lstm_data)
            X_lstm = lstm_scaled.reshape(1, 60, 2)
            
            # 従来のML用データ準備
            X_traditional = features.tail(1).values
            
            # 予測実行
            prediction = self.ensemble_model.predict(X_lstm, X_traditional)
            
            self.last_prediction = prediction[0]
            
            # 信頼度計算（簡易版）
            current_price = features['close'].iloc[-1]
            price_change_pct = abs(prediction[0] - current_price) / current_price
            confidence = max(0.5, min(0.95, 1.0 - price_change_pct * 10))
            self.last_confidence = confidence
            
            return prediction[0], confidence
            
        except Exception as e:
            print(f"予測エラー: {e}")
            return None, 0.0
    
    def generate_signal(self, recent_data, current_price):
        """売買シグナルを生成"""
        predicted_price, confidence = self.predict_next_price(recent_data)
        
        if predicted_price is None or confidence < 0.6:
            return "HOLD", 0.0, predicted_price
        
        price_change_pct = (predicted_price - current_price) / current_price * 100
        
        # シグナル判定
        if price_change_pct > 0.1 and confidence > 0.7:
            return "BUY", confidence, predicted_price
        elif price_change_pct < -0.1 and confidence > 0.7:
            return "SELL", confidence, predicted_price
        else:
            return "HOLD", confidence, predicted_price
    
    def save_model(self, filepath):
        """モデルを保存"""
        model_data = {
            'ensemble_model': self.ensemble_model,
            'lstm_scaler': self.lstm_scaler,
            'last_prediction': self.last_prediction,
            'last_confidence': self.last_confidence
        }
        joblib.dump(model_data, filepath)
        print(f"モデルを保存しました: {filepath}")
    
    def load_model(self, filepath):
        """モデルを読み込み"""
        try:
            model_data = joblib.load(filepath)
            self.ensemble_model = model_data['ensemble_model']
            self.lstm_scaler = model_data['lstm_scaler']
            self.last_prediction = model_data.get('last_prediction')
            self.last_confidence = model_data.get('last_confidence', 0.0)
            print(f"モデルを読み込みました: {filepath}")
            return True
        except Exception as e:
            print(f"モデル読み込みエラー: {e}")
            return False

# サンプル使用例
if __name__ == "__main__":
    # ダミーデータでテスト
    dates = pd.date_range('2020-01-01', '2024-01-01', freq='H')
    np.random.seed(42)
    
    # サンプルOHLCVデータ生成
    close_prices = 1.1000 + np.cumsum(np.random.randn(len(dates)) * 0.0001)
    sample_data = pd.DataFrame({
        'datetime': dates,
        'open': close_prices + np.random.randn(len(dates)) * 0.0001,
        'high': close_prices + np.abs(np.random.randn(len(dates)) * 0.0002),
        'low': close_prices - np.abs(np.random.randn(len(dates)) * 0.0002),
        'close': close_prices,
        'volume': np.random.randint(100, 1000, len(dates))
    })
    
    # システム初期化とテスト
    ml_system = MLTradingSystem()
    
    print("機械学習システムのテスト開始...")
    try:
        # モデル訓練（最初の90%のデータ）
        train_size = int(len(sample_data) * 0.9)
        train_data = sample_data[:train_size]
        
        ml_system.train_model(train_data)
        
        # 予測テスト（最後の100行）
        test_data = sample_data[-100:]
        current_price = test_data['close'].iloc[-1]
        
        signal, confidence, predicted_price = ml_system.generate_signal(test_data, current_price)
        
        print(f"現在価格: {current_price:.5f}")
        if predicted_price is not None:
            print(f"予測価格: {predicted_price:.5f}")
        else:
            print("予測価格: None (予測失敗)")
        print(f"シグナル: {signal}")
        print(f"信頼度: {confidence:.2f}")
        
        # モデル保存
        ml_system.save_model("trading_model.pkl")
        
    except Exception as e:
        print(f"エラー: {e}")
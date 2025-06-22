import sys
import os
import pytz

# ???????????????
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

# ??????????????(???????????)
try:
    from ml_trading_system import MLTradingSystem
    ML_SYSTEM_AVAILABLE = True
except ImportError as e:
    print(f"??: ml_trading_system ?????????????: {e}")
    print("????API????????????")
    ML_SYSTEM_AVAILABLE = False
    # ?????????
    class MLTradingSystem:
        def __init__(self):
            pass
        def load_model(self, path):
            return False
        def generate_signal(self, df, price):
            return "HOLD", 0.0, None, "ML system not available"

# ????
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('trading_api.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)

app = Flask(__name__)

class SymbolDataManager:
    """???????????????????????"""
    
    def __init__(self, base_dir, symbol, max_buffer_size=1000):
        self.symbol = symbol
        self.base_dir = Path(base_dir)
        self.max_buffer_size = max_buffer_size
        
        # ??????????????
        self.symbol_dir = self.base_dir / "data" / symbol
        self.symbol_dir.mkdir(parents=True, exist_ok=True)
        
        # ????????
        self.current_file = self.symbol_dir / f"{symbol}_current.csv"
        self.archive_dir = self.symbol_dir / "archive"
        self.archive_dir.mkdir(exist_ok=True)
        
        # ???????
        self.data_buffer = []
        self.last_backup_time = datetime.now()
        self.backup_interval = 300  # 5?
        
        # ??????
        self.last_unique_data = None
        self.duplicate_count = 0
        self.market_timezone = pytz.timezone('America/New_York')  # NYSE??
        
        # ???????????
        self.load_current_data()
    
    def is_market_open(self, timestamp=None):
        """??????????(???????)"""
        try:
            # ?????NY?????
            current_ny_time = datetime.now(self.market_timezone)
            weekday = current_ny_time.weekday()  # 0=??, 6=??
            hour = current_ny_time.hour
            
            # ????????
            #logging.debug(f"[{self.symbol}] ????DEBUG: current_ny_time={current_ny_time}, weekday={weekday}, hour={hour}")
            
            # ?????
            if weekday >= 5:  # ??(5), ??(6)
                logging.debug(f"[{self.symbol}] ???????")
                return False
            
            # ????21:00?? (NY??)
            if weekday == 4 and hour >= 21:
                logging.debug(f"[{self.symbol}] ??21????????")
                return False
                
            # ???17:00???? (NY??)
            if weekday == 0 and hour < 17:
                logging.debug(f"[{self.symbol}] ??17???????")
                return False
                
            logging.debug(f"[{self.symbol}] ?????")
            return True
            
        except Exception as e:
            logging.warning(f"[{self.symbol}] ?????????: {e}")
            return True  # ??????????????
    
    def is_duplicate_data(self, tick_data):
        """???????(????)"""
        if len(self.data_buffer) == 0:
            return False
            
        last_item = self.data_buffer[-1]
        
        # ???????????????????
        return (
            last_item['datetime'] == tick_data['datetime'] and
            last_item['open'] == tick_data['open'] and
            last_item['high'] == tick_data['high'] and
            last_item['low'] == tick_data['low'] and
            last_item['close'] == tick_data['close'] and
            last_item['volume'] == tick_data['volume']
        )
    
    def save_data(self):
        """?????????"""
        try:
            if len(self.data_buffer) == 0:
                return
            
            df = pd.DataFrame(self.data_buffer)
            
            # datetime????????
            if 'datetime' in df.columns:
                df['datetime'] = pd.to_datetime(df['datetime']).dt.strftime('%Y-%m-%d %H:%M:%S')
            
            # symbol??????
            df['symbol'] = self.symbol
            
            df.to_csv(self.current_file, index=False, encoding='utf-8')
            logging.info(f"[{self.symbol}] ?????: {len(self.data_buffer)}? -> {self.current_file}")
            self.last_backup_time = datetime.now()
            
        except Exception as e:
            logging.error(f"[{self.symbol}] ????????: {e}")
    
    def load_current_data(self):
        """???????????"""
        try:
            if not self.current_file.exists():
                logging.info(f"[{self.symbol}] ??????????????????")
                return
            
            df = pd.read_csv(self.current_file, encoding='utf-8')
            
            if len(df) == 0:
                return
            
            # datetime????
            if 'datetime' in df.columns:
                df['datetime'] = pd.to_datetime(df['datetime'])
            
            # symbol???????????????
            if 'symbol' in df.columns:
                df = df.drop('symbol', axis=1)
            
            self.data_buffer = df.to_dict('records')
            
            # ?????????
            if len(self.data_buffer) > self.max_buffer_size:
                self.data_buffer = self.data_buffer[-self.max_buffer_size:]
            
            logging.info(f"[{self.symbol}] ?????: {len(self.data_buffer)}?")
            
        except Exception as e:
            logging.error(f"[{self.symbol}] ??????????: {e}")
            self.data_buffer = []
    
    def add_data(self, tick_data):
        """??????????????????"""
        try:
            # ?????
            required_fields = ['datetime', 'open', 'high', 'low', 'close', 'volume']
            for field in required_fields:
                if field not in tick_data:
                    raise ValueError(f"??????????: {field}")
            
            # ???????????
            if isinstance(tick_data['datetime'], str):
                tick_data['datetime'] = pd.to_datetime(tick_data['datetime'])
            
            # ??????????
            market_open = self.is_market_open(tick_data['datetime'])
            
            # ?????????
            is_duplicate = self.is_duplicate_data(tick_data)

            # ???????? - ????
            #logging.debug(f"[{self.symbol}] DEBUG: is_duplicate={is_duplicate}, duplicate_count={self.duplicate_count}")
            #logging.debug(f"[{self.symbol}] DEBUG: market_open={market_open}")
            #if len(self.data_buffer) > 0:
            #    last_item = self.data_buffer[-1]
            #    logging.debug(f"[{self.symbol}] DEBUG: last_datetime={last_item['datetime']}, new_datetime={tick_data['datetime']}")
            #    logging.debug(f"[{self.symbol}] DEBUG: last_close={last_item['close']}, new_close={tick_data['close']}")
            #    logging.debug(f"[{self.symbol}] DEBUG: datetime_equal={last_item['datetime'] == tick_data['datetime']}")
            #    logging.debug(f"[{self.symbol}] DEBUG: close_equal={last_item['close'] == tick_data['close']}")
            # ???????? - ????
            
            if is_duplicate:
                self.duplicate_count += 1
                
                # ??????????????
                if not market_open:
                    if self.duplicate_count > 10:  # 10???????????
                        logging.debug(f"[{self.symbol}] ???????????? (#{self.duplicate_count})")
                        return True
                
                # ???????????????
                elif self.duplicate_count > 3:
                    logging.debug(f"[{self.symbol}] ????????? (#{self.duplicate_count})")
                    return True
            else:
                self.duplicate_count = 0  # ???????????????
            
            # ???????
            self.data_buffer.append(tick_data)
            
            # ?????????
            if market_open:
                logging.info(f"[{self.symbol}] ?????????: {tick_data['datetime']}, Close: {tick_data['close']}")
            else:
                logging.debug(f"[{self.symbol}] ??????: {tick_data['datetime']}, Close: {tick_data['close']}")
            
            # ?????????(??????????)
            if market_open:
                max_size = self.max_buffer_size
            else:
                max_size = self.max_buffer_size // 10  # ????1/10???
            
            if len(self.data_buffer) > max_size + 50:
                self.archive_old_data()
            
            # ????????????
            self.auto_backup_check()
            
            return True
            
        except Exception as e:
            logging.error(f"[{self.symbol}] ????????: {e}")
            return False
    
    def archive_old_data(self):
        """??????????"""
        try:
            current_max = self.max_buffer_size
            
            # ??????????????
            if len(self.data_buffer) > 0:
                last_time = self.data_buffer[-1]['datetime']
                if not self.is_market_open(last_time):
                    current_max = self.max_buffer_size // 10
            
            if len(self.data_buffer) <= current_max:
                return
            
            # ??????????
            excess_count = len(self.data_buffer) - current_max
            archive_data = self.data_buffer[:excess_count]
            
            if len(archive_data) == 0:
                return
            
            # ???????????????????
            unique_dates = set()
            for item in archive_data:
                unique_dates.add(pd.to_datetime(item['datetime']).date())
            
            if len(unique_dates) == 1 and excess_count > 100:
                # ???????????????(?????????)
                sample_data = archive_data[::10]  # 10??????????
                logging.info(f"[{self.symbol}] ????????????????????: {len(archive_data)}? -> {len(sample_data)}?")
                archive_data = sample_data
            
            if len(archive_data) == 0:
                self.data_buffer = self.data_buffer[excess_count:]
                return
            
            archive_df = pd.DataFrame(archive_data)
            
            # ???????
            first_date = pd.to_datetime(archive_df['datetime'].iloc[0]).strftime('%Y%m%d_%H%M')
            last_date = pd.to_datetime(archive_df['datetime'].iloc[-1]).strftime('%Y%m%d_%H%M')
            timestamp = datetime.now().strftime('%H%M%S')
            
            market_status = "closed" if not self.is_market_open(archive_df['datetime'].iloc[0]) else "open"
            archive_filename = f"{self.symbol}_{first_date}_{last_date}_{market_status}_{timestamp}.csv"
            archive_path = self.archive_dir / archive_filename
            
            # ???????
            archive_df['datetime'] = pd.to_datetime(archive_df['datetime']).dt.strftime('%Y-%m-%d %H:%M:%S')
            archive_df['symbol'] = self.symbol
            archive_df.to_csv(archive_path, index=False, encoding='utf-8')
            
            logging.info(f"[{self.symbol}] ???????: {len(archive_data)}? -> {archive_filename}")
            
            # ???????
            self.data_buffer = self.data_buffer[excess_count:]
            
        except Exception as e:
            logging.error(f"[{self.symbol}] ????????: {e}")
    
    def auto_backup_check(self):
        """????????????"""
        current_time = datetime.now()
        time_diff = (current_time - self.last_backup_time).total_seconds()
        
        if time_diff >= self.backup_interval:
            self.save_data()
    
    def get_recent_dataframe(self, periods=200):
        """???????DataFrame???"""
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
        """????????"""
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
        
        # ???????
        market_status = "Unknown"
        if len(self.data_buffer) > 0:
            last_time = self.data_buffer[-1]['datetime']
            market_status = "Open" if self.is_market_open(last_time) else "Closed"
        
        return {
            'symbol': self.symbol,
            'current_buffer_size': current_size,
            'archive_files': archive_count,
            'total_archived_records': total_archived,
            'total_records': current_size + total_archived,
            'last_backup': self.last_backup_time.isoformat(),
            'market_status': market_status,
            'duplicate_count': self.duplicate_count
        }

class TradingAPIServer:
    def __init__(self):
        if ML_SYSTEM_AVAILABLE:
            self.ml_system = MLTradingSystem()
        else:
            self.ml_system = None
            
        # ??????????????
        self.symbol_managers = {}
        self.data_base_dir = current_dir
        self.max_buffer_size = 1000
        
        # ??????
        self.last_signal = {}  # ?????
        self.last_confidence = {}  # ?????
        self.last_prediction = {}  # ?????
        self.model_loaded = {}  # ?????
        
        # ?????
        self.error_count = 0
        self.last_error_time = None
        self.connection_errors = 0
        self.last_successful_request = datetime.now()
        
        # ??????????
        if ML_SYSTEM_AVAILABLE:
            self.load_existing_models()
        
        # ????????????????
        self.start_background_tasks()
    
    def get_symbol_manager(self, symbol):
        """?????????????????"""
        if symbol not in self.symbol_managers:
            self.symbol_managers[symbol] = SymbolDataManager(
                self.data_base_dir, symbol, self.max_buffer_size
            )
            # ??????????????
            self.last_signal[symbol] = "HOLD"
            self.last_confidence[symbol] = 0.0
            self.last_prediction[symbol] = None
            self.model_loaded[symbol] = False
            
        return self.symbol_managers[symbol]
    
    def load_existing_models(self):
        """???????????(trading_model.pkl??)"""
        if not ML_SYSTEM_AVAILABLE:
            logging.warning("ML System not available - ???????")
            return
        
        try:
            # 1. ????? (trading_model.pkl) ?????
            generic_model_file = Path(current_dir) / "trading_model.pkl"
            if generic_model_file.exists():
                logging.info(f"????????????: {generic_model_file}")
                try:
                    if self.ml_system.load_model(str(generic_model_file)):
                        # ????????????????
                        for symbol in ['EURUSD', 'USDJPY', 'GBPUSD', 'AUDUSD', 'USDCAD']:  # ??????
                            self.model_loaded[symbol] = True
                            logging.info(f"[{symbol}] ???????????")
                        
                        logging.info("? ??ML??? (trading_model.pkl) ??????")
                        return True
                    else:
                        logging.warning("? ?????????????")
                except Exception as e:
                    logging.error(f"? ????????????: {e}")
            
            # 2. ??????????????? (???????)
            model_pattern = "trading_model_*.pkl"
            model_files = list(Path(current_dir).glob(model_pattern))
            
            if len(model_files) == 0:
                logging.info("?? ??????????????????")
                logging.info("?? ????????????? /retrain/<symbol> ?????????????")
                return False
            
            success_count = 0
            for model_file in model_files:
                symbol = model_file.stem.replace('trading_model_', '')
                try:
                    if self.ml_system.load_model(str(model_file)):
                        self.model_loaded[symbol] = True
                        success_count += 1
                        logging.info(f"[{symbol}] ???????????: {model_file}")
                    else:
                        logging.warning(f"[{symbol}] ?????????: {model_file}")
                except Exception as e:
                    logging.error(f"[{symbol}] ??????????: {e}")
            
            if success_count > 0:
                logging.info(f"? {success_count}??????????????????")
                return True
            else:
                logging.warning("? ?????????????????????")
                return False
                
        except Exception as e:
            logging.error(f"? ???????????????: {e}")
            return False
    
    def add_tick_data(self, tick_data, symbol):
        """??????????"""
        manager = self.get_symbol_manager(symbol)
        success = manager.add_data(tick_data)
                
        return success
    
    def generate_trading_signal(self, symbol):
        """?????????(???????????????)"""
        try:
            # ML????????????
            if not ML_SYSTEM_AVAILABLE:
                return "HOLD", 0.0, None, f"ML system not available"
            
            if self.ml_system is None:
                return "HOLD", 0.0, None, f"ML system not initialized"
            
            # ??????????????????
            if symbol not in self.model_loaded or not self.model_loaded[symbol]:
                # ???????????????????
                logging.info(f"[{symbol}] ???????? - ????????")
                self.load_existing_models()
                
                if symbol not in self.model_loaded or not self.model_loaded[symbol]:
                    return "HOLD", 0.0, None, f"Model not loaded for {symbol}"
            
            # ?????
            manager = self.get_symbol_manager(symbol)
            df = manager.get_recent_dataframe(200)
            
            if df is None or len(df) < 100:
                available_data = len(df) if df is not None else 0
                return "HOLD", 0.0, None, f"Insufficient data for {symbol} (have: {available_data}, need: 100)"
            
            # ??????
            current_price = df['close'].iloc[-1]
            
            # ML???????????
            signal, confidence, predicted_price = self.ml_system.generate_signal(df, current_price)
            
            # ?????????
            self.last_signal[symbol] = signal
            self.last_confidence[symbol] = confidence
            self.last_prediction[symbol] = predicted_price
            
            # ???????
            price_change = ""
            if predicted_price and predicted_price != current_price:
                change_pct = ((predicted_price - current_price) / current_price) * 100
                price_change = f" ({change_pct:+.2f}%)"
            
            logging.info(f"[{symbol}] ?? ??????: {signal}, ???: {confidence:.3f}{price_change}")
            return signal, confidence, predicted_price, "Success"
            
        except Exception as e:
            error_msg = f"[{symbol}] ?????????: {str(e)}"
            logging.error(error_msg)
            return "HOLD", 0.0, None, error_msg
    
    def retrain_model(self, symbol):
        """???????"""
        try:
            manager = self.get_symbol_manager(symbol)
            df = manager.get_recent_dataframe()
            
            if df is None or len(df) < 500:
                return False, f"Insufficient data for training {symbol} (minimum 500 required)"
            
            logging.info(f"[{symbol}] ????????...")
            self.ml_system.train_model(df)
            
            # ?????????????
            model_file = f"trading_model_{symbol}.pkl"
            self.ml_system.save_model(model_file)
            self.model_loaded[symbol] = True
            
            # ?????????????
            manager.save_data()
            
            logging.info(f"[{symbol}] ????????")
            return True, f"Model retrained successfully for {symbol}"
            
        except Exception as e:
            error_msg = f"[{symbol}] ?????????: {e}"
            logging.error(error_msg)
            return False, error_msg
    
    def start_background_tasks(self):
        """??????????????"""
        def background_worker():
            while True:
                try:
                    # ????????????????
                    for symbol, manager in self.symbol_managers.items():
                        buffer_size = len(manager.data_buffer)
                        if buffer_size >= 500 and buffer_size % 100 == 0:
                            logging.info(f"[{symbol}] ???????????????...")
                            self.retrain_model(symbol)
                        
                        # ????????
                        manager.auto_backup_check()
                    
                    time.sleep(300)  # 5????????
                    
                except Exception as e:
                    logging.error(f"??????????????: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=background_worker, daemon=True)
        thread.start()
    
    def get_all_symbols_stats(self):
        """??????????"""
        stats = {}
        for symbol, manager in self.symbol_managers.items():
            stats[symbol] = manager.get_symbol_stats()
            stats[symbol]['model_loaded'] = self.model_loaded.get(symbol, False)
            stats[symbol]['last_signal'] = self.last_signal.get(symbol, "HOLD")
            stats[symbol]['last_confidence'] = self.last_confidence.get(symbol, 0.0)
        
        return stats

# ?????API??????????
api_server = TradingAPIServer()

@app.route('/health', methods=['GET'])
def health_check():
    """???????"""
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
    """?????????(??????)"""
    try:
        data = request.get_json()
        
        if not data:
            api_server.connection_errors += 1
            return jsonify({'error': 'No data provided'}), 400
        
        # ????????
        symbol = data.get('symbol', 'UNKNOWN')
        if symbol == 'UNKNOWN':
            return jsonify({'error': 'Symbol not specified'}), 400
        
        # ?????????????????????
        tick_data = {k: v for k, v in data.items() if k != 'symbol'}
        
        # ?????
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
    """????????(??????)"""
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
        logging.error(f"????????? [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/retrain/<symbol>', methods=['POST'])
def manual_retrain(symbol):
    """????????(??????)"""
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
        logging.error(f"???????? [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status', methods=['GET'])
def get_status():
    """????????(?????)"""
    try:
        return jsonify({
            'symbols': api_server.get_all_symbols_stats(),
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logging.error(f"???????: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/status/<symbol>', methods=['GET'])
def get_symbol_status(symbol):
    """?????????"""
    try:
        manager = api_server.get_symbol_manager(symbol)
        stats = manager.get_symbol_stats()
        stats['model_loaded'] = api_server.model_loaded.get(symbol, False)
        stats['last_signal'] = api_server.last_signal.get(symbol, "HOLD")
        stats['last_confidence'] = round(api_server.last_confidence.get(symbol, 0.0), 3)
        stats['last_prediction'] = round(api_server.last_prediction.get(symbol, 0.0), 5) if api_server.last_prediction.get(symbol) else None
        
        return jsonify(stats)
        
    except Exception as e:
        logging.error(f"??????????? [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/data/<symbol>/latest', methods=['GET'])
def get_latest_data(symbol):
    """???????(??????)"""
    try:
        count = request.args.get('count', 10, type=int)
        count = min(count, 100)  # ??100?
        
        manager = api_server.get_symbol_manager(symbol)
        
        if len(manager.data_buffer) == 0:
            return jsonify({'symbol': symbol, 'data': [], 'count': 0})
        
        latest_data = manager.data_buffer[-count:]
        
        # datetime ???????
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
        logging.error(f"?????????? [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/backup/<symbol>', methods=['POST'])
def manual_backup(symbol):
    """???????????(??????)"""
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
        logging.error(f"??????????? [{symbol}]: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/backup/all', methods=['POST'])
def backup_all_symbols():
    """???????????????"""
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
        logging.error(f"??????????????: {e}")
        return jsonify({'error': str(e)}), 500

# if __name__ == '__main__': ??????????????????
# ?????????????

if __name__ == '__main__':
    print("=" * 80)
    print("?? Flask Trading API Server ???...")
    print("=" * 80)
    
    # ML????????
    if ML_SYSTEM_AVAILABLE:
        print("? ML Trading System: ????")
        
        # ??????????
        generic_model = Path(current_dir) / "trading_model.pkl"
        if generic_model.exists():
            print(f"? ???????????: {generic_model}")
            print("?? ????????????????????????")
        else:
            print("??  ????????? (trading_model.pkl) ????????")
            
            # ?????????????
            symbol_models = list(Path(current_dir).glob("trading_model_*.pkl"))
            if symbol_models:
                print(f"? ??????????: {len(symbol_models)}?")
                for model in symbol_models:
                    symbol = model.stem.replace('trading_model_', '')
                    print(f"   - {symbol}: {model}")
            else:
                print("?? ??????????????")
                print("   ??????? /retrain/<symbol> ?????????????")
    else:
        print("? ML Trading System: ????")
        print("   ????API????????????")
    
    print("")
    print("?? ?????API???????:")
    print("  GET  /health                    - ???????")
    print("  POST /tick                      - ????????? (symbol??)")
    print("  GET  /signal/<symbol>           - ????????")
    print("  POST /retrain/<symbol>          - ??????")
    print("  GET  /status                    - ???????")
    print("  GET  /status/<symbol>           - ???????")
    print("  GET  /data/<symbol>/latest      - ???????")
    print("  POST /backup/<symbol>           - ????????")
    print("  POST /backup/all                - ???????????")
    print("")
    print("?? ?????? (MT5??):")
    print('  POST /tick')
    print('  {')
    print('    "symbol": "EURUSD",')
    print('    "datetime": "2024-01-01T10:00:00",')
    print('    "open": 1.1000, "high": 1.1010,')
    print('    "low": 1.0990, "close": 1.1005,')
    print('    "volume": 100')
    print('  }')
    print("")
    print("?? ??????: http://localhost:5000")
    print("=" * 80)
    
    # ??????
    logging.info("Flask Trading API Server ???????")
    if ML_SYSTEM_AVAILABLE:
        logging.info("ML Trading System ready for predictions")
    
    # Flask ??????
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
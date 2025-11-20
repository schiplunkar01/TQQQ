#!/usr/bin/env python3
import os
import logging
try:
    from dotenv import load_dotenv
except Exception:
    def load_dotenv():
        return
from datetime import datetime
from .models import Models

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('tqqq_agent')

load_dotenv()
# Ensure yfinance uses a safe, writable tz-cache location to avoid cache-folder errors
import tempfile
try:
    import yfinance as _yf
    tmp_cache = os.path.join(tempfile.gettempdir(), 'py-yfinance-cache')
    try:
        _yf.set_tz_cache_location(tmp_cache)
    except Exception:
        # non-fatal: continue without setting cache
        pass
except Exception:
    # yfinance not installed yet or failed to import; that's fine for now
    pass
MODEL_DIR = os.getenv('MODEL_DIR', './models')
LGB_FILE = os.getenv('LGB_MODEL_FILE', 'lgb_model.pkl')
LSTM_FILE = os.getenv('LSTM_MODEL_FILE', 'lstm_model.pth')
SCALER_FILE = os.getenv('SCALER_FILE', 'scaler.pkl')
DRY_RUN = os.getenv('DRY_RUN', 'true').lower() in ['1','true','yes']
TH_LGB = float(os.getenv('THRESH_LGB', 0.60))
TH_LSTM = float(os.getenv('THRESH_LSTM', 0.65))
TH_VOTE = int(os.getenv('THRESH_VOTE', 2))

FEATURE_COLS = ['ret_5','ret_10','ret_20','vol_20','VIX','rsi','volume','month','dow','ret_1']
USE_MOCK_DATA = os.getenv('USE_MOCK_DATA', 'false').lower() in ['1','true','yes']


def main():
    logger.info('Starting TQQQ signal agent (dry_run=%s)', DRY_RUN)

    models = Models(MODEL_DIR, LGB_FILE, LSTM_FILE, SCALER_FILE)
    try:
        models.load()
    except Exception as e:
        logger.error('Model load failed: %s', e)
        return

    # Fetch data (or use mock)
    if USE_MOCK_DATA:
        # create simple mock data without external deps
        logger.info('Using mock data for offline run (no pandas/numpy)')
        from datetime import timedelta
        today = datetime.utcnow().date()
        dates = [today - timedelta(days=i) for i in range(400,100,-1)]  # 300 business-like days
        dates = list(reversed(dates))
        # synthetic QQQ price series
        q = [100.0]
        import random
        for _ in range(1, len(dates)):
            q.append(q[-1] * (1 + random.normalvariate(0.0005, 0.01)))
        vix = [20 + random.normalvariate(0,1) for _ in dates]
        vol = [abs(random.normalvariate(1e7, 2e6)) for _ in dates]

        # build a minimal DataFrame-like structure for build_features
        class MiniDF(dict):
            def __init__(self, d, idx):
                super().__init__(d)
                self.index = idx
            def copy(self):
                return MiniDF(dict(self), list(self.index))
        data = MiniDF({'QQQ': q, '^VIX': vix}, dates)
        vol_series = vol
        # build_features expects pandas; for mock run we'll implement a tiny adapter
        # We'll create a very small pandas-like df using lists and dicts handled in build_features
        # For simplicity, call build_features only when real pandas is present; otherwise
        # replicate simplified feature computations here.
        # Minimal feature calc for mock path:
        from statistics import mean, stdev
        df = {}
        df['QQQ'] = q
        df['VIX'] = vix
        df['volume'] = vol
        # simple returns
        def pct_change(arr, p):
            return [(arr[i] - arr[i-p]) / arr[i-p] if i>=p and arr[i-p]!=0 else None for i in range(len(arr))]
        for p in [5,10,20,50,100,200]:
            df[f'ret_{p}'] = pct_change(q, p)
            # rolling std of pct change - approximate
            ret1 = pct_change(q,1)
            vol_p = []
            for i in range(len(ret1)):
                window = ret1[max(0,i-p+1):i+1]
                window = [w for w in window if w is not None]
                vol_p.append(stdev(window) if len(window)>1 else 0.0)
            df[f'vol_{p}'] = vol_p
        # rsi simplified: set neutral
        df['rsi'] = [50.0]*len(q)
        df['month'] = [d.month for d in dates]
        df['dow'] = [d.weekday() for d in dates]
        # convert to a simple object that our prepare_lstm_sequence can handle in mock mode
        class SeriesLike:
            def __init__(self, arr):
                self._arr = arr
            @property
            def values(self):
                return self._arr
            def __getitem__(self, idx):
                return self._arr[idx]
            # allow bracket/negative indexing like .iloc[-1]
            @property
            def iloc(self):
                class _I:
                    def __init__(self, arr):
                        self.arr = arr
                    def __getitem__(self, idx):
                        return self.arr[idx]
                return _I(self._arr)

        class SimpleDF:
            def __init__(self, d, idx):
                self._d = d
                self.index = idx
            def __getitem__(self, key):
                v = self._d[key]
                if isinstance(v, list):
                    return SeriesLike(v)
                return v
            def copy(self):
                return SimpleDF(dict(self._d), list(self.index))
            def tail(self, n):
                s = {k: (v[-n:] if isinstance(v, list) else v) for k,v in self._d.items()}
                return SimpleDF(s, self.index[-n:])
            def __len__(self):
                return len(self.index)
        df = SimpleDF(df, dates)
    else:
        from .utils import fetch_data, build_features
        try:
            data = fetch_data(['QQQ','^VIX'], period='2y', interval='1d')
            vol = fetch_data(['QQQ'], period='2y', interval='1d')['QQQ'].to_frame('Volume')
        except Exception as e:
            logger.error('Data fetch failed: %s', e)
            return

        # Normalize into single DF
        df = data.copy()
        df.columns = ['QQQ','VIX']
        # Volume fetch may need reindex
        vol_series = vol['Volume'] if 'Volume' in vol.columns else vol

        df = build_features(df, vol_series)

    # Check sufficient history
    if len(df) < 252 or len(df) < 200:
        logger.error('Not enough historical rows: %d', len(df))
        return

    if USE_MOCK_DATA:
        # simple list-based computations for mock
        q_series = df['QQQ']
        latest = q_series[-1]
        sma200 = sum(q_series[-200:]) / len(q_series[-200:])
        signal_sma = 1 if latest > sma200 else 0

        # mock LGB probability
        lgb_probs = models.predict_lgb_prob([[]])
        try:
            lgb_prob = float(lgb_probs[0][1])
        except Exception:
            lgb_prob = 0.5
        signal_lgb = 1 if lgb_prob > TH_LGB else 0

        # mock LSTM probs
        try:
            regime_probs = models.predict_lstm_probs(None)[0]
            if hasattr(regime_probs, '__len__'):
                lstm_bull = float(regime_probs[0])
            else:
                lstm_bull = 1/3
        except Exception:
            lstm_bull = 1/3
            regime_probs = [lstm_bull, (1-lstm_bull)/2, (1-lstm_bull)/2]
        signal_lstm = 1 if lstm_bull >= TH_LSTM else 0
    else:
        # Signal 1: 200-day SMA on QQQ (mapped to TQQQ posture)
        latest = df['QQQ'].iloc[-1]
        sma200 = df['QQQ'].iloc[-200:].mean()
        signal_sma = 1 if latest > sma200 else 0

        # Signal 2: LightGBM
        # Use the explicit FEATURE_COLS (order matters) and validate presence
        # Support both pandas DataFrame and the lightweight mock SimpleDF
        if hasattr(df, 'columns'):
            available_cols = list(df.columns)
        else:
            # our SimpleDF stores data in _d
            available_cols = list(getattr(df, '_d', {}).keys())

        missing_cols = [c for c in FEATURE_COLS if c not in available_cols]
        if missing_cols:
            logger.error('Missing feature columns required by scaler: %s', missing_cols)
            return

        # select features in the exact order expected by the scaler
        try:
            X_df = None
            if hasattr(df, 'columns'):
                # pandas DataFrame
                X_df = df[FEATURE_COLS].iloc[-1:]
            else:
                # SimpleDF: build row list preserving order
                row = [df[c].values[-1] if hasattr(df[c], 'values') else df[c][-1] for c in FEATURE_COLS]
                import numpy as _np
                X_df = _np.array(row).reshape(1, -1)
        except Exception:
            logger.error('Failed to select FEATURE_COLS from dataframe')
            return

        try:
            Xs = models.scaler.transform(X_df.values if hasattr(X_df, 'values') else X_df)
        except Exception as e:
            logger.error('Scaler transform failed: %s', e)
            return
        lgb_probs = models.predict_lgb_prob(Xs)
        if lgb_probs.ndim == 1:
            # binary raw scores
            lgb_prob = float(lgb_probs[0])
        else:
            lgb_prob = float(lgb_probs[0][1])
        signal_lgb = 1 if lgb_prob > TH_LGB else 0

        # Signal 3: LSTM regime
        from .utils import prepare_lstm_sequence
        seq = prepare_lstm_sequence(df, FEATURE_COLS, seq_len=252)
        import torch
        seq_t = torch.tensor(seq, dtype=torch.float32).unsqueeze(0)
        try:
            regime_probs = models.predict_lstm_probs(seq_t)[0]
        except Exception as e:
            logger.error('LSTM inference failed: %s', e)
            return
        signal_lstm = 1 if regime_probs[0] >= TH_LSTM else 0

    bullish_count = signal_sma + signal_lgb + signal_lstm
    final_signal = 'LONG TQQQ (100%)' if bullish_count >= TH_VOTE else 'CASH / SHORT'

    # Output
    now = datetime.utcnow().strftime('%Y-%m-%d %H:%M')
    logger.info('Date: %s UTC', now)
    logger.info('SMA200: %s', 'Bullish' if signal_sma else 'Bearish')
    logger.info('LightGBM prob: %.2f', lgb_prob)
    logger.info('LSTM Bull prob: %.2f', regime_probs[0])
    logger.info('Bullish models: %d/3', bullish_count)
    logger.info('→ TOMORROW\'S SIGNAL: %s', final_signal)

    # If not dry run, here is where an execution module would be called.
    if not DRY_RUN:
        logger.warning('DRY_RUN is false but execution module not implemented in this prototype')

if __name__ == '__main__':
    main()

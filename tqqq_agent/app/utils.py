from typing import Tuple, List
import pandas as pd
import numpy as np
import yfinance as yf


def fetch_data(tickers: List[str], period: str = "2y", interval: str = "1d") -> pd.DataFrame:
    # Explicitly set auto_adjust to avoid FutureWarning and be explicit about which price to use
    raw = yf.download(tickers, period=period, interval=interval, auto_adjust=False)
    # try to select adjusted close first (old behavior); fall back to Close if missing
    try:
        df = raw['Adj Close']
    except Exception:
        # When 'Adj Close' level is not present, try 'Close'
        if 'Close' in raw.columns:
            df = raw['Close']
        else:
            # final fallback: use the raw dataframe (single-column)
            df = raw

    # if single ticker, yf may return a Series
    if isinstance(df, pd.Series):
        df = df.to_frame()
    return df


def build_features(df: pd.DataFrame, vol_series: pd.Series) -> pd.DataFrame:
    df = df.copy()
    df['volume'] = vol_series.reindex(df.index)

    for p in [5,10,20,50,100,200]:
        df[f'ret_{p}'] = df['QQQ'].pct_change(p)
        df[f'vol_{p}'] = df['QQQ'].pct_change().rolling(p).std()
    # 1-day return used by the LSTM/feature set
    df['ret_1'] = df['QQQ'].pct_change(1)
    df['rsi'] = 100 - 100/(1 + (df['QQQ'].diff(1).clip(lower=0).rolling(14).mean() / 
                              abs(df['QQQ'].diff(1)).rolling(14).mean()))
    df['month'] = df.index.month
    df['dow'] = df.index.dayofweek
    df = df.dropna()
    return df


def prepare_lstm_sequence(df: pd.DataFrame, feature_cols: List[str], seq_len: int = 252) -> np.ndarray:
    if len(df) < seq_len:
        raise ValueError(f'Need at least {seq_len} rows for LSTM sequence, got {len(df)}')
    seq = df[feature_cols].tail(seq_len).values
    return seq

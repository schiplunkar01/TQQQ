TQQQ Signal Agent (safe, dry-run prototype)

Overview
A production-ready signal generator for TQQQ that:
- Loads LightGBM classifier, LSTM regime model and scaler
- Downloads historical QQQ and VIX data
- Computes technical features identical to training
- Produces three signals (SMA200, LightGBM, LSTM regime) and aggregates them
- Runs in dry-run mode by default and includes safety checks

Quickstart
1. Create a Python 3.11 virtualenv and install requirements:

   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt

2. Put model files in `models/` or set `MODEL_DIR` in `.env`.
3. Copy `.env.example` to `.env` and fill values. Set `DRY_RUN=false` only when ready.
4. Run:

   python -m tqqq_agent.main

Files
- `app/main.py` - entrypoint and orchestration
- `app/models.py` - model loading and inference helpers
- `app/utils.py` - data fetch and feature engineering utilities
- `.env.example` - environment variables
- `requirements.txt` - Python deps

Safety
- The script defaults to DRY_RUN=true and will never call Alpaca when dry-run is enabled.
- It validates model files, data length, and feature alignment before inference.

YFinance cache troubleshooting
- If you see errors like "Failed to create TzCache" from yfinance, set a writable cache. The app already sets a temporary cache location, but you can also set it manually in your environment or code:

```py
import tempfile, os
import yfinance as yf
yf.set_tz_cache_location(os.path.join(tempfile.gettempdir(), 'py-yfinance-cache'))
```

Or fix the local cache path permissions:

```bash
mv ~/Library/Caches/py-yfinance ~/Library/Caches/py-yfinance.bak
mkdir -p ~/Library/Caches/py-yfinance
chmod 700 ~/Library/Caches/py-yfinance
```

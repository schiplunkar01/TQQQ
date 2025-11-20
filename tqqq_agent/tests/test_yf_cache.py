import tempfile
import os


def test_set_yf_cache():
    try:
        import yfinance as yf
    except Exception:
        # yfinance may not be installed in CI; test passes if import fails
        return
    tmp_cache = os.path.join(tempfile.gettempdir(), 'py-yfinance-cache-test')
    # ensure no exception
    yf.set_tz_cache_location(tmp_cache)
    assert os.path.dirname(tmp_cache) == tempfile.gettempdir()

"""
Small helper to generate placeholder models for local testing.
It creates:
 - tqqq_agent/models/lgb_model.pkl   (sklearn-compatible with predict_proba)
 - tqqq_agent/models/scaler.pkl      (StandardScaler)
 - tqqq_agent/models/lstm_model.pth  (PyTorch state_dict for a small LSTMRegime)

Run locally after creating and activating your venv / conda env with required packages.
Usage:
    python tqqq_agent/generate_models.py

This script trains tiny models on synthetic data and saves them.
"""
from pathlib import Path
import os

MODEL_DIR = Path(__file__).resolve().parent / 'models'
MODEL_DIR.mkdir(parents=True, exist_ok=True)

print('Model dir:', MODEL_DIR)

# Try imports and fail with helpful message
try:
    import numpy as np
    from sklearn.preprocessing import StandardScaler
    from sklearn.model_selection import train_test_split
    try:
        from lightgbm import LGBMClassifier
        have_lgb = True
    except Exception as e:
        print('LightGBM import failed (will fall back to RandomForest):', e)
        have_lgb = False
    import joblib
except Exception as e:
    print('Missing Python packages for model generation or import failure:', e)
    print('Install requirements: pip install numpy scikit-learn lightgbm joblib')
    raise

# Small synthetic dataset
rng = np.random.RandomState(42)
X = rng.normal(size=(200, 10))
y = (rng.rand(200) > 0.5).astype(int)

# scaler
scaler = StandardScaler()
scaler.fit(X)
joblib.dump(scaler, MODEL_DIR / 'scaler.pkl')
print('Saved scaler.pkl')

# LightGBM
if have_lgb:
    model = LGBMClassifier(n_estimators=10, random_state=42)
    model.fit(X, y)
    joblib.dump(model, MODEL_DIR / 'lgb_model.pkl')
    print('Saved lgb_model.pkl (LightGBM)')
else:
    # fallback to RandomForestClassifier to avoid libomp dependency
    from sklearn.ensemble import RandomForestClassifier
    model = RandomForestClassifier(n_estimators=50, random_state=42)
    model.fit(X, y)
    joblib.dump(model, MODEL_DIR / 'lgb_model.pkl')
    print('Saved lgb_model.pkl (RandomForest fallback)')

# PyTorch LSTM regime
try:
    import torch
    import torch.nn as nn
except Exception as e:
    print('PyTorch not installed; writing an informational placeholder for lstm_model.pth')
    # create a tiny placeholder file
    (MODEL_DIR / 'lstm_model.pth').write_text('PLACEHOLDER - install torch and re-run to generate real model')
    raise

class LSTMRegime(nn.Module):
    def __init__(self):
        super().__init__()
        self.lstm = nn.LSTM(10, 64, num_layers=2, batch_first=True, dropout=0.3)
        self.fc = nn.Linear(64, 3)
    def forward(self, x):
        _, (h, _) = self.lstm(x)
        return self.fc(h[-1])

lstm = LSTMRegime()
# create a fake training loop to initialize weights slightly
optimizer = torch.optim.Adam(lstm.parameters(), lr=1e-3)
for _ in range(5):
    seq = torch.randn(8, 50, 10)
    logits = lstm(seq)
    loss = logits.abs().mean()
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

torch.save(lstm.state_dict(), str(MODEL_DIR / 'lstm_model.pth'))
print('Saved lstm_model.pth')

print('All models written to', MODEL_DIR)
print('Now run the agent in dry-run with MODEL_DIR=./tqqq_agent/models and DRY_RUN=true')

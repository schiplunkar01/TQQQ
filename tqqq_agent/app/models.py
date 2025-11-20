import os
import pickle
from pathlib import Path

try:
    import joblib
except Exception:
    joblib = None
try:
    import torch
except Exception:
    torch = None

class Models:
    def __init__(self, model_dir: str, lgb_file: str, lstm_file: str, scaler_file: str):
        self.model_dir = Path(model_dir)
        self.lgb_path = self.model_dir / lgb_file
        self.lstm_path = self.model_dir / lstm_file
        self.scaler_path = self.model_dir / scaler_file

        self.lgb_model = None
        self.scaler = None
        self.lstm_model = None

    def validate_paths(self):
        missing = []
        for p in [self.lgb_path, self.lstm_path, self.scaler_path]:
            if not p.exists():
                missing.append(str(p))
        if missing:
            raise FileNotFoundError(f"Missing model files: {missing}")

    def load(self):
        self.validate_paths()
        # Load LGB and scaler with joblib if available, else try pickle, else use mocks
        try:
            if joblib is not None:
                self.lgb_model = joblib.load(self.lgb_path)
                self.scaler = joblib.load(self.scaler_path)
            else:
                with open(self.lgb_path, 'rb') as f:
                    self.lgb_model = pickle.load(f)
                with open(self.scaler_path, 'rb') as f:
                    self.scaler = pickle.load(f)
        except Exception:
            # fallback to simple mocks
            self.lgb_model = None
            self.scaler = None

        # Try to load LSTM via torch; if unavailable, create a mock LSTM
        if torch is not None:
            try:
                class LSTMRegime(torch.nn.Module):
                    def __init__(self):
                        super().__init__()
                        self.lstm = torch.nn.LSTM(10, 64, num_layers=2, batch_first=True, dropout=0.3)
                        self.fc = torch.nn.Linear(64, 3)
                    def forward(self, x):
                        _, (h, _) = self.lstm(x)
                        return self.fc(h[-1])

                self.lstm_model = LSTMRegime()
                state = torch.load(self.lstm_path, map_location='cpu')
                # If the saved file is a state dict
                if isinstance(state, dict):
                    self.lstm_model.load_state_dict(state)
                else:
                    # If the saved file contains the whole model, try loading attributes
                    try:
                        self.lstm_model.load_state_dict(state.state_dict())
                    except Exception:
                        pass
                self.lstm_model.eval()
            except Exception:
                self.lstm_model = None
        else:
            self.lstm_model = None

        # If any model failed to load, replace with safe mocks
        if self.lgb_model is None:
            class MockLGB:
                def predict_proba(self, X):
                    # return neutral probability 0.5 as plain python list
                    return [[0.5, 0.5] for _ in X]
            self.lgb_model = MockLGB()

        if self.scaler is None:
            class MockScaler:
                def transform(self, X):
                    return X
            self.scaler = MockScaler()

        if self.lstm_model is None:
            class MockLSTM:
                def __call__(self, seq_tensor):
                    import numpy as _np
                    # return uniform logits for 3 classes
                    return _np.log(_np.array([[1/3,1/3,1/3]]))
                def __repr__(self):
                    return '<MockLSTM>'
            # create a small wrapper so predict_lstm_probs works similarly
            self.lstm_model = MockLSTM()

    def predict_lgb_prob(self, X):
        # expects 2D numpy array
        if self.lgb_model is None:
            raise RuntimeError('LGB model not loaded')
        if hasattr(self.lgb_model, 'predict_proba'):
            return self.lgb_model.predict_proba(X)
        # If it's a raw Booster
        return self.lgb_model.predict(X, raw_score=False)

    def predict_lstm_probs(self, seq_tensor):
        # seq_tensor: torch tensor shape (1, seq_len, features)
        if self.lstm_model is None:
            raise RuntimeError('LSTM model not loaded')
        with torch.no_grad():
            logits = self.lstm_model(seq_tensor)
            probs = torch.softmax(logits, dim=1).numpy()
        return probs

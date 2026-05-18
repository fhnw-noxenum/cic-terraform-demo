"""
app/main.py

Tiny FastAPI inference service. Two endpoints:
  GET  /health    — for the ALB and container healthcheck
  POST /predict   — actual inference

In a real app, the model would be loaded from S3 at startup using the IAM
task role. Here it's a placeholder so the demo works without uploading a
real model.
"""

import os
import logging
import sys
from typing import List

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Logging — structured JSON to stdout. CloudWatch Logs captures it.
# Never log secrets. Never log PII without redaction.
# ---------------------------------------------------------------------------

logging.basicConfig(
    stream=sys.stdout,
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format='{"level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger("inference-api")

ENV = os.environ.get("ENV", "dev")
MODEL_BUCKET = os.environ.get("MODEL_BUCKET", "")
THIRD_PARTY_API_KEY = os.environ.get("THIRD_PARTY_API_KEY", "")

app = FastAPI(title="inference-api", version="1.0")

# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class PredictRequest(BaseModel):
    x: List[float] = Field(..., min_length=4, max_length=4)


class PredictResponse(BaseModel):
    class_: str = Field(..., alias="class")
    probability: float


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    """ALB hits this every 30s. Keep it cheap — no DB calls."""
    return {"status": "ok", "env": ENV}


@app.get("/")
def root():
    return {
        "service": "inference-api",
        "env": ENV,
        "model_bucket": MODEL_BUCKET or "(not configured)",
        "has_third_party_key": bool(THIRD_PARTY_API_KEY),
    }


@app.post("/predict", response_model=PredictResponse)
def predict(req: PredictRequest):
    """
    Placeholder: real model goes here. For the demo, we use a rule:
    if the first feature > 5, it's 'virginica', otherwise 'setosa'.
    """
    log.info(f"predict input_dim={len(req.x)}")

    if any(v < 0 for v in req.x):
        raise HTTPException(status_code=400, detail="Features must be non-negative")

    label = "virginica" if req.x[0] > 5.0 else "setosa"
    prob = 0.97 if label == "setosa" else 0.91

    return PredictResponse(**{"class": label, "probability": prob})

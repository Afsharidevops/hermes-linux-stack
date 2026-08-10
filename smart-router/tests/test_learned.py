from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

import joblib
import numpy as np

from smart_router.features import FEATURE_NAMES, extract_safe_features
from smart_router.learned.model import LearnedPolicy, load_learned_policy
from smart_router.learned.train import train_model
from smart_router.routing import build_policy_runtime, decide


class FixedEstimator:
    classes_ = np.array(["fast", "standard", "strong"])
    def __init__(self, probabilities):
        self.probabilities = probabilities
    def predict_proba(self, matrix):
        return np.array([self.probabilities], dtype=float)


def _write_artifact(tmp_path: Path, probabilities=(0.2, 0.6, 0.2), schema=1):
    model = tmp_path / "model.joblib"
    meta = tmp_path / "model.json"
    joblib.dump(FixedEstimator(probabilities), model)
    meta.write_text(json.dumps({
        "feature_schema_version": schema,
        "feature_names": list(FEATURE_NAMES),
        "classes": ["fast", "standard", "strong"],
        "min_confidence": 0.7,
        "fallback_tier": "standard"
    }))
    return model, meta


def test_low_confidence_falls_back_to_standard(tmp_path):
    model, meta = _write_artifact(tmp_path, (0.40, 0.34, 0.26))
    policy = load_learned_policy(str(model), str(meta))
    pred = policy.predict(extract_safe_features({"messages": [{"role": "user", "content": "hello"}]}))
    assert pred.raw_tier == "fast"
    assert pred.tier == "standard"
    assert pred.low_confidence_fallback


def test_schema_mismatch_rejected(tmp_path):
    model, meta = _write_artifact(tmp_path, schema=999)
    try:
        load_learned_policy(str(model), str(meta))
    except ValueError as exc:
        assert "schema" in str(exc)
    else:
        raise AssertionError("schema mismatch must fail")


def test_missing_model_fail_opens_to_heuristic(learned_settings):
    runtime = build_policy_runtime(learned_settings)
    assert runtime.learned is None
    decision = decide({"model": "auto", "messages": [{"role": "user", "content": "translate hello"}]}, learned_settings, runtime=runtime)
    assert decision.policy_fallback == "heuristic"
    assert decision.proposed_tier == "fast"


def test_training_is_reproducible(tmp_path):
    sample = Path(__file__).parents[1] / "examples" / "learned-routing-sample.jsonl"
    a = tmp_path / "a.joblib"; am = tmp_path / "a.json"
    b = tmp_path / "b.joblib"; bm = tmp_path / "b.json"
    ma = train_model(str(sample), str(a), str(am), random_seed=7)
    mb = train_model(str(sample), str(b), str(bm), random_seed=7)
    assert ma["metrics"] == mb["metrics"]
    assert ma["feature_schema_version"] == 1
    assert ma["training_rows"] == 60

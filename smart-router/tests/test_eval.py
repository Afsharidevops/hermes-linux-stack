from smart_router.eval.calibrate import fit_thresholds
from smart_router.routing import DEFAULT_WEIGHTS


def test_threshold_fit_returns_ordered_thresholds():
    rows = [
        ({k: 0.0 for k in DEFAULT_WEIGHTS}, "fast"),
        ({**{k: 0.0 for k in DEFAULT_WEIGHTS}, "tools_present": 1.0}, "standard"),
        ({**{k: 0.0 for k in DEFAULT_WEIGHTS}, "context_gt_50k": 1.0, "complex_language": 1.0, "failure_language": 1.0}, "strong"),
    ]
    thresholds, _ = fit_thresholds(rows, DEFAULT_WEIGHTS, 3, 1)
    assert thresholds["fast_max"] < thresholds["standard_max"]

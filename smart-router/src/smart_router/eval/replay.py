from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from smart_router.config import Settings
from smart_router.routing import PolicyEngine, decide, feature_flags
from .common import iter_jsonl


def main() -> None:
    parser = argparse.ArgumentParser(description="Replay OpenAI-compatible request JSONL through Smart Router without making model calls.")
    parser.add_argument("input", type=Path, help="JSONL; each line is a request body or {'body': request}")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Privacy-safe decision JSONL")
    args = parser.parse_args()

    # Settings validates the same deployment configuration as production.
    settings = Settings.from_env()
    engine = PolicyEngine(settings)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with args.output.open("w", encoding="utf-8") as handle:
        for record in iter_jsonl(args.input):
            body = record.get("body", record)
            if not isinstance(body, dict):
                raise ValueError("body must be a JSON object")
            decision = decide(body, settings, engine)
            safe = decision.safe_dict()
            safe["features"] = feature_flags(decision.facts)
            # Deliberately omit body/prompt/tool arguments.
            handle.write(json.dumps(safe, sort_keys=True, separators=(",", ":")) + "\n")
            count += 1
    print(f"wrote {count} privacy-safe replay decisions to {args.output}")


if __name__ == "__main__":
    main()

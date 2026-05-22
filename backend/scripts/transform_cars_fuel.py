#!/usr/bin/env python3
"""cars.json: model anahtarlarından (YYYY) sonekini temizler; yakıtlı varyantlara fuel_capacity atar."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "data" / "cars.json"


def _base_model(model_key: str) -> str:
    return re.sub(r"\s*\(\d{4}\)\s*$", "", model_key).strip()


def fuel_capacity_liters(engine: str, model_key: str) -> float | None:
    if engine == "Elektrik":
        return None
    m = _base_model(model_key).lower()
    rules: list[tuple[tuple[str, ...], float]] = [
        (("rav4",), 55.0),
        (("superb", "passat", "508"), 66.0),
        (("5 serisi", "e serisi"), 68.0),
        (("c serisi",), 66.0),
        (("chr",), 50.0),
        (("a4", "3 serisi"), 59.0),
        (("golf", "308", "focus"), 54.0),
        (("408",), 52.0),
        (("c4 x",), 48.0),
        (("c4",), 45.0),
        (("i20", "fiesta", "polo", "fabia", "corsa", "208", "city", "yaris", "ibiza"), 42.0),
        (("c3",), 40.0),
        (("a serisi",), 43.0),
        (("cla serisi",), 44.0),
        (("civic",), 47.0),
        (("egea",), 50.0),
        (("a3", "corolla", "elantra", "megane", "astra", "scala", "leon"), 50.0),
    ]
    for subs, cap in rules:
        if any(s in m for s in subs):
            return cap
    return 50.0


def main() -> None:
    data = json.loads(ROOT.read_text(encoding="utf-8"))
    out: dict = {}
    for brand, models in data.items():
        new_models: dict = {}
        for model_key, variants in models.items():
            display_key = _base_model(model_key)
            new_list = []
            for v in variants:
                nv = dict(v)
                et = nv["engine_type"]
                cap = fuel_capacity_liters(et, display_key)
                if cap is not None:
                    nv["fuel_capacity"] = cap
                else:
                    nv.pop("fuel_capacity", None)
                new_list.append(nv)
            new_models[display_key] = new_list
        out[brand] = new_models
    ROOT.write_text(json.dumps(out, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    print("OK:", ROOT)


if __name__ == "__main__":
    main()

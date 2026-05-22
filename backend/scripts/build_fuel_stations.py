#!/usr/bin/env python3
"""
İzmir bölgesindeki benzinlikleri OpenStreetMap Overpass API ile çeker,
yol grafiğine (izmir_graph.pkl) göre nearest_osm_node_id üretir ve
data/fuel_stations.json yazar.

Veri kaynağı: OSM etiketi amenity=fuel (Google Maps / Places API kullanılmaz).
https://wiki.openstreetmap.org/wiki/Tag:amenity=fuel

Önkoşul: backend/data/izmir_graph.pkl mevcut olmalı (sunucu bir kez çalıştırılmış).

Kullanım (backend klasöründen):
  .venv/bin/python scripts/build_fuel_stations.py
"""

from __future__ import annotations

import json
import pickle
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

import osmnx as ox

BACKEND = Path(__file__).resolve().parent.parent
DATA = BACKEND / "data"
GRAPH_PKL = DATA / "izmir_graph.pkl"
OUT_JSON = DATA / "fuel_stations.json"

# İl geneli bbox (yaklaşık İzmir ili)
OVERPASS_QUERY = """
[out:json][timeout:240];
(
  node["amenity"="fuel"](38.15,26.20,39.65,28.65);
  way["amenity"="fuel"](38.15,26.20,39.65,28.65);
);
out center;
"""


def _coords_from_el(el: dict) -> tuple[float, float] | None:
    if el["type"] == "node":
        lat, lon = el.get("lat"), el.get("lon")
    else:
        c = el.get("center") or {}
        lat, lon = c.get("lat"), c.get("lon")
    if lat is None or lon is None:
        return None
    return float(lat), float(lon)


def main() -> int:
    if not GRAPH_PKL.exists():
        print("Önce izmir_graph.pkl oluşturun (uvicorn ile backend başlatın).", file=sys.stderr)
        return 1

    print("Graf yükleniyor...")
    with open(GRAPH_PKL, "rb") as f:
        G = pickle.load(f)

    print("Overpass sorgusu gönderiliyor...")
    req = urllib.request.Request(
        "https://overpass-api.de/api/interpreter",
        data=OVERPASS_QUERY.encode("utf-8"),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "*/*",
            "User-Agent": "NaviFuelBuilder/1.0 (local dev)",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        err = str(e)
        if "CERT" in err or "SSL" in err:
            print("SSL doğrulama başarısız; OSM_TLS_INSECURE=1 ile yeniden deneniyor...", file=sys.stderr)
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            try:
                with urllib.request.urlopen(req, timeout=300, context=ctx) as resp:
                    raw = json.loads(resp.read().decode("utf-8"))
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e2:
                print(f"Overpass hatası: {e2}", file=sys.stderr)
                return 1
        else:
            print(f"Overpass hatası: {e}", file=sys.stderr)
            return 1
    except (TimeoutError, json.JSONDecodeError) as e:
        print(f"Overpass hatası: {e}", file=sys.stderr)
        return 1

    elements = raw.get("elements") or []
    print(f"{len(elements)} OSM öğesi alındı, düğümlere bağlanıyor...")

    out: list[dict] = []
    seen: set[tuple[int, int]] = set()
    max_rows = 600

    for el in elements:
        if len(out) >= max_rows:
            break
        coords = _coords_from_el(el)
        if coords is None:
            continue
        lat, lon = coords
        key = (round(lat, 5), round(lon, 5))
        if key in seen:
            continue
        seen.add(key)

        tags = el.get("tags") or {}
        name = tags.get("name") or tags.get("brand") or tags.get("operator") or "Benzinlik"
        oid = el.get("id")
        typ = el["type"]
        station_id = f"osm-fuel-{typ}-{oid}"

        try:
            nid = ox.distance.nearest_nodes(G, X=lon, Y=lat)
        except Exception:
            continue

        out.append(
            {
                "station_id": station_id,
                "name": str(name)[:200],
                "latitude": lat,
                "longitude": lon,
                "nearest_osm_node_id": int(nid),
            }
        )

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    print(f"Yazıldı: {OUT_JSON} ({len(out)} istasyon)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

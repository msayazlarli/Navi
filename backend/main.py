from __future__ import annotations

import asyncio
import contextlib
import json
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from graph_cache import load_graph
from models import CarVariant, RouteRequest, RouteResponse
from routing import compute_route

DATA_DIR = Path(__file__).parent / "data"
STATIC_DIR = Path(__file__).parent / "static"

# Shared application state populated at startup
_state: dict = {}


def _flatten_cars(raw: dict) -> dict[str, dict]:
    """Build a flat id→variant dict from the nested brand→model→[variants] structure."""
    flat: dict[str, dict] = {}
    for brand, models in raw.items():
        logo_url = f"/static/logos/{brand.lower()}.png"
        for model_name, variants in models.items():
            for v in variants:
                flat[v["id"]] = {**v, "brand": brand, "model": model_name, "logo_url": logo_url}
    return flat


def _build_brand_logos(brands: list[str]) -> dict[str, str]:
    return {brand: f"/static/logos/{brand.lower()}.png" for brand in brands}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Uvicorn opens the listen port only after this lifespan block yields.
    # load_graph() can take many minutes on first run; do it in the background
    # so /cars and /static respond immediately while the graph loads.
    _state["graph"] = None
    _state["graph_load_error"] = None

    with open(DATA_DIR / "cars.json", encoding="utf-8") as f:
        raw_cars = json.load(f)
    _state["cars_nested"] = raw_cars
    _state["cars_flat"] = _flatten_cars(raw_cars)
    _state["brand_logos"] = _build_brand_logos(list(raw_cars.keys()))

    with open(DATA_DIR / "charging_stations.json", encoding="utf-8") as f:
        _state["stations"] = json.load(f)

    fuel_path = DATA_DIR / "fuel_stations.json"
    if fuel_path.exists():
        with open(fuel_path, encoding="utf-8") as f:
            _state["fuel_stations"] = json.load(f)
    else:
        _state["fuel_stations"] = []

    async def _load_graph_task() -> None:
        try:
            _state["graph"] = await asyncio.to_thread(load_graph)
        except Exception as exc:  # noqa: BLE001 — log any OSM/pickle failure
            _state["graph_load_error"] = repr(exc)

    _state["graph_task"] = asyncio.create_task(_load_graph_task())

    yield

    task = _state.pop("graph_task", None)
    if isinstance(task, asyncio.Task):
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
    _state.clear()


app = FastAPI(title="Navi API", version="1.0.0", lifespan=lifespan)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    g = _state.get("graph")
    return {
        "status": "ok",
        "graph_loaded": g is not None,
        "graph_load_error": _state.get("graph_load_error"),
        "car_count": len(_state.get("cars_flat", {})),
        "station_count": len(_state.get("stations", [])),
        "fuel_station_count": len(_state.get("fuel_stations", [])),
    }


# ── Cars ──────────────────────────────────────────────────────────────────────

@app.get("/cars")
def get_cars():
    """Return brands structure plus brand logo URLs."""
    return {"brands": _state["cars_nested"], "brand_logos": _state["brand_logos"]}


@app.get("/cars/{car_id}", response_model=CarVariant)
def get_car(car_id: str):
    car = _state["cars_flat"].get(car_id)
    if not car:
        raise HTTPException(status_code=404, detail="Araç bulunamadı")
    return car


# ── Charging Stations ─────────────────────────────────────────────────────────

@app.get("/charging-stations")
def get_charging_stations():
    return _state["stations"]


@app.get("/fuel-stations")
def get_fuel_stations():
    """OpenStreetMap amenity=fuel —tanımlı JSON (Google Maps API kullanılmaz)."""
    return _state.get("fuel_stations", [])


# ── Route ─────────────────────────────────────────────────────────────────────

@app.post("/route", response_model=RouteResponse)
def route(req: RouteRequest):
    car = _state["cars_flat"].get(req.car_id)
    if not car:
        raise HTTPException(status_code=404, detail="Araç bulunamadı")

    if car["engine_type"] == "Elektrik":
        if req.charge_level_pct is None:
            raise HTTPException(
                status_code=422,
                detail="Elektrikli araçlar için şarj seviyesi (charge_level_pct) gereklidir",
            )
    else:
        if req.fuel_level_pct is None:
            raise HTTPException(
                status_code=422,
                detail="Benzin/dizel/hibrit için depo doluluk yüzdesi (fuel_level_pct, 0–100) gerekir",
            )
        if car.get("fuel_capacity") in (None, 0):
            raise HTTPException(
                status_code=422,
                detail="Seçilen araçta depo hacmi (fuel_capacity) tanımlı değil; cars.json güncelleyin",
            )
        if car.get("average_consumption_l_per_100km") in (None, 0):
            raise HTTPException(
                status_code=422,
                detail="Bu araç için L/100 km tüketim verisi yok; rota hesaplanamaz",
            )

    g = _state.get("graph")
    if g is None:
        err = _state.get("graph_load_error")
        if err:
            raise HTTPException(
                status_code=503,
                detail=f"Yol grafiği yüklenemedi: {err}",
            )
        raise HTTPException(
            status_code=503,
            detail=(
                "İzmir yol grafiği hâlâ yükleniyor veya indiriliyor; "
                "sunucu terminalindeki logu kontrol edip kısa süre sonra tekrar deneyin."
            ),
        )

    return compute_route(
        G=g,
        charging_stations=_state["stations"],
        fuel_stations=_state.get("fuel_stations", []),
        car=car,
        req=req,
    )

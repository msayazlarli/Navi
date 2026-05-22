from __future__ import annotations

from typing import Literal, Optional
from pydantic import BaseModel, Field


class CarVariant(BaseModel):
    id: str
    brand: str
    model: str
    variant: str
    engine_type: Literal["Benzin", "Dizel", "Hibrit", "Elektrik"]
    average_consumption_l_per_100km: Optional[float] = None
    battery_capacity_kwh: Optional[float] = None
    average_consumption_kwh_per_100km: Optional[float] = None
    fuel_capacity: Optional[float] = None  # litre; Benzin/Dizel/Hibrit
    logo_url: Optional[str] = None


class Socket(BaseModel):
    socket_no: str
    type: str
    connector: str
    power_kw: float


class ChargingStation(BaseModel):
    station_id: str
    name: str
    brand: str
    operator: str
    address: str
    latitude: float
    longitude: float
    nearest_osm_node_id: int
    sockets: list[Socket]


class RouteRequest(BaseModel):
    start_lat: float
    start_lon: float
    dest_lat: float
    dest_lon: float
    car_id: str
    charge_level_pct: Optional[float] = None  # 0–100, only for Elektrik
    # Benzin / Dizel / Hibrit — depo cars.json fuel_capacity; istemci sadece yüzde gönderir
    fuel_level_pct: Optional[float] = None  # 0–100


class Waypoint(BaseModel):
    lat: float
    lon: float
    type: Literal["charging_station", "gas_station", "start", "destination"]
    name: Optional[str] = None
    station_id: Optional[str] = None


class NavigationStep(BaseModel):
    instruction: str
    distance_meters: float
    type: Literal["straight", "turn_right", "turn_left"]


class RouteResponse(BaseModel):
    polyline: list[list[float]]  # [[lat, lon], ...]
    waypoints: list[Waypoint]
    distance_km: float
    estimated_fuel_l: Optional[float] = None
    estimated_charge_used_pct: Optional[float] = None
    needs_charge_stop: bool
    needs_fuel_stop: bool = False
    fuel_warning: Optional[str] = None
    steps: list[NavigationStep] = Field(default_factory=list)

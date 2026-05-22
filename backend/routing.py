from __future__ import annotations

import math
from typing import Optional

import networkx as nx
import osmnx as ox

from models import NavigationStep, RouteRequest, RouteResponse, Waypoint


# ── Geometry helpers ──────────────────────────────────────────────────────────

def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lon2 - lon1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _route_to_polyline(G, route_nodes: list[int]) -> list[list[float]]:
    pts: list[list[float]] = []
    for u, v in zip(route_nodes[:-1], route_nodes[1:]):
        edge_data = G.get_edge_data(u, v)          # {key: attrs} for MultiDiGraph
        best = min(edge_data.values(), key=lambda d: d.get("length", 0))
        if "geometry" in best:
            # Shapely coords are (x, y) = (lon, lat); exclude last point to avoid
            # duplicating the junction node that begins the next edge.
            for lon, lat in list(best["geometry"].coords)[:-1]:
                pts.append([lat, lon])
        else:
            pts.append([G.nodes[u]["y"], G.nodes[u]["x"]])
    if route_nodes:
        pts.append([G.nodes[route_nodes[-1]]["y"], G.nodes[route_nodes[-1]]["x"]])
    return pts


def _route_distance_m(G, route_nodes: list[int]) -> float:
    total = 0.0
    for u, v in zip(route_nodes[:-1], route_nodes[1:]):
        edge_data = G.get_edge_data(u, v)  # MultiDiGraph → {key: attrs}
        total += min(d.get("length", 0) for d in edge_data.values())
    return total


def _edge_length_m(G, u: int, v: int) -> float:
    edge_data = G.get_edge_data(u, v)
    return float(min(d.get("length", 0) for d in edge_data.values()))


def _bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """İki nokta arası ileri azimut (0–360°)."""
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dλ = math.radians(lon2 - lon1)
    y = math.sin(dλ) * math.cos(φ2)
    x = math.cos(φ1) * math.sin(φ2) - math.sin(φ1) * math.cos(φ2) * math.cos(dλ)
    θ = math.atan2(y, x)
    return (math.degrees(θ) + 360.0) % 360.0


def _bearing_delta_deg(b_prev: float, b_next: float) -> float:
    """İki yön arası fark (−180, 180]."""
    return (b_next - b_prev + 180.0) % 360.0 - 180.0


def _classify_turn(delta: float) -> str | None:
    """None = düz devam; aksi tur tipi string (NavigationStep.type ile uyumlu)."""
    if abs(delta) < 20.0:
        return None
    if 20.0 <= delta <= 160.0:
        return "turn_right"
    if -160.0 <= delta <= -20.0:
        return "turn_left"
    if delta > 0:
        return "turn_right"
    return "turn_left"


_MIN_STEP_STRAIGHT_M = 5.0


def _turkish_straight_instruction(meters: float) -> str:
    if meters >= 1000.0:
        t = f"{meters / 1000.0:.1f}".replace(".", ",")
        return f"{t} kilometre ilerleyin"
    m = max(1, int(round(meters)))
    return f"{m} metre ilerleyin"


def build_navigation_steps(G, path_nodes: list[int]) -> list[NavigationStep]:
    """Düğüm listesinden adım adım Türkçe yönergeler (düz birikim + dönüşler)."""
    if len(path_nodes) < 2:
        return []
    steps_out: list[NavigationStep] = []
    straight_m = 0.0

    for i in range(len(path_nodes) - 1):
        u, v = path_nodes[i], path_nodes[i + 1]
        L = _edge_length_m(G, u, v)
        straight_m += L
        if i >= len(path_nodes) - 2:
            break
        w = path_nodes[i + 2]
        lat_u, lon_u = G.nodes[u]["y"], G.nodes[u]["x"]
        lat_v, lon_v = G.nodes[v]["y"], G.nodes[v]["x"]
        lat_w, lon_w = G.nodes[w]["y"], G.nodes[w]["x"]
        b_in = _bearing_deg(lat_u, lon_u, lat_v, lon_v)
        b_out = _bearing_deg(lat_v, lon_v, lat_w, lon_w)
        delta = _bearing_delta_deg(b_in, b_out)
        kind = _classify_turn(delta)
        if kind is None:
            continue
        if straight_m >= _MIN_STEP_STRAIGHT_M:
            steps_out.append(
                NavigationStep(
                    instruction=_turkish_straight_instruction(straight_m),
                    distance_meters=round(straight_m, 1),
                    type="straight",
                )
            )
        steps_out.append(
            NavigationStep(
                instruction="Sağa dönün" if kind == "turn_right" else "Sola dönün",
                distance_meters=0.0,
                type="turn_right" if kind == "turn_right" else "turn_left",
            )
        )
        straight_m = 0.0

    if straight_m >= _MIN_STEP_STRAIGHT_M:
        steps_out.append(
            NavigationStep(
                instruction=_turkish_straight_instruction(straight_m),
                distance_meters=round(straight_m, 1),
                type="straight",
            )
        )
    return steps_out


# ── Station search helpers ────────────────────────────────────────────────────

def _stations_near_route(
    G,
    route_nodes: list[int],
    stations: list[dict],
    radius_m: float = 500,
) -> list[dict]:
    """Charging stations within radius_m of any node on the route."""
    route_coords = [(G.nodes[n]["y"], G.nodes[n]["x"]) for n in route_nodes]

    lats = [c[0] for c in route_coords]
    lons = [c[1] for c in route_coords]
    # Bounding box with a degree margin for fast exclusion
    margin = radius_m / 111_000  # ~1° ≈ 111 km
    bbox = (min(lats) - margin, max(lats) + margin, min(lons) - margin, max(lons) + margin)

    nearby: list[dict] = []
    for station in stations:
        slat, slon = station["latitude"], station["longitude"]
        if not (bbox[0] <= slat <= bbox[1] and bbox[2] <= slon <= bbox[3]):
            continue
        for rlat, rlon in route_coords:
            if _haversine_m(slat, slon, rlat, rlon) <= radius_m:
                nearby.append(station)
                break
    return nearby


# Kritik yakıt: en az 5 L veya depo hacminin %10'u (hangisi büyükse)
_FUEL_CRITICAL_MIN_L = 5.0
_FUEL_CRITICAL_TANK_FRAC = 0.10


def _fuel_critical_threshold_l(tank_l: float) -> float:
    return max(_FUEL_CRITICAL_MIN_L, _FUEL_CRITICAL_TANK_FRAC * tank_l)


def _find_best_intermediate_station(
    G,
    start_node: int,
    dest_node: int,
    stations: list[dict],
    range_m: float,
    *,
    prefer_closest_to_start: bool = False,
) -> Optional[dict]:
    """
    Among POIs reachable from start within range_m (road metres) with a path
    to dest, pick one station:

    - prefer_closest_to_start=False (EV şarj): toplam yol start→POI→dest en kısa.
    - prefer_closest_to_start=True (kritik yakıt): önce start'a ağ üzerinden en
      yakın (d1 en küçük); eşitlikte toplam yol kısa olanda kal — kullanıcı
      menzil dışına iten uzak istasyona yönlendirilmesin.

    Uses two single-source Dijkstra runs (start with cutoff, then from dest on
    the reversed graph) instead of per-station shortest_path_length, which was
    O(#stations × graph) and timed out on large city graphs.
    """
    dist_from_start: dict[int, float] = dict(
        nx.single_source_dijkstra_path_length(
            G, start_node, cutoff=range_m, weight="length"
        )
    )
    if not dist_from_start:
        return None

    # In G_rev, shortest path dest → n equals shortest path n → dest in G.
    # copy=False avoids duplicating the whole city graph in memory.
    gr = G.reverse(copy=False)
    dist_to_dest: dict[int, float] = dict(
        nx.single_source_dijkstra_path_length(gr, dest_node, weight="length")
    )

    best: Optional[dict] = None
    best_total = math.inf

    for station in stations:
        snode = station["nearest_osm_node_id"]
        d1 = dist_from_start.get(snode)
        if d1 is None:
            continue
        d2 = dist_to_dest.get(snode)
        if d2 is None:
            continue
        total = d1 + d2
        if best is None:
            best_total = total
            best = {**station, "_d1_m": d1, "_d2_m": d2}
            continue
        bd1 = best["_d1_m"]
        btot = best_total
        if prefer_closest_to_start:
            pick = d1 < bd1 - 1e-6 or (abs(d1 - bd1) < 1e-6 and total < btot - 1e-6)
        else:
            pick = total < btot - 1e-6 or (abs(total - btot) < 1e-6 and d1 < bd1 - 1e-6)
        if pick:
            best_total = total
            best = {**station, "_d1_m": d1, "_d2_m": d2}

    return best


def _ice_current_fuel_liters(tank_l: float, fuel_level_pct: float) -> float:
    """Depo litresi × doluluk yüzdesi."""
    pct = min(100.0, max(0.0, fuel_level_pct))
    return tank_l * (pct / 100.0)


# ── Main entry point ──────────────────────────────────────────────────────────

def compute_route(
    G,
    charging_stations: list[dict],
    fuel_stations: list[dict],
    car: dict,
    req: RouteRequest,
) -> RouteResponse:
    is_ev = car["engine_type"] == "Elektrik"

    start_node = ox.distance.nearest_nodes(G, X=req.start_lon, Y=req.start_lat)
    dest_node = ox.distance.nearest_nodes(G, X=req.dest_lon, Y=req.dest_lat)

    try:
        direct_route = nx.shortest_path(G, start_node, dest_node, weight="length")
    except (nx.NetworkXNoPath, nx.NodeNotFound):
        raise ValueError("Başlangıç ile hedef arasında rota bulunamadı")

    direct_dist_m = _route_distance_m(G, direct_route)
    direct_dist_km = direct_dist_m / 1000.0

    # ── EV ────────────────────────────────────────────────────────────────────
    if is_ev:
        battery_kwh: float = car["battery_capacity_kwh"]
        kwh_per_km: float = car["average_consumption_kwh_per_100km"] / 100.0
        range_km = (req.charge_level_pct / 100.0) * battery_kwh / kwh_per_km
        range_m = range_km * 1000.0

        if direct_dist_m > range_m:
            # Şarj %10 altındaysa önce başlangıca en yakın (ağ mesafesi) istasyon; aksi halde
            # toplam start→istasyon→hedef yolu en kısa olan.
            prefer_nearest = (
                req.charge_level_pct is not None and req.charge_level_pct < 10.0
            )
            best = _find_best_intermediate_station(
                G,
                start_node,
                dest_node,
                charging_stations,
                range_m,
                prefer_closest_to_start=prefer_nearest,
            )
            if best is None:
                raise ValueError("Menzil dahilinde erişilebilir şarj istasyonu bulunamadı")

            snode = best["nearest_osm_node_id"]
            seg1 = nx.shortest_path(G, start_node, snode, weight="length")
            seg2 = nx.shortest_path(G, snode, dest_node, weight="length")
            full_route = seg1 + seg2[1:]  # skip duplicate junction node
            total_dist_km = (best["_d1_m"] + best["_d2_m"]) / 1000.0

            return RouteResponse(
                polyline=_route_to_polyline(G, full_route),
                waypoints=[
                    Waypoint(
                        lat=best["latitude"],
                        lon=best["longitude"],
                        type="charging_station",
                        name=best["name"],
                        station_id=best["station_id"],
                    )
                ],
                distance_km=round(total_dist_km, 2),
                estimated_charge_used_pct=100.0,
                needs_charge_stop=True,
                needs_fuel_stop=False,
                steps=build_navigation_steps(G, full_route),
            )

        # Enough charge — surface nearby stations along the route as optional stops
        charge_used_pct = min(100.0, (direct_dist_km * kwh_per_km / battery_kwh) * 100.0)
        nearby = _stations_near_route(G, direct_route, charging_stations, radius_m=500)

        return RouteResponse(
            polyline=_route_to_polyline(G, direct_route),
            waypoints=[
                Waypoint(
                    lat=s["latitude"],
                    lon=s["longitude"],
                    type="charging_station",
                    name=s["name"],
                    station_id=s["station_id"],
                )
                for s in nearby
            ],
            distance_km=round(direct_dist_km, 2),
            estimated_charge_used_pct=round(charge_used_pct, 1),
            needs_charge_stop=False,
            needs_fuel_stop=False,
            steps=build_navigation_steps(G, direct_route),
        )

    # ── ICE / Hybrid ──────────────────────────────────────────────────────────
    l_per_km: float = car["average_consumption_l_per_100km"] / 100.0
    if l_per_km <= 0:
        raise ValueError("Araç için geçerli L/100 km tüketimi yok")

    tank_l = car.get("fuel_capacity")
    if tank_l is None or float(tank_l) <= 0:
        raise ValueError(
            "Bu araç için cars.json içinde fuel_capacity (litre) tanımlı değil veya geçersiz"
        )
    tank_l = float(tank_l)
    if req.fuel_level_pct is None:
        raise ValueError("fuel_level_pct (0–100) gerekli")
    current_l = _ice_current_fuel_liters(tank_l, req.fuel_level_pct)

    range_km = current_l / l_per_km
    range_m = range_km * 1000.0
    crit = _fuel_critical_threshold_l(tank_l)

    fuel_used_direct = direct_dist_km * l_per_km
    remaining_at_dest_direct = current_l - fuel_used_direct

    if direct_dist_m > range_m:
        # Menzil yetmiyor — OSM amenity=fuel istasyonlarından en uygun ara durak
        if not fuel_stations:
            raise ValueError(
                "Yakıt istasyonu verisi yok veya boş; sunucuda fuel_stations.json gerekir "
                "(OpenStreetMap amenity=fuel, Google Maps kullanılmaz)."
            )
        best = _find_best_intermediate_station(
            G,
            start_node,
            dest_node,
            fuel_stations,
            range_m,
            prefer_closest_to_start=True,
        )
        if best is None:
            raise ValueError("Menzil dahilinde erişilebilir yakıt istasyonu bulunamadı")

        fuel_to_station_l = (best["_d1_m"] / 1000.0) * l_per_km
        warn_parts: list[str] = []
        # İstasyona varınca depoda kalacak tahmini litre
        remaining_at_station_l = current_l - fuel_to_station_l
        # Kritik eşik (örn. 5 L), başlangıçtaki toplam yakıttan büyük olabilir; o zaman
        # "kritik altı" karşılaştırması anlamsız uyarı üretirdi (örn. depo %5 iken).
        tight_reserve_l = min(crit, max(0.3, current_l * 0.15))
        if remaining_at_station_l < -0.05:
            warn_parts.append(
                "Hesap, mevcut yakıtla önerilen istasyona güvenli biçimde yetişmeyebilir; "
                "daha yakın bir benzinlik seçin veya yakıt ekleyin."
            )
        elif remaining_at_station_l < tight_reserve_l:
            warn_parts.append(
                f"İstasyona vardığınızda depoda yaklaşık {max(0.0, remaining_at_station_l):.1f} L kalacak "
                f"(çok düşük rezerva). Mümkünse daha erken durun."
            )

        snode = best["nearest_osm_node_id"]
        seg1 = nx.shortest_path(G, start_node, snode, weight="length")
        seg2 = nx.shortest_path(G, snode, dest_node, weight="length")
        full_route = seg1 + seg2[1:]
        total_dist_km = (best["_d1_m"] + best["_d2_m"]) / 1000.0
        fuel_second_leg_l = (best["_d2_m"] / 1000.0) * l_per_km
        # İstasyonda doldurulduğu varsayılan: ikinci bacak için tam depo
        remaining_at_dest = tank_l - fuel_second_leg_l
        if remaining_at_dest < crit:
            warn_parts.append(
                f"Hedefe vardığınızda tahmini yakıt yaklaşık {remaining_at_dest:.1f} L "
                f"(kritik eşik ≈ {crit:.0f} L)."
            )
        fuel_warning = "\n".join(warn_parts) if warn_parts else None

        return RouteResponse(
            polyline=_route_to_polyline(G, full_route),
            waypoints=[
                Waypoint(
                    lat=best["latitude"],
                    lon=best["longitude"],
                    type="gas_station",
                    name=best.get("name"),
                    station_id=best.get("station_id"),
                )
            ],
            distance_km=round(total_dist_km, 2),
            estimated_fuel_l=round(fuel_to_station_l + fuel_second_leg_l, 2),
            needs_charge_stop=False,
            needs_fuel_stop=True,
            fuel_warning=fuel_warning,
            steps=build_navigation_steps(G, full_route),
        )

    # Tek parça rota — menzil yeterli; yakıt istasyonlarını bilgi amaçlı göster
    nearby_fuel = _stations_near_route(G, direct_route, fuel_stations, radius_m=500)
    fuel_warning: Optional[str] = None
    if remaining_at_dest_direct < crit:
        fuel_warning = (
            f"Hedefe vardığınızda tahmini yakıt yaklaşık {remaining_at_dest_direct:.1f} L "
            f"(kritik eşik ≈ {crit:.0f} L). Yakında benzinlik aramanız önerilir."
        )

    return RouteResponse(
        polyline=_route_to_polyline(G, direct_route),
        waypoints=[
            Waypoint(
                lat=s["latitude"],
                lon=s["longitude"],
                type="gas_station",
                name=s.get("name"),
                station_id=s.get("station_id"),
            )
            for s in nearby_fuel
        ],
        distance_km=round(direct_dist_km, 2),
        estimated_fuel_l=round(fuel_used_direct, 2),
        needs_charge_stop=False,
        needs_fuel_stop=False,
        fuel_warning=fuel_warning,
        steps=build_navigation_steps(G, direct_route),
    )

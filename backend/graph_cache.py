import pickle
from pathlib import Path

import osmnx as ox

CACHE_PATH = Path(__file__).parent / "data" / "izmir_graph.pkl"


def load_graph():
    if CACHE_PATH.exists():
        print("İzmir grafiği önbellekten yükleniyor...")
        with open(CACHE_PATH, "rb") as f:
            return pickle.load(f)

    print("İzmir yol ağı OSM'den indiriliyor (birkaç dakika sürebilir)...")
    G = ox.graph_from_place("İzmir, Turkey", network_type="drive")

    with open(CACHE_PATH, "wb") as f:
        pickle.dump(G, f)

    print(f"Graf önbelleğe alındı: {CACHE_PATH}")
    return G

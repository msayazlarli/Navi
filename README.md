# Navi

İzmir için araç tipine göre rota planlayan mobil uygulama. Flutter istemci, FastAPI backend; OpenStreetMap yol ağı, şarj ve yakıt istasyonu verileriyle elektrikli, hibrit ve içten yanmalı araçlar için menzil odaklı güzergâh hesaplar.

## Özellikler

- Harita üzerinde başlangıç / varış seçimi ve adres arama (Nominatim)
- Marka ve model seçimi; elektrikli araçlarda şarj seviyesi, diğerlerinde depo doluluk yüzdesi
- Backend üzerinden rota, mesafe, süre ve menzil / şarj–yakıt durak önerileri
- İzmir OSM sürüş ağı (önbelleklenmiş graf veya ilk çalıştırmada indirme)

## Proje yapısı

```
navi/
├── lib/              # Flutter UI ve servisler
├── backend/          # FastAPI API, rota motoru, veri dosyaları
│   ├── data/         # cars.json, istasyonlar, izmir_graph.pkl (üretilebilir)
│   └── static/       # Marka logoları
├── android/ ios/ …   # Platform projeleri
└── pubspec.yaml
```

## Gereksinimler

- [Flutter](https://docs.flutter.dev/get-started/install) (SDK ^3.11)
- Python 3.11+ (backend)
- macOS / Linux / Windows geliştirme ortamı; fiziksel cihazda test için telefon ve bilgisayar **aynı Wi‑Fi**

## Backend kurulumu

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Sunucuyu başlatın (telefondan erişim için `0.0.0.0` gerekli):

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

İlk çalıştırmada `backend/data/izmir_graph.pkl` yoksa İzmir yol ağı OSM’den indirilir; birkaç dakika sürebilir ve dosya ~65 MB olur. Sonraki açılışlar önbellekten hızlıdır.

Sağlık kontrolü: [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health)

## Flutter uygulaması

Bağımlılıklar:

```bash
flutter pub get
```

**iOS simülatör / masaüstü** (backend aynı makinede):

```bash
flutter run
```

**Android emülatör** — emülatör `10.0.2.2` üzerinden host’a bağlanır; backend `0.0.0.0` ile dinlemeli.

**Fiziksel telefon** (bilgisayar IP’si gerekir):

```bash
# Mac’te IP: ipconfig getifaddr en0
flutter run --dart-define=API_HOST=192.168.1.10
```

Tam URL vermek için:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## API özeti

| Endpoint | Açıklama |
|----------|----------|
| `GET /health` | Graf yükleme durumu |
| `GET /cars` | Araç marka / model listesi |
| `GET /charging-stations` | Şarj istasyonları |
| `GET /fuel-stations` | Yakıt istasyonları (OSM) |
| `POST /route` | Rota hesaplama |

## Lisans

Henüz lisans dosyası eklenmedi. Repoyu public paylaşacaksanız köke `LICENSE` (ör. MIT) eklemeniz önerilir.

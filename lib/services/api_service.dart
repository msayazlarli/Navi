import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;

import '../models/car_model.dart';
import '../models/route_model.dart';

class NominatimResult {
  final String displayName;
  final double lat;
  final double lon;

  const NominatimResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory NominatimResult.fromJson(Map<String, dynamic> json) =>
      NominatimResult(
        displayName: json['display_name'] as String,
        lat: double.parse(json['lat'] as String),
        lon: double.parse(json['lon'] as String),
      );
}

class ApiService {
  /// Tam taban URL (öncelikli). Örn. `http://192.168.1.10:8000`
  /// `--dart-define=API_BASE_URL=http://192.168.1.10:8000`
  static const String _baseUrlFromEnv = String.fromEnvironment('API_BASE_URL');

  /// Sadece bilgisayarın LAN IP’si; port ayrı: [API_PORT]. Örn. `--dart-define=API_HOST=192.168.1.10`
  static const String _hostFromEnv = String.fromEnvironment('API_HOST');

  /// [API_HOST] kullanılırken port (varsayılan 8000).
  /// `--dart-define=API_PORT=8000`
  static const int _portFromEnv = int.fromEnvironment('API_PORT', defaultValue: 8000);

  // Android emülatör → 10.0.2.2 = geliştirme makinesi.
  // iOS simülatör / masaüstü → 127.0.0.1.
  // Fiziksel telefon: aynı Wi‑Fi’de bilgisayarın IP’si → --dart-define=API_HOST=... veya API_BASE_URL.
  // Backend: `uvicorn main:app --reload --host 0.0.0.0` (dışarıdan erişim için şart).
  static String get baseUrl {
    if (_baseUrlFromEnv.isNotEmpty) return _baseUrlFromEnv;
    if (_hostFromEnv.isNotEmpty) {
      return 'http://$_hostFromEnv:$_portFromEnv';
    }
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const _nominatimBase = 'https://nominatim.openstreetmap.org';

  static const _headers = {
    'User-Agent': 'Navi-App/1.0 (vasfikaandeniz@gmail.com)',
    'Accept-Language': 'tr',
  };

  /// Brand name → full logo URL. Populated after fetchCars() succeeds.
  static Map<String, String> brandLogos = {};

  // ── Cars ────────────────────────────────────────────────────────────────────

  static Future<Map<String, Map<String, List<CarVariant>>>> fetchCars() async {
    final uri = Uri.parse('$baseUrl/cars');
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Araçlar yüklenemedi (${response.statusCode})');
    }

    final raw =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final rawLogos = raw['brand_logos'] as Map<String, dynamic>? ?? {};
    brandLogos = {
      for (final e in rawLogos.entries) e.key: '$baseUrl${e.value as String}'
    };

    final brandsRaw = raw['brands'] as Map<String, dynamic>;
    final result = <String, Map<String, List<CarVariant>>>{};
    for (final brandEntry in brandsRaw.entries) {
      final brand = brandEntry.key;
      result[brand] = {};
      final models = brandEntry.value as Map<String, dynamic>;
      for (final modelEntry in models.entries) {
        final modelName = modelEntry.key;
        result[brand]![modelName] = (modelEntry.value as List<dynamic>)
            .map((v) => CarVariant.fromJson({
                  ...v as Map<String, dynamic>,
                  'brand': brand,
                  'model': modelName,
                }))
            .toList();
      }
    }
    return result;
  }

  // ── Route ────────────────────────────────────────────────────────────────────

  static Future<RouteResponseModel> fetchRoute({
    required double startLat,
    required double startLon,
    required double destLat,
    required double destLon,
    required String carId,
    double? chargeLevelPct,
    double? fuelLevelPct,
  }) async {
    final uri = Uri.parse('$baseUrl/route');
    final body = <String, dynamic>{
      'start_lat': startLat,
      'start_lon': startLon,
      'dest_lat': destLat,
      'dest_lon': destLon,
      'car_id': carId,
    };
    if (chargeLevelPct != null) body['charge_level_pct'] = chargeLevelPct;
    if (fuelLevelPct != null) body['fuel_level_pct'] = fuelLevelPct;

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      final detail = _extractDetail(response.body);
      throw Exception(detail ?? 'Rota hesaplanamadı (${response.statusCode})');
    }

    return RouteResponseModel.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  // ── Nominatim ────────────────────────────────────────────────────────────────

  /// Forward geocode — restricts results to İzmir province bounding box.
  static Future<List<NominatimResult>> searchAddress(String query) async {
    if (query.trim().length < 2) return [];

    final uri = Uri.parse('$_nominatimBase/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '6',
      'countrycodes': 'tr',
      // İzmir province bounding box: W, S, E, N
      'viewbox': '26.0,38.0,28.5,39.5',
      'bounded': '1',
    });

    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => NominatimResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocode — returns a short human-readable address string.
  static Future<String> reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse('$_nominatimBase/reverse').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'format': 'json',
    });

    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return _coordLabel(lat, lon);
      final json =
          jsonDecode(response.body) as Map<String, dynamic>;
      return (json['display_name'] as String?)?.split(',').take(2).join(',').trim() ??
          _coordLabel(lat, lon);
    } catch (_) {
      return _coordLabel(lat, lon);
    }
  }

  static String _coordLabel(double lat, double lon) =>
      '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

  static String? _extractDetail(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['detail'] as String?;
    } catch (_) {
      return null;
    }
  }
}

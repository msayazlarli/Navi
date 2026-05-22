import 'package:latlong2/latlong.dart';

class WaypointModel {
  final double lat;
  final double lon;
  final String type; // charging_station | gas_station | start | destination
  final String? name;
  final String? stationId;

  const WaypointModel({
    required this.lat,
    required this.lon,
    required this.type,
    this.name,
    this.stationId,
  });

  LatLng get latLng => LatLng(lat, lon);

  factory WaypointModel.fromJson(Map<String, dynamic> json) => WaypointModel(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        type: json['type'] as String,
        name: json['name'] as String?,
        stationId: json['station_id'] as String?,
      );
}

class NavigationStepModel {
  final String instruction;
  final double distanceMeters;
  final String type; // straight | turn_right | turn_left

  const NavigationStepModel({
    required this.instruction,
    required this.distanceMeters,
    required this.type,
  });

  factory NavigationStepModel.fromJson(Map<String, dynamic> json) =>
      NavigationStepModel(
        instruction: json['instruction'] as String,
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        type: json['type'] as String,
      );
}

class RouteResponseModel {
  final List<LatLng> polyline;
  final List<WaypointModel> waypoints;
  final double distanceKm;
  final double? estimatedFuelL;
  final double? estimatedChargeUsedPct;
  final bool needsChargeStop;
  final bool needsFuelStop;
  final String? fuelWarning;
  final List<NavigationStepModel> steps;

  const RouteResponseModel({
    required this.polyline,
    required this.waypoints,
    required this.distanceKm,
    this.estimatedFuelL,
    this.estimatedChargeUsedPct,
    required this.needsChargeStop,
    this.needsFuelStop = false,
    this.fuelWarning,
    this.steps = const [],
  });

  factory RouteResponseModel.fromJson(Map<String, dynamic> json) {
    final rawPolyline = json['polyline'] as List<dynamic>;
    return RouteResponseModel(
      polyline: rawPolyline
          .map((p) => LatLng(
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList(),
      waypoints: (json['waypoints'] as List<dynamic>)
          .map((w) => WaypointModel.fromJson(w as Map<String, dynamic>))
          .toList(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      estimatedFuelL: (json['estimated_fuel_l'] as num?)?.toDouble(),
      estimatedChargeUsedPct:
          (json['estimated_charge_used_pct'] as num?)?.toDouble(),
      needsChargeStop: json['needs_charge_stop'] as bool,
      needsFuelStop: json['needs_fuel_stop'] as bool? ?? false,
      fuelWarning: json['fuel_warning'] as String?,
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) =>
                  NavigationStepModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

import 'dart:convert';

class CarVariant {
  final String id;
  final String brand;
  final String model;
  final String variant;
  final String engineType; // Benzin | Dizel | Hibrit | Elektrik
  final double? averageConsumptionLPer100km;
  final double? batteryCapacityKwh;
  final double? averageConsumptionKwhPer100km;
  /// Depo (litre); cars.json — yalnız yakıtlı varyantlarda
  final double? fuelCapacityL;
  final String? logoUrl;

  const CarVariant({
    required this.id,
    required this.brand,
    required this.model,
    required this.variant,
    required this.engineType,
    this.averageConsumptionLPer100km,
    this.batteryCapacityKwh,
    this.averageConsumptionKwhPer100km,
    this.fuelCapacityL,
    this.logoUrl,
  });

  bool get isEv => engineType == 'Elektrik';

  factory CarVariant.fromJson(Map<String, dynamic> json) => CarVariant(
        id: json['id'] as String,
        brand: json['brand'] as String,
        model: json['model'] as String,
        variant: json['variant'] as String,
        engineType: json['engine_type'] as String,
        averageConsumptionLPer100km:
            (json['average_consumption_l_per_100km'] as num?)?.toDouble(),
        batteryCapacityKwh:
            (json['battery_capacity_kwh'] as num?)?.toDouble(),
        averageConsumptionKwhPer100km:
            (json['average_consumption_kwh_per_100km'] as num?)?.toDouble(),
        fuelCapacityL: (json['fuel_capacity'] as num?)?.toDouble(),
        logoUrl: json['logo_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'model': model,
        'variant': variant,
        'engine_type': engineType,
        if (averageConsumptionLPer100km != null)
          'average_consumption_l_per_100km': averageConsumptionLPer100km,
        if (batteryCapacityKwh != null)
          'battery_capacity_kwh': batteryCapacityKwh,
        if (averageConsumptionKwhPer100km != null)
          'average_consumption_kwh_per_100km': averageConsumptionKwhPer100km,
        if (fuelCapacityL != null) 'fuel_capacity': fuelCapacityL,
        if (logoUrl != null) 'logo_url': logoUrl,
      };

  static CarVariant fromJsonString(String s) =>
      CarVariant.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());

  String get engineLabel => switch (engineType) {
        'Benzin' => '⛽ Benzin',
        'Dizel' => '⛽ Dizel',
        'Hibrit' => '🔋 Hibrit',
        'Elektrik' => '⚡ Elektrik',
        _ => engineType,
      };
}

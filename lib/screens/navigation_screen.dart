import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/car_model.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';

class NavigationScreen extends StatefulWidget {
  final RouteResponseModel route;
  final LatLng startLatLng;
  final LatLng destLatLng;
  final CarVariant car;

  const NavigationScreen({
    super.key,
    required this.route,
    required this.startLatLng,
    required this.destLatLng,
    required this.car,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _mapController = MapController();

  late LatLng _userLatLng;
  StreamSubscription<Position>? _positionSub;
  bool _cameraFollowsUser = true;

  @override
  void initState() {
    super.initState();
    _userLatLng = widget.startLatLng;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenLivePosition();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _listenLivePosition() async {
    if (!mounted) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position p) {
        if (!mounted) return;
        final ll = LatLng(p.latitude, p.longitude);
        setState(() => _userLatLng = ll);
        if (_cameraFollowsUser) {
          final z = _mapController.camera.zoom;
          _mapController.moveAndRotate(ll, z, 0);
        }
      },
    );
  }

  void _onMapPositionChanged(MapCamera _, bool hasGesture) {
    if (hasGesture && _cameraFollowsUser) {
      setState(() => _cameraFollowsUser = false);
    }
  }

  void _recenterOnUser() {
    setState(() => _cameraFollowsUser = true);
    final z = _mapController.camera.zoom;
    _mapController.moveAndRotate(_userLatLng, z, 0);
  }

  void _zoomIn() {
    final z = (_mapController.camera.zoom + 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, z);
  }

  void _zoomOut() {
    final z = (_mapController.camera.zoom - 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, z);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.startLatLng,
              initialZoom: 13,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.navi.navi',
              ),
              // Route polyline
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.route.polyline,
                    strokeWidth: 5,
                    color: AppTheme.aegeanTurquoise,
                    borderStrokeWidth: 2,
                    borderColor:
                        AppTheme.aegeanTurquoise.withValues(alpha: 0.3),
                  ),
                ],
              ),
              // Markers: start + dest + waypoints
              MarkerLayer(
                markers: [
                  // User / start marker — turquoise circle
                  Marker(
                    point: _userLatLng,
                    width: 34,
                    height: 34,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.deepSeaBlue,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Destination
                  Marker(
                    point: widget.destLatLng,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_pin,
                      color: AppTheme.sunsetOrange,
                      size: 44,
                    ),
                  ),
                  // Charging / gas waypoints
                  ...widget.route.waypoints.map(
                    (w) => Marker(
                      point: w.latLng,
                      width: 36,
                      height: 36,
                      child: _WaypointMarker(type: w.type),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Top info panel (geri: panel içi sol — haritayı kapatmaz, mobil uyumlu)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _RouteInfoPanel(
              route: widget.route,
              car: widget.car,
              onBack: () => Navigator.pop(context),
            ),
          ),

          // ── Rotayı İptal Et button ──────────────────────────────────────────────
          Positioned(
            bottom: bottomPadding + 20,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Rotayı İptal Et'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          // ── Zoom controls ──────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ZoomButton(icon: Icons.add, onPressed: _zoomIn),
                  const SizedBox(height: 8),
                  _ZoomButton(icon: Icons.remove, onPressed: _zoomOut),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    icon: _cameraFollowsUser
                        ? Icons.gps_fixed
                        : Icons.gps_not_fixed,
                    onPressed: _recenterOnUser,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Route info panel ───────────────────────────────────────────────────────────

class _RouteInfoPanel extends StatelessWidget {
  final RouteResponseModel route;
  final CarVariant car;
  final VoidCallback onBack;

  const _RouteInfoPanel({
    required this.route,
    required this.car,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          color: AppTheme.deepSeaBlue.withValues(alpha: 0.88),
          padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onBack,
                      borderRadius: BorderRadius.circular(22),
                      customBorder: const CircleBorder(),
                      child: Ink(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x33FFFFFF),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.alt_route, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Aktif Navigasyon',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.straighten,
                    label: '${route.distanceKm.toStringAsFixed(1)} km',
                  ),
                ],
              ),
              if (route.steps.isNotEmpty) ...[
                const SizedBox(height: 10),
                _TurnByTurnBanner(step: route.steps.first),
              ],
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    if (car.isEv && route.estimatedChargeUsedPct != null) ...[
                      _InfoChip(
                        icon: Icons.bolt,
                        label:
                            '-%${route.estimatedChargeUsedPct!.toStringAsFixed(0)} şarj',
                        color: AppTheme.aegeanTurquoise,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!car.isEv && route.estimatedFuelL != null) ...[
                      _InfoChip(
                        icon: Icons.local_gas_station,
                        label:
                            '≈ ${route.estimatedFuelL!.toStringAsFixed(1)} L tüketim',
                        color: AppTheme.aegeanTurquoise,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (route.needsChargeStop) ...[
                      const _InfoChip(
                        icon: Icons.warning_amber,
                        label: 'Şarj durağı gerekli',
                        color: Color(0xFFFFA726),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (route.needsFuelStop) ...[
                      const _InfoChip(
                        icon: Icons.local_gas_station,
                        label: 'Yakıt durağı eklendi',
                        color: Color(0xFFFFA726),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (route.waypoints.isNotEmpty)
                      _InfoChip(
                        icon: Icons.place,
                        label: '${route.waypoints.length} durak',
                      ),
                  ],
                ),
              ),
              if (route.fuelWarning != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFFE082), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        route.fuelWarning!,
                        style: const TextStyle(
                          color: Color(0xFFFFF9C4),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnByTurnBanner extends StatelessWidget {
  final NavigationStepModel step;

  const _TurnByTurnBanner({required this.step});

  IconData get _icon {
    switch (step.type) {
      case 'turn_right':
        return Icons.turn_right;
      case 'turn_left':
        return Icons.turn_left;
      default:
        return Icons.arrow_upward;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(_icon, color: Colors.white, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  step.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Waypoint marker ────────────────────────────────────────────────────────────

class _WaypointMarker extends StatelessWidget {
  final String type;

  const _WaypointMarker({required this.type});

  @override
  Widget build(BuildContext context) {
    final isCharging = type == 'charging_station';
    final isGas = type == 'gas_station';
    return Container(
      decoration: BoxDecoration(
        color: isCharging
            ? AppTheme.aegeanTurquoise
            : (isGas ? const Color(0xFF2E7D32) : const Color(0xFF4CAF50)),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(
        isCharging ? Icons.bolt : Icons.local_gas_station_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

// ── Zoom button ────────────────────────────────────────────────────────────────

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ZoomButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: AppTheme.deepSeaBlue, size: 22),
      ),
    );
  }
}


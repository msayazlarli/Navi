import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/car_model.dart';
import '../screens/car_selection_screen.dart';
import '../screens/navigation_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ev_battery_slider.dart';
import '../widgets/glassmorphism_panel.dart';

// İzmir city center
const _izmirCenter = LatLng(38.4192, 27.1287);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  CarVariant? _selectedCar;
  LatLng? _startLatLng;
  LatLng? _destLatLng;
  String _startLabel = '';
  String _destLabel = '';
  double _batteryLevel = 80.0;
  /// Benzin / dizel / hibrit — depo doluluk % (kapasite cars.json)
  double _fuelLevelPct = 50;
  bool _isLoadingRoute = false;
  bool _isLoadingLocation = false;

  /// Konumumu kullan sonrası canlı GPS; elle harita kaydırılınca kapatılır.
  StreamSubscription<Position>? _gpsSub;
  bool _gpsLiveActive = false;
  bool _cameraFollowsGps = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedCar();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }

  void _stopGpsStream() {
    _gpsSub?.cancel();
    _gpsSub = null;
    if (_gpsLiveActive && mounted) {
      setState(() => _gpsLiveActive = false);
    } else {
      _gpsLiveActive = false;
    }
  }

  Future<void> _startGpsStream() async {
    _gpsSub?.cancel();
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) _showSnack('Konum servisleri kapalı');
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position p) {
        if (!mounted) return;
        final ll = LatLng(p.latitude, p.longitude);
        setState(() => _startLatLng = ll);
        if (_cameraFollowsGps) {
          final z = _mapController.camera.zoom;
          _mapController.moveAndRotate(ll, z, 0);
        }
      },
      onError: (_) {
        if (mounted) _showSnack('Canlı konum akışı kesildi');
      },
    );
    if (mounted) setState(() => _gpsLiveActive = true);
  }

  void _onMapPositionChanged(MapCamera _, bool hasGesture) {
    if (hasGesture && _cameraFollowsGps) {
      setState(() => _cameraFollowsGps = false);
    }
  }

  void _recenterOnGps() {
    if (_startLatLng == null) return;
    setState(() => _cameraFollowsGps = true);
    final z = _mapController.camera.zoom;
    _mapController.moveAndRotate(_startLatLng!, z, 0);
  }

  Future<void> _loadSelectedCar() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('selected_car_json');
    if (json != null && mounted) {
      setState(() => _selectedCar = CarVariant.fromJsonString(json));
    }
  }

  // ── Map interactions ─────────────────────────────────────────────────────────

  void _zoomIn() {
    final z = (_mapController.camera.zoom + 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, z);
  }

  void _zoomOut() {
    final z = (_mapController.camera.zoom - 1.0).clamp(1.0, 18.0);
    _mapController.move(_mapController.camera.center, z);
  }

  void _onMapLongPress(TapPosition _, LatLng point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PointPickerSheet(
        onStart: () {
          Navigator.pop(context);
          _setPoint(point, isStart: true);
        },
        onDest: () {
          Navigator.pop(context);
          _setPoint(point, isStart: false);
        },
      ),
    );
  }

  void _setPoint(LatLng point, {required bool isStart}) {
    if (isStart) {
      _stopGpsStream();
      setState(() => _cameraFollowsGps = true);
    }
    final label =
        '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    setState(() {
      if (isStart) {
        _startLatLng = point;
        _startLabel = label;
      } else {
        _destLatLng = point;
        _destLabel = label;
      }
    });
    _mapController.move(point, 13.5);
    _reverseGeocodePoint(point, isStart: isStart);
  }

  Future<void> _reverseGeocodePoint(LatLng point, {required bool isStart}) async {
    final address =
        await ApiService.reverseGeocode(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      if (isStart) {
        _startLabel = address;
      } else {
        _destLabel = address;
      }
    });
  }

  // ── GPS ──────────────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Konum izni verilmedi');
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('Konum servisleri kapalı');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      // GPS’ten geldiği için _setPoint içindeki stream durdurmayı atlıyoruz.
      final label =
          '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
      setState(() {
        _startLatLng = latLng;
        _startLabel = label;
        _cameraFollowsGps = true;
      });
      _mapController.moveAndRotate(latLng, 14, 0);
      _reverseGeocodePoint(latLng, isStart: true);
      await _startGpsStream();
    } catch (e) {
      _showSnack('Konum alınamadı: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Address search ────────────────────────────────────────────────────────────

  Future<void> _showAddressSearch(bool isStart) async {
    final result = await showModalBottomSheet<NominatimResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddressSearchSheet(),
    );
    if (result == null || !mounted) return;

    final latLng = LatLng(result.lat, result.lon);
    if (isStart) {
      _stopGpsStream();
      setState(() => _cameraFollowsGps = true);
    }
    setState(() {
      if (isStart) {
        _startLatLng = latLng;
        _startLabel = result.displayName.split(',').take(2).join(',').trim();
      } else {
        _destLatLng = latLng;
        _destLabel = result.displayName.split(',').take(2).join(',').trim();
      }
    });
    _mapController.move(latLng, 14);
  }

  // ── Route ─────────────────────────────────────────────────────────────────────

  Future<void> _calculateRoute() async {
    if (_startLatLng == null || _destLatLng == null || _selectedCar == null) {
      return;
    }
    setState(() => _isLoadingRoute = true);
    try {
      final route = await ApiService.fetchRoute(
        startLat: _startLatLng!.latitude,
        startLon: _startLatLng!.longitude,
        destLat: _destLatLng!.latitude,
        destLon: _destLatLng!.longitude,
        carId: _selectedCar!.id,
        chargeLevelPct: _selectedCar!.isEv ? _batteryLevel : null,
        fuelLevelPct: _selectedCar!.isEv ? null : _fuelLevelPct,
      );

      if (!mounted) return;
      _stopGpsStream();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NavigationScreen(
            route: route,
            startLatLng: _startLatLng!,
            destLatLng: _destLatLng!,
            car: _selectedCar!,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final canRoute = _startLatLng != null && _destLatLng != null;
    final fuelOk = _selectedCar == null ||
        _selectedCar!.isEv ||
        (_selectedCar!.fuelCapacityL != null && _selectedCar!.fuelCapacityL! > 0);
    final canSubmitRoute = canRoute && _selectedCar != null && fuelOk;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _izmirCenter,
              initialZoom: 11,
              onLongPress: _onMapLongPress,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.navi.navi',
              ),
              MarkerLayer(
                markers: [
                  if (_startLatLng != null)
                    Marker(
                      point: _startLatLng!,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.trip_origin,
                        color: AppTheme.deepSeaBlue,
                        size: 36,
                      ),
                    ),
                  if (_destLatLng != null)
                    Marker(
                      point: _destLatLng!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppTheme.sunsetOrange,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ── Top toolbar ───────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _MapIconButton(
              icon: Icons.directions_car_outlined,
              tooltip: 'Araç Değiştir',
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const CarSelectionScreen()),
              ),
            ),
          ),

          // ── Zoom + canlı takip (yeniden merkezle) ─────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 12,
            child: Column(
              children: [
                _MapIconButton(
                  icon: Icons.add,
                  tooltip: 'Yakınlaştır',
                  onTap: _zoomIn,
                  iconColor: AppTheme.deepSeaBlue,
                ),
                const SizedBox(height: 8),
                _MapIconButton(
                  icon: Icons.remove,
                  tooltip: 'Uzaklaştır',
                  onTap: _zoomOut,
                  iconColor: AppTheme.deepSeaBlue,
                ),
                if (_gpsLiveActive) ...[
                  const SizedBox(height: 8),
                  _MapIconButton(
                    icon: _cameraFollowsGps
                        ? Icons.gps_fixed
                        : Icons.gps_not_fixed,
                    tooltip: _cameraFollowsGps
                        ? 'Konumuma yeniden ortala'
                        : 'Konumuma dön (canlı takip)',
                    onTap: _recenterOnGps,
                    iconColor: _cameraFollowsGps
                        ? AppTheme.aegeanTurquoise
                        : AppTheme.deepSeaBlue,
                  ),
                ],
              ],
            ),
          ),

          // ── Bottom glassmorphism panel ─────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GlassmorphismPanel(
              padding: EdgeInsets.fromLTRB(
                  16, 14, 16, bottomPadding + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Nereden
                  _LocationField(
                    icon: Icons.trip_origin,
                    iconColor: AppTheme.deepSeaBlue,
                    label: 'Nereden',
                    value: _startLabel,
                    trailing: _isLoadingLocation
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.my_location,
                                color: AppTheme.aegeanTurquoise),
                            tooltip: 'Konumumu Kullan',
                            onPressed: _useCurrentLocation,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                    onTap: () => _showAddressSearch(true),
                  ),

                  const _Divider(),

                  // Nereye
                  _LocationField(
                    icon: Icons.location_pin,
                    iconColor: AppTheme.sunsetOrange,
                    label: 'Nereye',
                    value: _destLabel,
                    onTap: () => _showAddressSearch(false),
                  ),

                  // EV slider
                  if (_selectedCar?.isEv ?? false) ...[
                    const SizedBox(height: 12),
                    EvBatterySlider(
                      value: _batteryLevel,
                      onChanged: (v) => setState(() => _batteryLevel = v),
                    ),
                  ],

                  if (_selectedCar != null && !_selectedCar!.isEv) ...[
                    const SizedBox(height: 12),
                    if (_selectedCar!.fuelCapacityL != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Depo: ${_selectedCar!.fuelCapacityL!.toStringAsFixed(0)} L',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Bu araç kaydında depo hacmi yok. Araç seçiminden yeniden seçin.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_selectedCar!.fuelCapacityL != null)
                      EvBatterySlider(
                        title: 'Depo doluluğu',
                        isFuel: true,
                        value: _fuelLevelPct,
                        onChanged: (v) => setState(() => _fuelLevelPct = v),
                      ),
                  ],

                  const SizedBox(height: 14),

                  // Rota Bul
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: canSubmitRoute && !_isLoadingRoute
                          ? _calculateRoute
                          : null,
                      icon: _isLoadingRoute
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.alt_route),
                      label: Text(
                          _isLoadingRoute ? 'Hesaplanıyor...' : 'Rota Bul'),
                    ),
                  ),

                  // Hint when points missing
                  if (!canRoute)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Haritaya uzun basarak nokta ekleyin',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (canRoute &&
                      _selectedCar != null &&
                      !_selectedCar!.isEv &&
                      !fuelOk)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Yakıtlı araç için depo verisi yok; araç seçiminden yeniden seçin.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red[600]),
                        textAlign: TextAlign.center,
                      ),
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

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? iconColor;

  const _MapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
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
          child: Icon(icon, color: iconColor ?? AppTheme.deepSeaBlue, size: 22),
        ),
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback onTap;

  const _LocationField({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                Text(
                  hasValue ? value : 'Ara veya haritaya uzun bas...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        hasValue ? FontWeight.w600 : FontWeight.normal,
                    color: hasValue ? AppTheme.darkText : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 22),
      child: Divider(height: 1, color: Colors.grey[200]),
    );
  }
}

class _PointPickerSheet extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onDest;

  const _PointPickerSheet({required this.onStart, required this.onDest});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Bu konumu ayarla',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.trip_origin, color: AppTheme.deepSeaBlue),
              title: const Text('Başlangıç Noktası'),
              onTap: onStart,
            ),
            ListTile(
              leading:
                  const Icon(Icons.location_pin, color: AppTheme.sunsetOrange),
              title: const Text('Hedef'),
              onTap: onDest,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Address search sheet ───────────────────────────────────────────────────────

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet();

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _controller = TextEditingController();
  List<NominatimResult> _results = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await ApiService.searchAddress(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'İzmir\'de konum ara...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.deepSeaBlue),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.aegeanTurquoise),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_results.isEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'İzmir\'de bir adres veya yer adı yazın',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: const Icon(Icons.place_outlined,
                      color: AppTheme.deepSeaBlue),
                  title: Text(
                    r.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => Navigator.pop(context, r),
                );
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

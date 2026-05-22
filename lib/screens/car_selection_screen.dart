import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../models/car_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'car_variants_screen.dart';

class CarSelectionScreen extends StatefulWidget {
  const CarSelectionScreen({super.key});

  @override
  State<CarSelectionScreen> createState() => _CarSelectionScreenState();
}

class _CarSelectionScreenState extends State<CarSelectionScreen> {
  Map<String, Map<String, List<CarVariant>>>? _cars;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCars();
  }

  Future<void> _loadCars() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cars = await ApiService.fetchCars();
      setState(() {
        _cars = cars;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = kDebugMode
            ? 'Araçlar yüklenemedi.\nAdres: ${ApiService.baseUrl}\n\n$e'
            : 'Araçlar yüklenemedi.\nLütfen sunucunun çalıştığından emin olun.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Aracınızı Seçin'),
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.aegeanTurquoise),
            SizedBox(height: 16),
            Text('Araçlar yükleniyor...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: AppTheme.deepSeaBlue),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadCars,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    final brands = _cars!.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            'Marka seçin',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: brands.length,
            itemBuilder: (context, index) {
              final brand = brands[index];
              return _BrandCard(
                brand: brand,
                modelCount: _cars![brand]!.values
                    .fold(0, (sum, v) => sum + v.length),
                logoUrl: ApiService.brandLogos[brand],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CarVariantsScreen(
                      brand: brand,
                      models: _cars![brand]!,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BrandCard extends StatelessWidget {
  final String brand;
  final int modelCount;
  final String? logoUrl;
  final VoidCallback onTap;

  const _BrandCard({
    required this.brand,
    required this.modelCount,
    required this.onTap,
    this.logoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: logoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: logoUrl!,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.aegeanTurquoise,
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.directions_car_rounded,
                          color: AppTheme.deepSeaBlue,
                          size: 40,
                        ),
                      )
                    : const Icon(
                        Icons.directions_car_rounded,
                        color: AppTheme.deepSeaBlue,
                        size: 40,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  brand,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkText,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$modelCount model',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

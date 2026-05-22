import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/car_model.dart';
import '../theme/app_theme.dart';
import 'map_screen.dart';

class CarVariantsScreen extends StatefulWidget {
  final String brand;
  final Map<String, List<CarVariant>> models;

  const CarVariantsScreen({
    super.key,
    required this.brand,
    required this.models,
  });

  @override
  State<CarVariantsScreen> createState() => _CarVariantsScreenState();
}

class _CarVariantsScreenState extends State<CarVariantsScreen> {
  CarVariant? _selected;

  Future<void> _saveAndContinue() async {
    final car = _selected!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_car_id', car.id);
    await prefs.setString('selected_car_json', car.toJsonString());

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MapScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelNames = widget.models.keys.toList();

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: Text(widget.brand),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: modelNames.length,
              itemBuilder: (context, i) {
                final modelName = modelNames[i];
                final variants = widget.models[modelName]!;
                return _ModelSection(
                  modelName: modelName,
                  variants: variants,
                  selectedId: _selected?.id,
                  onVariantTap: (v) => setState(() => _selected = v),
                );
              },
            ),
          ),
          if (_selected != null) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: AppTheme.offWhite,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.aegeanTurquoise.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.aegeanTurquoise.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.aegeanTurquoise, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_selected!.brand} ${_selected!.model} — ${_selected!.variant}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _saveAndContinue,
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }
}

class _ModelSection extends StatelessWidget {
  final String modelName;
  final List<CarVariant> variants;
  final String? selectedId;
  final ValueChanged<CarVariant> onVariantTap;

  const _ModelSection({
    required this.modelName,
    required this.variants,
    required this.selectedId,
    required this.onVariantTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            modelName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.deepSeaBlue,
            ),
          ),
        ),
        ...variants.map((v) => _VariantCard(
              variant: v,
              selected: v.id == selectedId,
              onTap: () => onVariantTap(v),
            )),
      ],
    );
  }
}

class _VariantCard extends StatelessWidget {
  final CarVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _VariantCard({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.aegeanTurquoise.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.aegeanTurquoise : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.10 : 0.05),
              blurRadius: selected ? 12 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              variant.isEv ? Icons.bolt : Icons.local_gas_station,
              color: selected ? AppTheme.aegeanTurquoise : AppTheme.deepSeaBlue,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.variant,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTheme.aegeanTurquoise : AppTheme.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    variant.engineLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.aegeanTurquoise, size: 20),
          ],
        ),
      ),
    );
  }
}

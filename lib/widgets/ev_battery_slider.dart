import 'package:flutter/material.dart';

class EvBatterySlider extends StatelessWidget {
  final double value; // 0–100
  final ValueChanged<double> onChanged;
  /// Varsayılan: şarj. Yakıt için `isFuel: true` ve [fuelTitle] kullanın.
  final bool isFuel;
  final String title;

  const EvBatterySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.isFuel = false,
    this.title = 'Mevcut Şarj',
  });

  Color get _trackColor {
    if (value <= 20) return Colors.red;
    if (value <= 45) {
      return Color.lerp(Colors.red, Colors.orange, (value - 20) / 25)!;
    }
    if (value <= 70) {
      return Color.lerp(Colors.orange, const Color(0xFFCDC700), (value - 45) / 25)!;
    }
    return Color.lerp(const Color(0xFF8BC34A), Colors.green, (value - 70) / 30)!;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isFuel)
              Icon(Icons.local_gas_station_outlined,
                  size: 26, color: _trackColor)
            else
              _BatteryIcon(level: value / 100, color: _trackColor),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const Spacer(),
            Text(
              '%${value.round()}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _trackColor,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _trackColor,
            inactiveTrackColor: _trackColor.withValues(alpha: 0.2),
            thumbColor: _trackColor,
            overlayColor: _trackColor.withValues(alpha: 0.15),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  final double level; // 0.0–1.0
  final Color color;

  const _BatteryIcon({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 14),
      painter: _BatteryPainter(level: level, color: color),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final double level;
  final Color color;

  const _BatteryPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final terminalWidth = 3.0;
    final bodyWidth = size.width - terminalWidth;
    final borderRadius = Radius.circular(2.5);

    // Body outline
    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, bodyWidth, size.height),
        borderRadius,
      ),
      outlinePaint,
    );

    // Terminal nub
    final terminalPaint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bodyWidth + 1, size.height * 0.3, terminalWidth - 1,
            size.height * 0.4),
        const Radius.circular(1),
      ),
      terminalPaint,
    );

    // Fill
    final fillWidth = (bodyWidth - 4) * level.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2, 2, fillWidth, size.height - 4),
          const Radius.circular(1.5),
        ),
        terminalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.level != level || old.color != color;
}

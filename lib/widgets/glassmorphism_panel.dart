import 'dart:ui';

import 'package:flutter/material.dart';

class GlassmorphismPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const GlassmorphismPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        const BorderRadius.vertical(top: Radius.circular(24));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: child,
        ),
      ),
    );
  }
}

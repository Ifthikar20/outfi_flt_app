import 'dart:math';
import 'package:flutter/material.dart';

/// A luxurious animated watercolor background with flowing ink blobs.
/// Used as the hero landing animation on login/register screens.
class WatercolorBackground extends StatefulWidget {
  final Widget? child;
  const WatercolorBackground({super.key, this.child});

  @override
  State<WatercolorBackground> createState() => _WatercolorBackgroundState();
}

class _WatercolorBackgroundState extends State<WatercolorBackground>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _pulseController]),
      builder: (context, child) {
        return CustomPaint(
          painter: _WatercolorPainter(
            progress: _controller.value,
            pulse: _pulseController.value,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _WatercolorPainter extends CustomPainter {
  final double progress;
  final double pulse;

  _WatercolorPainter({required this.progress, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm ivory base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFDFBF7),
    );

    // ── Watercolor blobs ──
    // Each blob is a radial gradient with soft edges, animated positions
    final blobs = <_WatercolorBlob>[
      // Warm gold (top-left, drifting)
      _WatercolorBlob(
        center: Offset(
          w * (0.15 + 0.08 * sin(progress * 2 * pi)),
          h * (0.12 + 0.06 * cos(progress * 2 * pi * 0.7)),
        ),
        radius: w * (0.45 + 0.05 * pulse),
        colors: [
          const Color(0xFFC9A96E).withValues(alpha: 0.12 + 0.04 * pulse),
          const Color(0xFFDFC99B).withValues(alpha: 0.06),
          const Color(0xFFC9A96E).withValues(alpha: 0.0),
        ],
      ),

      // Soft blush pink (top-right)
      _WatercolorBlob(
        center: Offset(
          w * (0.85 + 0.1 * sin(progress * 2 * pi * 1.3 + 1.0)),
          h * (0.08 + 0.05 * cos(progress * 2 * pi * 0.5 + 0.5)),
        ),
        radius: w * (0.4 + 0.06 * pulse),
        colors: [
          const Color(0xFFE8C4B8).withValues(alpha: 0.14 + 0.03 * pulse),
          const Color(0xFFF0D5CA).withValues(alpha: 0.07),
          const Color(0xFFE8C4B8).withValues(alpha: 0.0),
        ],
      ),

      // Dusty sage (center-left, slow drift)
      _WatercolorBlob(
        center: Offset(
          w * (0.25 + 0.12 * cos(progress * 2 * pi * 0.6 + 2.0)),
          h * (0.35 + 0.08 * sin(progress * 2 * pi * 0.4)),
        ),
        radius: w * (0.5 + 0.04 * pulse),
        colors: [
          const Color(0xFFB5C7A3).withValues(alpha: 0.10 + 0.03 * pulse),
          const Color(0xFFCBD9BC).withValues(alpha: 0.05),
          const Color(0xFFB5C7A3).withValues(alpha: 0.0),
        ],
      ),

      // Deep terracotta (right side, mid)
      _WatercolorBlob(
        center: Offset(
          w * (0.78 + 0.06 * sin(progress * 2 * pi * 0.9 + 3.0)),
          h * (0.42 + 0.07 * cos(progress * 2 * pi * 0.35 + 1.5)),
        ),
        radius: w * (0.38 + 0.05 * pulse),
        colors: [
          const Color(0xFFD4A373).withValues(alpha: 0.11 + 0.03 * pulse),
          const Color(0xFFE5C4A1).withValues(alpha: 0.06),
          const Color(0xFFD4A373).withValues(alpha: 0.0),
        ],
      ),

      // Lavender haze (bottom, large)
      _WatercolorBlob(
        center: Offset(
          w * (0.5 + 0.1 * sin(progress * 2 * pi * 0.5 + 4.0)),
          h * (0.7 + 0.05 * cos(progress * 2 * pi * 0.3 + 2.0)),
        ),
        radius: w * (0.55 + 0.06 * pulse),
        colors: [
          const Color(0xFFCDB4DB).withValues(alpha: 0.09 + 0.03 * pulse),
          const Color(0xFFDDCDE6).withValues(alpha: 0.05),
          const Color(0xFFCDB4DB).withValues(alpha: 0.0),
        ],
      ),

      // Warm peach (bottom right)
      _WatercolorBlob(
        center: Offset(
          w * (0.75 + 0.08 * cos(progress * 2 * pi * 0.45 + 5.0)),
          h * (0.85 + 0.04 * sin(progress * 2 * pi * 0.6)),
        ),
        radius: w * (0.42 + 0.04 * pulse),
        colors: [
          const Color(0xFFFAD2CF).withValues(alpha: 0.12 + 0.02 * pulse),
          const Color(0xFFF8E1DE).withValues(alpha: 0.06),
          const Color(0xFFFAD2CF).withValues(alpha: 0.0),
        ],
      ),

      // Honey gold accent (floating, small)
      _WatercolorBlob(
        center: Offset(
          w * (0.5 + 0.15 * sin(progress * 2 * pi * 1.1 + 0.7)),
          h * (0.2 + 0.1 * cos(progress * 2 * pi * 0.8 + 3.0)),
        ),
        radius: w * (0.25 + 0.04 * pulse),
        colors: [
          const Color(0xFFC9A96E).withValues(alpha: 0.08 + 0.02 * pulse),
          const Color(0xFFE8D5A8).withValues(alpha: 0.04),
          const Color(0xFFC9A96E).withValues(alpha: 0.0),
        ],
      ),
    ];

    for (final blob in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: blob.colors,
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: blob.center, radius: blob.radius),
        );
      canvas.drawCircle(blob.center, blob.radius, paint);
    }

    // Add subtle "water texture" — organic spots
    _drawWaterTexture(canvas, size);
  }

  void _drawWaterTexture(Canvas canvas, Size size) {
    final rand = Random(42);  // Deterministic for consistency
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < 20; i++) {
      final x = rand.nextDouble() * w;
      final y = rand.nextDouble() * h;
      final r = 2.0 + rand.nextDouble() * 8;

      // Animate each spot's opacity with a unique phase
      final phase = i * 0.3 + progress * 2 * pi * 0.2;
      final alpha = (0.02 + 0.015 * sin(phase)).clamp(0.0, 0.05);

      final colors = [
        const Color(0xFFC9A96E),
        const Color(0xFFD4A373),
        const Color(0xFFCDB4DB),
        const Color(0xFFB5C7A3),
        const Color(0xFFE8C4B8),
      ];

      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WatercolorPainter old) =>
      old.progress != progress || old.pulse != pulse;
}

class _WatercolorBlob {
  final Offset center;
  final double radius;
  final List<Color> colors;

  const _WatercolorBlob({
    required this.center,
    required this.radius,
    required this.colors,
  });
}

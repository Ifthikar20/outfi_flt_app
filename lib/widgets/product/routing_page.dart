import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Animated "Routing to [store]..." overlay shown before opening the affiliate URL.
class RoutingPage extends StatefulWidget {
  final String storeName;
  final VoidCallback onComplete;

  const RoutingPage({super.key, required this.storeName, required this.onComplete});

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _dotCount = (_dotCount + 1) % 4);
        _dotCtrl.forward(from: 0);
      }
    });
    _dotCtrl.forward();

    // Navigate after short delay — kept brief so the redirect feels instant.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (_dotCount + 1);
    return Scaffold(
      backgroundColor: AppTheme.bgMain,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Store icon with pulse
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined, size: 32, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Routing to ${widget.storeName}$dots',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Opening in your browser',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

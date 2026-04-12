import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  void _onTap(int i) {
    // goBranch keeps pages alive — only switches the visible branch
    navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgMain,
          border: Border(
            top: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  assetPath: 'assets/images/nav_home.png',
                  label: 'HOME',
                  active: navigationShell.currentIndex == 0,
                  onTap: () => _onTap(0),
                ),
                _NavItem(
                  assetPath: 'assets/images/nav_save.png',
                  label: 'SAVED',
                  active: navigationShell.currentIndex == 1,
                  onTap: () => _onTap(1),
                ),

                // Camera FAB
                GestureDetector(
                  onTap: () => context.push('/camera'),
                  child: Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/images/camera_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                _NavItem(
                  assetPath: 'assets/images/nav_boards.png',
                  label: 'BOARDS',
                  active: navigationShell.currentIndex == 2,
                  onTap: () => _onTap(2),
                ),

                _NavItem(
                  assetPath: 'assets/images/nav_you.png',
                  label: 'YOU',
                  active: navigationShell.currentIndex == 3,
                  onTap: () => _onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String assetPath;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.assetPath,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                color: active ? AppTheme.primary : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppTheme.primary : AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

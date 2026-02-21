import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Bottom navigation bar — pixel-matched to screenshot:
/// Home | Feed | Create (+) | Community | Me
///
/// Rules from image:
///  • Selected tab  → filled black icon + black bold label
///  • Unselected    → gray outline icon + gray label
///  • Create        → always green "+" icon + green "Create" label (no circle)
///  • Background    → white/cream, hairline top border, no shadow
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int notificationCount;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.notificationCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAF8), // very light cream matching screenshot
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavTab(
                icon: Icons.home_outlined,
                filledIcon: Icons.home,
                label: 'Home',
                isSelected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavTab(
                icon: Icons.explore_outlined,
                filledIcon: Icons.explore,
                label: 'Explore',
                isSelected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _CreateTab(
                onTap: () => onTap(2),
              ),
              _NavTab(
                icon: Icons.groups_outlined,
                filledIcon: Icons.groups,
                label: 'Community',
                isSelected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavTab(
                icon: Icons.person_outline,
                filledIcon: Icons.person,
                label: 'Me',
                isSelected: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Regular nav tab
// ─────────────────────────────────────────────────────────────
class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData filledIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badge;

  const _NavTab({
    required this.icon,
    required this.filledIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Selected = near-black, unselected = medium gray (matching screenshot)
    final Color iconColor = isSelected
        ? const Color(0xFF1A1A1A)
        : const Color(0xFF8A8A8A);
    final Color labelColor = isSelected
        ? const Color(0xFF1A1A1A)
        : const Color(0xFF8A8A8A);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? filledIcon : icon,
                  size: 26,
                  color: iconColor,
                ),
                if (badge > 0)
                  Positioned(
                    top: -3,
                    right: -5,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppTheme.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create tab — green "+" icon, green label, NO circle/bubble
// ─────────────────────────────────────────────────────────────
class _CreateTab extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateTab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.add,
              size: 30,
              color: AppTheme.primary, // #2F7D6A green
            ),
            SizedBox(height: 3),
            Text(
              'Create',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

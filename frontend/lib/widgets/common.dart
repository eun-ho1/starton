import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_outlined, '홈'),
      (Icons.monitor_heart_outlined, '리도전'),
      (Icons.emoji_events_outlined, '랭킹'),
      (Icons.bar_chart_rounded, '기록'),
    ];

    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.zero,
      child: BottomAppBar(
        color: const Color(0xFFF1F3F8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFDDE3EE))),
          ),
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    item: items[0],
                    selected: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    item: items[1],
                    selected: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                ),
                const SizedBox(width: 76),
                Expanded(
                  child: _NavItem(
                    item: items[2],
                    selected: currentIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    item: items[3],
                    selected: currentIndex == 3,
                    onTap: () => onTap(3),
                  ),
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
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final (IconData, String) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: item.$2,
        child: Center(
          child: Icon(
            item.$1,
            size: 24,
            color: selected ? const Color(0xFF6F63FF) : const Color(0xFF8F949E),
          ),
        ),
      ),
    );
  }
}

class RoundedCard extends StatelessWidget {
  const RoundedCard({required this.child, required this.padding, super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8C7DE).withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class NeumorphicRoundedCard extends StatelessWidget {
  const NeumorphicRoundedCard({
    required this.child,
    required this.padding,
    super.key,
    this.color = const Color(0xFFF7FAFF),
    this.depth = 7,
    this.intensity = 0.9,
    this.surfaceIntensity = 0.18,
    this.borderRadius = 24,
    this.shadowDarkColor = const Color(0xFFD4DDEB),
    this.shadowLightColor = const Color(0xFFFFFFFF),
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double depth;
  final double intensity;
  final double surfaceIntensity;
  final double borderRadius;
  final Color shadowDarkColor;
  final Color shadowLightColor;

  @override
  Widget build(BuildContext context) {
    return neu.Neumorphic(
      style: neu.NeumorphicStyle(
        depth: depth,
        intensity: intensity,
        surfaceIntensity: surfaceIntensity,
        color: color,
        shadowDarkColor: shadowDarkColor,
        shadowLightColor: shadowLightColor,
        boxShape: neu.NeumorphicBoxShape.roundRect(
          BorderRadius.circular(borderRadius),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6F63FF), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C2940),
          ),
        ),
      ],
    );
  }
}

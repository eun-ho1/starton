import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/pages/home/home_top_icon_button.dart';

// 오늘 인사말과 빠른 액션 버튼을 보여주는 헤더 영역입니다.
class HomeHeaderSection extends StatelessWidget {
  const HomeHeaderSection({
    super.key,
    required this.todayLabel,
    required this.userName,
    required this.credits,
    required this.userEnergy,
    required this.completedTodayCount,
    required this.totalTaskCount,
    required this.completionProgress,
    required this.showCreditAmount,
    required this.onEnergyTap,
    required this.onOpenSettings,
  });

  final String todayLabel;
  final String userName;
  final int credits;
  final String userEnergy;
  final int completedTodayCount;
  final int totalTaskCount;
  final double completionProgress;
  final bool showCreditAmount;
  final VoidCallback onEnergyTap;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: -5,
                  intensity: 0.86,
                  surfaceIntensity: 0.26,
                  color: const Color(0xFFE3E9F6),
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(0xFFC9D0DE),
                  boxShape: const neu.NeumorphicBoxShape.circle(),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFFF6B42D),
                  size: 29,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todayLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7E899D),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$userName 님',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF07080A),
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: showCreditAmount ? -3 : 0,
                  intensity: 0.82,
                  surfaceIntensity: 0.22,
                  color: const Color(0xFFF1F3F8),
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(0xFFD0D7E5),
                  boxShape: neu.NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(7),
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: showCreditAmount ? 8 : 0,
                  vertical: showCreditAmount ? 5 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 13,
                      color: Color(0xFFFF4B4B),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            axis: Axis.horizontal,
                            axisAlignment: -1,
                            child: child,
                          ),
                        );
                      },
                      child: showCreditAmount
                          ? Padding(
                              key: const ValueKey('credit-text'),
                              padding: const EdgeInsets.only(left: 5),
                              child: Text(
                                '$credits위',
                                style: const TextStyle(
                                  color: Color(0xFF111318),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : const SizedBox(key: ValueKey('credit-empty')),
                    ),
                    if (!showCreditAmount)
                      const SizedBox(width: 6, height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            HomeTopIconButton(
              icon: Icons.notifications_none_rounded,
              onTap: () {},
            ),
            const SizedBox(width: 12),
            HomeTopIconButton(
              icon: Icons.settings_outlined,
              onTap: onOpenSettings,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [

            _HomeContextMetric(
              icon: Icons.battery_charging_full_rounded,
              progress: _energyProgress(userEnergy),
              fillColor: _energyColor(userEnergy),
              onTap: onEnergyTap,
            ),
            SizedBox(width: 15,),
            _HomeContextMetric(
              icon: Icons.assignment_turned_in_rounded,
              progress: completionProgress,
              fillColor: const Color(0xFF6F63FF),
            ),
            SizedBox(width: 16,),
          ],
        ),
      ],
    );
  }
}

class _HomeContextMetric extends StatelessWidget {
  const _HomeContextMetric({
    required this.icon,
    required this.progress,
    required this.fillColor,
    this.onTap,
  });

  final IconData icon;
  final double progress;
  final Color fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 30,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: 5,
            intensity: 0.86,
            surfaceIntensity: 0.2,
            color: const Color(0xFFF1F3F8),
            shadowLightColor: Colors.white,
            shadowDarkColor: const Color(0xFFD0D7E5),
            boxShape: const neu.NeumorphicBoxShape.circle(),
          ),
          child: Center(
            child: _FilledIcon(
              icon: icon,
              fillColor: fillColor,
              progress: clampedProgress,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilledIcon extends StatelessWidget {
  const _FilledIcon({
    required this.icon,
    required this.fillColor,
    required this.progress,
  });

  final IconData icon;
  final Color fillColor;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Icon(icon, size: 22, color: const Color(0xFFB4BBC9)),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: progress <= 0 ? 0.01 : progress,
              child: Icon(icon, size: 22, color: fillColor),
            ),
          ),
        ],
      ),
    );
  }
}

double _energyProgress(String value) {
  return switch (value) {
    'low' => 0.34,
    'high' => 1,
    _ => 0.67,
  };
}

Color _energyColor(String value) {
  return switch (value) {
    'low' => const Color(0xFFFF9F6E),
    'high' => const Color(0xFF38A169),
    _ => const Color(0xFF6B9AF5),
  };
}

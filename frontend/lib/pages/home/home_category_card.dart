import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;

// 카테고리 한 칸의 아이콘과 이름을 표현하는 카드입니다.
class HomeCategoryCard extends StatelessWidget {
  const HomeCategoryCard({
    super.key,
    required this.title,
    required this.completedCount,
    required this.pendingCount,
    required this.onTap,
    required this.onAddTap,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });

  final String title;
  final int completedCount;
  final int pendingCount;
  final VoidCallback onTap;
  final VoidCallback onAddTap;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final totalCount = completedCount + pendingCount;
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final progressLabel = '$completedCount/$totalCount';
    final emptyOpacity = totalCount == 0 ? 0.46 : 1.0;

    return SizedBox(
      height: 104,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(1, 1, 3, 4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              key: ValueKey('category-card-$title-$totalCount'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: emptyOpacity,
              child: neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: 6,
                  intensity: 1,
                  surfaceIntensity: 0.44,
                  lightSource: neu.LightSource.topLeft,
                  color: backgroundColor,
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(
                    0xFF6E7685,
                  ).withValues(alpha: 0.54),
                  boxShape: neu.NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(13),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(13),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 15, 13, 13),
                  child: Stack(
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF090A0D),
                          height: 1,
                        ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 1,
                        child: Icon(icon, color: Colors.black, size: 25),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: _CategoryProgressBadge(
                          progress: progress,
                          label: progressLabel,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryProgressBadge extends StatelessWidget {
  const _CategoryProgressBadge({
    required this.progress,
    required this.label,
    required this.color,
  });

  final double progress;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(58),
            painter: _CategoryProgressPainter(progress: progress, color: color),
          ),
          Container(
            width: 39,
            height: 39,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8EBF1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF111318),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryProgressPainter extends CustomPainter {
  const _CategoryProgressPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.5;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.5;
    final dotPaint = Paint()..color = color;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * clampedProgress,
      false,
      progressPaint,
    );

    final dotAngle = -math.pi / 2 + (math.pi * 2 * clampedProgress);
    final dotCenter = Offset(
      center.dx + math.cos(dotAngle) * radius,
      center.dy + math.sin(dotAngle) * radius,
    );
    canvas.drawCircle(dotCenter, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(dotCenter, 3.2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _CategoryProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

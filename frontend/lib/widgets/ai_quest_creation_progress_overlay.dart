import 'package:flutter/material.dart';

class AiQuestCreationProgressOverlay extends StatefulWidget {
  const AiQuestCreationProgressOverlay({super.key});

  @override
  State<AiQuestCreationProgressOverlay> createState() =>
      _AiQuestCreationProgressOverlayState();
}

class _AiQuestCreationProgressOverlayState
    extends State<AiQuestCreationProgressOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..forward();

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: const Color(0x66171B2A),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24171B2A),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  final progress =
                      Curves.easeOutCubic.transform(_progressController.value) *
                      0.9;
                  final percent = (progress * 100).round().clamp(1, 90);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'AI 퀘스트 생성 중...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF252B3A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AI 제안 페이지를 준비하고 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF7E899D),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          color: const Color(0xFF6F63FF),
                          backgroundColor: const Color(0xFFE5E9F2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$percent%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFF6F63FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

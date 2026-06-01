import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/widgets/path_image_provider.dart';

// 오늘 완료한 퀘스트의 결과와 보상을 보여주는 기록 카드입니다.
class HomeCompletedQuestCard extends StatelessWidget {
  const HomeCompletedQuestCard({super.key, required this.record});

  final CompletedQuestRecord record;

  @override
  Widget build(BuildContext context) {
    // 완료 시각을 읽기 쉬운 문자열로 변환합니다.
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
    final completedTime = completedAt == null
        ? '완료'
        : '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')} 완료';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 8),
      child: neu.Neumorphic(
        style: neu.NeumorphicStyle(
          depth: 4,
          intensity: 0.78,
          surfaceIntensity: 0.24,
          color: const Color(0xFFEAF8EE),
          shadowLightColor: Colors.white.withValues(alpha: 0.9),
          shadowDarkColor: const Color(0xFFCEE6D4),
          boxShape: neu.NeumorphicBoxShape.roundRect(BorderRadius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: [
            neu.Neumorphic(
              style: neu.NeumorphicStyle(
                depth: 3,
                intensity: 0.74,
                surfaceIntensity: 0.18,
                color: const Color(0xFFEAF8EE),
                shadowLightColor: Colors.white,
                shadowDarkColor: const Color(0xFFD2E7D7),
                boxShape: neu.NeumorphicBoxShape.roundRect(
                  BorderRadius.circular(12),
                ),
              ),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF2E9B57),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF33415C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$completedTime  ·  ${record.category}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E9AAE),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (record.proofImagePath != null &&
                record.proofImagePath!.isNotEmpty) ...[
              // 인증 이미지가 있으면 썸네일을 보여주고, 실패하면 대체 아이콘을 사용합니다.
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image(
                  image: imageProviderForPath(record.proofImagePath!),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    return Container(
                      width: 52,
                      height: 52,
                      color: const Color(0xFFE8F5E9),
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF7FA58A),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${record.earnedExp}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFF8B93),
                  ),
                ),
                const Text(
                  'EXP',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF98A2B3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

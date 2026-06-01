import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/widgets/path_image_provider.dart';

const double _compactProofSectionHeight = 141;

class QuestTimerProofSection extends StatelessWidget {
  const QuestTimerProofSection({
    super.key,
    required this.proofImagePath,
    required this.isCompleting,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onClearImage,
    this.compact = false,
  });

  final String? proofImagePath;
  final bool isCompleting;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onClearImage;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (proofImagePath == null) {
      return Stack(
        children: [
          GestureDetector(
            onTap: isCompleting ? null : onPickGallery,
            child: Opacity(
              opacity: isCompleting ? 0.48 : 1,
              child: neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: -5,
                  intensity: 0.92,
                  surfaceIntensity: 0.22,
                  color: const Color(0xFFF1F3F8),
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(0xFFD0D7E5),
                  boxShape: neu.NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(12),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: compact ? _compactProofSectionHeight : null,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? 10 : 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_outlined,
                            size: compact ? 18 : 20,
                            color: Colors.black,
                          ),
                          SizedBox(height: compact ? 2 : 3),
                          Text(
                            '사진 업로드',
                            style: TextStyle(
                              fontSize: compact ? 10 : 11,
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: compact ? 6 : 9,
            right: compact ? 6 : 9,
            child: Tooltip(
              message: '카메라로 촬영',
              child: _QuestTimerProofIconButton(
                icon: Icons.photo_camera_outlined,
                onTap: isCompleting ? null : onPickCamera,
                size: compact ? 30 : 34,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: 7,
            intensity: 0.9,
            surfaceIntensity: 0.18,
            color: const Color(0xFFF1F3F8),
            shadowLightColor: Colors.white,
            shadowDarkColor: const Color(0xFFD0D7E5),
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(12),
            ),
          ),
          padding: EdgeInsets.all(compact ? 6 : 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 7 : 8),
            child: Image(
              image: imageProviderForPath(proofImagePath!),
              width: double.infinity,
              height: compact ? _compactProofSectionHeight - 12 : 180,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: compact ? 10 : 14,
          right: compact ? 10 : 14,
          child: _QuestTimerProofIconButton(
            icon: Icons.close_rounded,
            onTap: isCompleting ? null : onClearImage,
            size: compact ? 32 : 38,
          ),
        ),
      ],
    );
  }
}

class _QuestTimerProofIconButton extends StatelessWidget {
  const _QuestTimerProofIconButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: neu.Neumorphic(
          style: const neu.NeumorphicStyle(
            depth: 6,
            intensity: 0.9,
            surfaceIntensity: 0.18,
            color: Color(0xFFF1F3F8),
            shadowLightColor: Colors.white,
            shadowDarkColor: Color(0xFFD0D7E5),
            boxShape: neu.NeumorphicBoxShape.circle(),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 20, color: const Color(0xFF667085)),
          ),
        ),
      ),
    );
  }
}

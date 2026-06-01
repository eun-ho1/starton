import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class QuestImageStore {
  const QuestImageStore();

  Future<String> savePickedImage(
    XFile image, {
    required String questId,
    required DateTime completedAt,
  }) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}quest_images',
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final extensionIndex = image.path.lastIndexOf('.');
    final extension =
        extensionIndex >= 0 ? image.path.substring(extensionIndex) : '.jpg';
    final timestamp = completedAt.microsecondsSinceEpoch;
    final savedFile = File(
      '${imageDirectory.path}${Platform.pathSeparator}quest_${questId}_$timestamp$extension',
    );

    await File(image.path).copy(savedFile.path);
    return savedFile.path;
  }
}

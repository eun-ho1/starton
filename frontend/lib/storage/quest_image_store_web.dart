import 'package:image_picker/image_picker.dart';

class QuestImageStore {
  const QuestImageStore();

  Future<String> savePickedImage(
    XFile image, {
    required String questId,
    required DateTime completedAt,
  }) async {
    return image.path;
  }
}

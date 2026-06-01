import 'dart:io';

import 'package:flutter/painting.dart';

ImageProvider<Object> imageProviderForPath(String path) {
  return FileImage(File(path));
}

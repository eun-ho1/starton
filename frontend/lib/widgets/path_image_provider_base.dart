import 'package:flutter/painting.dart';

ImageProvider<Object> imageProviderForPath(String path) {
  return NetworkImage(path);
}

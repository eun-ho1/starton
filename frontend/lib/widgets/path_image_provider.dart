import 'package:flutter/widgets.dart';
import 'package:start_on/widgets/path_image_provider_base.dart'
    if (dart.library.io) 'package:start_on/widgets/path_image_provider_io.dart'
    as provider;

ImageProvider<Object> imageProviderForPath(String path) {
  return provider.imageProviderForPath(path);
}

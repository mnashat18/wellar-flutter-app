import 'package:image_picker/image_picker.dart';

import 'video_compress_stub.dart'
    if (dart.library.io) 'video_compress_io.dart';

Future<XFile> compressVideo(XFile file) => compressVideoImpl(file);

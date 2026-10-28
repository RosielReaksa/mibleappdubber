import 'dart:typed_data';
import 'file_reader_interface.dart';
import 'file_reader_io.dart' if (dart.library.html) 'file_reader_web.dart' as impl;

export 'file_reader_interface.dart';

AppFileReader getFileReader(String path, Uint8List? bytes) {
  return impl.createFileReader(path, bytes);
}

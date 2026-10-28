import 'dart:typed_data';
import 'file_reader_interface.dart';

class MemoryFileReader implements AppFileReader {
  MemoryFileReader(this.bytes);
  final Uint8List bytes;

  @override
  Future<int> getLength() async => bytes.length;

  @override
  Future<Uint8List> readRange(int start, int length) async {
    final end = (start + length > bytes.length) ? bytes.length : start + length;
    return bytes.sublist(start, end);
  }

  @override
  Future<void> close() async {}
}

AppFileReader createFileReader(String path, Uint8List? bytes) {
  return MemoryFileReader(bytes ?? Uint8List(0));
}

import 'dart:io';
import 'dart:typed_data';
import 'file_reader_interface.dart';

class IoFileReader implements AppFileReader {
  IoFileReader(this.path);
  final String path;
  RandomAccessFile? _raf;

  @override
  Future<int> getLength() async {
    return File(path).length();
  }

  @override
  Future<Uint8List> readRange(int start, int length) async {
    _raf ??= await File(path).open();
    await _raf!.setPosition(start);
    return _raf!.read(length);
  }

  @override
  Future<void> close() async {
    await _raf?.close();
    _raf = null;
  }
}

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
  if (bytes != null) {
    return MemoryFileReader(bytes);
  }
  return IoFileReader(path);
}

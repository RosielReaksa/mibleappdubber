import 'dart:typed_data';

abstract class AppFileReader {
  Future<int> getLength();
  Future<Uint8List> readRange(int start, int length);
  Future<void> close();
}

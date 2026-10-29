import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'api_client.dart';
import 'api_error.dart';

/// Downloads [url] and saves it with the Android save dialog (Storage Access
/// Framework), so the file really lands in the folder the user picks
/// (typically Downloads) instead of just claiming it did.
Future<void> downloadAndSaveVideo(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  required String fileName,
}) async {
  if (url.isEmpty) {
    _show(context, 'This video has not finished yet.');
    return;
  }

  _show(context, 'Downloading video…');
  try {
    final dio = ref.read(apiClientProvider).dio;
    final res = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(res.data ?? const <int>[]);

    final savedPath = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: bytes,
    );
    if (!context.mounted) return;
    if (savedPath != null) {
      _show(context, 'Saved to $savedPath');
    } else {
      _show(context, 'Save cancelled.');
    }
  } catch (e) {
    if (!context.mounted) return;
    final err = e is ApiError ? e : ApiClient.toApiError(e);
    _show(context, 'Could not save the video. ${err.message}');
  }
}

void _show(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

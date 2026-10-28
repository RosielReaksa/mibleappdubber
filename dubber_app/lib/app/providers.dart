import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../features/projects/data/dubber_api.dart';

/// Base URL, overridable with --dart-define=API_BASE=...
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: '',
);

String resolveApiBase() {
  if (apiBase.isNotEmpty) return apiBase;
  if (kIsWeb) {
    try {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin.startsWith('http')) {
        return '$origin/v1';
      }
    } catch (_) {}
  }
  return 'https://reaksaccc10--dubber-real-server-web-app.us-east.modal.run/v1';
}

/// Resolves media paths like `/media/xyz.mp4` into full URLs using the active server origin.
String resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  final base = resolveApiBase();
  final origin = base.endsWith('/v1') ? base.substring(0, base.length - 3) : base;
  final cleanPath = url.startsWith('/') ? url : '/$url';
  return '$origin$cleanPath';
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: resolveApiBase(),
    tokens: ref.watch(tokenStoreProvider),
  );
  return client;
});

final apiProvider = Provider<DubberApi>((ref) {
  return DubberApi(ref.watch(apiClientProvider));
});

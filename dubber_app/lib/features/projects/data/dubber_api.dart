import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/api/file_reader.dart';
import '../../library/domain/library_models.dart';
import '../domain/models.dart';

/// The server's answer to adding several videos at once.
class QueueAddResponse {
  const QueueAddResponse({
    required this.nowDubbing,
    required this.upNext,
    required this.rejected,
    this.reservedCredits = 0,
    this.balance,
    this.stoppedReason,
  });

  /// The job the server started, when nothing was running before.
  final Project? nowDubbing;

  /// Everything that was accepted and is now waiting, in order.
  final List<Project> upNext;

  /// Items the server refused, with a machine reason.
  final List<QueueRejection> rejected;

  /// Credits the server actually reserved for this add.
  final int reservedCredits;

  /// Balance after reserving, so the app can update the credits pill.
  final int? balance;

  /// Set when a limit stopped the add part way through, e.g. credits ran out.
  final String? stoppedReason;

  List<Project> get added => [if (nowDubbing != null) nowDubbing!, ...upNext];

  factory QueueAddResponse.fromJson(Map<String, dynamic> j) {
    final now = j['now_dubbing'];
    final upNext = (j['up_next'] as List?) ?? const [];
    final rejected = (j['rejected'] as List?) ?? const [];
    return QueueAddResponse(
      nowDubbing:
          now == null ? null : Project.fromJson((now as Map).cast<String, dynamic>()),
      upNext: upNext
          .map((e) => Project.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      rejected: rejected
          .map((e) => QueueRejection.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      reservedCredits: (j['reserved_credits'] as num?)?.toInt() ?? 0,
      balance: (j['balance'] as num?)?.toInt(),
      stoppedReason: j['stopped_reason'] as String?,
    );
  }
}

/// One refused item from a queue add.
class QueueRejection {
  const QueueRejection({
    required this.fileName,
    required this.code,
    required this.message,
  });

  final String fileName;
  final String code;
  final String message;

  factory QueueRejection.fromJson(Map<String, dynamic> j) => QueueRejection(
        fileName: j['file_name'] as String? ?? '',
        code: j['code'] as String? ?? 'rejected',
        message: j['message'] as String? ?? 'This file was not added.',
      );
}

/// Talks to the Dubber server. Never returns raw maps.
class DubberApi {
  DubberApi(this._client);

  final ApiClient _client;

  Dio get _dio => _client.dio;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw ApiClient.toApiError(e);
    }
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  Future<({String access, String refresh})> login({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': email, 'password': password},
        );
        final d = res.data ?? const {};
        return (
          access: d['access_token'] as String? ?? '',
          refresh: d['refresh_token'] as String? ?? '',
        );
      });

  Future<({String access, String refresh})> register({
    required String name,
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/register',
          data: {'name': name, 'email': email, 'password': password},
        );
        final d = res.data ?? const {};
        return (
          access: d['access_token'] as String? ?? '',
          refresh: d['refresh_token'] as String? ?? '',
        );
      });

  Future<void> forgotPassword(String email) => _guard(() async {
        await _dio.post('/auth/forgot-password', data: {'email': email});
      });

  Future<Map<String, dynamic>> me() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/me');
        return res.data ?? const {};
      });

  // ── Content ─────────────────────────────────────────────────────────────
  Future<List<Language>> languages() => _guard(() async {
        final res = await _dio.get<dynamic>('/languages');
        final list = res.data is List ? res.data as List : const [];
        return list
            .map((e) => Language.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<List<Voice>> voices() => _guard(() async {
        final res = await _dio.get<dynamic>('/voices');
        final list = res.data is List ? res.data as List : const [];
        return list
            .map((e) => Voice.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<List<Template>> templates() => _guard(() async {
        final res = await _dio.get<dynamic>('/templates');
        final list = res.data is List ? res.data as List : const [];
        return list
            .map((e) => Template.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  // ── Projects ────────────────────────────────────────────────────────────
  Future<List<Project>> projects() => _guard(() async {
        final res = await _dio.get<dynamic>('/projects');
        final list = res.data is List ? res.data as List : const [];
        return list
            .map((e) => Project.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<Project> project(String id) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/projects/$id');
        return Project.fromJson(res.data ?? const {});
      });

  Future<void> deleteProject(String id) => _guard(() async {
        await _dio.delete('/projects/$id');
      });

  /// Cancels a running job. Assumed endpoint: `DELETE /projects/{id}`.
  Future<void> cancelProject(String id) => deleteProject(id);

  /// The job that is currently processing or queued, if any.
  ///
  /// Returns null when the user has nothing active, which is when the New
  /// screen may start a job. The server is the source of truth; this is only
  /// used to decide what the screen shows.
  Future<Project?> activeProject() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/queue/active');
        final data = res.data?['project'];
        if (data == null) return null;
        return Project.fromJson((data as Map).cast<String, dynamic>());
      });

  /// The full queue, in server order, with positions.
  ///
  /// Shape: `{ "now_dubbing": Project?, "up_next": [Project, ...],
  /// "failed": [Project, ...], "slots_left": int }` where each item in
  /// `up_next` carries a `position`, and failed items carry a `reason`.
  Future<
      ({
        Project? nowDubbing,
        List<Project> upNext,
        List<Project> failed,
        int slotsLeft,
      })> queue() =>
      _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/queue');
        final d = res.data ?? const {};
        final now = d['now_dubbing'];
        final upNext = (d['up_next'] as List?) ?? const [];
        final failed = (d['failed'] as List?) ?? const [];
        return (
          nowDubbing:
              now == null ? null : Project.fromJson((now as Map).cast<String, dynamic>()),
          upNext: upNext
              .map((e) => Project.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
          failed: failed
              .map((e) => Project.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
          slotsLeft: (d['slots_left'] as num?)?.toInt() ?? 0,
        );
      });

  /// Adds several uploaded videos to the queue.
  ///
  /// Each item carries its `upload_id`, settings and its own idempotency key,
  /// so retrying an add never creates the same job twice. The server checks
  /// credits and the queue limit per item, in order, and stops when either
  /// runs out — accepted items stay added.
  Future<QueueAddResponse> addToQueue({
    required List<Map<String, dynamic>> items,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/queue/items',
          data: {'items': items},
        );
        return QueueAddResponse.fromJson(res.data ?? const {});
      });

  /// Removes one item from the queue. Credits for it are returned.
  Future<void> removeFromQueue(String projectId) => _guard(() async {
        await _dio.delete('/queue/items/$projectId');
      });

  /// Moves an item to the front of the queue.
  Future<void> moveToTop(String projectId) => _guard(() async {
        await _dio.post('/queue/items/$projectId/move', data: {'to': 'top'});
      });

  /// Reorders the queue. [orderedIds] is the full list, front to back.
  Future<void> reorderQueue(List<String> orderedIds) => _guard(() async {
        await _dio.put('/queue/order', data: {'order': orderedIds});
      });

  /// Starts a failed job again with the same settings and upload.
  Future<Project> retryQueueItem(String projectId) => _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/queue/items/$projectId/retry',
        );
        return Project.fromJson(res.data ?? const {});
      });

  /// Estimate the credit price of one file. Multiply by the batch size.
  Future<int> estimate({
    required String sourceLanguage,
    required String targetLanguage,
    required VideoFormat format,
    required VoiceChoice voice,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/projects/estimate',
          data: {
            'source_language': sourceLanguage,
            'target_language': targetLanguage,
            'format': format.wire,
            'voice': voice.wire,
          },
        );
        return (res.data?['credits'] as num?)?.toInt() ?? 0;
      });

  Future<Project> createProject({
    required String uploadId,
    required String sourceLanguage,
    required String targetLanguage,
    required VideoFormat format,
    required VoiceChoice voice,
    required AudioMix mix,
    required String idempotencyKey,
    String? templateId,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/projects',
          data: {
            'upload_id': uploadId,
            'source_language': sourceLanguage,
            'target_language': targetLanguage,
            'format': format.wire,
            'voice': voice.wire,
            'mix': mix.toJson(),
            'template_id': templateId,
            'idempotency_key': idempotencyKey,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Project.fromJson(res.data ?? const {});
      });

  Future<JobProgress> job(String id) => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/jobs/$id');
        return JobProgress.fromJson(res.data ?? const {});
      });

  Future<void> updateMix(String projectId, AudioMix mix) => _guard(() async {
        await _dio.put('/projects/$projectId/mix', data: {'mix': mix.toJson()});
      });

  /// Sends the edit settings and starts a server-side render.
  Future<String> startExport({
    required String projectId,
    required Map<String, dynamic> settings,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/projects/$projectId/exports',
          data: settings,
        );
        return res.data?['id'] as String? ?? '';
      });

  /// Export status; returns `(status, percent, downloadUrl)`.
  Future<({String status, int percent, String? downloadUrl, String? reason})>
      exportStatus(String exportId) => _guard(() async {
            final res = await _dio.get<Map<String, dynamic>>('/exports/$exportId');
            final d = res.data ?? const {};
            return (
              status: d['status'] as String? ?? 'processing',
              percent: (d['percent'] as num?)?.toInt() ?? 0,
              downloadUrl: d['download_url'] as String?,
              reason: d['reason'] as String?,
            );
          });

  // ── Upload (chunked, resumable) ─────────────────────────────────────────
  /// Uploads [path] in parts and returns the completed upload id.
  ///
  /// [onProgress] receives 0..1. Progress is reported per completed part so a
  /// dropped connection resumes from the last finished part.
  Future<String> uploadFile({
    required String path,
    required String fileName,
    required String mime,
    Uint8List? bytesData,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final reader = getFileReader(path, bytesData);
    final size = await reader.getLength();

    final start = await _dio.post<Map<String, dynamic>>(
      '/uploads',
      data: {'file_name': fileName, 'size': size, 'mime': mime},
      cancelToken: cancelToken,
    );
    final data = start.data ?? const {};
    final id = data['id'] as String? ?? '';
    final partSize = (data['part_size'] as num?)?.toInt() ?? (8 * 1024 * 1024);
    final totalParts =
        (data['parts'] as num?)?.toInt() ?? (size / partSize).ceil();

    try {
      for (var part = 1; part <= totalParts; part++) {
        final offset = (part - 1) * partSize;
        final length = (offset + partSize > size) ? size - offset : partSize;
        final bytes = await reader.readRange(offset, length);

        await _putWithRetry(
          url: '/uploads/$id/parts/$part',
          bytes: bytes,
          cancelToken: cancelToken,
        );
        onProgress?.call(part / totalParts);
      }
    } finally {
      await reader.close();
    }

    final done = await _dio.post<Map<String, dynamic>>(
      '/uploads/$id/complete',
      cancelToken: cancelToken,
    );
    return done.data?['upload_id'] as String? ?? id;
  }

  /// Retries a part up to 5 times with exponential backoff.
  Future<void> _putWithRetry({
    required String url,
    required List<int> bytes,
    CancelToken? cancelToken,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        await _dio.put<void>(
          url,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {
              Headers.contentLengthHeader: bytes.length,
              Headers.contentTypeHeader: 'application/octet-stream',
            },
          ),
          cancelToken: cancelToken,
        );
        return;
      } catch (e) {
        attempt++;
        final error = ApiClient.toApiError(e);
        if (attempt >= 5 || !error.retryable) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
      }
    }
  }

  // ── Credits ─────────────────────────────────────────────────────────────
  Future<({int balance, List<CreditPack> packs})> credits() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/credits');
        final d = res.data ?? const {};
        final packs = (d['packs'] as List?)
                ?.map((e) => CreditPack.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const <CreditPack>[];
        return (balance: (d['balance'] as num?)?.toInt() ?? 0, packs: packs);
      });

  // ── Library (TODO(server): these endpoints are assumed) ─────────────────
  //
  // Implemented here so the repositories are one line away from live data.
  // Until the server answers, each call surfaces a 404 ApiError and the
  // repositories keep everything in the local store instead.

  /// `GET /assets/logos`.
  Future<List<Map<String, dynamic>>> libraryLogos() => _guard(() async {
        final res = await _dio.get<dynamic>('/assets/logos');
        final list = res.data is List ? res.data as List : const [];
        return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      });

  /// `POST /assets/logos` (multipart) — returns the created logo.
  Future<Map<String, dynamic>> uploadLibraryLogo({
    required String path,
    required String fileName,
    required String name,
  }) =>
      _guard(() async {
        final form = FormData.fromMap({
          'name': name,
          'file': await MultipartFile.fromFile(path, filename: fileName),
        });
        final res =
            await _dio.post<Map<String, dynamic>>('/assets/logos', data: form);
        return res.data ?? const {};
      });

  /// `POST /assets/logos` for a logo that already exists on the server (for
  /// example one picked from the device before the file upload completed).
  Future<Map<String, dynamic>> createLibraryLogoRecord(SavedLogo item) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/assets/logos',
          data: {'name': item.name, 'url': item.url},
        );
        return res.data ?? const {};
      });

  /// `PUT /assets/logos/{id}` — renames a saved logo.
  Future<void> updateLibraryLogo(String id, {required String itemName}) =>
      _guard(() async {
        await _dio.put('/assets/logos/$id', data: {'name': itemName});
      });

  /// `DELETE /assets/logos/{id}`.
  Future<void> deleteLibraryLogo(String id) => _guard(() async {
        await _dio.delete('/assets/logos/$id');
      });

  /// `GET /styles`.
  Future<List<Map<String, dynamic>>> libraryStyles() => _guard(() async {
        final res = await _dio.get<dynamic>('/styles');
        final list = res.data is List ? res.data as List : const [];
        return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      });

  /// `POST /styles`.
  Future<Map<String, dynamic>> createLibraryStyle(Map<String, dynamic> body) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/styles', data: body);
        return res.data ?? const {};
      });

  /// `PUT /styles/{id}`.
  Future<void> updateLibraryStyle(String id, Map<String, dynamic> body) =>
      _guard(() async {
        await _dio.put('/styles/$id', data: body);
      });

  /// `DELETE /styles/{id}`.
  Future<void> deleteLibraryStyle(String id) => _guard(() async {
        await _dio.delete('/styles/$id');
      });

  /// `GET /presets`.
  Future<List<Map<String, dynamic>>> libraryPresets() => _guard(() async {
        final res = await _dio.get<dynamic>('/presets');
        final list = res.data is List ? res.data as List : const [];
        return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
      });

  /// `POST /presets`.
  Future<Map<String, dynamic>> createLibraryPreset(Map<String, dynamic> body) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>('/presets', data: body);
        return res.data ?? const {};
      });

  /// `PUT /presets/{id}`.
  Future<void> updateLibraryPreset(String id, Map<String, dynamic> body) =>
      _guard(() async {
        await _dio.put('/presets/$id', data: body);
      });

  /// `DELETE /presets/{id}`.
  Future<void> deleteLibraryPreset(String id) => _guard(() async {
        await _dio.delete('/presets/$id');
      });
}

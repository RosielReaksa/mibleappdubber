import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bspatch/flutter_bspatch.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:io';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';

/// Cloud fallback used when the local development server is unreachable.
const _cloudBase =
    'https://reaksaccc10--dubber-real-server-web-app.us-east.modal.run/v1';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.apkSha256,
    required this.apkSize,
    required this.patches,
    required this.changelog,
    required this.forceUpdate,
    required this.baseUrl,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String apkSha256;
  final int apkSize;
  final List<AppUpdatePatch> patches;
  final String changelog;
  final bool forceUpdate;

  /// Server origin the update info came from; the APK is fetched from here.
  final String baseUrl;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json, String baseUrl) {
    return AppUpdateInfo(
      versionName: json['version_name'] as String? ?? '1.0.0',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 1,
      apkUrl: json['apk_url'] as String? ?? '/media/dubber-app.apk',
      apkSha256: json['apk_sha256'] as String? ?? '',
      apkSize: (json['apk_size'] as num?)?.toInt() ?? 0,
      patches: (json['patches'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((patch) => AppUpdatePatch.fromJson(patch, baseUrl))
          .toList(growable: false),
      changelog:
          json['changelog'] as String? ??
          'Bug fixes and performance improvements.',
      forceUpdate: json['force_update'] as bool? ?? false,
      baseUrl: baseUrl,
    );
  }

  /// Absolute APK URL, resolved against the server that reported the update.
  String get absoluteApkUrl {
    if (apkUrl.startsWith('http://') || apkUrl.startsWith('https://')) {
      return apkUrl;
    }
    final origin = baseUrl.endsWith('/v1')
        ? baseUrl.substring(0, baseUrl.length - 3)
        : baseUrl;
    return apkUrl.startsWith('/') ? '$origin$apkUrl' : '$origin/$apkUrl';
  }

  AppUpdatePatch? patchFrom(int versionCode) {
    for (final patch in patches) {
      if (patch.fromVersionCode == versionCode &&
          patch.targetApkSha256 == apkSha256) {
        return patch;
      }
    }
    return null;
  }
}

class AppUpdatePatch {
  const AppUpdatePatch({
    required this.fromVersionCode,
    required this.baseApkSha256,
    required this.patchUrl,
    required this.patchSha256,
    required this.patchSize,
    required this.targetApkSha256,
    required this.targetApkSize,
    required this.baseUrl,
  });

  final int fromVersionCode;
  final String baseApkSha256;
  final String patchUrl;
  final String patchSha256;
  final int patchSize;
  final String targetApkSha256;
  final int targetApkSize;
  final String baseUrl;

  factory AppUpdatePatch.fromJson(Map<String, dynamic> json, String baseUrl) =>
      AppUpdatePatch(
        fromVersionCode: (json['from_version_code'] as num?)?.toInt() ?? 0,
        baseApkSha256: json['base_apk_sha256'] as String? ?? '',
        patchUrl: json['patch_url'] as String? ?? '',
        patchSha256: json['patch_sha256'] as String? ?? '',
        patchSize: (json['patch_size'] as num?)?.toInt() ?? 0,
        targetApkSha256: json['target_apk_sha256'] as String? ?? '',
        targetApkSize: (json['target_apk_size'] as num?)?.toInt() ?? 0,
        baseUrl: json['base_url'] as String? ?? baseUrl,
      );

  String get absolutePatchUrl {
    if (patchUrl.startsWith('http://') || patchUrl.startsWith('https://')) {
      return patchUrl;
    }
    final root = baseUrl.endsWith('/v1')
        ? baseUrl.substring(0, baseUrl.length - 3)
        : baseUrl;
    return patchUrl.startsWith('/') ? '$root$patchUrl' : '$root/$patchUrl';
  }
}

/// Result of one update check, so the UI can show a persistent banner.
enum UpdateCheckResult { updateAvailable, upToDate, unreachable }

class AppUpdateChecker {
  static DateTime? _lastAutoCheck;

  /// Cached pending update, exposed as a notifier so any banner listening to
  /// it rebuilds the moment a check finds a newer version.
  static final ValueNotifier<AppUpdateInfo?> pendingUpdateNotifier =
      ValueNotifier<AppUpdateInfo?>(null);

  static AppUpdateInfo? get pendingUpdate => pendingUpdateNotifier.value;
  static set pendingUpdate(AppUpdateInfo? value) =>
      pendingUpdateNotifier.value = value;

  static String currentVersion = '';
  static int currentBuildCode = 1;

  /// Checks for an update.
  ///
  /// [manual] forces a check even if one just ran and reports the outcome to
  /// the user. Auto checks are throttled to once per app launch / 10 minutes.
  static Future<UpdateCheckResult> check(
    BuildContext context,
    WidgetRef ref, {
    bool manual = false,
    bool showDialog = true,
  }) async {
    if (kIsWeb) return UpdateCheckResult.unreachable;

    // Capture the Dio instance before any await: using `ref` after the widget
    // was disposed throws and would kill the update check.
    final dio = ref.read(apiClientProvider).dio;

    if (!manual) {
      final last = _lastAutoCheck;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 10)) {
        return pendingUpdate != null
            ? UpdateCheckResult.updateAvailable
            : UpdateCheckResult.upToDate;
      }
    }
    _lastAutoCheck = DateTime.now();

    final info = await PackageInfo.fromPlatform();
    currentVersion = '${info.version}+${info.buildNumber}';
    final currentCode = int.tryParse(info.buildNumber) ?? 1;
    currentBuildCode = currentCode;

    // Try the configured server first, then the cloud fallback, so the check
    // still works when the phone is not on the developer hotspot.
    final bases = <String>{resolveApiBase(), _cloudBase}.toList();

    for (final base in bases) {
      final data = await _fetchVersion(dio, base);
      if (data == null) continue;

      final updateInfo = AppUpdateInfo.fromJson(data, base);
      if (updateInfo.versionCode > currentCode) {
        pendingUpdate = updateInfo;
        if (showDialog && context.mounted) {
          _showUpdateDialog(context, updateInfo);
        }
        return UpdateCheckResult.updateAvailable;
      }

      pendingUpdate = null;
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dubber is up to date (v${info.version}).')),
        );
      }
      return UpdateCheckResult.upToDate;
    }

    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reach the update server. Check your connection.',
          ),
        ),
      );
    }
    return UpdateCheckResult.unreachable;
  }

  static Future<Map<String, dynamic>?> _fetchVersion(
    Dio dio,
    String base,
  ) async {
    try {
      // Build the absolute URL ourselves: the shared Dio instance carries the
      // default base URL, and Dio has no per-request baseUrl override.
      final root = base.endsWith('/v1')
          ? base.substring(0, base.length - 3)
          : base;
      final res = await dio.get<Map<String, dynamic>>(
        '$root/v1/version',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          extra: {'retried': true},
        ),
      );
      return res.data;
    } catch (e) {
      debugPrint('Version check failed for $base: $e');
      return null;
    }
  }

  static void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }

  /// Opens the update dialog for the cached pending update, if any.
  static void showPendingUpdate(BuildContext context) {
    final info = pendingUpdate;
    if (info == null) return;
    _showUpdateDialog(context, info);
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final AppUpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  String _progress = '0%';
  double _progressValue = 0.0;
  String? _error;
  String _stage = 'Downloading update...';

  static const _nativeUpdater = MethodChannel('com.dubber.dubber_app/update');

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = '0%';
      _progressValue = 0.0;
      _stage = 'Checking for a smaller update...';
    });

    final currentCode = AppUpdateChecker.currentBuildCode;
    final patch = Platform.isAndroid
        ? widget.info.patchFrom(currentCode)
        : null;
    if (patch != null) {
      try {
        await _downloadApplyAndInstallPatch(patch);
        return;
      } catch (e) {
        debugPrint('Delta update failed; using full APK: $e');
        if (!mounted) return;
        setState(() {
          _stage = 'Patch unavailable. Downloading the complete update...';
          _progress = '0%';
          _progressValue = 0.0;
        });
      }
    }

    await _downloadAndInstallFullApk();
  }

  Future<void> _downloadApplyAndInstallPatch(AppUpdatePatch patch) async {
    if (patch.patchUrl.isEmpty ||
        patch.baseApkSha256.isEmpty ||
        patch.patchSha256.isEmpty ||
        patch.targetApkSha256.isEmpty ||
        patch.targetApkSha256 != widget.info.apkSha256) {
      throw StateError('The server returned incomplete patch metadata.');
    }

    setState(() {
      _stage =
          'Downloading smaller update (${_formatBytes(patch.patchSize)})...';
    });
    final installedPath = await _nativeUpdater.invokeMethod<String>(
      'getInstalledApkPath',
    );
    if (installedPath == null || installedPath.isEmpty) {
      throw StateError('Could not read the installed APK for patching.');
    }
    final installedApk = File(installedPath);
    if (!await installedApk.exists() ||
        await _sha256OfFile(installedApk) != patch.baseApkSha256) {
      throw StateError('The installed APK does not match this patch.');
    }

    final support = await getApplicationSupportDirectory();
    final updateDir = Directory(
      '${support.path}${Platform.pathSeparator}ota_update',
    );
    await updateDir.create(recursive: true);
    final patchFile = File(
      '${updateDir.path}${Platform.pathSeparator}update.patch',
    );
    final outputApk = File(
      '${updateDir.path}${Platform.pathSeparator}dubber_update.apk',
    );
    await patchFile.delete().catchError((_) => patchFile);
    await outputApk.delete().catchError((_) => outputApk);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        followRedirects: true,
      ),
    );
    await dio.download(
      patch.absolutePatchUrl,
      patchFile.path,
      onReceiveProgress: (received, total) {
        if (!mounted || total <= 0) return;
        final fraction = (received / total).clamp(0.0, 1.0);
        setState(() {
          _stage =
              'Downloading smaller update (${_formatBytes(patch.patchSize)})...';
          _progressValue = fraction * 0.65;
          _progress = '${(fraction * 65).round()}%';
        });
      },
    );
    if (patch.patchSize > 0 && await patchFile.length() != patch.patchSize) {
      throw StateError('The downloaded patch has an unexpected size.');
    }
    if (await _sha256OfFile(patchFile) != patch.patchSha256) {
      throw StateError('The downloaded patch failed its SHA-256 check.');
    }

    if (!mounted) return;
    setState(() {
      _stage = 'Applying and verifying update...';
      _progressValue = 0.72;
      _progress = 'Applying...';
    });
    await BsPatch.patch(
      oldFile: installedApk.path,
      patchFile: patchFile.path,
      newFile: outputApk.path,
    );
    if (patch.targetApkSize > 0 &&
        await outputApk.length() != patch.targetApkSize) {
      throw StateError('The reconstructed APK has an unexpected size.');
    }
    if (await _sha256OfFile(outputApk) != patch.targetApkSha256) {
      throw StateError('The reconstructed APK failed its SHA-256 check.');
    }

    if (!mounted) return;
    setState(() {
      _stage = 'Opening Android installer...';
      _progressValue = 1.0;
      _progress = 'Installing...';
    });
    await _nativeUpdater.invokeMethod<void>('installPatchedApk', {
      'path': outputApk.path,
    });
  }

  Future<void> _downloadAndInstallFullApk() async {
    final stream = OtaUpdate().execute(
      widget.info.absoluteApkUrl,
      destinationFilename: 'dubber_update.apk',
      androidProviderAuthority: 'com.dubber.dubber_app.ota_update_provider',
      sha256checksum: widget.info.apkSha256.isEmpty
          ? null
          : widget.info.apkSha256,
    );
    try {
      await for (final event in stream) {
        if (!mounted) return;
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            final pct = int.tryParse(event.value ?? '0') ?? 0;
            setState(() {
              _stage = widget.info.apkSize > 0
                  ? 'Downloading complete update (${_formatBytes(widget.info.apkSize)})...'
                  : 'Downloading complete update...';
              _progress = '$pct%';
              _progressValue = pct / 100.0;
            });
            break;
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            setState(() {
              _stage = 'Installing...';
              _progress = 'Installing...';
              _progressValue = 1.0;
            });
            break;
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            setState(() {
              _downloading = false;
              _error =
                  'Allow installing from this app in Android settings, then tap Update again.';
            });
            break;
          default:
            setState(() {
              _downloading = false;
              _error = 'Update failed (${event.status.name}).';
            });
            break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Could not download or start the complete update.';
      });
      debugPrint('Full APK update failed: $e');
    }
  }

  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'unknown size';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Tokens.softClay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: Tokens.clayButton,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Update Dubber', style: AppText.pageTitle())),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${widget.info.versionName} is available.',
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            widget.info.changelog,
            style: AppText.caption.copyWith(color: Tokens.muted, height: 1.4),
          ),
          if (_downloading) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_stage, style: AppText.caption),
                Text(
                  _progress,
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              child: LinearProgressIndicator(
                value: _progressValue,
                minHeight: 8,
                backgroundColor: Tokens.oat,
                valueColor: const AlwaysStoppedAnimation(Tokens.clayButton),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
        ],
      ),
      actions: [
        if (!widget.info.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Later',
              style: AppText.label.copyWith(color: Tokens.muted),
            ),
          ),
        if (!_downloading)
          FilledButton(
            onPressed: _startUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: Tokens.clayButton,
              foregroundColor: Tokens.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
              ),
            ),
            child: Text(_error == null ? 'Update now' : 'Try again'),
          ),
      ],
    );
  }
}

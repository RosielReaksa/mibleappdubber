import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';

/// Cloud fallback used when the local development server is unreachable.
const _cloudBase = 'https://reaksaccc10--dubber-real-server-web-app.us-east.modal.run/v1';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.changelog,
    required this.forceUpdate,
    required this.baseUrl,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String changelog;
  final bool forceUpdate;

  /// Server origin the update info came from; the APK is fetched from here.
  final String baseUrl;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json, String baseUrl) {
    return AppUpdateInfo(
      versionName: json['version_name'] as String? ?? '1.0.0',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 1,
      apkUrl: json['apk_url'] as String? ?? '/media/dubber-app.apk',
      changelog:
          json['changelog'] as String? ?? 'Bug fixes and performance improvements.',
      forceUpdate: json['force_update'] as bool? ?? false,
      baseUrl: baseUrl,
    );
  }

  /// Absolute APK URL, resolved against the server that reported the update.
  String get absoluteApkUrl {
    if (apkUrl.startsWith('http://') || apkUrl.startsWith('https://')) {
      return apkUrl;
    }
    final origin =
        baseUrl.endsWith('/v1') ? baseUrl.substring(0, baseUrl.length - 3) : baseUrl;
    return apkUrl.startsWith('/') ? '$origin$apkUrl' : '$origin/$apkUrl';
  }
}

/// Result of one update check, so the UI can show a persistent banner.
enum UpdateCheckResult { updateAvailable, upToDate, unreachable }

class AppUpdateChecker {
  static DateTime? _lastAutoCheck;

  /// Cached pending update, so a banner can be shown without re-checking.
  static AppUpdateInfo? pendingUpdate;
  static String currentVersion = '';

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

    // Try the configured server first, then the cloud fallback, so the check
    // still works when the phone is not on the developer hotspot.
    final bases = <String>{
      resolveApiBase(),
      _cloudBase,
    }.toList();

    for (final base in bases) {
      final data = await _fetchVersion(ref, base);
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
          SnackBar(
            content: Text('Dubber is up to date (v${info.version}).'),
          ),
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
    WidgetRef ref,
    String base,
  ) async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      // Build the absolute URL ourselves: the shared Dio instance carries the
      // default base URL, and Dio has no per-request baseUrl override.
      final root =
          base.endsWith('/v1') ? base.substring(0, base.length - 3) : base;
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

  void _startUpdate() {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = '0%';
      _progressValue = 0.0;
    });

    final downloadUrl = widget.info.absoluteApkUrl;

    try {
      OtaUpdate()
          .execute(
            downloadUrl,
            destinationFilename: 'dubber_update.apk',
            androidProviderAuthority: 'com.dubber.dubber_app.ota_update_provider',
          )
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = int.tryParse(event.value ?? '0') ?? 0;
              setState(() {
                _progress = '${event.value}%';
                _progressValue = pct / 100.0;
              });
              break;
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              setState(() {
                _progress = 'Installing...';
                _progressValue = 1.0;
              });
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() {
                _downloading = false;
                _error = 'Allow installing from this app in Android settings, '
                    'then tap Update again.';
              });
              break;
            default:
              setState(() {
                _downloading = false;
                _error = 'Update failed (${event.status.name}).';
              });
              break;
          }
        },
        onError: (dynamic err) {
          if (!mounted) return;
          setState(() {
            _downloading = false;
            _error = 'Download failed. Check your connection and try again.';
          });
        },
      );
    } catch (e) {
      setState(() {
        _downloading = false;
        _error = 'Could not start the download.';
      });
    }
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
            child: const Icon(Icons.system_update_rounded,
                color: Tokens.clayButton, size: 20),
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
                Text('Downloading update...', style: AppText.caption),
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

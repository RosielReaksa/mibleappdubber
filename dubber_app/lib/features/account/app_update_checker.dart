import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String changelog;
  final bool forceUpdate;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      versionName: json['version_name'] as String? ?? '1.0.0',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 1,
      apkUrl: json['apk_url'] as String? ?? '/media/dubber-app.apk',
      changelog: json['changelog'] as String? ?? 'Bug fixes and performance improvements.',
      forceUpdate: json['force_update'] as bool? ?? false,
    );
  }
}

class AppUpdateChecker {
  static bool _checked = false;

  /// Checks if a newer version is available and shows the in-app update dialog.
  static Future<void> check(BuildContext context, WidgetRef ref, {bool manual = false}) async {
    if ((_checked && !manual) || kIsWeb) return;
    _checked = true;

    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get<Map<String, dynamic>>('/version');
      final data = response.data;
      if (data == null) {
        if (manual && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not reach update server.')),
          );
        }
        return;
      }

      final updateInfo = AppUpdateInfo.fromJson(data);
      final currentInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(currentInfo.buildNumber) ?? 1;

      if (updateInfo.versionCode > currentCode) {
        if (!context.mounted) return;
        _showUpdateDialog(context, updateInfo);
      } else if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dubber is up to date! (v1.0.4)')),
        );
      }
    } catch (e) {
      debugPrint('Auto-update check ignored: $e');
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e')),
        );
      }
    }
  }

  static void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => _UpdateDialog(info: info),
    );
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
    });

    final downloadUrl = resolveMediaUrl(widget.info.apkUrl);

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
            default:
              setState(() {
                _downloading = false;
                _error = 'Update status: ${event.status.name}';
              });
              break;
          }
        },
        onError: (dynamic err) {
          if (!mounted) return;
          setState(() {
            _downloading = false;
            _error = 'Download failed. Please check network.';
          });
        },
      );
    } catch (e) {
      setState(() {
        _downloading = false;
        _error = 'Failed to start download.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Tokens.softClay,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded, color: Tokens.clayButton, size: 20),
          ),
          const SizedBox(width: 12),
          Text('Update Dubber', style: AppText.pageTitle()),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A new version (${widget.info.versionName}) is ready.',
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            widget.info.changelog,
            style: AppText.caption.copyWith(color: Tokens.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_downloading) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Downloading update...', style: AppText.caption),
                Text(_progress, style: AppText.caption.copyWith(fontWeight: FontWeight.w600)),
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
            const SizedBox(height: 10),
            Text(_error!, style: AppText.caption.copyWith(color: Tokens.clayDeep)),
          ],
        ],
      ),
      actions: [
        if (!widget.info.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Later', style: AppText.label.copyWith(color: Tokens.muted)),
          ),
        if (!_downloading)
          PrimaryButton(
            label: 'Update now',
            onPressed: _startUpdate,
          ),
      ],
    );
  }
}

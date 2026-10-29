import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../app_update_checker.dart';

/// Small persistent banner shown above a tab when an update is available.
///
/// It listens to [AppUpdateChecker.pendingUpdateNotifier] so it appears the
/// moment a version check finds a newer build, without a full app restart.
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateInfo?>(
      valueListenable: AppUpdateChecker.pendingUpdateNotifier,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Material(
            color: Tokens.softClay,
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            child: InkWell(
              onTap: onTap ?? () => AppUpdateChecker.showPendingUpdate(context),
              borderRadius: BorderRadius.circular(Tokens.radiusCard),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Tokens.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        size: 18,
                        color: Tokens.clayButton,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update available · v${info.versionName}',
                            style: AppText.label.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Tokens.clayDeep,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to install the new version',
                            style:
                                AppText.caption.copyWith(color: Tokens.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Tokens.clayButton),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

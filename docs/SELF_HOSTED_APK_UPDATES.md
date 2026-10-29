# Self-hosted Android delta updates

Dubber's update endpoint serves the normal signed APK plus optional BSDIFF40
patch metadata. The app downloads a patch only when its installed `versionCode`
and installed APK SHA-256 match the patch base. It checks the patch hash, applies
it to Android's installed APK, verifies the rebuilt APK hash and size, then
opens Android's package installer. Any mismatch or patch error falls back to
the full APK.

## First rollout

Version 1.0.12 (2013) is the first build with the patch applier. Devices on
older builds must download this full APK once because those apps cannot apply
patch files. Later releases can use delta updates.

## Package a release

Keep the previous signed APK at a known path before replacing the server's
current APK. Increase `version` in `dubber_app/pubspec.yaml`, then build the
release APK. Package it with the previous version as the patch base:

```powershell
python -m pip install -r tools/update-requirements.txt
python tools/package_android_update.py `
  --from-apk server/data/update_bases/dubber-app-2013.apk `
  --from-code 2013 `
  --to-apk dubber_app/build/app/outputs/flutter-apk/app-release.apk `
  --to-code 2014 `
  --to-version-name 1.0.13 `
  --changelog "Describe the release"
```

The script creates `server/media/dubber-app.apk`, an optional
`server/media/updates/*.patch`, and `server/app_update_manifest.json`. It
round-trip-checks the delta before publishing it and skips the patch when it is
not at least 15% smaller than the full APK. Keep the same Android signing key
for every release; Android rejects updates signed by a different key.

Deploy the APK, patch directory, manifest, and server code together. Keep the
previous APK archive (`server/data/update_bases/`) for the next release. Users
on versions older than the patch base safely receive the full APK.

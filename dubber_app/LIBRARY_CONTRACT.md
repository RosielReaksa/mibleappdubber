# Library feature — shared contract for parallel work

Read this before writing any code. The foundation below already exists and
compiles as of commit-less working tree. **Do not modify foundation files**;
build only the files assigned to you.

## Files that exist (owned by the lead — do not edit)

```
lib/features/library/domain/library_models.dart      SavedLogo, SavedStyle, StyleKind, Preset
lib/features/library/data/library_local_store.dart   LibraryLocalStore, PrefsLibraryLocalStore, MemoryLibraryLocalStore
lib/features/library/data/library_repository.dart    LibraryRepository<T>, Loaded, MutationResult/Ok/Local/Failed, DataOrigin
lib/features/library/application/library_controller.dart
                                                    LibraryPhase, LibraryState<T>, LibraryController<T>, providers
lib/features/library/widgets/library_widgets.dart    LibraryHeader, LibrarySections, LibrarySection, OfflineBanner,
                                                    LibraryBody<T>, showNameDialog, confirmDelete, showLibrarySnack,
                                                    mutationMessage, isOfflineError, LibrarySectionX.fromWire
lib/features/library/library_screen.dart             shell (lead fills in the switch)
```

## Design tokens — use ONLY these

`lib/app/theme/tokens.dart` → `Tokens` (ivory, ink, muted, clay, clayButton,
softClay, oat, border, borderStrong, white, doneText/doneBg, workingText/workingBg,
uploadBorder, clayDeep, segmentBg, bodyOnChip; radiusCard 20, radiusButton 14,
radiusField 14, radiusPill; screenPadding 20, buttonHeight 52, minTouchTarget 44)
and `AppText` (display(n), screenTitle, pageTitle, sheetTitle, body, bodyMuted,
label, labelMuted, caption, button, chip).

Fonts: headings Newsreader w500, body/buttons Inter. Never introduce a new color.

## Existing shared widgets — reuse, do not reinvent

- `core/widgets/app_widgets.dart`: `PrimaryButton(label,onPressed,loading)`,
  `SecondaryButton(label,onPressed,icon)`, `NeutralButton`, `AppCard(child,padding,radius,selected)`,
  `AppTextField(label,controller,hint,onChanged,...)`
- `core/widgets/controls.dart`: `SegmentedControl<T>(options,value,onChanged)`,
  `AppChip(label,selected,onTap,icon)`, `MixSlider(label,value,onChanged)`,
  `ListTileCard(child,onTap,onLongPress,padding)`
- `core/widgets/status_chip.dart`: `StatusChip`, `StatusPill`, `AppBarRow`, `StateView(title,message,mood,actionLabel,onAction,compact)`
- `core/widgets/dubber_character.dart`: `DubberCharacter(size, mood)`, `CharacterMood.happy|worried`

## State contract

`LibraryState<T>` has `phase` (`loading|empty|ready|error`), `items`, `error`,
`offline`, `busy`, and `canMutate => !offline && !busy`.

`LibraryController<T>` exposes `load()`, `create(item)`, `rename(id,name)`,
`delete(id)` — each returns `Future<MutationResult>`. After a mutation the
controller re-reads local storage, so `state.items` is authoritative.

Providers: `logoLibraryProvider`, `styleLibraryProvider`, `presetLibraryProvider`
(`StateNotifierProvider<LibraryController<X>, LibraryState<X>>`), plus the
repository providers.

**Every section MUST render all four states** via `LibraryBody<T>`, passing
`errorTitle`/`onRetry` and `emptyTitle`/`emptyMessage`/`emptyAction`/`onAction`,
and must show `OfflineBanner` above the grid when `state.offline` is true while
the list is non-empty. In the offline state create/delete controls are disabled
(`state.canMutate` false).

## Repository fallback behaviour (already implemented)

`LibraryRepository.load()` tries the server (`fetchRemoteRaw`, which is null or
throws for now) and falls back to the local store, returning
`Loaded(items, DataOrigin.cache)`. Mutations write locally first; a 404/405/501
from the server yields `MutationLocal` (not an error). So with no server
endpoints everything works, and the offline banner is what marks it as cached.

## Verification rules for this machine

- `flutter analyze` and `dart analyze` CRASH (broken SDK analyzer). Never run them.
- Compile check = `flutter build web --no-tree-shake-icons` (~80 s).
- Unit/widget tests = `flutter test` (works).
- ALWAYS set PATH explicitly. PowerShell:
  ```
  $env:Path = "D:\flutter\bin;C:\Program Files\Git\cmd;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0;C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin;D:\Android\Sdk\platform-tools"; $env:JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"; $env:ANDROID_HOME="D:\Android\Sdk"
  ```
  Without this, flutter fails with "Unable to find git in your PATH".
- Do NOT run a full web/apk build unless your brief says to; the lead does the
  final build. A targeted `flutter test test/<your>_test.dart` is enough, plus
  one web build if you changed something structurally risky.

## Style rules

- Match the existing code: dartdoc on public classes, `// ── Section ──` banners,
  trailing commas, `const` everywhere possible, no `print`.
- Accessibility: 44 min touch targets, `Semantics(label/selected/button)` on
  custom tappables, never color-only status.
- Never call `dio` from a widget. Widget → provider → controller → repository.
- No new dependencies.
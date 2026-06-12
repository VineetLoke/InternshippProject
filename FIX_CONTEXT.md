# FIX_CONTEXT.md - Repair plan for FocusGuard (focus_lock)

This file is the "memory" for the codebase repair effort. If work is interrupted,
read this file to know what was found, what is fixed, and what is left.

- **Branch:** `fix/broken-codebase` (based on `main`)
- **App:** Flutter + Kotlin Android app that blocks distracting apps (Instagram, Reddit, Twitter, Chrome incognito)

---

## 1. Bug inventory (found so far)

| # | File(s) | Problem | Severity | Status |
|---|---------|---------|----------|--------|
| 1 | `android/app/src/main/AndroidManifest.xml` | File is corrupted: all `<` and `>` were replaced with HTML codes (`&lt;` / `&gt;`). Android cannot parse it. Also uses the old `package=` attribute (removed in AGP 8) and declares the `tools` namespace in the wrong place. | CRITICAL | [x] fixed |
| 2 | `android/app/src/debug/AndroidManifest.xml` | Same HTML-escaping corruption. | CRITICAL | [x] fixed |
| 3 | `android/app/src/profile/AndroidManifest.xml` | Same HTML-escaping corruption (identical file to debug). | CRITICAL | [x] fixed |
| 4 | `android/build.gradle` + `android/build.gradle.kts`, `android/app/build.gradle` + `android/app/build.gradle.kts`, `android/settings.gradle` + `android/settings.gradle.kts` | Duplicate Groovy AND Kotlin-DSL build scripts exist side by side. They disagree with each other (AGP 7.4.2 vs 9.0.1, Kotlin 1.9.10 vs 2.3.20, Java 8 vs 17). The `.kts` versions are also missing the `kotlin-android` and `kotlin-kapt` plugins that the Room database code requires. Gradle cannot work like this. | CRITICAL | [x] fixed (.kts files deleted, Groovy kept) |
| 5 | Version matrix | Gradle wrapper is 8.3 but AGP is 7.4.2 (incompatible pairing). `compileSdk 33` is too low for the plugins in pubspec (camera 0.11, permission_handler 11, ML Kit pose detection). | HIGH | [x] fixed (Gradle 8.10.2 / AGP 8.7.3 / Kotlin 1.9.25 / Java 17 / compileSdk 35) |
| 6 | `android/build.gradle` (root) | Old-style `buildscript { classpath ... }` block conflicts with the plugin versions declared in `settings.gradle` `pluginManagement`. Plugins must be declared in only one place. | HIGH | [x] fixed |
| 7 | `evaluate_test.kt` (repo root) | Stray Kotlin file sitting outside any source set. Not compiled, just confusing clutter. | LOW | [x] removed |
| 8 | `lib/services/step_challenge.dart` | `_resetIfNewDay()` is async but called without `await` in `startMonitoring()` and `isChallengeComplete()` - possible race condition. | MEDIUM | [x] fixed |
| 9 | Whole `lib/` (~40 files) and `android/.../focus_lock/` (~20 Kotlin files) | Audited via GitHub Actions `flutter analyze`: **0 compile errors**, 9 warnings, 79 style infos. | DONE | [x] |
| 10 | 6 files (quote_model, emergency_unlock_screen, permissions_screen, home_screen, notification_service, widget_test) | 9 analyzer warnings: unused imports, unused local variable `statusIcon`, unused field `_isInitialized`. These made CI fail (warnings are fatal). | HIGH | [x] fixed |
| 11 | Various `lib/` files | 79 style infos (`avoid_print`, deprecated `withOpacity`/`WillPopScope`, `prefer_const`). Not fatal to CI - optional cleanup later. | LOW | [ ] optional |

---

## 2. Fix plan (in order)

1. **Commit this file** so context is never lost. (done by this commit)
2. **Fix the three AndroidManifest.xml files** - restore real XML, remove the obsolete `package=` attribute, move `xmlns:tools` to the root tag.
3. **Unify the Gradle build** - keep the Groovy scripts (they have the Room/kapt setup the Kotlin code needs), delete the three `.kts` duplicates, and align versions to a known-good matrix:
   - Gradle wrapper **8.10.2**
   - Android Gradle Plugin **8.7.3** (declared only in `settings.gradle`)
   - Kotlin **1.9.25**
   - Java/Kotlin target **17**
   - `compileSdk 35`, `targetSdk 34`, `minSdk 29`
   - Remove the conflicting `buildscript` block from the root `build.gradle` and the manual `kotlin-stdlib` dependency (the Kotlin plugin adds it automatically).
4. **Remove stray file** `evaluate_test.kt` from the repo root.
5. **Fix Dart issues** found in audit (start with `step_challenge.dart` await bug).
6. **Local verification (needs your machine):** run `flutter pub get`, `flutter analyze`, `flutter test`, then `flutter build apk --debug`. Paste any remaining errors back into chat; they get added to the table above and fixed one by one.
7. **Open a merge request** from `fix/broken-codebase` to `main` once analyze/build pass.

---

## 3. How to resume after losing context

1. Open this file on branch `fix/broken-codebase`.
2. Every fixed item is ticked `[x]` in the table above with a commit reference.
3. Continue with the first unticked item.

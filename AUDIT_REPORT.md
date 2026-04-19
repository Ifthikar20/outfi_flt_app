# Outfi Flutter App — Security & Performance Audit Report

**Date:** 2026-04-19
**Branch:** `claude/hopeful-maxwell-59FHR`
**Scope:** `lib/`, `ios/Runner/Info.plist`, `pubspec.yaml`, `scripts/`, `run.sh`
**Status:** Analysis only — no code has been modified yet.

---

## Summary

| Severity  | Count |
| --------- | ----- |
| Critical  | 1     |
| High      | 7     |
| Medium    | 10    |
| Low       | 17    |
| **Total** | **35** |

- **Security issues:** 14
- **Performance bottlenecks:** 16
- **Verified clean (not issues):** 5

---

## How Each File Was Checked

| Area | What I looked for |
| ---- | ----------------- |
| `lib/config/api_config.dart` | Hardcoded URLs, empty cert pin lists, dev-mode leaks |
| `lib/services/api_client.dart` | Cert pinning bypass, token logging, response decoding |
| `lib/services/auth_service.dart` | Use of raw `http` vs pinned Dio, password handling, logs |
| `lib/services/freemium_gate_service.dart` | Auth guards, race conditions, stale caches |
| `lib/services/device_info_service.dart` | Device-ID generation entropy/persistence |
| `lib/services/background_removal_service.dart` | Unverified external downloads |
| `lib/services/deal_alert_service.dart` | Pagination on list endpoints |
| `lib/services/push_notification_service.dart` | Token transport security |
| `lib/services/cache_interceptor.dart` | Request dedup, cache TTLs |
| `lib/bloc/auth/auth_event.dart` | Secrets in event objects |
| `lib/bloc/image_search/image_search_bloc.dart` | Main-thread upload work |
| `lib/screens/*` | `MediaQuery`/`Theme` calls per build, `DateTime.now()` in build, timer disposal, `mounted` guards, image placeholders |
| `lib/widgets/deal_card.dart` | `const` usage, `RepaintBoundary`, rebuild surface |
| `lib/models/deal.dart`, `storyboard.dart` | Unbounded parsing, token entropy |
| `ios/Runner/Info.plist` | `NSAppTransportSecurity`, cleartext exceptions |
| `pubspec.yaml` | Asset bundling, unused heavy deps |

---

# 1. Security Issues

## 1.1 Critical

### S1. No certificate pinning in production
- **Files:** `lib/config/api_config.dart:48-52`, `lib/services/api_client.dart:82-84`
- **What:** `certificatePins = []` is a TODO placeholder; pinning is also skipped when `kDebugMode` is true.
- **Why it matters:** Any attacker on the network (rogue Wi-Fi, compromised router, captive portal) can terminate TLS with their own cert and read/modify all traffic — including auth tokens, purchase receipts, and user data.
- **Fix:**
  ```dart
  // openssl s_client -connect api.outfi.ai:443 \
  //   | openssl x509 -pubkey -noout \
  //   | openssl pkey -pubin -outform der \
  //   | openssl dgst -sha256 -binary | base64
  static const List<String> certificatePins = [
    'LEAF_SHA256_BASE64',
    'BACKUP_CA_SHA256_BASE64',
  ];
  ```
  Remove the `kDebugMode` bypass or limit it to a single local dev host.

---

## 1.2 High

### S2. Freemium gate bypass — no auth check on record
- **Files:** `lib/services/freemium_gate_service.dart:99-106, 136-144`
- **What:** `recordBuyClick()` and `recordImageSearch()` write usage counters locally without checking whether the caller is authenticated.
- **Why it matters:** An attacker (or buggy code path) can call these directly, skewing quota and letting unauthenticated users consume gated actions.
- **Fix:** Gate every record call on `await _api.hasTokens()` and bail out early if false.

### S3. Auth tokens logged in debug
- **Files:** `lib/services/api_client.dart:161, 201-204`, `lib/services/auth_service.dart:132, 166-168`
- **What:** Logs the first 20 chars of the bearer token.
- **Why it matters:** Debug logs end up in `adb logcat`, crash reporters, and screen-share recordings. Even partial tokens can help an attacker (and full ones are often logged elsewhere).
- **Fix:** Log only `"Bearer token set"` / `"NONE"`; never log substrings, lengths, or response keys of auth responses.

### S4. Auth endpoints use raw `package:http`, bypassing Dio pinning
- **File:** `lib/services/auth_service.dart:18-64`
- **What:** Login/register go through `http.post()`, not the `ApiClient` that owns the pinning adapter.
- **Why it matters:** Even when pinning is added (S1), the most sensitive endpoint — login — still won't be pinned.
- **Fix:** Route all auth requests through the same `ApiClient` instance used for other endpoints.

### S5. Passwords live on BLoC event objects
- **File:** `lib/bloc/auth/auth_event.dart`
- **What:** `AuthLoginRequested` and `AuthRegisterRequested` carry a `final String password`.
- **Why it matters:** BLoC observers, state dumps, devtools, and crash reporters (Sentry/Crashlytics) can serialize events — sending plaintext passwords off-device.
- **Fix:** Override `props`/`toString` to exclude the password; ideally pass it via a short-lived channel and clear it right after use.

### S6. No input validation on login/register
- **Files:** `lib/screens/login_screen.dart:34`, `lib/screens/register_screen.dart`
- **What:** Only `isEmpty` is checked — no email regex, no password length/complexity.
- **Why it matters:** Allows garbage input to reach the server, and allows trivial passwords if the backend doesn't enforce rules.
- **Fix:** Client-side email regex + minimum password length (≥ 8) with error UI.

### S7. Unverified CDN image downloads
- **File:** `lib/services/background_removal_service.dart:20`
- **What:** Uses raw `http.get()` on arbitrary image URLs.
- **Why it matters:** No host allowlist + no pinning means a compromised CDN or MITM can feed malicious images into the ML pipeline.
- **Fix:** Whitelist image hosts; route through pinned Dio.

### S8. Weak device-ID fallback
- **File:** `lib/services/device_info_service.dart:41-42`
- **What:** Fallback uses `DateTime.now().millisecondsSinceEpoch`.
- **Why it matters:** Regenerates every launch → breaks rate limiting and fraud detection; also trivially forgeable.
- **Fix:** On first run, generate a UUID and persist it in `flutter_secure_storage`.

---

## 1.3 Medium

### S9. Hardcoded URLs + commented LAN IPs
- **File:** `lib/config/api_config.dart:11-18`
- **What:** Production URL is hardcoded; `192.168.1.66` style dev URLs are commented in the same file.
- **Why it matters:** Easy to accidentally ship a build pointing at localhost, and these comments disclose internal network layout.
- **Fix:** Use `--dart-define` env flags, strip LAN IPs from source.

### S10. Freemium race condition
- **File:** `lib/services/freemium_gate_service.dart:84-96, 111-126`
- **What:** `canImageSearch()` reads the counter, returns, then the caller increments. Two concurrent calls both pass.
- **Fix:** Replace `can…()` with `try…()` that atomically checks-and-increments.

### S11. Storyboard share tokens
- **Files:** `lib/models/storyboard.dart`, `lib/screens/fashion_board_share_screen.dart:96-98`
- **What:** Token used as the share identifier — verify it's high-entropy and server-generated, not an auto-increment.
- **Fix:** Enforce ≥ 128-bit random tokens backend-side; consider expiry for shared links.

### S12. Missing `NSAppTransportSecurity` in iOS plist
- **File:** `ios/Runner/Info.plist`
- **What:** No explicit ATS config.
- **Why it matters:** Defaults have historically shifted; without an explicit `NSAllowsArbitraryLoads = false`, a future build could allow cleartext.
- **Fix:** Add an explicit ATS block with all arbitrary-loads flags set to `false`.

---

## 1.4 Low

### S13. Fire-and-forget server sync swallows errors
- **File:** `lib/services/freemium_gate_service.dart:104, 182-191`
- **Fix:** Retry queue (like `StoreKitService` does for receipts), or surface sync failures.

### S14. APNs token sent without pinning
- **File:** `lib/services/push_notification_service.dart:69-77`
- **Fix:** Automatically resolved once S1 lands.

---

# 2. Performance Bottlenecks

## 2.1 Medium

### P1. `DateTime.now()` called inside build
- **File:** `lib/screens/deal_alerts_screen.dart:~123`
- **What:** `DateTime.now().difference(dt)` computed per frame for "time ago" labels.
- **Fix:** Capture the base timestamp in `initState`; refresh with a 60 s `Timer`, not every frame.

### P2. Repeated `MediaQuery.of` / `Theme.of`
- **Files:** ~47 call sites across screens (e.g. `login_screen.dart:62`)
- **What:** Each `.of(context)` walks the widget tree and registers a dependency.
- **Fix:**
  ```dart
  final mq = MediaQuery.of(context);
  final theme = Theme.of(context);
  ```
  Reuse the locals inside `build`.

### P3. Unbounded JSON parse
- **File:** `lib/models/deal.dart:48-80`
- **What:** No max-count guard on the incoming list.
- **Fix:** Clamp at the service layer (e.g. reject > 1000) and always paginate.

### P4. `DealCard` as `StatefulWidget`
- **File:** `lib/widgets/deal_card.dart:10-53`
- **What:** Whole card rebuilds on any parent BLoC change; no `const`.
- **Fix:** Split into a `const`-friendly stateless shell + small animated child; wrap in `RepaintBoundary`.

### P5. Unpaginated deal-alert matches
- **File:** `lib/services/deal_alert_service.dart:84-91`
- **Fix:** Always send `limit`/`offset`.

---

## 2.2 Low

### P6. Premium cache stale on resume
- **File:** `lib/services/freemium_gate_service.dart:54-71`
- **Fix:** Invalidate cache on `AppLifecycleState.resumed`.

### P7. Featured + trending fetched sequentially
- **File:** `lib/screens/home_screen.dart:57-60, 186-206`
- **Fix:** `Future.wait` or merge into one backend endpoint.

### P8. No in-flight request deduplication
- **File:** `lib/services/cache_interceptor.dart:8-87`
- **Fix:** Keep a `Map<key, Future<Response>>` and return the existing future if a request is already in flight.

### P9. Image upload on UI thread
- **File:** `lib/bloc/image_search/image_search_bloc.dart:25-40`
- **Fix:** `compute()` the multipart encoding.

### P10. Timer callbacks without `mounted` guard
- **File:** `lib/screens/home_screen.dart:61-62`
- **Fix:** `if (mounted) setState(...)` inside `Timer.periodic` bodies.

### P11. Global `ValueNotifier`s
- **File:** `lib/screens/fashion_board_screen.dart:10-15`
- **Status:** Listeners are cleaned up; keep an eye on added screens.

### P12. Response bytes decoded twice
- **File:** `lib/services/api_client.dart:106-139, 185`
- **Fix:** Decode once in the interceptor; callers consume `Map`/`List` directly.

### P13. No local preview during image-search loading
- **File:** `lib/screens/camera_screen.dart:50-57`
- **Fix:** Show `Image.file(File(widget.imagePath))` while the request is in flight.

### P14. Wholesale asset bundling
- **File:** `pubspec.yaml:67-70`
- **Fix:** Remove unused sticker/video directories or split them into a downloadable pack.

### P15. Camera controller disposal on rapid navigation
- **File:** `lib/screens/camera_screen.dart:64-75`
- **Status:** Currently OK; regression risk when adding new lifecycle paths.

### P16. Paywall double-subscribe window
- **File:** `lib/screens/paywall_screen.dart:40-41, 52-54`
- **Status:** Broadcast streams — safe, just inefficient under rapid push/pop.

---

# 3. Verified Clean

- No bare `ListView()` — every list uses `ListView.builder`.
- No regexes compiled inside loops.
- No Firestore listeners (REST + BLoC only).
- No large `sort`/`filter` inside `build` methods.
- No Firebase realtime listeners to leak.

---

# 4. Recommended Fix Order

### Batch 1 — Security, one PR
1. S3: strip token/password logging
2. S4: route auth through pinned Dio
3. S5: remove password from BLoC events
4. S6: input validation on login/register
5. S8: persistent device-ID fallback
6. S12: explicit ATS plist block

### Batch 2 — Security, needs product/backend coordination
7. S1: cert pinning with real pins
8. S2: auth guard on freemium record
9. S10: atomic freemium increment
10. S11: verify storyboard token entropy

### Batch 3 — Performance
11. P2: cache `MediaQuery` / `Theme` per build
12. P5 + P3: pagination on matches, clamp on parse
13. P1: `DateTime.now()` out of build
14. P7 + P8: parallel fetch + in-flight dedup
15. P4: split `DealCard`
16. P9: move upload encoding to isolate

---

# 5. How to Verify After Fixes

```bash
flutter pub get
flutter analyze
flutter test
flutter run                       # smoke test on simulator
# iOS specifically:
cd ios && pod install && cd ..
flutter run -d <ios-simulator-id>
```

Recommended manual checks per batch:
- **S3:** run with `flutter logs`, attempt login, grep the log — no token substrings should appear.
- **S4:** put a proxy (Charles/mitmproxy) in front with the pinning cert installed — login must fail when pinning is on and the proxy is untrusted.
- **S6:** attempt `a@a`, empty, and 1-char password — UI must reject.
- **S10:** fire two concurrent image searches at quota boundary — second must be gated.
- **P1/P2:** open DevTools → Performance → record frame time before/after on the affected screens.
- **P5:** inspect network tab; match list should paginate, not return everything.

---

*This file is a planning artifact. No source files have been edited.*

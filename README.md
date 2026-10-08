# Cypher Track

Cypher Track is an Android-first, two-button fork of [Traccar Client](https://github.com/traccar/traccar-client) for a sales team. The salesperson sees a device identifier, a trip timer, Start Trip, and End Trip. The screen uses a soft, high-contrast light palette outdoors and a dark palette when the phone is in dark mode.

The app uses the Traccar Client SDK for background location tracking and offline GPS buffering. It does not send separate trip start/end markers or `tripId`/`tripState` attributes. The Traccar dashboard can be used to review each device's location history.

## Embedded tracking policy

| Setting | Value |
| --- | --- |
| Server | `https://tracking.arnabroy.co.in/` |
| Accuracy | High |
| Distance | 75 metres |
| Heartbeat | About every 5 minutes during an active trip when movement has not already produced an update |
| Offline position buffering | On |
| Android system location provider | On |
| Stop detection | On |

Only Start Trip starts the tracker. End Trip waits for the SDK to stop before the app shows tracking as off; it does not request another location. On launch, an orphaned tracking session with no stored trip is stopped. Push commands, deep links, shortcuts, and settings cannot start tracking. GPS points collected before End Trip may still upload later from the SDK's offline buffer; check the GPS fix time, not the server receipt time, when testing this boundary.

Each Start Trip now asks for a new GPS fix without waiting for 75 metres of movement. The fix is accepted only if it was obtained after tracking started, and it enters the SDK's normal offline queue. GPS acquisition can still take time outdoors, and the phone must have a fix before anything can be sent. Later positions use the 75-metre distance policy. A new trip does not inherit the previous trip's distance threshold.

While a trip is active, the SDK schedules a heartbeat every five minutes, including when the phone is stationary. If no recent movement update has been sent, it obtains a fresh location; if no fix is available, it sends a heartbeat without coordinates. Android may defer alarms in deep sleep, so five minutes is a requested cadence rather than an exact guarantee. End Trip cancels future heartbeats; already buffered reports can still upload later.

## Install the signed test release

The release APK is `build/app/outputs/flutter-apk/app-release.apk`. It is a universal Android APK, not the earlier debug APK with a test device identifier. Release builds generate a different eight-digit identifier for each new installation and show it on the home screen. The package is `co.in.arnabroy.cyphertrack`.

1. First let the old debug build upload any offline positions. Then uninstall it: Android will not install this differently signed release over a debug-signed copy. Uninstalling clears its local data and generates a new identifier.
2. Share the signed APK with a salesperson by a trusted channel. On the phone, open it and allow installation from that source when Android asks.
3. Open Cypher Track, read its Device Identifier, and add a Traccar device with exactly that identifier to the Salesmen group. Set its `employeeId` and `employeeName` device attributes. Do this separately for each phone. A reinstall creates a new identifier and needs a new Traccar device registration.
4. Grant Precise Location, background location, and notification permissions when requested. Keep Location enabled. For the reliability test, allow unrestricted battery use; later compare battery use on the phone's normal policy.

Do not share the old debug APK or run the official Traccar Client with the same test identifier during a test.

## Field-test checklist

Run these checks on at least one real phone before a team rollout. Use Traccar's position **fix time** to distinguish collection time from a delayed offline upload.

| Scenario | Expected result |
| --- | --- |
| Fresh install | Unique displayed identifier; no tracking before Start Trip. |
| Outdoor trip, screen on | Start Trip enables End Trip and timer; the first fix appears without moving 75 m, once GPS has a fresh fix. Later positions follow the 75 m rule. |
| Second trip from the same place | A new starting fix appears even if the previous trip ended less than 75 m away. |
| Screen off and app in background | Tracking continues with Android's location service notification. |
| Stationary for several minutes, then move | Stop detection conserves power; a heartbeat is sent about every 5 minutes while stationary, and regular positions resume on movement. |
| End Trip while stationary | No new heartbeat or GPS request after End Trip. |
| Offline during a trip | The timer continues; positions collected offline arrive after reconnecting. |
| Start while offline and stationary outdoors | The starting fix is buffered and arrives after reconnecting, even without moving 75 m. |
| End while offline, then reconnect | No new GPS fixes after End Trip; earlier buffered fixes may arrive later. |
| End online, then keep walking | No new GPS fixes after End Trip. |
| Swipe app away, reopen during a trip | Tracking and the original timer continue. Android's explicit **Force stop** is different and suspends app work until reopened. |
| Reboot during a trip | Tracking and timer recover after boot, subject to the phone's background restrictions. |
| Reopen after End Trip | Tracking stays off and End Trip is disabled. |
| Deny or revoke a required permission | Start fails visibly; the app must not falsely show an active trip. |
| Second salesperson's phone | It has a different identifier and separate position history. |

On the phone, also check battery use over a representative workday. Manufacturer battery policies vary, so a successful test on one phone does not guarantee identical background behavior on every model. Do not distribute beyond the test group until the relevant scenarios pass.

## Rebuild a signed release

Flutter, Android SDK, and JDK 17 are needed on the Mac. The release keystore lives outside this public repository at `../.cypher-track-signing/release.jks`; its password is stored in the macOS Keychain as service `co.in.arnabroy.cyphertrack.release` for account `cypher-track`. Back up both securely. **Without the same signing key, Android will not accept future APKs as updates to existing installations.** Increment the version in `pubspec.yaml` for each later release.

The pinned Flutter wrapper still uses Traccar Client SDK 1.1.1. The Android build substitutes `third_party/traccar-client-sdk` (copied from upstream tag `v1.1.1`, commit `69dc67b`) for the native SDK. Only the start-fix/reset behavior and the minimum build/test setup are changed there. This keeps the app fork's tracking customization isolated when pulling Traccar Client updates. The Android SDK location must be available through `ANDROID_HOME`, including for the included SDK build.

```sh
cd /Users/arnab/my_experiments/android/cypher-track
export CYPHER_TRACK_SIGNING_STORE="$PWD/../.cypher-track-signing/release.jks"
export CYPHER_TRACK_SIGNING_PASSWORD="$(security find-generic-password -a cypher-track -s co.in.arnabroy.cyphertrack.release -w)"
export ANDROID_HOME="$(sed -n 's/^sdk.dir=//p' android/local.properties)"
flutter analyze
flutter test
JAVA_HOME="$(/usr/libexec/java_home -v 17)" android/gradlew -p third_party/traccar-client-sdk :core:testAndroidHostTest
flutter build apk --release
unset CYPHER_TRACK_SIGNING_PASSWORD
```

Keep the keystore, password, and APK out of Git. The app source is a fork with `upstream` pointing to Traccar; review upstream SDK and permission changes before merging updates. See [AGENTS.md](AGENTS.md) for development invariants.

## License and attribution

Based on Traccar Client, copyright its contributors. See [LICENSE.txt](LICENSE.txt) for the Apache License, Version 2.0. Traccar and Traccar Client SDK are separate upstream projects.

# Cypher Track

Cypher Track is an Android-first, two-button fork of [Traccar Client](https://github.com/traccar/traccar-client) for a sales team. The salesperson sees a device identifier, a trip timer, Start Trip, and End Trip. The screen uses a soft, high-contrast light palette outdoors and a dark palette when the phone is in dark mode.

The app uses the unmodified Traccar Client SDK 1.1.1 for background location tracking and offline GPS buffering. It does not send separate trip start/end markers or `tripId`/`tripState` attributes. The Traccar dashboard can be used to review each device's location history.

## Embedded tracking policy

| Setting | Value |
| --- | --- |
| Server | `https://tracking.arnabroy.co.in/` |
| Accuracy | High |
| Distance | 75 metres |
| Stationary heartbeat | 5 minutes after the SDK detects a stationary pause |
| Offline position buffering | On |
| Android system location provider | On |
| Stop detection | On |

Only Start Trip starts the tracker. End Trip waits for the SDK to stop before the app shows tracking as off; it does not request another location. On launch, an orphaned tracking session with no stored trip is stopped. Push commands, deep links, shortcuts, and settings cannot start tracking. GPS points collected before End Trip may still upload later from the SDK's offline buffer; check the GPS fix time, not the server receipt time, when testing this boundary.

Start Trip uses the same stock SDK start path as the working development APK. It starts the timer and requests GPS updates, but a first fix is not guaranteed at the instant the button is tapped. Moving outdoors may be needed before the first position reaches Traccar. Ordinary movement updates use a 75-metre distance threshold.

The SDK's stationary heartbeat is configured for 300 seconds. It only runs after stop detection pauses tracking, and Android can defer alarms. The stock SDK may filter a heartbeat position that is less than 75 metres from the previous position, so this is **not a guarantee of a new GPS point every five minutes**. If no fix is available, it may send a heartbeat without coordinates. End Trip stops collection; already buffered reports can still upload later.

## Install a test build

Both the debug and signed release APKs now use the stored eight-digit Device Identifier. There is no hard-coded test identifier or debug override. The package is `co.in.arnabroy.cyphertrack`, and build number 162 is higher than both the original development APK (161) and the previous signed release (2).

1. If the original debug APK is installed, install the new debug APK over it. If a signed release is installed, install the new signed release over it. Android cannot switch between these signing keys without uninstalling; uninstalling clears local data and generates a new identifier.
2. Open Cypher Track and register the identifier currently shown on screen as a Traccar device in the Salesmen group. When upgrading the original debug APK, the displayed identifier changes from the former hard-coded test value to the generated stored value, so register the new one. A normal upgrade from a signed release preserves its displayed identifier.
3. Grant Precise Location, background location, and notification permissions when requested. Keep Location enabled. For the reliability test, allow unrestricted battery use; later compare battery use on the phone's normal policy.

Do not run the original hard-coded-ID debug APK on multiple phones with the same identifier.

## Field-test checklist

Run these checks on at least one real phone before a team rollout. Use Traccar's position **fix time** to distinguish collection time from a delayed offline upload.

| Scenario | Expected result |
| --- | --- |
| Fresh install | Unique displayed identifier; no tracking before Start Trip. |
| Outdoor trip, screen on | Start Trip enables End Trip and timer; after a GPS fix and sufficient movement, positions reach Traccar. |
| Second trip from the same place | The SDK may wait for a 75 m movement before another position is accepted. |
| Screen off and app in background | Tracking continues with Android's location service notification. |
| Stationary for several minutes, then move | Stop detection conserves power; heartbeat timing and position filtering should be observed on the phone and dashboard. |
| End Trip while stationary | No new heartbeat or GPS request should start after End Trip. |
| Offline during a trip | The timer continues; positions collected offline arrive after reconnecting. |
| Start while offline outdoors | Positions accepted by the SDK are buffered and arrive after reconnecting. |
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

The native SDK is no longer patched or vendored. Release builds also disable native-code minification to align with the working debug APK as closely as possible.

```sh
cd /Users/arnab/my_experiments/android/cypher-track
export CYPHER_TRACK_SIGNING_STORE="$PWD/../.cypher-track-signing/release.jks"
export CYPHER_TRACK_SIGNING_PASSWORD="$(security find-generic-password -a cypher-track -s co.in.arnabroy.cyphertrack.release -w)"
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
unset CYPHER_TRACK_SIGNING_PASSWORD
```

Keep the keystore, password, and APK out of Git. The app source is a fork with `upstream` pointing to Traccar; review upstream SDK and permission changes before merging updates. See [AGENTS.md](AGENTS.md) for development invariants.

## License and attribution

Based on Traccar Client, copyright its contributors. See [LICENSE.txt](LICENSE.txt) for the Apache License, Version 2.0. Traccar and Traccar Client SDK are separate upstream projects.

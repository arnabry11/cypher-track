# Cypher Track

An Android first, two-button fork of [Traccar Client](https://github.com/traccar/traccar-client) for trips made by a sales team. The application uses the open-source Traccar Client SDK for background tracking and offline position buffering. The server URL and tracking policy are embedded in the app; the salesperson sees a device identifier, trip timer, Start Trip, and End Trip. The screen uses a high-contrast, soft light palette outdoors and a dark palette when the phone is in dark mode.

This repository is a fork, with `upstream` pointing to Traccar. The [agent guidance](AGENTS.md) describes the privacy rules; the remaining work is listed below.

## Current build status

- The app starts and stops the SDK only through the trip controller. On launch it stops an orphaned tracking session if no trip is stored. It does not initialize Traccar's push commands, deep links, quick actions, Firebase, or settings screen.
- The configured URL is `https://tracking.arnabroy.co.in/`; accuracy is High, distance is 50 m, stationary heartbeat is off, offline buffering is on, Android system location is on, and stop detection is on.
- Start and end markers carry `tripId`, `tripState`, and `tripEventAt` as OsmAnd custom attributes. If sending fails, markers stay in app storage and are retried every 30 seconds while the app runs, and on the next app launch. They do not request a location fix. A metadata-only marker inherits the previous GPS fix time in Traccar; use its device time or `tripEventAt` to read the boundary time.
- **Experimental limitation:** the stock SDK does not yet attach `tripId` to every normal position. Its offline queue also lacks a field for it. A small SDK fork is required before we can claim that every point is tagged or that offline marker delivery is automatic while the app remains closed. Do not deploy this build to the sales team until that work and phone tests are complete.
- The user confirmed the root URL works in the official client. A form POST to this URL was also accepted by the live Traccar server, and a test position showed both custom attributes in the Traccar UI. A physical phone test is still required before deployment.

## Test it on your Android phone

You do not need to know Android development to run a debug copy. Flutter and Android command-line tools are needed on the Mac. Run `flutter doctor` first; its Android toolchain section should have a check mark. If it does not, install Android Studio and let it install the Android SDK, then run `flutter doctor --android-licenses` and accept the Android licenses.

1. On the phone, open **Settings → About phone**, tap **Build number** seven times, then enable **USB debugging** in **Developer options**. The exact Settings path varies by phone.
2. Connect the phone by USB and approve its debugging prompt. On the Mac, run `flutter devices`; your phone should be listed.
3. In Terminal, run:

   ```sh
   cd /Users/arnab/my_experiments/android/cypher-track
   flutter pub get
   flutter test
   flutter run
   ```

   If Flutter lists several devices, use `flutter run -d DEVICE_ID` with the ID from `flutter devices`.

   For a debug build on the already registered test device, run `flutter run --dart-define=CYPHER_TEST_DEVICE_ID=YOUR_TEST_ID`. Do not leave the official Traccar Client tracking with that same ID at the same time. Release builds ignore this override and generate their own ID.

4. The app appears as **Cypher Track**, alongside the official Traccar Client. Read the **Device Identifier** on the screen. In your Traccar server, add a device with that exact identifier under the Salesmen group, then set its `employeeId` and `employeeName` device attributes.
5. Tap **Start Trip** and grant the requested location permissions. Allow background location and unrestricted battery use for reliable tracking. Walk outdoors for at least 100–200 metres. Open Traccar and check the device's position history.
6. Tap **End Trip**. Walk farther and check that no newly *collected* points appear after the end time. Previously buffered points from the trip may arrive later with earlier timestamps.
7. Repeat while offline: start a trip, disconnect mobile data/Wi-Fi but leave Location enabled, walk, end the trip, then reconnect. Check that historical trip points arrive, and that none has a timestamp after End Trip.
8. Close and reopen the app during a trip; the timer should continue from the original start time. Close and reopen it after End Trip; tracking should remain off.

If a device shows no positions, check its identifier, permissions, Traccar logs, and the HTTPS proxy route. The configured root URL was verified to accept an OsmAnd form POST on this server.

To build an installable debug APK instead of using `flutter run`, run `flutter build apk --debug`. The resulting file is `build/app/outputs/flutter-apk/app-debug.apk`. Debug APKs are for testing; a release build needs its own signing key and a completed privacy and offline test pass.

## Development

```sh
dart format lib test
flutter analyze
flutter test
```

`origin` uses the `github.com-personal` SSH alias, which selects the owner's existing personal key. Private keys, signing keys, and tokens must never be copied into this repository.

## License and attribution

Based on Traccar Client, copyright its contributors. See [LICENSE.txt](LICENSE.txt) for the Apache License, Version 2.0. Traccar and Traccar Client SDK are separate upstream projects.

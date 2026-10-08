# Working on Cypher Track

This is an Android first Flutter fork of Traccar Client. Preserve a clean route for merging `upstream/main` and keep custom behavior in small, clearly named files.

## Product invariants

- Location collection is initiated only by the salesperson's Start Trip action.
- End Trip must call and await the tracking SDK's stop operation before the app reports that the trip ended. Do not request a new position afterward.
- No deep link, shortcut, push message, boot path, or diagnostics action may initiate collection when there is no active trip.
- Offline positions collected during a trip may upload later. Never request a fresh location fix after End Trip.
- Never log coordinates, server credentials, SSH keys, or other employee data in analytics or crash reports.

## Flutter and Dart practices

- Run `dart format`, `flutter analyze`, and focused `flutter test` before proposing a change.
- Keep widgets declarative and free of network and persistence logic. Put the trip state machine behind a small controller with injected tracker, storage, and clock so it is testable.
- Persist UTC timestamps and derive elapsed time from the persisted start time. Do not accumulate timer ticks as the source of truth.
- Check `mounted` after awaited work before calling `setState` or using a `BuildContext`.
- Disable conflicting actions while start or end is pending; show an actionable error if an SDK call fails.
- Use typed constants for embedded config and avoid mutable, user editable settings for tracking policy.
- Keep Android package ID and app label distinct from the upstream application. Do not commit signing material.
- Add tests for state transitions and privacy sensitive paths. Fakes should assert calls to `start`, `stop`, and one-off position requests.

## Maintaining the fork

- `origin` is the user's public fork through the personal SSH alias. `upstream` is the official Traccar repository.
- Keep the Apache 2.0 license and upstream attribution. Document behavior differences and SDK changes in `README.md`.
- If a dependency needs a fork, pin a known revision, document how it is built, and test offline queue behavior. Do not patch generated files or the global pub cache.
- Review upstream changes to tracking permissions, background services, offline queue, and protocol encoding before merging.

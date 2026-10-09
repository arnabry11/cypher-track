import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:traccar_client/main.dart';
import 'package:traccar_client/preferences.dart';
import 'package:traccar_client/trip_controller.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

class FakeTracker implements TripTracker {
  bool tracking = false;
  bool failStart = false;
  bool failStop = false;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> isTracking() async => tracking;

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw StateError('permission denied');
    tracking = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('stop failed');
    tracking = false;
  }
}

class UncertainStartTracker extends FakeTracker {
  @override
  Future<void> start() async {
    tracking = true;
    throw StateError('start result unknown');
  }

  @override
  Future<void> stop() async => throw StateError('stop failed');
}

class MemoryTripStore implements TripStore {
  Trip? trip;
  bool failClear = false;

  @override
  Trip? get activeTrip => trip;

  @override
  Future<void> saveActiveTrip(Trip value) async => trip = value;

  @override
  Future<void> clearActiveTrip() async {
    if (failClear) throw StateError('storage failed');
    trip = null;
  }
}

void main() {
  final fixedTime = DateTime.utc(2026, 10, 8, 9);

  test('embedded tracker policy, identifier, and old marker cleanup', () async {
    SharedPreferencesAsyncPlatform
        .instance = InMemorySharedPreferencesAsync.withData({
      'active_trip_id': 'old-trip-id',
      'pending_trip_markers': '[{"tripId":"old"}]',
      'active_trip_started_at': fixedTime.millisecondsSinceEpoch,
    });
    await Preferences.init();
    final config = Preferences.buildConfig();
    expect(config.serverUrl, 'https://tracking.arnabroy.co.in/');
    expect(config.deviceId, Preferences.instance.getString(Preferences.id));
    expect(config.deviceId, matches(RegExp(r'^[1-9][0-9]{7}$')));
    expect(config.location.accuracy, Accuracy.high);
    expect(config.location.distanceMeters, 75);
    expect(config.location.heartbeatIntervalSeconds, 300);
    expect(config.location.stopDetection, isTrue);
    expect(config.buffer, isTrue);
    expect(config.preferPlatformProviders, isTrue);
    expect(Preferences.instance.get('active_trip_id'), isNull);
    expect(Preferences.instance.get('pending_trip_markers'), isNull);
    expect(
      PreferencesTripStore(Preferences.instance).activeTrip?.startedAt,
      fixedTime,
    );
  });

  TripController makeController(FakeTracker tracker, MemoryTripStore store) =>
      TripController(tracker: tracker, store: store, now: () => fixedTime);

  test('start and end only start and stop SDK tracking', () async {
    final tracker = FakeTracker();
    final store = MemoryTripStore();
    final controller = makeController(tracker, store);
    await controller.initialize();

    await controller.startTrip();
    expect(tracker.starts, 1);
    expect(tracker.tracking, isTrue);
    expect(store.activeTrip?.startedAt, fixedTime);

    await controller.endTrip();
    expect(tracker.stops, 1);
    expect(tracker.tracking, isFalse);
    expect(store.activeTrip, isNull);
    expect(controller.activeTrip, isNull);
    controller.dispose();
  });

  test('failed start leaves no active trip and stops the tracker', () async {
    final tracker = FakeTracker()..failStart = true;
    final store = MemoryTripStore();
    final controller = makeController(tracker, store);

    await expectLater(controller.startTrip(), throwsStateError);
    expect(tracker.stops, 1);
    expect(store.activeTrip, isNull);
    expect(controller.activeTrip, isNull);
    controller.dispose();
  });

  test('uncertain start remains visible if stopping also fails', () async {
    final tracker = UncertainStartTracker();
    final store = MemoryTripStore();
    final controller = makeController(tracker, store);

    await expectLater(controller.startTrip(), throwsStateError);
    expect(tracker.tracking, isTrue);
    expect(controller.activeTrip?.startedAt, fixedTime);
    expect(store.activeTrip?.startedAt, fixedTime);
    controller.dispose();
  });

  test('startup stops tracking when there is no active trip', () async {
    final tracker = FakeTracker()..tracking = true;
    final controller = makeController(tracker, MemoryTripStore());

    await controller.initialize();
    expect(tracker.stops, 1);
    expect(tracker.tracking, isFalse);
    controller.dispose();
  });

  test('startup restores an active trip without restarting tracking', () async {
    final tracker = FakeTracker()..tracking = true;
    final store = MemoryTripStore()..trip = Trip(fixedTime);
    final controller = makeController(tracker, store);

    await controller.initialize();
    expect(controller.activeTrip?.startedAt, fixedTime);
    expect(tracker.starts, 0);
    controller.dispose();
  });

  test('startup clears an interrupted trip when tracking is off', () async {
    final store = MemoryTripStore()..trip = Trip(fixedTime);
    final controller = makeController(FakeTracker(), store);

    await controller.initialize();
    expect(controller.activeTrip, isNull);
    expect(store.activeTrip, isNull);
    controller.dispose();
  });

  test('failed stop keeps the trip active', () async {
    final tracker = FakeTracker()..failStop = true;
    final store = MemoryTripStore();
    final controller = makeController(tracker, store);
    await controller.startTrip();

    await expectLater(controller.endTrip(), throwsStateError);
    expect(controller.activeTrip?.startedAt, fixedTime);
    expect(store.activeTrip?.startedAt, fixedTime);
    expect(tracker.tracking, isTrue);
    controller.dispose();
  });

  test('completed stop displays privacy mode even if storage fails', () async {
    final tracker = FakeTracker();
    final store = MemoryTripStore();
    final controller = makeController(tracker, store);
    await controller.startTrip();
    store.failClear = true;

    await expectLater(controller.endTrip(), throwsStateError);
    expect(tracker.tracking, isFalse);
    expect(controller.activeTrip, isNull);
    controller.dispose();
  });

  testWidgets('screen shows identifier, timer and correct button states', (
    tester,
  ) async {
    final tracker = FakeTracker()..tracking = true;
    final store =
        MemoryTripStore()
          ..trip = Trip(
            DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
          );
    final controller = makeController(tracker, store);
    await controller.initialize();

    await tester.pumpWidget(
      CypherTrackApp(trips: controller, deviceId: '12345678'),
    );
    expect(find.text('12345678'), findsOneWidget);
    expect(find.text('TRIP IN PROGRESS'), findsOneWidget);
    expect(find.textContaining('00:02:'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
          Theme.of(
            tester.element(find.byType(Scaffold)),
          ).scaffoldBackgroundColor,
      isNot(const Color(0xFFFFFFFF)),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Trip'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'End Trip'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('End Trip'));
    await tester.pump();
    expect(find.text('NO ACTIVE TRIP'), findsOneWidget);
    expect(tracker.tracking, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('outdoor and dark themes remain legible on a phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );

    final controller = makeController(FakeTracker(), MemoryTripStore());
    await controller.initialize();
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(
      CypherTrackApp(trips: controller, deviceId: '12345678'),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cypher_daylight.png'),
    );

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cypher_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

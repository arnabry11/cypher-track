import 'dart:async';

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
    tracking = false;
  }
}

class FailingStopTracker extends FakeTracker {
  @override
  Future<void> stop() async => throw StateError('stop failed');
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
  List<TripMarker> markers = [];

  @override
  Trip? get activeTrip => trip;

  @override
  Future<void> saveActiveTrip(Trip value) async => trip = value;

  @override
  Future<void> clearActiveTrip() async => trip = null;

  @override
  List<TripMarker> get pendingMarkers => List.of(markers);

  @override
  Future<void> savePendingMarkers(List<TripMarker> value) async =>
      markers = List.of(value);
}

class FakeMarkerSender implements TripMarkerSender {
  FakeMarkerSender({this.succeeds = false, this.onSend});
  bool succeeds;
  void Function(TripMarker)? onSend;
  final sent = <TripMarker>[];

  @override
  Future<bool> send(TripMarker marker) async {
    sent.add(marker);
    onSend?.call(marker);
    return succeeds;
  }
}

class BlockingMarkerSender implements TripMarkerSender {
  final releaseFirst = Completer<void>();
  final sent = <TripMarker>[];

  @override
  Future<bool> send(TripMarker marker) async {
    if (sent.isEmpty) await releaseFirst.future;
    sent.add(marker);
    return true;
  }
}

void main() {
  final fixedTime = DateTime.utc(2026, 10, 8, 9);

  test('embedded tracker policy and optional debug device ID', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await Preferences.init();
    final config = Preferences.buildConfig();
    const testDeviceId = String.fromEnvironment('CYPHER_TEST_DEVICE_ID');

    expect(config.serverUrl, 'https://tracking.arnabroy.co.in/');
    expect(config.deviceId, testDeviceId.isEmpty ? isNotEmpty : testDeviceId);
    expect(config.location.accuracy, Accuracy.high);
    expect(config.location.distanceMeters, 50);
    expect(config.location.heartbeatIntervalSeconds, 0);
    expect(config.location.stopDetection, isTrue);
    expect(config.buffer, isTrue);
    expect(config.preferPlatformProviders, isTrue);
  });

  test('trip marker retains an explicit event time', () {
    final marker = TripMarker('trip-123', 'end', fixedTime);
    expect(marker.toJson()['tripEventAt'], '2026-10-08T09:00:00.000Z');
    expect(
      marker.toJson()['timestamp'],
      fixedTime.millisecondsSinceEpoch.toString(),
    );
  });

  TripController makeController(
    FakeTracker tracker,
    MemoryTripStore store,
    FakeMarkerSender sender,
  ) => TripController(
    tracker: tracker,
    store: store,
    markerSender: sender,
    now: () => fixedTime,
    newTripId: () => 'trip-123',
  );

  test(
    'start and end create boundaries and stop before end marker upload',
    () async {
      final tracker = FakeTracker();
      final store = MemoryTripStore();
      final sender = FakeMarkerSender(
        onSend: (marker) {
          if (marker.state == 'end') expect(tracker.tracking, isFalse);
        },
      );
      final controller = makeController(tracker, store, sender);
      await controller.initialize();

      await controller.startTrip();
      expect(tracker.starts, 1);
      expect(store.activeTrip?.id, 'trip-123');
      expect(store.markers.first.state, 'start');

      await controller.endTrip();
      expect(tracker.stops, 1);
      expect(tracker.tracking, isFalse);
      expect(store.activeTrip, isNull);
      expect(store.markers.map((marker) => marker.state), ['start', 'end']);
      expect(
        store.markers.every((marker) => marker.tripId == 'trip-123'),
        isTrue,
      );
      await controller.flushMarkers();
      controller.dispose();
    },
  );

  test(
    'failed start leaves no active trip and stops a partially started tracker',
    () async {
      final tracker = FakeTracker()..failStart = true;
      final store = MemoryTripStore();
      final controller = makeController(tracker, store, FakeMarkerSender());

      await expectLater(controller.startTrip(), throwsStateError);
      expect(tracker.stops, 1);
      expect(store.activeTrip, isNull);
      expect(controller.activeTrip, isNull);
      expect(store.markers, isEmpty);
      controller.dispose();
    },
  );

  test('uncertain start remains visible if stopping also fails', () async {
    final tracker = UncertainStartTracker();
    final store = MemoryTripStore();
    final controller = makeController(tracker, store, FakeMarkerSender());

    await expectLater(controller.startTrip(), throwsStateError);
    expect(tracker.tracking, isTrue);
    expect(controller.activeTrip?.id, 'trip-123');
    expect(store.activeTrip?.id, 'trip-123');
    controller.dispose();
  });

  test('startup stops tracking when there is no active trip', () async {
    final tracker = FakeTracker()..tracking = true;
    final controller = makeController(
      tracker,
      MemoryTripStore(),
      FakeMarkerSender(),
    );

    await controller.initialize();
    expect(tracker.stops, 1);
    expect(tracker.tracking, isFalse);
    controller.dispose();
  });

  test(
    'startup restores a real trip without starting tracking again',
    () async {
      final tracker = FakeTracker()..tracking = true;
      final store = MemoryTripStore()..trip = Trip('old-trip', fixedTime);
      final controller = makeController(tracker, store, FakeMarkerSender());

      await controller.initialize();
      expect(controller.activeTrip?.id, 'old-trip');
      expect(tracker.starts, 0);
      controller.dispose();
    },
  );

  test('failed stop keeps the trip active', () async {
    final tracker = FailingStopTracker();
    final store = MemoryTripStore();
    final controller = makeController(tracker, store, FakeMarkerSender());
    await controller.startTrip();

    await expectLater(controller.endTrip(), throwsStateError);
    expect(controller.activeTrip?.id, 'trip-123');
    expect(store.activeTrip?.id, 'trip-123');
    expect(store.markers.map((marker) => marker.state), ['start']);
    controller.dispose();
  });

  test(
    'pending markers remain queued when offline and flush in order',
    () async {
      final tracker = FakeTracker();
      final store = MemoryTripStore();
      final sender = FakeMarkerSender();
      final controller = makeController(tracker, store, sender);

      await controller.startTrip();
      await controller.endTrip();
      await controller.flushMarkers();
      expect(store.markers.length, 2);

      sender.succeeds = true;
      await controller.flushMarkers();
      expect(store.markers, isEmpty);
      expect(sender.sent.take(sender.sent.length - 2).last.state, 'start');
      expect(sender.sent.last.state, 'end');
      controller.dispose();
    },
  );

  test('ending during a marker upload does not lose the end marker', () async {
    final store = MemoryTripStore();
    final sender = BlockingMarkerSender();
    final controller = TripController(
      tracker: FakeTracker(),
      store: store,
      markerSender: sender,
      now: () => fixedTime,
      newTripId: () => 'trip-123',
    );

    await controller.startTrip();
    await controller.endTrip();
    sender.releaseFirst.complete();
    await controller.flushMarkers();

    expect(sender.sent.map((marker) => marker.state), ['start', 'end']);
    expect(store.markers, isEmpty);
    controller.dispose();
  });

  testWidgets(
    'screen shows identifier, restored timer and correct button states',
    (tester) async {
      final tracker = FakeTracker()..tracking = true;
      final store =
          MemoryTripStore()
            ..trip = Trip(
              'restored',
              DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
            );
      final controller = makeController(tracker, store, FakeMarkerSender());
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
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start Trip'),
            )
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
    },
  );

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

    final controller = makeController(
      FakeTracker(),
      MemoryTripStore(),
      FakeMarkerSender(),
    );
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

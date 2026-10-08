import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

import 'preferences.dart';

class Trip {
  const Trip(this.startedAt);

  final DateTime startedAt;
}

abstract class TripTracker {
  Future<bool> isTracking();
  Future<void> start();
  Future<void> stop();
}

class SdkTripTracker implements TripTracker {
  SdkTripTracker(this.sdk);
  final TraccarClientSdk sdk;

  @override
  Future<bool> isTracking() => sdk.isTracking();

  @override
  Future<void> start() => sdk.start();

  @override
  Future<void> stop() => sdk.stop();
}

abstract class TripStore {
  Trip? get activeTrip;
  Future<void> saveActiveTrip(Trip trip);
  Future<void> clearActiveTrip();
}

class PreferencesTripStore implements TripStore {
  PreferencesTripStore(this.preferences);
  final SharedPreferencesWithCache preferences;

  @override
  Trip? get activeTrip {
    final startedAt = preferences.getInt(Preferences.activeTripStartedAt);
    if (startedAt == null) return null;
    return Trip(DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true));
  }

  @override
  Future<void> saveActiveTrip(Trip trip) => preferences.setInt(
    Preferences.activeTripStartedAt,
    trip.startedAt.millisecondsSinceEpoch,
  );

  @override
  Future<void> clearActiveTrip() =>
      preferences.remove(Preferences.activeTripStartedAt);
}

class TripController extends ChangeNotifier {
  TripController({
    required TripTracker tracker,
    required TripStore store,
    DateTime Function()? now,
  }) : _tracker = tracker,
       _store = store,
       _now = now ?? DateTime.now;

  final TripTracker _tracker;
  final TripStore _store;
  final DateTime Function() _now;

  Trip? _activeTrip;
  bool _busy = false;

  Trip? get activeTrip => _activeTrip;
  bool get busy => _busy;

  Future<void> initialize() async {
    final stored = _store.activeTrip;
    final tracking = await _tracker.isTracking();
    if (stored == null && tracking) {
      await _tracker.stop();
    } else if (stored != null && !tracking) {
      await _store.clearActiveTrip();
    } else {
      _activeTrip = stored;
    }
    notifyListeners();
  }

  Future<void> startTrip() async {
    if (_busy || _activeTrip != null) return;
    _setBusy(true);
    final trip = Trip(_now().toUtc());
    var startAttempted = false;
    try {
      await _store.saveActiveTrip(trip);
      startAttempted = true;
      await _tracker.start();
      _activeTrip = trip;
    } catch (error, stackTrace) {
      if (startAttempted) {
        try {
          await _tracker.stop();
        } catch (stopError, stopStackTrace) {
          // Do not claim privacy mode is on unless stopping succeeded.
          _activeTrip = trip;
          Error.throwWithStackTrace(stopError, stopStackTrace);
        }
      }
      await _store.clearActiveTrip();
      _activeTrip = null;
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> endTrip() async {
    if (_busy || _activeTrip == null) return;
    _setBusy(true);
    try {
      await _tracker.stop();
      _activeTrip = null;
      await _store.clearActiveTrip();
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}

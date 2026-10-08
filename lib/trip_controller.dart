import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

import 'preferences.dart';

class Trip {
  const Trip(this.id, this.startedAt);

  final String id;
  final DateTime startedAt;
}

class TripMarker {
  const TripMarker(this.tripId, this.state, this.at);

  final String tripId;
  final String state;
  final DateTime at;

  Map<String, String> toJson() => {
    'tripId': tripId,
    'tripState': state,
    'timestamp': at.millisecondsSinceEpoch.toString(),
    'tripEventAt': at.toIso8601String(),
  };

  factory TripMarker.fromJson(Map<String, dynamic> value) => TripMarker(
    value['tripId'] as String,
    value['tripState'] as String,
    DateTime.fromMillisecondsSinceEpoch(
      int.parse(value['timestamp'] as String),
      isUtc: true,
    ),
  );
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
  List<TripMarker> get pendingMarkers;
  Future<void> savePendingMarkers(List<TripMarker> markers);
}

class PreferencesTripStore implements TripStore {
  PreferencesTripStore(this.preferences);
  final SharedPreferencesWithCache preferences;

  @override
  Trip? get activeTrip {
    final id = preferences.getString(Preferences.activeTripId);
    final startedAt = preferences.getInt(Preferences.activeTripStartedAt);
    if (id == null || startedAt == null) return null;
    return Trip(
      id,
      DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
    );
  }

  @override
  Future<void> saveActiveTrip(Trip trip) async {
    await preferences.setString(Preferences.activeTripId, trip.id);
    await preferences.setInt(
      Preferences.activeTripStartedAt,
      trip.startedAt.millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> clearActiveTrip() async {
    await preferences.remove(Preferences.activeTripId);
    await preferences.remove(Preferences.activeTripStartedAt);
  }

  @override
  List<TripMarker> get pendingMarkers {
    final raw = preferences.getString(Preferences.pendingTripMarkers);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((value) => TripMarker.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> savePendingMarkers(List<TripMarker> markers) =>
      preferences.setString(
        Preferences.pendingTripMarkers,
        jsonEncode(markers.map((marker) => marker.toJson()).toList()),
      );
}

abstract class TripMarkerSender {
  Future<bool> send(TripMarker marker);
}

/// Sends metadata only. It never asks Android for a location fix.
class OsmAndTripMarkerSender implements TripMarkerSender {
  OsmAndTripMarkerSender({required this.serverUrl, required this.deviceId});

  final Uri serverUrl;
  final String deviceId;

  @override
  Future<bool> send(TripMarker marker) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(serverUrl)
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(
        Uri(queryParameters: {'id': deviceId, ...marker.toJson()}).query,
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      // An HTML 200 often means the reverse proxy sent us to the web UI.
      return response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.headers.contentType?.mimeType != 'text/html';
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

class TripController extends ChangeNotifier {
  TripController({
    required TripTracker tracker,
    required TripStore store,
    required TripMarkerSender markerSender,
    DateTime Function()? now,
    String Function()? newTripId,
  }) : _tracker = tracker,
       _store = store,
       _markerSender = markerSender,
       _now = now ?? DateTime.now,
       _newTripId = newTripId ?? _generateTripId {
    _retryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(flushMarkers()),
    );
  }

  final TripTracker _tracker;
  final TripStore _store;
  final TripMarkerSender _markerSender;
  final DateTime Function() _now;
  final String Function() _newTripId;

  Trip? _activeTrip;
  bool _busy = false;
  Future<void>? _flushFuture;
  Future<void> _queueTail = Future.value();
  late final Timer _retryTimer;

  Trip? get activeTrip => _activeTrip;
  bool get busy => _busy;

  static String _generateTripId() {
    final random = Random.secure().nextInt(0x100000000);
    return '${DateTime.now().toUtc().millisecondsSinceEpoch}-${random.toRadixString(16).padLeft(8, '0')}';
  }

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
    unawaited(flushMarkers());
  }

  Future<void> startTrip() async {
    if (_busy || _activeTrip != null) return;
    _setBusy(true);
    final trip = Trip(_newTripId(), _now().toUtc());
    var startAttempted = false;
    try {
      await _store.saveActiveTrip(trip);
      startAttempted = true;
      await _tracker.start();
      _activeTrip = trip;
      await _enqueue(TripMarker(trip.id, 'start', trip.startedAt));
      unawaited(flushMarkers());
    } catch (error, stackTrace) {
      if (startAttempted) {
        try {
          await _tracker.stop();
        } catch (stopError, stopStackTrace) {
          // Keep the trip visible if we cannot prove tracking has stopped.
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
    final trip = _activeTrip;
    if (_busy || trip == null) return;
    _setBusy(true);
    try {
      await _tracker.stop();
      await _store.clearActiveTrip();
      _activeTrip = null;
      await _enqueue(TripMarker(trip.id, 'end', _now().toUtc()));
      unawaited(flushMarkers());
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _enqueue(TripMarker marker) => _withQueueLock(() async {
    await _store.savePendingMarkers([..._store.pendingMarkers, marker]);
  });

  Future<T> _withQueueLock<T>(Future<T> Function() action) async {
    final previous = _queueTail;
    final done = Completer<void>();
    _queueTail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<void> flushMarkers() =>
      _flushFuture ??= _flush().whenComplete(() => _flushFuture = null);

  Future<void> _flush() async {
    while (_store.pendingMarkers.isNotEmpty) {
      final marker = _store.pendingMarkers.first;
      if (!await _markerSender.send(marker)) return;
      await _withQueueLock(() async {
        final pending = _store.pendingMarkers;
        if (pending.isNotEmpty &&
            pending.first.tripId == marker.tripId &&
            pending.first.state == marker.state &&
            pending.first.at == marker.at) {
          await _store.savePendingMarkers(pending.skip(1).toList());
        }
      });
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer.cancel();
    super.dispose();
  }
}

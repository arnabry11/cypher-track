import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

class Preferences {
  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  static const String id = 'id';
  static const String url = 'url';
  static const String accuracy = 'accuracy';
  static const String distance = 'distance';
  static const String interval = 'interval';
  static const String angle = 'angle';
  static const String heartbeat = 'heartbeat';
  static const String buffer = 'buffer';
  static const String wakelock = 'wakelock';
  static const String stopDetection = 'stop_detection';
  static const String preferPlatformProviders = 'prefer_platform_providers';
  static const String password = 'password';
  static const String _legacyActiveTripId = 'active_trip_id';
  static const String activeTripStartedAt = 'active_trip_started_at';
  static const String _legacyPendingTripMarkers = 'pending_trip_markers';

  static Future<void> init() async {
    _initFuture ??= _createInstance();
    await _initFuture;
  }

  static Future<void> _createInstance() async {
    instance = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions:
          Platform.isAndroid
              ? SharedPreferencesAsyncAndroidOptions(
                backend:
                    SharedPreferencesAndroidBackendLibrary.SharedPreferences,
              )
              : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id,
          url,
          accuracy,
          distance,
          interval,
          angle,
          heartbeat,
          buffer,
          wakelock,
          stopDetection,
          preferPlatformProviders,
          password,
          _legacyActiveTripId,
          activeTripStartedAt,
          _legacyPendingTripMarkers,
        },
      ),
    );
    if (Platform.isAndroid) {
      for (final key in {interval, distance, angle, heartbeat}) {
        if (instance.get(key) is String) {
          await instance.setInt(
            key,
            int.tryParse(instance.getString(key) ?? '') ?? 0,
          );
        }
      }
    }
    // Remove unsent metadata markers from older builds. Normal GPS buffering
    // belongs to the SDK and is intentionally untouched.
    await instance.remove(_legacyActiveTripId);
    await instance.remove(_legacyPendingTripMarkers);
    if (instance.getString(id) == null) {
      await instance.setString(
        id,
        (Random.secure().nextInt(90000000) + 10000000).toString(),
      );
    }
  }

  static Config buildConfig() {
    return Config(
      serverUrl: 'https://tracking.arnabroy.co.in/',
      deviceId: instance.getString(id) ?? '',
      location: LocationConfig(
        accuracy: Accuracy.high,
        distanceMeters: 75,
        heartbeatIntervalSeconds: 300,
        stopDetection: true,
      ),
      buffer: true,
      preferPlatformProviders: true,
    );
  }
}

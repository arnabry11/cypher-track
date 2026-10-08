import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
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
  static const String activeTripId = 'active_trip_id';
  static const String activeTripStartedAt = 'active_trip_started_at';
  static const String pendingTripMarkers = 'pending_trip_markers';

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
          activeTripId,
          activeTripStartedAt,
          pendingTripMarkers,
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
    if (instance.getString(id) == null) {
      await instance.setString(
        id,
        (Random.secure().nextInt(90000000) + 10000000).toString(),
      );
    }
  }

  static Config buildConfig() {
    const testDeviceId = String.fromEnvironment('CYPHER_TEST_DEVICE_ID');
    return Config(
      serverUrl: 'https://tracking.arnabroy.co.in/',
      deviceId:
          kDebugMode && testDeviceId.isNotEmpty
              ? testDeviceId
              : instance.getString(id) ?? '',
      location: LocationConfig(
        accuracy: Accuracy.high,
        distanceMeters: 50,
        heartbeatIntervalSeconds: 0,
        stopDetection: true,
      ),
      buffer: true,
      preferPlatformProviders: true,
    );
  }
}

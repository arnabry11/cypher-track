import 'package:flutter/material.dart';

import 'geolocation_service.dart';
import 'main_screen.dart';
import 'preferences.dart';
import 'trip_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferences.init();

  final tracker = GeolocationService.tracker;
  final config = Preferences.buildConfig();
  await tracker.init(config);
  final store = PreferencesTripStore(Preferences.instance);
  if (store.activeTrip == null && await tracker.isTracking()) {
    await tracker.stop();
  }
  await tracker.setConfig(config);

  final trips = TripController(tracker: SdkTripTracker(tracker), store: store);
  await trips.initialize();
  runApp(CypherTrackApp(trips: trips, deviceId: config.deviceId));
}

class CypherTrackApp extends StatelessWidget {
  const CypherTrackApp({
    required this.trips,
    required this.deviceId,
    super.key,
  });

  final TripController trips;
  final String deviceId;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cypher Track',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF006A61),
        brightness: Brightness.light,
        surface: const Color(0xFFF6F8F7),
      ),
      scaffoldBackgroundColor: const Color(0xFFE8EFF0),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF81D8CB),
        brightness: Brightness.dark,
        surface: const Color(0xFF17242C),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D151B),
    ),
    home: MainScreen(trips: trips, deviceId: deviceId),
  );
}

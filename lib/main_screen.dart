import 'dart:async';

import 'package:flutter/material.dart';

import 'trip_controller.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({required this.trips, required this.deviceId, super.key});

  final TripController trips;
  final String deviceId;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.trips.addListener(_refresh);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.trips.activeTrip != null) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trips != widget.trips) {
      oldWidget.trips.removeListener(_refresh);
      widget.trips.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.trips.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _elapsed(DateTime startedAt) {
    final seconds = DateTime.now()
        .toUtc()
        .difference(startedAt)
        .inSeconds
        .clamp(0, 999999999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Trip action failed. Check location permission and try again. ($error)',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trips.activeTrip;
    final active = trip != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFFAABBC3) : const Color(0xFF425D63);
    final accent = dark ? const Color(0xFF81D8CB) : const Color(0xFF005F56);
    final panel = dark ? const Color(0xFF17242C) : const Color(0xFFF6F8F7);
    final border = dark ? const Color(0xFF355159) : const Color(0xFFB8C9C9);
    final activeBorder =
        dark ? const Color(0xFF5A9990) : const Color(0xFF3B8179);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                        ),
                        child: Icon(
                          Icons.alt_route_rounded,
                          color: accent,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CYPHER',
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'TRACK',
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4.6,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEVICE IDENTIFIER',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 9),
                        SelectableText(
                          widget.deviceId,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: active ? activeBorder : border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: active ? accent : muted,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              active ? 'TRIP IN PROGRESS' : 'NO ACTIVE TRIP',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.7,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          active ? _elapsed(trip.startedAt) : '00:00:00',
                          key: const Key('tripTimer'),
                          style: Theme.of(
                            context,
                          ).textTheme.displayMedium?.copyWith(
                            color:
                                active
                                    ? accent
                                    : (dark
                                        ? const Color(0xFFE2ECEF)
                                        : const Color(0xFF12343A)),
                            fontWeight: FontWeight.w600,
                            fontFeatures: [const FontFeature.tabularFigures()],
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'TRIP DURATION',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              active || widget.trips.busy
                                  ? null
                                  : () => _perform(widget.trips.startTrip),
                          child: const Text('Start Trip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              !active || widget.trips.busy
                                  ? null
                                  : () => _perform(widget.trips.endTrip),
                          child: const Text('End Trip'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          active
                              ? 'Location is shared only during this trip.'
                              : 'Location tracking is off until you start a trip.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

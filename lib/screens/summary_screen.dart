import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:camera/camera.dart';
import '../models/run_sessions.dart';
import '../providers/sessions_provider.dart';
import 'home_screen.dart';

class SummaryScreen extends ConsumerStatefulWidget {
  final RunSession session;
  final CameraController? cam;
  const SummaryScreen({super.key, required this.session, this.cam});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {

  @override
  void initState() {
    super.initState();
    // Dispose the passed-in controller — we don't use it here
    widget.cam?.dispose();
  }

  LatLng get _center {
    final pts = widget.session.routePoints;
    if (pts.isEmpty) return const LatLng(0, 0);
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: const Color(0xFF080808),
          leading: GestureDetector(
            onTap: _goHome,
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          ),
          title: const Text('RUNNE\$T',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  fontSize: 16)),
          flexibleSpace: FlexibleSpaceBar(
            background: s.routePoints.isNotEmpty
                ? FlutterMap(
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.runnest',
                ),
                if (s.routePoints.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: s.routePoints,
                      color: Colors.black.withOpacity(0.5),
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                    ),
                    Polyline(
                      points: s.routePoints,
                      color: Colors.white,
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (s.routePoints.isNotEmpty) ...[
                    Marker(
                      point: s.routePoints.first,
                      width: 14, height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: Colors.black54, width: 1.5),
                        ),
                      ),
                    ),
                    Marker(
                      point: s.routePoints.last,
                      width: 14, height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade400,
                          border: Border.all(
                              color: Colors.black54, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            )
                : Container(
                color: const Color(0xFF141414),
                child: const Center(
                    child: Text('No route recorded',
                        style: TextStyle(color: Colors.white24)))),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(children: [
                const Text('🎉', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                const Text('Run Complete!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(_fmtDate(s.startTime),
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
              const SizedBox(height: 24),

              // Stats grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _card('Distance', '${s.formattedDistance} km',
                      Icons.straighten),
                  _card('Time', s.formattedTime, Icons.timer_outlined),
                  _card('Avg Pace', '${s.formattedPace} /km',
                      Icons.speed_outlined),
                  _card('Calories', s.estimatedCalories,
                      Icons.local_fire_department_outlined),
                  _card('Steps', s.steps > 0 ? s.formattedSteps : '--',
                      Icons.directions_walk_outlined),
                  _card('Cadence', s.formattedCadence,
                      Icons.av_timer_outlined),
                ],
              ),
              const SizedBox(height: 24),

              // Show photo only if one was taken during the run
              if (s.photoPath != null) _photoSection(s),

              const SizedBox(height: 32),

              // Done button
              GestureDetector(
                onTap: _goHome,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(29),
                    gradient: const LinearGradient(
                      colors: [Colors.white, Color(0xFFBBBBBB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2)
                    ],
                  ),
                  child: const Center(
                    child: Text('DONE',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 4)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _card(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF111111),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ],
    ),
  );

  Widget _photoSection(RunSession s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Run Photo',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(File(s.photoPath!),
            width: double.infinity, fit: BoxFit.cover),
      ),
      const SizedBox(height: 8),
      const Text('Stats & route overlaid on photo',
          style: TextStyle(color: Colors.white24, fontSize: 11)),
      const SizedBox(height: 24),
    ]);
  }

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}  •  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
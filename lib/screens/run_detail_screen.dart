import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/run_sessions.dart';

class RunDetailScreen extends StatelessWidget {
  final RunSession session;
  const RunDetailScreen({super.key, required this.session});

  LatLng get _center {
    final pts = session.routePoints;
    if (pts.isEmpty) return const LatLng(0, 0);
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          backgroundColor: const Color(0xFF080808),
          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
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
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all),
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
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                    Polyline(
                      points: s.routePoints,
                      color: Colors.white,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (s.routePoints.isNotEmpty) ...[
                    Marker(
                      point: s.routePoints.first,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: Colors.black54, width: 2),
                        ),
                      ),
                    ),
                    Marker(
                      point: s.routePoints.last,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade400,
                          border: Border.all(
                              color: Colors.black54, width: 2),
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
                    child: Text('No route data',
                        style: TextStyle(color: Colors.white24)))),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(_fmtDate(s.startTime),
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                const Text('Run Activity',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),

                // Primary stats
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.07)),
                  ),
                  child: Row(children: [
                    _bigStat('${s.formattedDistance}', 'km', 'Distance'),
                    _vDivider(),
                    _bigStat(s.formattedTime, '', 'Time'),
                    _vDivider(),
                    _bigStat(s.formattedPace, '/km', 'Avg Pace'),
                  ]),
                ),
                const SizedBox(height: 16),

                // Secondary grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                  children: [
                    _miniCard('Calories', s.estimatedCalories,
                        Icons.local_fire_department_outlined),
                    _miniCard('Avg Speed', _avgSpeed(s),
                        Icons.speed_outlined),
                    _miniCard('Duration', s.formattedTime,
                        Icons.timer_outlined),
                    _miniCard('Points', '${s.routePoints.length}',
                        Icons.location_on_outlined),
                  ],
                ),
                const SizedBox(height: 24),

                // Route legend
                if (s.routePoints.isNotEmpty) ...[
                  const Text('Route',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(children: [
                    _legendDot(Colors.white),
                    const SizedBox(width: 8),
                    const Text('Start',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13)),
                    const SizedBox(width: 24),
                    _legendDot(Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Finish',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13)),
                    const Spacer(),
                    Container(
                      width: 30,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Route',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 13)),
                  ]),
                  const SizedBox(height: 24),
                ],

                // Photo
                if (s.photoPath != null) ...[
                  const Text('Run Photo',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(File(s.photoPath!),
                        width: double.infinity, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 16),
              ])),
        ),
      ]),
    );
  }

  Widget _bigStat(String value, String unit, String label) =>
      Expanded(
        child: Column(children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900)),
                if (unit.isNotEmpty)
                  Padding(
                    padding:
                    const EdgeInsets.only(bottom: 3, left: 3),
                    child: Text(unit,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  ),
              ]),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 0.5)),
        ]),
      );

  Widget _vDivider() => Container(
      width: 1,
      height: 38,
      color: Colors.white12,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _miniCard(String label, String value, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white54, size: 18),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
          ]),
        ]),
      );

  Widget _legendDot(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.black38, width: 1.5)));

  String _avgSpeed(RunSession s) {
    if (s.elapsed.inSeconds == 0) return '0.0 km/h';
    final kmh =
        s.distanceKm / (s.elapsed.inSeconds / 3600);
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  String _fmtDate(DateTime dt) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    const days = [
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
    ];
    final day = days[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$day, $month ${dt.day} ${dt.year}  •  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
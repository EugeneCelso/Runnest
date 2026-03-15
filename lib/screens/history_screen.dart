import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/run_sessions.dart';
import '../providers/sessions_provider.dart';
import 'run_detail_screen.dart';

// Keep the same constructor so home_screen.dart still passes sessions/onDelete
// but now HistoryScreen also watches the provider directly for live updates
class HistoryScreen extends ConsumerWidget {
  final List<RunSession> sessions;
  final Function(String id) onDelete;

  const HistoryScreen(
      {super.key, required this.sessions, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch provider so deleting a run auto-refreshes without calling _load()
    final sessionsAsync = ref.watch(sessionsProvider);
    final liveList = sessionsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => sessions, // fallback to prop while loading
    );

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFFAAAAAA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Text('My Runs',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        if (liveList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
                '${liveList.length} run${liveList.length == 1 ? '' : 's'} recorded',
                style:
                const TextStyle(color: Colors.white24, fontSize: 13)),
          ),
        if (liveList.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF111111),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.directions_run,
                          color: Colors.white12, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text('No runs yet',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const Text('Complete a run to see it here',
                        style: TextStyle(
                            color: Colors.white12, fontSize: 13)),
                  ]),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: liveList.length,
              itemBuilder: (_, i) => _RunCard(session: liveList[i]),
            ),
          ),
      ]),
    );
  }
}

class _RunCard extends ConsumerWidget {
  final RunSession session;
  const _RunCard({required this.session});

  LatLng get _center {
    final pts = session.routePoints;
    if (pts.isEmpty) return const LatLng(0, 0);
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => RunDetailScreen(session: s))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Map preview
          ClipRRect(
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(22)),
            child: Stack(children: [
              SizedBox(
                height: 160,
                child: s.routePoints.isNotEmpty
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
                            strokeCap: StrokeCap.round),
                        Polyline(
                            points: s.routePoints,
                            color: Colors.white,
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round),
                      ]),
                    MarkerLayer(markers: [
                      if (s.routePoints.isNotEmpty) ...[
                        Marker(
                            point: s.routePoints.first,
                            width: 12,
                            height: 12,
                            child: Container(
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                        color: Colors.black38,
                                        width: 1.5)))),
                        Marker(
                            point: s.routePoints.last,
                            width: 12,
                            height: 12,
                            child: Container(
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey.shade400,
                                    border: Border.all(
                                        color: Colors.black38,
                                        width: 1.5)))),
                      ],
                    ]),
                  ],
                )
                    : Container(
                    color: const Color(0xFF181818),
                    child: const Center(
                        child: Icon(Icons.map_outlined,
                            color: Colors.white12, size: 40))),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.open_in_new,
                        color: Colors.white38, size: 11),
                    SizedBox(width: 4),
                    Text('Details',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ]),
                ),
              ),
            ]),
          ),

          // Photo thumbnail
          if (s.photoPath != null)
            Stack(children: [
              Container(
                height: 100,
                decoration: BoxDecoration(
                  image: DecorationImage(
                      image: FileImage(File(s.photoPath!)),
                      fit: BoxFit.cover),
                ),
              ),
              Positioned(
                bottom: 6,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Row(children: [
                    Icon(Icons.photo_camera,
                        color: Colors.white38, size: 11),
                    SizedBox(width: 4),
                    Text('Run photo',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 10)),
                  ]),
                ),
              ),
            ]),

          // Stats
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fmtDate(s.startTime),
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _stat('${s.formattedDistance} km', 'Distance'),
                    _stat(s.formattedTime, 'Time'),
                    _stat('${s.formattedPace} /km', 'Pace'),
                    _stat(s.estimatedCalories, 'Cal'),
                  ]),
                  if (s.steps > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                        height: 1,
                        color: Colors.white.withOpacity(0.05)),
                    const SizedBox(height: 10),
                    Row(children: [
                      _stat(s.formattedSteps, 'Steps'),
                      _stat(s.formattedCadence, 'Cadence'),
                      _stat('', ''),
                      _stat('', ''),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    RunDetailScreen(session: s))),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [
                                Colors.white,
                                Color(0xFFBBBBBB)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Text('View Details',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 0.5)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _confirmDelete(context, ref),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.15)),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white38, size: 18),
                      ),
                    ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(
              color: Colors.white24, fontSize: 10)),
    ]),
  );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
          title: const Text('Delete Run?',
              style: TextStyle(color: Colors.white)),
          content: const Text('This cannot be undone.',
              style: TextStyle(color: Colors.white54)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.bold))),
          ],
        ));
    if (ok == true) {
      ref.read(sessionsProvider.notifier).deleteSession(session.id);
    }
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
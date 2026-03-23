import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/run_sessions.dart';
import 'ios_icons.dart';

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
    final topPad = MediaQuery.of(context).padding.top;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF080808),
      child: Column(children: [
        // ── Fixed map header ──────────────────────────────────────
        SizedBox(
          height: 300 + topPad,
          child: Stack(children: [
            Positioned.fill(
              child: s.routePoints.isNotEmpty
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
                        color: const Color(0x80000000),
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                      Polyline(
                        points: s.routePoints,
                        color: CupertinoColors.white,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                    ]),
                  MarkerLayer(markers: [
                    if (s.routePoints.isNotEmpty) ...[
                      Marker(
                        point: s.routePoints.first,
                        width: 18, height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CupertinoColors.white,
                            border: Border.all(
                                color: const Color(0x80000000),
                                width: 2),
                          ),
                        ),
                      ),
                      Marker(
                        point: s.routePoints.last,
                        width: 18, height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFAAAAAA),
                            border: Border.all(
                                color: const Color(0x80000000),
                                width: 2),
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
                      child: AppIcon(Ic.map, size: 40,
                          color: Color(0xFF3A3A3C)))),
            ),

            // Top gradient
            Positioned(
              top: 0, left: 0, right: 0,
              height: topPad + 70,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),

            // Bottom fade
            Positioned(
              bottom: 0, left: 0, right: 0, height: 70,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xFF080808), Color(0x00000000)],
                  ),
                ),
              ),
            ),

            // Nav
            Positioned(
              top: topPad, left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xCC000000),
                          border: Border.all(
                              color: const Color(0xFF3A3A3C), width: 0.5),
                        ),
                        child: const Center(
                            child: AppIcon(Ic.back, size: 20,
                                color: CupertinoColors.white)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF2C2C2E), width: 0.5),
                      ),
                      child: const Text('RUNNE\$T',
                          style: TextStyle(
                              color: CupertinoColors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              fontSize: 13,
                              decoration: TextDecoration.none)),
                    ),
                    const SizedBox(width: 38),
                  ],
                ),
              ),
            ),
          ]),
        ),

        // ── Scrollable content ────────────────────────────────────
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(_fmtDate(s.startTime),
                        style: const TextStyle(
                            color: Color(0xFF636366),
                            fontSize: 12,
                            letterSpacing: 0.3,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 4),
                    const Text('Run Activity',
                        style: TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 20),

                    // Primary stat bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: const Color(0xFF2C2C2E), width: 0.5),
                      ),
                      child: Row(children: [
                        _bigStat(s.formattedDistance, 'km', 'Distance'),
                        _vDiv(),
                        _bigStat(s.formattedTime, '', 'Time'),
                        _vDiv(),
                        _bigStat(s.formattedPace, '/km', 'Avg Pace'),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Secondary grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.55,
                      children: [
                        _miniCard('Calories', s.estimatedCalories, Ic.fire),
                        _miniCard('Avg Speed', _avgSpeed(s), Ic.speed),
                        _miniCard('Steps',
                            s.steps > 0 ? s.formattedSteps : '--', Ic.steps),
                        _miniCard('Cadence', _cadence(s), Ic.cadence),
                        _miniCard('Duration', s.formattedTime, Ic.timer),
                        _miniCard(
                            'GPS Points', '${s.routePoints.length}', Ic.gps),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Route legend
                    if (s.routePoints.isNotEmpty) ...[
                      _sectionLabel('Route'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFF2C2C2E), width: 0.5),
                        ),
                        child: Row(children: [
                          _dot(CupertinoColors.white),
                          const SizedBox(width: 6),
                          const Text('Start',
                              style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 13,
                                  decoration: TextDecoration.none)),
                          const SizedBox(width: 20),
                          _dot(const Color(0xFF8E8E93)),
                          const SizedBox(width: 6),
                          const Text('Finish',
                              style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 13,
                                  decoration: TextDecoration.none)),
                          const Spacer(),
                          Container(
                            width: 28, height: 3,
                            decoration: BoxDecoration(
                              color: CupertinoColors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Route',
                              style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 13,
                                  decoration: TextDecoration.none)),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Photo
                    if (s.photoPath != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _sectionLabel('Run Photo'),
                          GestureDetector(
                            onTap: () => _sharePhoto(s.photoPath!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF2C2C2E),
                                    width: 0.5),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('⬆',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: CupertinoColors.white,
                                          decoration: TextDecoration.none)),
                                  SizedBox(width: 6),
                                  Text('Share',
                                      style: TextStyle(
                                          color: CupertinoColors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.none)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(File(s.photoPath!),
                            width: double.infinity, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _sharePhoto(s.photoPath!),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: const Color(0xFF2C2C2E), width: 0.5),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('⬆',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: CupertinoColors.white,
                                      decoration: TextDecoration.none)),
                              SizedBox(width: 8),
                              Text('Share Run Photo',
                                  style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                      decoration: TextDecoration.none)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _sharePhoto(String path) async {
    try {
      await Share.shareXFiles(
        [XFile(path)],
        text: 'My run with RUNNE\$T 🏃',
      );
    } catch (e) {
      debugPrint('Share error: \$e');
    }
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          color: CupertinoColors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none));

  Widget _bigStat(String value, String unit, String label) => Expanded(
    child: Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none)),
          if (unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 2),
              child: Text(unit,
                  style: const TextStyle(
                      color: Color(0xFF636366),
                      fontSize: 12,
                      decoration: TextDecoration.none)),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(
              color: Color(0xFF636366),
              fontSize: 11,
              letterSpacing: 0.3,
              decoration: TextDecoration.none)),
    ]),
  );

  Widget _vDiv() => Container(
      width: 0.5,
      height: 36,
      color: const Color(0xFF2C2C2E),
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _miniCard(String label, String value, String glyph) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Icon badge top-left
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
              child: AppIcon(glyph, size: 16,
                  color: const Color(0xFF8E8E93))),
        ),
        // Value + label stacked
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.3,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF636366),
                    fontSize: 11,
                    decoration: TextDecoration.none)),
          ],
        ),
      ],
    ),
  );

  Widget _dot(Color c) => Container(
      width: 11, height: 11,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border:
          Border.all(color: const Color(0x61000000), width: 1.5)));

  String _avgSpeed(RunSession s) {
    if (s.elapsed.inSeconds == 0) return '0.0 km/h';
    return '${(s.distanceKm / (s.elapsed.inSeconds / 3600)).toStringAsFixed(1)} km/h';
  }

  String _cadence(RunSession s) {
    if (s.elapsed.inSeconds < 10 || s.steps == 0) return '--';
    return '${(s.steps / (s.elapsed.inSeconds / 60)).round()} spm';
  }

  String _fmtDate(DateTime dt) {
    const mo = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    const dy = [
      'Monday','Tuesday','Wednesday','Thursday',
      'Friday','Saturday','Sunday'
    ];
    return '${dy[dt.weekday - 1]}, ${mo[dt.month - 1]} ${dt.day} ${dt.year}  ·  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:camera/camera.dart';
import '../models/run_sessions.dart';
import '../providers/sessions_provider.dart';
import 'home_screen.dart';
import 'ios_icons.dart';

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

  void _goHome() => Navigator.pushAndRemoveUntil(
    context,
    CupertinoPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
  );

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

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final topPad = MediaQuery.of(context).padding.top;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF080808),
      child: Column(children: [
        // ── Fixed map header ──────────────────────────────────────
        SizedBox(
          height: 280 + topPad,
          child: Stack(children: [
            Positioned.fill(
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
                        color: const Color(0x80000000),
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                      ),
                      Polyline(
                        points: s.routePoints,
                        color: CupertinoColors.white,
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
                            color: CupertinoColors.white,
                            border: Border.all(
                                color: const Color(0x80000000),
                                width: 1.5),
                          ),
                        ),
                      ),
                      Marker(
                        point: s.routePoints.last,
                        width: 14, height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFAAAAAA),
                            border: Border.all(
                                color: const Color(0x80000000),
                                width: 1.5),
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
                      onTap: _goHome,
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Header
                    Row(children: [
                      const Text('🎉',
                          style: TextStyle(fontSize: 26,
                              decoration: TextDecoration.none)),
                      const SizedBox(width: 10),
                      const Text('Run Complete!',
                          style: TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none)),
                    ]),
                    const SizedBox(height: 4),
                    Text(_fmtDate(s.startTime),
                        style: const TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 12,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 22),

                    // Stats grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.65,
                      children: [
                        _card('Distance',
                            '${s.formattedDistance} km', Ic.distance),
                        _card('Time', s.formattedTime, Ic.timer),
                        _card('Avg Pace',
                            '${s.formattedPace} /km', Ic.pace),
                        _card('Calories', s.estimatedCalories, Ic.fire),
                        _card('Steps',
                            s.steps > 0 ? s.formattedSteps : '--',
                            Ic.steps),
                        _card('Cadence', s.formattedCadence, Ic.cadence),
                      ],
                    ),
                    const SizedBox(height: 22),

                    if (s.photoPath != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Run Photo',
                              style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  decoration: TextDecoration.none)),
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
                      // Full-width share button below image
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
                      const SizedBox(height: 22),
                    ],

                    // Done
                    GestureDetector(
                      onTap: _goHome,
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: CupertinoColors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                                color:
                                CupertinoColors.white.withOpacity(0.15),
                                blurRadius: 24,
                                spreadRadius: 2),
                          ],
                        ),
                        child: const Center(
                          child: Text('DONE',
                              style: TextStyle(
                                  color: CupertinoColors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 4,
                                  decoration: TextDecoration.none)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _card(String label, String value, String glyph) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
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
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF636366),
                  fontSize: 11,
                  decoration: TextDecoration.none)),
        ]),
      ],
    ),
  );

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}  ·  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
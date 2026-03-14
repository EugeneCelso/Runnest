import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:camera/camera.dart';
import '../models/run_sessions.dart';
import '../services/photo_overlay_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';

class SummaryScreen extends StatefulWidget {
  final RunSession session;
  final CameraController? cam;
  const SummaryScreen({super.key, required this.session, this.cam});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _overlay = PhotoOverlayService();
  final _storage = StorageService();
  bool _taking = false;
  bool _camReady = false;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _camReady = widget.cam != null && widget.cam!.value.isInitialized;
        });
      }
    });
  }

  @override
  void dispose() {
    widget.cam?.dispose();
    super.dispose();
  }

  LatLng get _center {
    final pts = widget.session.routePoints;
    if (pts.isEmpty) return const LatLng(0, 0);
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
    );
  }

  Future<void> _takeFinishPhoto() async {
    if (!_camReady || _taking) return;
    final cam = widget.cam;
    if (cam == null || !cam.value.isInitialized) return;

    setState(() => _taking = true);
    try {
      final xfile = await cam.takePicture();
      final path = await _overlay.burnOverlay(xfile.path, widget.session);
      if (path != null && mounted) {
        // Update session in memory
        widget.session.photoPath = path;
        // Persist the updated session so photo shows in history
        await _storage.updateSession(widget.session);
        setState(() => _showPreview = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('📸 Photo saved!'),
                duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('Summary photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo failed — please retry'),
              duration: Duration(seconds: 2)),
        );
      }
    }
    if (mounted) setState(() => _taking = false);
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
                      point: s.routePoints.first, width: 14, height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: Colors.white,
                          border: Border.all(color: Colors.black54, width: 1.5),
                        ),
                      ),
                    ),
                    Marker(
                      point: s.routePoints.last, width: 14, height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: Colors.grey.shade400,
                          border: Border.all(color: Colors.black54, width: 1.5),
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

              // Stats grid — 6 cards including steps + cadence
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
                  _card('Cadence', _cadence(s), Icons.av_timer_outlined),
                ],
              ),
              const SizedBox(height: 24),

              // Photo section
              _photoSection(s),
              const SizedBox(height: 32),

              // Done
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
                        blurRadius: 20, spreadRadius: 2,
                      )
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
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ],
    ),
  );

  Widget _photoSection(RunSession s) {
    // ── Photo already taken ───────────────────────────────────────────
    if (s.photoPath != null) {
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
      ]);
    }

    // ── Camera available ──────────────────────────────────────────────
    if (_camReady && widget.cam != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Capture the moment',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),

        if (_showPreview) ...[
          // Full-width tall preview
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: CameraPreview(widget.cam!),
              ),
              // Bottom gradient
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 130,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(18)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.78),
                      ],
                    ),
                  ),
                ),
              ),
              // Shutter
              Positioned(
                bottom: 28, left: 0, right: 0,
                child: Center(
                  child: _taking
                      ? const SizedBox(
                    width: 76, height: 76,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                      : GestureDetector(
                    onTap: _takeFinishPhoto,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.black26, width: 3),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.white.withOpacity(0.35),
                              blurRadius: 22,
                              spreadRadius: 2)
                        ],
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.black, size: 36),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _showPreview = false),
            child: const Center(
              child: Text('Cancel',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          ),
        ] else ...[
          // Wide open-camera button
          GestureDetector(
            onTap: () => setState(() => _showPreview = true),
            child: Container(
              width: double.infinity,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF111111),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(children: [
                const SizedBox(width: 20),
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: Colors.white70, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Open Camera',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      Text('Photo will include stats + route overlay',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 22),
                const SizedBox(width: 16),
              ]),
            ),
          ),
        ],
      ]);
    }

    return const SizedBox.shrink();
  }

  String _cadence(RunSession s) {
    if (s.elapsed.inSeconds < 10 || s.steps == 0) return '--';
    final spm = (s.steps / (s.elapsed.inSeconds / 60)).round();
    return '$spm spm';
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
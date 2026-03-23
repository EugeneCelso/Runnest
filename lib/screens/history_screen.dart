import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/run_sessions.dart';
import '../providers/sessions_provider.dart';
import 'run_detail_screen.dart';
import 'ios_icons.dart';

class HistoryScreen extends ConsumerWidget {
  final List<RunSession> sessions;
  final Function(String id) onDelete;

  const HistoryScreen(
      {super.key, required this.sessions, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveList = ref.watch(sessionsProvider).maybeWhen(
      data: (l) => l,
      orElse: () => sessions,
    );

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverNavigationBar(
          backgroundColor: const Color(0xFF080808),
          border: const Border(),
          largeTitle: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [CupertinoColors.white, Color(0xFF8E8E93)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(b),
            child: const Text('My Runs',
                style: TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w800)),
          ),
        ),

        if (liveList.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${liveList.length} run${liveList.length == 1 ? '' : 's'} recorded',
                style: const TextStyle(
                    color: Color(0xFF3A3A3C),
                    fontSize: 13,
                    decoration: TextDecoration.none),
              ),
            ),
          ),

        if (liveList.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1C1C1E),
                        border: Border.all(
                            color: const Color(0xFF2C2C2E), width: 0.5),
                      ),
                      child: const Center(
                          child: AppIcon(Ic.run, size: 30,
                              color: Color(0xFF3A3A3C))),
                    ),
                    const SizedBox(height: 18),
                    const Text('No runs yet',
                        style: TextStyle(
                            color: Color(0xFF636366),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 6),
                    const Text('Complete a run to see it here',
                        style: TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 13,
                            decoration: TextDecoration.none)),
                  ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) => _RunCard(session: liveList[i]),
                childCount: liveList.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ── Run card ─────────────────────────────────────────────────────
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
      onTap: () => Navigator.push(context,
          CupertinoPageRoute(builder: (_) => RunDetailScreen(session: s))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Map ───────────────────────────────────────────────
              ClipRRect(
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
                child: Stack(children: [
                  SizedBox(
                    height: 155,
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
                                strokeCap: StrokeCap.round),
                            Polyline(
                                points: s.routePoints,
                                color: CupertinoColors.white,
                                strokeWidth: 3.5,
                                strokeCap: StrokeCap.round),
                          ]),
                        MarkerLayer(markers: [
                          if (s.routePoints.isNotEmpty) ...[
                            Marker(
                              point: s.routePoints.first,
                              width: 12, height: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: CupertinoColors.white,
                                  border: Border.all(
                                      color: const Color(0x61000000),
                                      width: 1.5),
                                ),
                              ),
                            ),
                            Marker(
                              point: s.routePoints.last,
                              width: 12, height: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFAAAAAA),
                                  border: Border.all(
                                      color: const Color(0x61000000),
                                      width: 1.5),
                                ),
                              ),
                            ),
                          ],
                        ]),
                      ],
                    )
                        : Container(
                        color: const Color(0xFF2C2C2E),
                        child: const Center(
                            child: AppIcon(Ic.map, size: 36,
                                color: Color(0xFF3A3A3C)))),
                  ),
                  // Details pill
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xA6000000),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF2C2C2E), width: 0.5),
                      ),
                      child: Row(children: const [
                        AppIcon(Ic.detail, size: 11,
                            color: Color(0xFF636366)),
                        SizedBox(width: 4),
                        Text('Details',
                            style: TextStyle(
                                color: Color(0xFF636366),
                                fontSize: 11,
                                decoration: TextDecoration.none)),
                      ]),
                    ),
                  ),
                ]),
              ),

              // ── Photo ─────────────────────────────────────────────
              if (s.photoPath != null)
                Stack(children: [
                  Container(
                    height: 96,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                          image: FileImage(File(s.photoPath!)),
                          fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    bottom: 6, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xA6000000),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: const [
                        AppIcon(Ic.camera, size: 10,
                            color: Color(0xFF636366)),
                        SizedBox(width: 4),
                        Text('Run photo',
                            style: TextStyle(
                                color: Color(0xFF636366),
                                fontSize: 10,
                                decoration: TextDecoration.none)),
                      ]),
                    ),
                  ),
                ]),

              // ── Stats ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtDate(s.startTime),
                          style: const TextStyle(
                              color: Color(0xFF636366),
                              fontSize: 11,
                              letterSpacing: 0.3,
                              decoration: TextDecoration.none)),
                      const SizedBox(height: 12),
                      // Primary stats
                      Row(children: [
                        _statCol('${s.formattedDistance}', 'km', 'Distance'),
                        _statCol(s.formattedTime, '', 'Time'),
                        _statCol(s.formattedPace, '/km', 'Pace'),
                        _statCol(
                            (s.distanceKm * 62).round().toString(), 'kcal', 'Cal'),
                      ]),
                      if (s.steps > 0) ...[
                        const SizedBox(height: 10),
                        Container(height: 0.5, color: const Color(0xFF2C2C2E)),
                        const SizedBox(height: 10),
                        Row(children: [
                          _statCol(s.formattedSteps, '', 'Steps'),
                          _statCol(s.formattedCadence, '', 'Cadence'),
                          const Expanded(child: SizedBox()),
                          const Expanded(child: SizedBox()),
                        ]),
                      ],
                      const SizedBox(height: 14),
                      // Buttons
                      Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                    builder: (_) =>
                                        RunDetailScreen(session: s))),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: CupertinoColors.white,
                                borderRadius: BorderRadius.circular(21),
                              ),
                              child: const Center(
                                child: Text('View Details',
                                    style: TextStyle(
                                        color: CupertinoColors.black,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        letterSpacing: 0.3,
                                        decoration: TextDecoration.none)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => _confirmDelete(context, ref),
                          child: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2C2C2E),
                              border: Border.all(
                                  color: const Color(0xFF3A3A3C), width: 0.5),
                            ),
                            child: const Center(
                                child: AppIcon(Ic.trash, size: 16,
                                    color: Color(0xFF636366))),
                          ),
                        ),
                      ]),
                    ]),
              ),
            ]),
      ),
    );
  }

  Widget _statCol(String value, String unit, String label) => Expanded(
    child: Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: -0.3,
                  decoration: TextDecoration.none)),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(unit,
                  style: const TextStyle(
                      color: Color(0xFF636366),
                      fontSize: 10,
                      decoration: TextDecoration.none)),
            ),
          ],
        ],
      ),
      const SizedBox(height: 3),
      Text(label,
          style: const TextStyle(
              color: Color(0xFF636366),
              fontSize: 11,
              decoration: TextDecoration.none)),
    ]),
  );

  Future<void> _confirmDelete(BuildContext ctx, WidgetRef ref) async {
    await showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Delete Run?'),
        message: const Text('This cannot be undone.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sessionsProvider.notifier).deleteSession(session.id);
            },
            child: const Text('Delete Run'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}  ·  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
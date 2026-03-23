import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_sessions.dart';
import '../providers/sessions_provider.dart';
import 'run_screen.dart';
import 'history_screen.dart';
import 'ios_icons.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Computed stats ──────────────────────────────────────────────
  double _totalKm(List<RunSession> s) =>
      s.fold(0.0, (a, r) => a + r.distanceKm);
  int _totalSteps(List<RunSession> s) =>
      s.fold(0, (a, r) => a + r.steps);
  int _totalCal(List<RunSession> s) =>
      s.fold(0, (a, r) => a + (r.distanceKm * 62).round());
  Duration _totalTime(List<RunSession> s) =>
      s.fold(Duration.zero, (a, r) => a + r.elapsed);

  String _avgPace(List<RunSession> s) {
    final v = s.where((r) => r.pacePerKm > 0).toList();
    if (v.isEmpty) return '--:--';
    final avg = v.fold(0.0, (a, r) => a + r.pacePerKm) / v.length;
    return '${(avg / 60).floor().toString().padLeft(2, '0')}:${(avg % 60).round().toString().padLeft(2, '0')}';
  }

  String _bestPace(List<RunSession> s) {
    final v = s.where((r) => r.pacePerKm > 0).toList();
    if (v.isEmpty) return '--:--';
    final b = v.map((r) => r.pacePerKm).reduce((a, b) => a < b ? a : b);
    return '${(b / 60).floor().toString().padLeft(2, '0')}:${(b % 60).round().toString().padLeft(2, '0')}';
  }

  String _longest(List<RunSession> s) {
    if (s.isEmpty) return '0.00';
    return s.map((r) => r.distanceKm).reduce((a, b) => a > b ? a : b).toStringAsFixed(2);
  }

  String _fmtDur(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _fmtNum(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  double _weekKm(List<RunSession> s) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return s.where((r) => r.startTime.isAfter(start))
        .fold(0.0, (a, r) => a + r.distanceKm);
  }

  int _weekRuns(List<RunSession> s) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return s.where((r) => r.startTime.isAfter(start)).length;
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider);
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF080808),
      child: Column(children: [
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: sessionsAsync.when(
              loading: () => const Center(
                  child: CupertinoActivityIndicator(
                      color: CupertinoColors.white, radius: 14)),
              error: (e, _) => Center(
                  child: Text('$e',
                      style: const TextStyle(
                          color: Color(0xFF636366)))),
              data: (sessions) => _tab == 0
                  ? _buildHome(sessions)
                  : HistoryScreen(
                sessions: sessions,
                onDelete: (id) => ref
                    .read(sessionsProvider.notifier)
                    .deleteSession(id),
              ),
            ),
          ),
        ),
        _buildTabBar(),
      ]),
    );
  }

  // ── Tab bar ─────────────────────────────────────────────────────
  Widget _buildTabBar() => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF0A0A0A),
      border: Border(
          top: BorderSide(color: Color(0xFF1C1C1E), width: 0.5)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 52,
        child: Row(children: [
          _tabItem(0, Ic.home, 'Home'),
          _tabItem(1, Ic.history, 'History'),
        ]),
      ),
    ),
  );

  Widget _tabItem(int index, String glyph, String label) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1C1C1E)
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AppIcon(glyph,
                  size: 18,
                  color: active
                      ? CupertinoColors.white
                      : const Color(0xFF48484A)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  color: active
                      ? CupertinoColors.white
                      : const Color(0xFF48484A),
                  fontWeight:
                  active ? FontWeight.w600 : FontWeight.normal,
                  decoration: TextDecoration.none,
                )),
          ],
        ),
      ),
    );
  }

  // ── Home tab ────────────────────────────────────────────────────
  Widget _buildHome(List<RunSession> sessions) {
    final km = _totalKm(sessions);
    final steps = _totalSteps(sessions);
    final cal = _totalCal(sessions);
    final time = _totalTime(sessions);
    final wKm = _weekKm(sessions);
    final wRuns = _weekRuns(sessions);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        // Large title
        CupertinoSliverNavigationBar(
          backgroundColor: const Color(0xFF080808),
          border: const Border(),
          largeTitle: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [CupertinoColors.white, Color(0xFF8E8E93)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(b),
            child: const Text('RUNNE\$T',
                style: TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
          ),
          trailing: _avatarBtn(),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                sessions.isEmpty
                    ? 'Ready to run?'
                    : '${sessions.length} run${sessions.length == 1 ? '' : 's'} logged',
                style: const TextStyle(
                    color: Color(0xFF48484A), fontSize: 13,
                    decoration: TextDecoration.none),
              ),
              const SizedBox(height: 16),

              if (sessions.isNotEmpty) ...[
                _weekCard(wKm, wRuns),
                const SizedBox(height: 12),
                _statsGrid(sessions, km, steps, cal, time),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 8),

              _startRunCard(),
              const SizedBox(height: 28),

              if (sessions.isNotEmpty) ...[
                _sectionHeader('Recent', onTap: () => setState(() => _tab = 1)),
                const SizedBox(height: 10),
                ...sessions.take(3).map((s) => _recentRow(s)),
              ],
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _avatarBtn() => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF1C1C1E),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: const Center(child: AppIcon(Ic.person, size: 15)),
  );

  Widget _weekCard(double wKm, int wRuns) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: Row(children: [
      const AppIcon(Ic.week, size: 13, color: Color(0xFF636366)),
      const SizedBox(width: 8),
      const Text('This week',
          style: TextStyle(
              color: Color(0xFF636366),
              fontSize: 13,
              decoration: TextDecoration.none)),
      const Spacer(),
      Text('${wKm.toStringAsFixed(1)} km',
          style: const TextStyle(
              color: CupertinoColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: TextDecoration.none)),
      const SizedBox(width: 6),
      Text('· $wRuns run${wRuns == 1 ? '' : 's'}',
          style: const TextStyle(
              color: Color(0xFF48484A),
              fontSize: 13,
              decoration: TextDecoration.none)),
    ]),
  );

  Widget _statsGrid(List<RunSession> s, double km, int steps, int cal,
      Duration time) =>
      Column(children: [
        _statRow(
          '${km.toStringAsFixed(1)} km', 'Total Distance', Ic.distance,
          '${_avgPace(s)} /km', 'Avg Pace', Ic.pace,
        ),
        const SizedBox(height: 10),
        _statRow(
          _fmtNum(steps), 'Total Steps', Ic.steps,
          '${_fmtNum(cal)} kcal', 'Calories', Ic.fire,
        ),
        const SizedBox(height: 10),
        _statRow(
          '${_bestPace(s)} /km', 'Best Pace', Ic.star,
          '${_longest(s)} km', 'Longest Run', Ic.longest,
        ),
        const SizedBox(height: 10),
        _statRow(
          _fmtDur(time), 'Total Time', Ic.timer,
          '${s.length}', 'Total Runs', Ic.repeat,
        ),
      ]);

  Widget _statRow(String v1, String l1, String g1, String v2, String l2,
      String g2) =>
      Row(children: [
        Expanded(child: _statCard(v1, l1, g1)),
        const SizedBox(width: 10),
        Expanded(child: _statCard(v2, l2, g2)),
      ]);

  Widget _statCard(String value, String label, String glyph) => Container(
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
            child: AppIcon(glyph, size: 14,
                color: const Color(0xFF8E8E93))),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 1),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF636366),
                    fontSize: 10,
                    decoration: TextDecoration.none)),
          ],
        ),
      ),
    ]),
  );

  Widget _startRunCard() => GestureDetector(
    onTap: () async {
      await Navigator.push(context,
          CupertinoPageRoute(builder: (_) => const RunScreen()));
      ref.read(sessionsProvider.notifier).reload();
    },
    child: Container(
      height: 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF141414),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
      ),
      child: Stack(alignment: Alignment.center, children: [
        // Subtle grid
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: CustomPaint(painter: _GridPainter()),
          ),
        ),
        // Glow behind button
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x00000000),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.white.withOpacity(0.06),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Play button
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CupertinoColors.white,
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.white.withOpacity(0.3),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: AppIcon(Ic.play, size: 26,
                  color: CupertinoColors.black),
            ),
          ),
          const SizedBox(height: 14),
          const Text('START RUN',
              style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                  decoration: TextDecoration.none)),
          const SizedBox(height: 4),
          const Text('Tap to begin tracking',
              style: TextStyle(
                  color: Color(0xFF3A3A3C),
                  fontSize: 12,
                  decoration: TextDecoration.none)),
        ]),
      ]),
    ),
  );

  Widget _sectionHeader(String title, {VoidCallback? onTap}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title,
          style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none)),
      if (onTap != null)
        GestureDetector(
          onTap: onTap,
          child: const Text('See All',
              style: TextStyle(
                  color: Color(0xFF636366),
                  fontSize: 13,
                  decoration: TextDecoration.none)),
        ),
    ],
  );

  Widget _recentRow(RunSession s) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
    ),
    child: Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2C2C2E),
          border: Border.all(
              color: const Color(0xFF3A3A3C), width: 0.5),
        ),
        child: const Center(
            child: AppIcon(Ic.run, size: 16,
                color: Color(0xFF8E8E93))),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.formattedDistance} km',
                  style: const TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      decoration: TextDecoration.none)),
              const SizedBox(height: 3),
              Text('${s.formattedPace} /km  ·  ${s.formattedTime}'
                  '${s.steps > 0 ? '  ·  ${s.formattedSteps} steps' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF636366),
                      fontSize: 12,
                      decoration: TextDecoration.none)),
            ]),
      ),
      const SizedBox(width: 8),
      Text(_fmtDate(s.startTime),
          style: const TextStyle(
              color: Color(0xFF3A3A3C),
              fontSize: 11,
              decoration: TextDecoration.none)),
    ]),
  );

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}';
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = CupertinoColors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
import 'package:flutter/material.dart';
import '../models/run_sessions.dart';
import '../services/storage_service.dart';
import 'run_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  List<RunSession> _sessions = [];
  final _storage = StorageService();
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _storage.loadSessions();
    if (mounted) setState(() => _sessions = s);
  }

  double get _totalKm =>
      _sessions.fold(0.0, (sum, s) => sum + s.distanceKm);

  int get _totalSteps =>
      _sessions.fold(0, (sum, s) => sum + s.steps);

  int get _totalCalories =>
      _sessions.fold(0, (sum, s) => sum + (s.distanceKm * 62).round());

  Duration get _totalTime =>
      _sessions.fold(Duration.zero, (sum, s) => sum + s.elapsed);

  String get _avgPace {
    final valid = _sessions.where((s) => s.pacePerKm > 0).toList();
    if (valid.isEmpty) return '--:--';
    final avg =
        valid.fold(0.0, (sum, s) => sum + s.pacePerKm) / valid.length;
    final m = (avg / 60).floor();
    final s = (avg % 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _bestPace {
    final valid = _sessions.where((s) => s.pacePerKm > 0).toList();
    if (valid.isEmpty) return '--:--';
    final best =
    valid.map((s) => s.pacePerKm).reduce((a, b) => a < b ? a : b);
    final m = (best / 60).floor();
    final s = (best % 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _longestRun {
    if (_sessions.isEmpty) return '0.00';
    return _sessions
        .map((s) => s.distanceKm)
        .reduce((a, b) => a > b ? a : b)
        .toStringAsFixed(2);
  }

  String get _formattedTotalTime {
    final h = _totalTime.inHours;
    final m = _totalTime.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get _formattedTotalSteps {
    if (_totalSteps >= 1000)
      return '${(_totalSteps / 1000).toStringAsFixed(1)}k';
    return '$_totalSteps';
  }

  String get _formattedTotalCalories {
    if (_totalCalories >= 1000)
      return '${(_totalCalories / 1000).toStringAsFixed(1)}k';
    return '$_totalCalories';
  }

  double get _weekKm {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _sessions
        .where((s) => s.startTime.isAfter(start))
        .fold(0.0, (sum, s) => sum + s.distanceKm);
  }

  int get _weekRuns {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return _sessions.where((s) => s.startTime.isAfter(start)).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _tab == 0
            ? _buildHome()
            : HistoryScreen(
            sessions: _sessions,
            onDelete: (id) async {
              await _storage.deleteSession(id);
              _load();
            }),
      ),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildHome() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 26),

            // ── Header ──────────────────────────────────────────────
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, Color(0xFFAAAAAA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text('RUNNE\$T',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 4)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _sessions.isEmpty
                              ? 'Ready to run?'
                              : '${_sessions.length} run${_sessions.length == 1 ? '' : 's'} logged',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ]),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(Icons.person_outline,
                        color: Colors.white54, size: 20),
                  ),
                ]),
            const SizedBox(height: 16),

            // ── This week pill ───────────────────────────────────────
            if (_sessions.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border:
                  Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: Colors.white38, size: 13),
                  const SizedBox(width: 8),
                  const Text('This week',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 12)),
                  const Spacer(),
                  Text('${_weekKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                      '· $_weekRuns run${_weekRuns == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 12),

              // ── Stats grid: 2 columns, medium cards ─────────────
              // Row 1
              Row(children: [
                _statCard(
                  '${_totalKm.toStringAsFixed(1)} km',
                  'Total Distance',
                  Icons.route_outlined,
                ),
                const SizedBox(width: 10),
                _statCard(
                  '$_avgPace /km',
                  'Avg Pace',
                  Icons.speed_outlined,
                ),
              ]),
              const SizedBox(height: 10),
              // Row 2
              Row(children: [
                _statCard(
                  _formattedTotalSteps,
                  'Total Steps',
                  Icons.directions_walk_outlined,
                ),
                const SizedBox(width: 10),
                _statCard(
                  '$_formattedTotalCalories kcal',
                  'Calories Burned',
                  Icons.local_fire_department_outlined,
                ),
              ]),
              const SizedBox(height: 10),
              // Row 3
              Row(children: [
                _statCard(
                  '$_bestPace /km',
                  'Best Pace',
                  Icons.emoji_events_outlined,
                ),
                const SizedBox(width: 10),
                _statCard(
                  '$_longestRun km',
                  'Longest Run',
                  Icons.straighten_outlined,
                ),
              ]),
              const SizedBox(height: 10),
              // Row 4
              Row(children: [
                _statCard(
                  _formattedTotalTime,
                  'Total Time',
                  Icons.timer_outlined,
                ),
                const SizedBox(width: 10),
                _statCard(
                  '${_sessions.length}',
                  'Total Runs',
                  Icons.replay_outlined,
                ),
              ]),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 4),

            // ── START RUN button ────────────────────────────────────
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RunScreen()));
                _load();
              },
              child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C1C1C), Color(0xFF111111)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.04),
                      blurRadius: 20,
                    )
                  ],
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                      child: CustomPaint(painter: _GridPainter())),
                  Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Colors.white,
                                Color(0xFFBBBBBB)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.28),
                                blurRadius: 24,
                                spreadRadius: 3,
                              )
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              size: 36, color: Colors.black),
                        ),
                        const SizedBox(height: 13),
                        const Text('START RUN',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 5)),
                        const SizedBox(height: 3),
                        const Text('Tap to begin tracking',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 11)),
                      ]),
                ]),
              ),
            ),
            const SizedBox(height: 22),

            // ── Recent runs ──────────────────────────────────────────
            if (_sessions.isNotEmpty) ...[
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Recent',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    GestureDetector(
                      onTap: () => setState(() => _tab = 1),
                      child: const Text('See all',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ),
                  ]),
              const SizedBox(height: 10),
              ..._sessions.take(3).map((s) => _recentCard(s)),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Medium card — 2 per row, icon + large value + label
  Widget _statCard(String value, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10)),
              ]),
        ),
      ]),
    ),
  );

  Widget _recentCard(RunSession s) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFF111111),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.07),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.directions_run,
            color: Colors.white54, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.formattedDistance} km',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                      '${s.formattedPace} /km  •  ${s.formattedTime}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ),
                if (s.steps > 0) ...[
                  const Text('  •  ',
                      style: TextStyle(
                          color: Colors.white24, fontSize: 11)),
                  Text('${s.formattedSteps} steps',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ]),
            ]),
      ),
      const SizedBox(width: 8),
      Text(_fmtDate(s.startTime),
          style: const TextStyle(
              color: Colors.white24, fontSize: 10)),
    ]),
  );

  Widget _buildNav() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Colors.white12)),
      color: Color(0xFF080808),
    ),
    child: BottomNavigationBar(
      currentIndex: _tab,
      onTap: (i) {
        setState(() => _tab = i);
        if (i == 1) _load();
      },
      backgroundColor: Colors.transparent,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white24,
      elevation: 0,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History'),
      ],
    ),
  );

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}';
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
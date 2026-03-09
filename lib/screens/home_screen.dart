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
      _sessions.fold(0, (sum, s) => sum + s.distanceKm);

  String get _avgPace {
    final valid = _sessions.where((s) => s.pacePerKm > 0).toList();
    if (valid.isEmpty) return '--:--';
    final avg =
        valid.fold(0.0, (sum, s) => sum + s.pacePerKm) / valid.length;
    final m = (avg / 60).floor();
    final s = (avg % 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            // Header
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              const LinearGradient(
                                colors: [Colors.white, Color(0xFFAAAAAA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                          child: const Text('RUNNE\$T',
                              style: TextStyle(
                                  fontSize: 32,
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
                              color: Colors.white38, fontSize: 13),
                        ),
                      ]),
                  Container(
                    width: 48,
                    height: 48,
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
                        color: Colors.white54),
                  ),
                ]),
            const SizedBox(height: 28),

            // Stats row
            Row(children: [
              _statCard('Total Distance',
                  '${_totalKm.toStringAsFixed(1)} km', Icons.route_outlined),
              const SizedBox(width: 12),
              _statCard(
                  'Avg Pace', '$_avgPace /km', Icons.speed_outlined),
            ]),
            const SizedBox(height: 24),

            // START button — hero card
            GestureDetector(
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RunScreen()));
                _load();
              },
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1C1C1C),
                      Color(0xFF111111),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.04),
                      blurRadius: 20,
                      spreadRadius: 0,
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
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Colors.white, Color(0xFFBBBBBB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.3),
                              blurRadius: 28,
                              spreadRadius: 4,
                            )
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            size: 42, color: Colors.black),
                      ),
                      const SizedBox(height: 16),
                      const Text('START RUN',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 5)),
                      const SizedBox(height: 4),
                      const Text('Tap to begin tracking',
                          style: TextStyle(
                              color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 28),

            // Recent runs
            if (_sessions.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () => setState(() => _tab = 1),
                    child: const Text('See all',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._sessions.take(3).map((s) => _recentCard(s)),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _recentCard(RunSession s) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF111111),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.07),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.directions_run,
            color: Colors.white54, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.formattedDistance} km',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              Text(
                  '${s.formattedPace} /km  •  ${s.formattedTime}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12)),
            ]),
      ),
      Text(_fmtDate(s.startTime),
          style: const TextStyle(
              color: Colors.white24, fontSize: 11)),
    ]),
  );

  Widget _statCard(String label, String value, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white54, size: 22),
                const SizedBox(height: 10),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ]),
        ),
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
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
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
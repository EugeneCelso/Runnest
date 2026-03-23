import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/run_sessions.dart';
import '../services/locations_services.dart';
import '../services/storage_service.dart';
import '../services/photo_overlay_service.dart';
import '../services/step_counter_service.dart';
import 'summary_screen.dart';
import 'ios_icons.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});
  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with TickerProviderStateMixin {
  final _loc = LocationService();
  final _storage = StorageService();
  final _overlay = PhotoOverlayService();
  final _steps = StepCounterService();
  final _mapCtrl = MapController();

  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  bool _camVisible = false;
  bool _camExpanded = false;
  bool _savingPhoto = false;
  bool _isFrontCam = false;
  bool _camSwitching = false;
  bool _flashOn = false;
  bool get _camReady =>
      _cam != null && (_cam?.value.isInitialized ?? false) && !_camSwitching;
  bool _camSetupInProgress = false;
  bool _camTransferred = false;
  bool _pendingFinish = false;

  bool _isRunning = false;
  bool _isPaused = false;
  bool _ready = false;

  late RunSession _session;
  Timer? _uiTimer;
  StreamSubscription<Position>? _locSub;
  StreamSubscription<int>? _stepSub;

  Position? _lastRecordedPos;
  LatLng? _currentLatLng;
  final List<LatLng> _polylinePoints = [];

  double _distanceMeters = 0;
  int _elapsedSeconds = 0;
  double _currentSpeedMs = 0;
  double _gpsAccuracy = 0;
  int _currentSteps = 0;

  static const double _minDistM = 2.0;
  static const int _minIntervalMs = 1500;
  DateTime? _lastRecordedTime;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _camExpandCtrl;
  late Animation<double> _camExpandAnim;

  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _session = RunSession(id: const Uuid().v4(), startTime: DateTime.now());

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.88, end: 1.12)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _camExpandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _camExpandAnim =
        CurvedAnimation(parent: _camExpandCtrl, curve: Curves.easeInOut);

    _init();
  }

  Future<void> _init() async {
    final ok = await _loc.requestPermissions();
    if (!ok && mounted) { _toast('Location permission required'); return; }
    _initCam();
    _loc.start(resetKalman: true);
    _locSub = _loc.rawStream.listen(_onPreview);
  }

  void _onPreview(Position pos) {
    if (!mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    if (!_ready && pos.accuracy > 15.0) return;
    setState(() {
      _gpsAccuracy = pos.accuracy;
      _currentSpeedMs = pos.speed;
      _currentLatLng = ll;
      if (!_ready) {
        _lastRecordedPos = pos;
        _ready = true;
        try { _mapCtrl.move(ll, 17.5); } catch (_) {}
      } else {
        try { _mapCtrl.move(ll, _mapCtrl.camera.zoom); } catch (_) {}
      }
      _lastRecordedPos = pos;
    });
  }

  Future<void> _initCam() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) await _setupCam(0);
    } catch (e) { debugPrint('Camera init: $e'); }
  }

  Future<void> _setupCam(int index) async {
    if (_camSetupInProgress) return;
    _camSetupInProgress = true;
    final old = _cam;
    try {
      if (mounted) setState(() { _cam = null; _camSwitching = true; });
      if (old != null) { try { await old.dispose(); } catch (_) {} }
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final c = CameraController(_cameras[index], ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) { await c.dispose(); return; }
      setState(() { _cam = c; _camSwitching = false; });
    } catch (e) {
      debugPrint('Camera setup: $e');
      if (mounted) setState(() { _cam = null; _camSwitching = false; });
    } finally { _camSetupInProgress = false; }
  }

  Future<void> _flipCam() async {
    if (_cameras.length < 2 || _camSetupInProgress || _camSwitching) return;
    final dir = _isFrontCam ? CameraLensDirection.back : CameraLensDirection.front;
    final idx = _cameras.indexWhere((c) => c.lensDirection == dir);
    if (idx == -1) { _toast('Camera not found'); return; }
    _isFrontCam = !_isFrontCam;
    setState(() => _flashOn = false);
    await _setupCam(idx);
  }

  Future<void> _toggleFlash() async {
    if (!_camReady) return;
    try {
      await _cam!.setFlashMode(_flashOn ? FlashMode.off : FlashMode.torch);
      setState(() => _flashOn = !_flashOn);
    } catch (_) { _toast('Flash unavailable'); }
  }

  void _startRun() {
    if (!_ready) return;
    _locSub?.cancel();
    final seed = _loc.lastPosition ?? _lastRecordedPos;
    setState(() {
      _isRunning = true; _isPaused = false;
      _distanceMeters = 0; _elapsedSeconds = 0; _currentSteps = 0;
      _polylinePoints.clear();
      _lastRecordedPos = seed;
      _lastRecordedTime = DateTime.now();
    });
    _steps.start(initialSteps: 0);
    _stepSub = _steps.stepStream.listen((s) {
      if (mounted && !_isPaused) setState(() => _currentSteps = s);
    });
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _isRunning && mounted) setState(() => _elapsedSeconds++);
    });
    _locSub = _loc.rawStream.listen(_onTracking);
  }

  void _onTracking(Position pos) {
    if (!mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _gpsAccuracy = pos.accuracy;
      _currentSpeedMs = pos.speed;
      _currentLatLng = ll;
    });
    if (_isRunning && !_isPaused) {
      try { _mapCtrl.move(ll, _mapCtrl.camera.zoom); } catch (_) {}
    }
    if (_isPaused || !_isRunning) return;
    if (_loc.isStationary && pos.speed <= 0.5) return;
    final now = DateTime.now();
    if (_lastRecordedTime != null &&
        now.difference(_lastRecordedTime!).inMilliseconds < _minIntervalMs) return;
    if (_lastRecordedPos == null) {
      setState(() { _lastRecordedPos = pos; _lastRecordedTime = now; _polylinePoints.add(ll); });
      return;
    }
    final m = _loc.metersBetween(_lastRecordedPos!, pos);
    if (m >= _minDistM) {
      setState(() {
        if (_polylinePoints.isEmpty) {
          _polylinePoints.add(LatLng(_lastRecordedPos!.latitude, _lastRecordedPos!.longitude));
        }
        _distanceMeters += m;
        _polylinePoints.add(ll);
        _lastRecordedPos = pos;
        _lastRecordedTime = now;
      });
    }
  }

  double get _km => _distanceMeters / 1000;

  String get _dispDist => _km.toStringAsFixed(2);

  String get _dispPace {
    if (_km < 0.01 || _elapsedSeconds < 5) return '--:--';
    final s = _elapsedSeconds / _km;
    return '${(s / 60).floor().toString().padLeft(2, '0')}:${(s % 60).round().toString().padLeft(2, '0')}';
  }

  String get _dispTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _dispSteps =>
      _currentSteps >= 1000
          ? '${(_currentSteps / 1000).toStringAsFixed(1)}k'
          : '$_currentSteps';

  String get _cadence {
    if (_elapsedSeconds < 10 || _currentSteps == 0) return '--';
    return '${(_currentSteps / (_elapsedSeconds / 60)).round()}';
  }

  String get _calories => '${(_km * 62).round()}';

  void _syncSession() {
    _session.distanceKm = _km;
    _session.elapsed = Duration(seconds: _elapsedSeconds);
    _session.pacePerKm = _km > 0 ? _elapsedSeconds / _km : 0;
    _session.routePoints = List.from(_polylinePoints);
    _session.steps = _currentSteps;
  }

  Future<void> _takePhoto() async {
    if (!_camReady || _savingPhoto) return;
    setState(() => _savingPhoto = true);
    try {
      _syncSession();
      final xf = await _cam!.takePicture();
      final path = await _overlay.burnOverlay(xf.path, _session);
      if (path != null && mounted) {
        _session.photoPath = path;
        setState(() { _camVisible = false; _camExpanded = false; _flashOn = false; });
        _camExpandCtrl.reverse();
        _cam?.setFlashMode(FlashMode.off).catchError((_) {});
        if (_pendingFinish) { _pendingFinish = false; await _stopRun(); }
        else { _toast('📸 Photo saved!'); }
      } else if (mounted) { _toast('Photo failed — retry'); }
    } catch (e) {
      _toast('Camera error — retry');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  void _toggleCamExpand() {
    setState(() => _camExpanded = !_camExpanded);
    _camExpanded ? _camExpandCtrl.forward() : _camExpandCtrl.reverse();
  }

  Future<void> _showStop() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Finish Run?'),
        content: const Text('Your run will be saved.'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finish')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (_session.photoPath == null && _camReady) {
      final photo = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Save a photo?'),
          content: const Text(
              "Capture this moment with your stats overlay?"),
          actions: [
            CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip')),
            CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Take Photo')),
          ],
        ),
      );
      if (photo == true && mounted) {
        _pendingFinish = true;
        setState(() { _camVisible = true; _camExpanded = true; });
        _camExpandCtrl.forward();
        _toast('Take photo — run will finish automatically');
        return;
      }
    }
    await _stopRun();
  }

  Future<void> _stopRun() async {
    if (_flashOn && _camReady) {
      try { await _cam!.setFlashMode(FlashMode.off); } catch (_) {}
    }
    _uiTimer?.cancel();
    _locSub?.cancel();
    _stepSub?.cancel();
    _steps.stop();
    _loc.stop();
    _syncSession();
    _session.endTime = DateTime.now();
    await _storage.saveSession(_session);
    if (!mounted) return;
    final camToPass = _camReady ? _cam : null;
    _camTransferred = camToPass != null;
    _cam = null;
    Navigator.pushReplacement(context,
        CupertinoPageRoute(
            builder: (_) =>
                SummaryScreen(session: _session, cam: camToPass)));
  }

  void _toast(String msg) {
    if (!mounted) return;
    _toastEntry?.remove();
    _toastEntry = null;
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        bottom: MediaQuery.of(ctx).padding.bottom + 110,
        left: 24, right: 24,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xF02C2C2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF3A3A3C), width: 0.5),
          ),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 14,
                  decoration: TextDecoration.none)),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
      if (_toastEntry == entry) _toastEntry = null;
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _uiTimer?.cancel();
    _locSub?.cancel();
    _stepSub?.cancel();
    _steps.dispose();
    _loc.dispose();
    try { _mapCtrl.dispose(); } catch (_) {}
    if (!_camTransferred) _cam?.dispose();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _camExpandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          _buildMap(),
          _buildTopGrad(),
          _buildTopBar(),
          if (_camVisible) _buildCam(),
          if (_camExpanded && _isRunning) _buildFinishFab(),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _camExpanded ? const SizedBox.shrink() : _buildPanel(),
          ),
        ]),
      ),
    );
  }

  Widget _buildFinishFab() => Positioned(
    bottom: MediaQuery.of(context).padding.bottom + 24,
    left: 24, right: 24,
    child: GestureDetector(
      onTap: _stopRun,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
                color: CupertinoColors.white.withOpacity(0.2),
                blurRadius: 20),
          ],
        ),
        child: const Center(
          child: Text('✓  Finish Run',
              style: TextStyle(
                  color: CupertinoColors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1.5,
                  decoration: TextDecoration.none)),
        ),
      ),
    ),
  );

  Widget _buildMap() {
    if (_currentLatLng == null) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CupertinoActivityIndicator(
                color: CupertinoColors.white, radius: 14),
            const SizedBox(height: 22),
            const Text('Acquiring GPS signal...',
                style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 15,
                    letterSpacing: 0.5,
                    decoration: TextDecoration.none)),
            const SizedBox(height: 6),
            const Text('Move outside for best accuracy',
                style: TextStyle(
                    color: Color(0xFF3A3A3C),
                    fontSize: 12,
                    decoration: TextDecoration.none)),
          ]),
        ),
      );
    }
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _currentLatLng!,
        initialZoom: 17.5,
        interactionOptions:
        const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.runnest',
          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
        ),
        if (_polylinePoints.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: List.from(_polylinePoints),
              color: const Color(0x80000000),
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
            Polyline(
              points: List.from(_polylinePoints),
              color: CupertinoColors.white,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ]),
        MarkerLayer(markers: [
          if (_polylinePoints.isNotEmpty)
            Marker(
              point: _polylinePoints.first,
              width: 16, height: 16,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CupertinoColors.white,
                  border: Border.all(
                      color: const Color(0x80000000), width: 2),
                ),
              ),
            ),
          if (_currentLatLng != null)
            Marker(
              point: _currentLatLng!,
              width: 36, height: 36,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _isRunning && !_isPaused ? _pulseAnim.value : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPaused
                          ? const Color(0xFFAAAAAA)
                          : CupertinoColors.white,
                      border: Border.all(
                          color: const Color(0x80000000), width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: CupertinoColors.white.withOpacity(0.6),
                            blurRadius: 16,
                            spreadRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _buildTopGrad() => Positioned(
    top: 0, left: 0, right: 0, height: 120,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CupertinoColors.black, Color(0x00000000)],
        ),
      ),
    ),
  );

  Widget _buildTopBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(
      child: Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _mapBtn(Ic.back, false,
                    () => _isRunning ? _showExit() : Navigator.pop(context)),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF2C2C2E), width: 0.5),
              ),
              child: const Text('RUNNE\$T',
                  style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 2,
                      decoration: TextDecoration.none)),
            ),
            Row(children: [
              if (_isRunning)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: CupertinoColors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF2C2C2E), width: 0.5),
                  ),
                  child: Text(
                    '${(_currentSpeedMs * 3.6).toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 11,
                        decoration: TextDecoration.none),
                  ),
                ),
              _mapBtn(Ic.camera, _camVisible, () {
                if (_camReady) {
                  setState(() => _camVisible = !_camVisible);
                  if (!_camVisible) {
                    _camExpanded = false;
                    _flashOn = false;
                    _pendingFinish = false;
                    _camExpandCtrl.reverse();
                    _cam?.setFlashMode(FlashMode.off).catchError((_) {});
                  }
                } else {
                  _toast((_camSetupInProgress || _camSwitching)
                      ? 'Camera loading...'
                      : 'Camera unavailable');
                }
              }),
            ]),
          ],
        ),
      ),
    ),
  );

  Widget _mapBtn(String glyph, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: active
                ? CupertinoColors.white
                : CupertinoColors.black.withOpacity(0.65),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3A3A3C), width: 0.5),
          ),
          child: Center(
            child: AppIcon(glyph,
                size: 16,
                color: active ? CupertinoColors.black : CupertinoColors.white),
          ),
        ),
      );

  Widget _buildCam() {
    final screen = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;

    const smallW = 200.0, smallH = 266.0, smallRight = 12.0;
    final smallTop = topPad + 70.0;
    final bigW = screen.width - 32;
    final bigH = screen.height * 0.68;
    const bigRight = 16.0;
    final bigTop = topPad + 56.0;

    return AnimatedBuilder(
      animation: _camExpandAnim,
      builder: (ctx, _) {
        final t = _camExpandAnim.value;
        final w = smallW + (bigW - smallW) * t;
        final h = smallH + (bigH - smallH) * t;
        final right = smallRight + (bigRight - smallRight) * t;
        final top = smallTop + (bigTop - smallTop) * t;
        final r = 20.0 - 4.0 * t;

        return Positioned(
          top: top, right: right,
          child: Container(
            width: w, height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(
                  color: const Color(0x4DFFFFFF), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: CupertinoColors.black.withOpacity(0.7),
                    blurRadius: 20)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r - 1),
              child: Stack(children: [
                if (_camSwitching || !_camReady)
                  Container(
                    width: w, height: h,
                    color: CupertinoColors.black,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CupertinoActivityIndicator(
                            color: Color(0xFF8E8E93), radius: 12),
                        const SizedBox(height: 8),
                        Text(_camSwitching ? 'Switching...' : 'Loading...',
                            style: const TextStyle(
                                color: Color(0xFF636366),
                                fontSize: 12,
                                decoration: TextDecoration.none)),
                      ]),
                    ),
                  )
                else
                  KeyedSubtree(
                    key: ValueKey(_cam),
                    child: GestureDetector(
                      onTap: !_camExpanded ? _toggleCamExpand : null,
                      child: SizedBox(
                          width: w, height: h, child: CameraPreview(_cam!)),
                    ),
                  ),

                if (!_camExpanded && _camReady && t < 0.1)
                  Positioned(
                    top: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: CupertinoColors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Tap to expand',
                            style: TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 9,
                                decoration: TextDecoration.none)),
                      ),
                    ),
                  ),

                if (_flashOn)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemYellow
                            .withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(Ic.bolt, size: 10,
                                color: CupertinoColors.black),
                            SizedBox(width: 2),
                            Text('ON',
                                style: TextStyle(
                                    color: CupertinoColors.black,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none)),
                          ]),
                    ),
                  ),

                if (_pendingFinish)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0x4DFFFFFF), width: 0.5),
                      ),
                      child: const Text('FINISHING',
                          style: TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              decoration: TextDecoration.none)),
                    ),
                  ),

                // Camera controls
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: _camExpanded ? 20 : 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          CupertinoColors.black.withOpacity(0.88),
                          const Color(0x00000000),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _camBtn(Ic.flip,
                            (_camSwitching || _camSetupInProgress)
                                ? null
                                : _flipCam,
                            size: _camExpanded ? 48 : 36),
                        GestureDetector(
                          onTap: _camReady ? _takePhoto : null,
                          child: Container(
                            width: _camExpanded ? 72 : 52,
                            height: _camExpanded ? 72 : 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_savingPhoto || !_camReady)
                                  ? const Color(0xFF636366)
                                  : CupertinoColors.white,
                              border: Border.all(
                                  color: const Color(0x61000000),
                                  width: 2.5),
                            ),
                            child: _savingPhoto
                                ? Padding(
                                padding: EdgeInsets.all(
                                    _camExpanded ? 16 : 12),
                                child: const CupertinoActivityIndicator(
                                    color: CupertinoColors.black,
                                    radius: 10))
                                : Center(
                                child: AppIcon(Ic.camera,
                                    size: _camExpanded ? 30 : 22,
                                    color: CupertinoColors.black)),
                          ),
                        ),
                        _camBtn(
                          _flashOn ? Ic.bolt : Ic.boltOff,
                          _camReady ? _toggleFlash : null,
                          size: _camExpanded ? 48 : 36,
                          active: _flashOn,
                          activeColor: CupertinoColors.systemYellow,
                        ),
                        _camBtn(
                          _camExpanded ? Ic.collapse : Ic.close,
                          _camExpanded
                              ? _toggleCamExpand
                              : () {
                            if (_flashOn) {
                              _cam?.setFlashMode(FlashMode.off)
                                  .catchError((_) {});
                            }
                            setState(() {
                              _camVisible = false;
                              _camExpanded = false;
                              _flashOn = false;
                              _pendingFinish = false;
                            });
                            _camExpandCtrl.reverse();
                          },
                          size: _camExpanded ? 48 : 36,
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _camBtn(String glyph, VoidCallback? onTap,
      {double size = 36,
        bool active = false,
        Color activeColor = CupertinoColors.white}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null
                ? CupertinoColors.white.withOpacity(0.08)
                : active
                ? activeColor.withOpacity(0.3)
                : CupertinoColors.white.withOpacity(0.22),
            border: active
                ? Border.all(
                color: activeColor.withOpacity(0.7), width: 1.5)
                : null,
          ),
          child: Center(
            child: AppIcon(glyph,
                size: size * 0.42,
                color: onTap == null
                    ? const Color(0x4DFFFFFF)
                    : active
                    ? activeColor
                    : CupertinoColors.white),
          ),
        ),
      );

  Widget _buildPanel() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          CupertinoColors.black,
          CupertinoColors.black.withOpacity(0.97),
          CupertinoColors.black.withOpacity(0.9),
          const Color(0x00000000),
        ],
        stops: const [0, 0.55, 0.8, 1],
      ),
    ),
    padding: EdgeInsets.only(
      left: 20, right: 20,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      top: 32,
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // GPS pill
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF2C2C2E), width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gpsAccuracy <= 8
                  ? CupertinoColors.white
                  : _gpsAccuracy <= 20
                  ? const Color(0xFFAAAAAA)
                  : const Color(0xFF636366),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _gpsAccuracy > 0
                ? 'GPS ±${_gpsAccuracy.toStringAsFixed(0)}m'
                '${_isPaused ? '  ·  PAUSED' : _loc.isStationary && _isRunning ? '  ·  STILL' : ''}'
                : 'Searching GPS...',
            style: TextStyle(
              color: _isPaused
                  ? const Color(0xFFAAAAAA)
                  : const Color(0xFF636366),
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: _isPaused ? FontWeight.w600 : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ]),
      ),

      // Stats container
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: CupertinoColors.white.withOpacity(0.07),
              width: 0.5),
        ),
        child: Column(children: [
          Row(children: [
            _stat('DISTANCE', _dispDist, 'km'),
            _vDiv(),
            _stat('PACE', _dispPace, '/km'),
            _vDiv(),
            _stat('TIME', _dispTime, ''),
          ]),
          if (_isRunning) ...[
            const SizedBox(height: 14),
            Container(
                height: 0.5,
                color: CupertinoColors.white.withOpacity(0.06)),
            const SizedBox(height: 14),
            Row(children: [
              _stat('STEPS', _dispSteps, ''),
              _vDiv(),
              _stat('CADENCE', _cadence, 'spm'),
              _vDiv(),
              _stat('CAL', _calories, 'kcal'),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 20),

      // Controls
      if (!_isRunning)
        _startBtn()
      else
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ctrlBtn(
            glyph: _isPaused ? Ic.play : Ic.pause,
            onTap: () => setState(() => _isPaused = !_isPaused),
            size: 56, filled: false,
          ),
          const SizedBox(width: 20),
          _ctrlBtn(
              glyph: Ic.stop, onTap: _showStop, size: 72, filled: true),
          const SizedBox(width: 20),
          _ctrlBtn(
            glyph: Ic.camera,
            onTap: () {
              if (_camReady) {
                setState(() => _camVisible = !_camVisible);
                if (!_camVisible) {
                  _camExpanded = false;
                  _flashOn = false;
                  _pendingFinish = false;
                  _camExpandCtrl.reverse();
                  _cam?.setFlashMode(FlashMode.off).catchError((_) {});
                }
              } else {
                _toast((_camSetupInProgress || _camSwitching)
                    ? 'Camera loading...'
                    : 'Camera unavailable');
              }
            },
            size: 56, filled: false, active: _camVisible,
          ),
        ]),
    ]),
  );

  Widget _stat(String label, String value, String unit) => Expanded(
    child: Column(children: [
      Text(label,
          style: const TextStyle(
              color: Color(0xFF636366),
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none)),
      const SizedBox(height: 5),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value,
            style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                decoration: TextDecoration.none)),
      ),
      if (unit.isNotEmpty)
        Text(unit,
            style: const TextStyle(
                color: Color(0xFF636366),
                fontSize: 10,
                decoration: TextDecoration.none)),
    ]),
  );

  Widget _vDiv() => Container(
      width: 0.5, height: 40,
      color: const Color(0xFF2C2C2E),
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _startBtn() => GestureDetector(
    onTap: _ready ? _startRun : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity, height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: _ready ? CupertinoColors.white : const Color(0xFF2C2C2E),
        boxShadow: _ready
            ? [
          BoxShadow(
              color: CupertinoColors.white.withOpacity(0.22),
              blurRadius: 24, spreadRadius: 2)
        ]
            : [],
      ),
      child: Center(
        child: Text(
          _ready ? 'START RUN' : 'GETTING GPS...',
          style: TextStyle(
            color: _ready
                ? CupertinoColors.black
                : const Color(0xFF636366),
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 3,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );

  Widget _ctrlBtn({
    required String glyph,
    required VoidCallback onTap,
    required double size,
    required bool filled,
    bool active = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? CupertinoColors.white
                : active
                ? CupertinoColors.white.withOpacity(0.18)
                : CupertinoColors.white.withOpacity(0.08),
            border: Border.all(
                color: CupertinoColors.white
                    .withOpacity(filled ? 0 : 0.18),
                width: 0.5),
          ),
          child: Center(
            child: AppIcon(glyph,
                size: size * 0.38,
                color: filled
                    ? CupertinoColors.black
                    : CupertinoColors.white),
          ),
        ),
      );

  Future<void> _showExit() async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Leave?'),
        content: const Text('This run will not be saved.'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Leave')),
        ],
      ),
    );
  }
}
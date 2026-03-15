import 'dart:async';
import 'package:flutter/material.dart';
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
      _cam != null &&
          (_cam?.value.isInitialized ?? false) &&
          !_camSwitching;
  bool _camSetupInProgress = false;
  bool _camTransferred = false;

  // When true, the next successful photo triggers _stopRun() automatically
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

  static const double _minRecordDistMeters = 2.0;
  static const int _minRecordIntervalMs = 1500;
  DateTime? _lastRecordedTime;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _camExpandCtrl;
  late Animation<double> _camExpandAnim;

  @override
  void initState() {
    super.initState();
    _session = RunSession(id: const Uuid().v4(), startTime: DateTime.now());

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.88, end: 1.12).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

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
    if (!ok && mounted) {
      _snack('Location permission required');
      return;
    }
    _initCam();
    _loc.start(resetKalman: true);
    _locSub = _loc.rawStream.listen(_onPreviewPosition);
  }

  void _onPreviewPosition(Position pos) {
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
      if (_cameras.isNotEmpty) await _setupCamera(0);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _setupCamera(int index) async {
    if (_camSetupInProgress) return;
    _camSetupInProgress = true;
    final oldCam = _cam;
    try {
      if (mounted) setState(() { _cam = null; _camSwitching = true; });
      if (oldCam != null) {
        try { await oldCam.dispose(); } catch (e) { debugPrint('Old cam dispose: $e'); }
      }
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final controller = CameraController(
        _cameras[index], ResolutionPreset.high,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) { await controller.dispose(); return; }
      setState(() { _cam = controller; _camSwitching = false; });
    } catch (e) {
      debugPrint('Camera setup error: $e');
      if (mounted) setState(() { _cam = null; _camSwitching = false; });
    } finally {
      _camSetupInProgress = false;
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _camSetupInProgress || _camSwitching) return;
    final targetDirection =
    _isFrontCam ? CameraLensDirection.back : CameraLensDirection.front;
    final camIndex = _cameras.indexWhere((c) => c.lensDirection == targetDirection);
    if (camIndex == -1) { _snack('Camera not found'); return; }
    _isFrontCam = !_isFrontCam;
    setState(() => _flashOn = false);
    await _setupCamera(camIndex);
  }

  Future<void> _toggleFlash() async {
    if (!_camReady) return;
    final newMode = _flashOn ? FlashMode.off : FlashMode.torch;
    try {
      await _cam!.setFlashMode(newMode);
      setState(() => _flashOn = !_flashOn);
    } catch (e) {
      _snack('Flash unavailable');
    }
  }

  void _startRun() {
    if (!_ready) return;
    _locSub?.cancel();
    final seedPos = _loc.lastPosition ?? _lastRecordedPos;
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _distanceMeters = 0;
      _elapsedSeconds = 0;
      _currentSteps = 0;
      _polylinePoints.clear();
      _lastRecordedPos = seedPos;
      _lastRecordedTime = DateTime.now();
    });

    // Start step counter
    _steps.start(initialSteps: 0);
    _stepSub = _steps.stepStream.listen((s) {
      if (mounted && !_isPaused) setState(() => _currentSteps = s);
    });

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && _isRunning && mounted) setState(() => _elapsedSeconds++);
    });
    _locSub = _loc.rawStream.listen(_onTrackingPosition);
  }

  void _onTrackingPosition(Position pos) {
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
    final speedOk = pos.speed > 0.5;
    if (_loc.isStationary && !speedOk) return;
    final now = DateTime.now();
    if (_lastRecordedTime != null) {
      if (now.difference(_lastRecordedTime!).inMilliseconds < _minRecordIntervalMs) return;
    }
    if (_lastRecordedPos == null) {
      setState(() {
        _lastRecordedPos = pos;
        _lastRecordedTime = now;
        _polylinePoints.add(ll);
      });
      return;
    }
    final meters = _loc.metersBetween(_lastRecordedPos!, pos);
    if (meters >= _minRecordDistMeters) {
      setState(() {
        if (_polylinePoints.isEmpty) {
          _polylinePoints.add(LatLng(_lastRecordedPos!.latitude, _lastRecordedPos!.longitude));
        }
        _distanceMeters += meters;
        _polylinePoints.add(ll);
        _lastRecordedPos = pos;
        _lastRecordedTime = now;
      });
    }
  }

  double get _distanceKm => _distanceMeters / 1000;
  String get _displayDistance => _distanceKm.toStringAsFixed(2);

  String get _displayPace {
    if (_distanceKm < 0.01 || _elapsedSeconds < 5) return '--:--';
    final secsPerKm = _elapsedSeconds / _distanceKm;
    final m = (secsPerKm / 60).floor();
    final s = (secsPerKm % 60).round();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _displayTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _displaySteps {
    if (_currentSteps >= 1000) return '${(_currentSteps / 1000).toStringAsFixed(1)}k';
    return '$_currentSteps';
  }

  void _syncSession() {
    _session.distanceKm = _distanceKm;
    _session.elapsed = Duration(seconds: _elapsedSeconds);
    _session.pacePerKm = _distanceKm > 0 ? _elapsedSeconds / _distanceKm : 0;
    _session.routePoints = List.from(_polylinePoints);
    _session.steps = _currentSteps;
  }

  Future<void> _takePhoto() async {
    if (!_camReady || _savingPhoto) return;
    setState(() => _savingPhoto = true);
    try {
      _syncSession();
      final xfile = await _cam!.takePicture();
      final overlayPath = await _overlay.burnOverlay(xfile.path, _session);
      if (overlayPath != null && mounted) {
        _session.photoPath = overlayPath;
        setState(() {
          _camVisible = false;
          _camExpanded = false;
          _flashOn = false;
        });
        _camExpandCtrl.reverse();
        _cam?.setFlashMode(FlashMode.off).catchError((_) {});

        if (_pendingFinish) {
          // User took the end-of-run photo → finish the run automatically
          _pendingFinish = false;
          await _stopRun();
        } else {
          _snack('📸 Photo saved!');
        }
      } else if (mounted) {
        _snack('Photo processing failed — please retry');
      }
    } catch (e) {
      _snack('Camera error — please retry');
      debugPrint('Photo error: $e');
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  void _toggleCamExpand() {
    setState(() => _camExpanded = !_camExpanded);
    _camExpanded ? _camExpandCtrl.forward() : _camExpandCtrl.reverse();
  }

  Future<void> _showStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Finish Run?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Your run will be saved.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (_session.photoPath == null && _camReady && mounted) {
      final takePhoto = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Save a photo?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            "You haven't taken a run photo yet.\nCapture this moment with your stats overlay?",
            style: TextStyle(color: Colors.white54),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip', style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Take Photo',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (takePhoto == true && mounted) {
        // Flag that the next photo should trigger auto-finish
        _pendingFinish = true;
        setState(() {
          _camVisible = true;
          _camExpanded = true;
        });
        _camExpandCtrl.forward();
        _snack('Take your photo — run will finish automatically');
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

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(session: _session, cam: camToPass),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          _buildMap(),
          _buildTopGradient(),
          _buildTopBar(),
          if (_camVisible) _buildCamOverlay(),
          if (_camExpanded && _isRunning) _buildFinishRunFab(),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _camExpanded ? const SizedBox.shrink() : _buildPanel(),
          ),
        ]),
      ),
    );
  }

  Widget _buildFinishRunFab() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 24,
      left: 24,
      right: 24,
      child: GestureDetector(
        onTap: _stopRun,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(27),
            boxShadow: [
              BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 20),
            ],
          ),
          child: const Center(
            child: Text('✓  Finish Run',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.5)),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_currentLatLng == null) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Colors.white70, strokeWidth: 1.5),
            SizedBox(height: 24),
            Text('Acquiring GPS signal...',
                style: TextStyle(color: Colors.white54, fontSize: 15,
                    letterSpacing: 0.8, fontWeight: FontWeight.w400)),
            SizedBox(height: 6),
            Text('Move outside for best accuracy',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ]),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _currentLatLng!,
        initialZoom: 17.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.runnest',
          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
        ),
        if (_polylinePoints.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: List<LatLng>.from(_polylinePoints),
              color: Colors.black.withOpacity(0.5),
              strokeWidth: 12.0,
              strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round,
            ),
            Polyline(
              points: List<LatLng>.from(_polylinePoints),
              color: Colors.white,
              strokeWidth: 5.0,
              strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round,
            ),
          ]),
        MarkerLayer(markers: [
          if (_polylinePoints.isNotEmpty)
            Marker(
              point: _polylinePoints.first, width: 16, height: 16,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white,
                  border: Border.all(color: Colors.black54, width: 2),
                ),
              ),
            ),
          if (_currentLatLng != null)
            Marker(
              point: _currentLatLng!, width: 36, height: 36,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _isRunning && !_isPaused ? _pulseAnim.value : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPaused ? Colors.grey.shade400 : Colors.white,
                      border: Border.all(color: Colors.black54, width: 3),
                      boxShadow: [
                        BoxShadow(color: Colors.white.withOpacity(0.6), blurRadius: 16, spreadRadius: 3),
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

  Widget _buildTopGradient() => Positioned(
    top: 0, left: 0, right: 0, height: 120,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.transparent],
        ),
      ),
    ),
  );

  Widget _buildTopBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _topBtn(Icons.arrow_back_ios_new, false,
                  () => _isRunning ? _showExit() : Navigator.pop(context)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text('RUNNE\$T',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
                    fontSize: 14, letterSpacing: 2)),
          ),
          Row(children: [
            if (_isRunning)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${(_currentSpeedMs * 3.6).toStringAsFixed(1)} km/h',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            _topBtn(Icons.camera_alt_outlined, _camVisible, () {
              if (_camReady) {
                setState(() { _camVisible = !_camVisible; });
                if (!_camVisible) {
                  _camExpanded = false;
                  _flashOn = false;
                  _pendingFinish = false; // cancel pending finish if camera dismissed
                  _camExpandCtrl.reverse();
                  _cam?.setFlashMode(FlashMode.off).catchError((_) {});
                }
              } else if (_camSetupInProgress || _camSwitching) {
                _snack('Camera is loading...');
              } else {
                _snack('Camera unavailable');
              }
            }),
          ]),
        ]),
      ),
    ),
  );

  Widget _topBtn(IconData icon, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.black.withOpacity(0.65),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: active ? Colors.black : Colors.white, size: 18),
        ),
      );

  Widget _buildCamOverlay() {
    final screen = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;

    const double smallW = 200.0;
    const double smallH = 266.0;
    const double smallRight = 12.0;
    final double smallTop = topPad + 70;

    final double bigW = screen.width - 32;
    final double bigH = screen.height * 0.68;
    const double bigRight = 16.0;
    final double bigTop = topPad + 56;

    return AnimatedBuilder(
      animation: _camExpandAnim,
      builder: (context, _) {
        final t = _camExpandAnim.value;
        final w = smallW + (bigW - smallW) * t;
        final h = smallH + (bigH - smallH) * t;
        final right = smallRight + (bigRight - smallRight) * t;
        final top = smallTop + (bigTop - smallTop) * t;
        final radius = 20.0 - 4.0 * t;

        return Positioned(
          top: top, right: right,
          child: Container(
            width: w, height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white30, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 20)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: Stack(children: [
                if (_camSwitching || !_camReady)
                  Container(
                    width: w, height: h, color: Colors.black,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(color: Colors.white54, strokeWidth: 1.5),
                        const SizedBox(height: 10),
                        Text(
                          _camSwitching ? 'Switching...' : 'Loading...',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ]),
                    ),
                  )
                else
                  KeyedSubtree(
                    key: ValueKey(_cam),
                    child: GestureDetector(
                      onTap: !_camExpanded ? _toggleCamExpand : null,
                      child: SizedBox(width: w, height: h, child: CameraPreview(_cam!)),
                    ),
                  ),

                if (!_camExpanded && _camReady && t < 0.1)
                  Positioned(
                    top: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Tap to expand',
                            style: TextStyle(color: Colors.white60, fontSize: 9, letterSpacing: 0.4)),
                      ),
                    ),
                  ),

                if (_flashOn)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.flash_on, color: Colors.black, size: 10),
                        SizedBox(width: 2),
                        Text('ON', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),

                // Pending finish indicator
                if (_pendingFinish)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Text('FINISHING',
                          style: TextStyle(color: Colors.white,
                              fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ),

                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: _camExpanded ? 20 : 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.88), Colors.transparent],
                      ),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _camBtn(Icons.flip_camera_ios_outlined,
                          (_camSwitching || _camSetupInProgress) ? null : _flipCamera,
                          size: _camExpanded ? 48 : 36),
                      GestureDetector(
                        onTap: _camReady ? _takePhoto : null,
                        child: Container(
                          width: _camExpanded ? 72 : 52,
                          height: _camExpanded ? 72 : 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (_savingPhoto || !_camReady) ? Colors.grey.shade600 : Colors.white,
                            border: Border.all(color: Colors.black38, width: 2.5),
                          ),
                          child: _savingPhoto
                              ? Padding(
                              padding: EdgeInsets.all(_camExpanded ? 16 : 12),
                              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : Icon(Icons.camera_alt, color: Colors.black, size: _camExpanded ? 34 : 26),
                        ),
                      ),
                      _camBtn(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        _camReady ? _toggleFlash : null,
                        size: _camExpanded ? 48 : 36,
                        active: _flashOn,
                        activeColor: Colors.amber,
                      ),
                      _camBtn(
                        _camExpanded ? Icons.fullscreen_exit : Icons.close,
                        _camExpanded ? _toggleCamExpand : () {
                          if (_flashOn) _cam?.setFlashMode(FlashMode.off).catchError((_) {});
                          setState(() {
                            _camVisible = false;
                            _camExpanded = false;
                            _flashOn = false;
                            _pendingFinish = false; // cancel if user manually closes
                          });
                          _camExpandCtrl.reverse();
                        },
                        size: _camExpanded ? 48 : 36,
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _camBtn(IconData icon, VoidCallback? onTap, {
    double size = 36,
    bool active = false,
    Color activeColor = Colors.white,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null
                ? Colors.white.withOpacity(0.08)
                : active
                ? activeColor.withOpacity(0.30)
                : Colors.white.withOpacity(0.22),
            border: active ? Border.all(color: activeColor.withOpacity(0.7), width: 1.5) : null,
          ),
          child: Icon(icon,
              color: onTap == null ? Colors.white30 : active ? activeColor : Colors.white,
              size: size * 0.5),
        ),
      );

  Widget _buildPanel() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter, end: Alignment.topCenter,
        colors: [
          Colors.black, Colors.black.withOpacity(0.98),
          Colors.black.withOpacity(0.92), Colors.transparent,
        ],
        stops: const [0, 0.6, 0.8, 1],
      ),
    ),
    padding: EdgeInsets.only(
      left: 24, right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 28,
      top: 36,
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gpsAccuracy <= 8
                  ? Colors.white
                  : _gpsAccuracy <= 20 ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _gpsAccuracy > 0
                ? 'GPS ±${_gpsAccuracy.toStringAsFixed(0)}m'
                '${_isPaused ? '  •  PAUSED' : _loc.isStationary && _isRunning ? '  •  STILL' : ''}'
                : 'Searching for GPS...',
            style: TextStyle(
              color: _isPaused ? Colors.grey.shade400 : Colors.white38,
              fontSize: 10, letterSpacing: 0.8,
              fontWeight: _isPaused ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),

      // Main stats
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(children: [
          Row(children: [
            _statWidget('DISTANCE', '$_displayDistance', 'km'),
            _vDivider(),
            _statWidget('PACE', _displayPace, '/km'),
            _vDivider(),
            _statWidget('TIME', _displayTime, ''),
          ]),
          if (_isRunning) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 14),
            Row(children: [
              _statWidget('STEPS', _displaySteps, ''),
              _vDivider(),
              _statWidget('CADENCE', _cadence, 'spm'),
              _vDivider(),
              _statWidget('CALORIES', _calories, 'kcal'),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 24),
      if (!_isRunning)
        _startButton()
      else
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ctrlBtn(
            icon: _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: () => setState(() => _isPaused = !_isPaused),
            size: 56, filled: false,
          ),
          const SizedBox(width: 20),
          _ctrlBtn(icon: Icons.stop_rounded, onTap: _showStop, size: 72, filled: true),
          const SizedBox(width: 20),
          _ctrlBtn(
            icon: Icons.camera_alt_outlined,
            onTap: () {
              if (_camReady) {
                setState(() { _camVisible = !_camVisible; });
                if (!_camVisible) {
                  _camExpanded = false;
                  _flashOn = false;
                  _pendingFinish = false;
                  _camExpandCtrl.reverse();
                  _cam?.setFlashMode(FlashMode.off).catchError((_) {});
                }
              } else {
                _snack((_camSetupInProgress || _camSwitching)
                    ? 'Camera is loading...' : 'Camera unavailable');
              }
            },
            size: 56, filled: false, active: _camVisible,
          ),
        ]),
    ]),
  );

  // Cadence: steps per minute
  String get _cadence {
    if (_elapsedSeconds < 10 || _currentSteps == 0) return '--';
    final spm = (_currentSteps / (_elapsedSeconds / 60)).round();
    return '$spm';
  }

  // Live calorie estimate
  String get _calories {
    final cal = (_distanceKm * 62).round();
    return '$cal';
  }

  Widget _statWidget(String label, String value, String unit) => Expanded(
    child: Column(children: [
      Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 9,
              letterSpacing: 1.4, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      if (unit.isNotEmpty)
        Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]),
  );

  Widget _vDivider() => Container(
    width: 1, height: 40, color: Colors.white12,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );

  Widget _startButton() => GestureDetector(
    onTap: _ready ? _startRun : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity, height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(31),
        gradient: _ready
            ? const LinearGradient(
          colors: [Colors.white, Color(0xFFBBBBBB)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        )
            : LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade700]),
        boxShadow: _ready
            ? [BoxShadow(color: Colors.white.withOpacity(0.25), blurRadius: 24, spreadRadius: 2)]
            : [],
      ),
      child: Center(
        child: Text(
          _ready ? 'START RUN' : 'GETTING GPS...',
          style: TextStyle(
            color: _ready ? Colors.black : Colors.grey.shade500,
            fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 3,
          ),
        ),
      ),
    ),
  );

  Widget _ctrlBtn({
    required IconData icon,
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
            color: filled ? Colors.white
                : active ? Colors.white.withOpacity(0.2)
                : Colors.white.withOpacity(0.08),
            border: Border.all(color: Colors.white.withOpacity(filled ? 0 : 0.2)),
          ),
          child: Icon(icon, color: filled ? Colors.black : Colors.white, size: size * 0.44),
        ),
      );

  Future<void> _showExit() async {
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Leave?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('This run will not be saved.',
              style: TextStyle(color: Colors.white54)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text('Leave',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ));
  }
}
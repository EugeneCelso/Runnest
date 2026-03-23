import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class StepCounterService {
  StreamSubscription? _sub;
  final _stepCtrl = StreamController<int>.broadcast();

  int _totalSteps = 0;
  int get totalSteps => _totalSteps;

  Stream<int> get stepStream => _stepCtrl.stream;

  double _lastMagnitude = 0;
  final double _threshold = 11.5;
  bool _peakDetected = false;
  DateTime? _lastStepTime;

  final List<double> _buffer = [];
  static const int _bufferSize = 5;

  void start({int initialSteps = 0}) {
    _totalSteps = initialSteps;
    _sub?.cancel();
    _sub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen(_onAccelerometer);
  }

  void _onAccelerometer(AccelerometerEvent e) {
    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    _buffer.add(magnitude);
    if (_buffer.length > _bufferSize) _buffer.removeAt(0);
    final smoothed = _buffer.reduce((a, b) => a + b) / _buffer.length;

    final now = DateTime.now();

    if (_lastMagnitude < _threshold &&
        smoothed >= _threshold &&
        !_peakDetected) {
      if (_lastStepTime == null ||
          now.difference(_lastStepTime!).inMilliseconds >= 250) {
        _totalSteps++;
        _lastStepTime = now;
        if (!_stepCtrl.isClosed) _stepCtrl.add(_totalSteps);
        _peakDetected = true;
      }
    }

    if (smoothed < _threshold - 0.5) {
      _peakDetected = false;
    }

    _lastMagnitude = smoothed;
  }

  void reset() {
    _totalSteps = 0;
    _buffer.clear();
    _peakDetected = false;
    _lastStepTime = null;
    if (!_stepCtrl.isClosed) _stepCtrl.add(0);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    if (!_stepCtrl.isClosed) _stepCtrl.close();
  }
}
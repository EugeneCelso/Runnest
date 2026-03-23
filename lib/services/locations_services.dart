import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _sub;
  final _ctrl = StreamController<Position>.broadcast();

  double _kLat = 0, _kLng = 0, _kVariance = -1;
  DateTime? _lastKalmanTimestamp;

  static const int _stationaryWindowSize = 6;
  final List<Position> _recentPositions = [];
  bool _isStationary = false;

  static const int _warmupFixCount = 4;
  int _fixesSinceStart = 0;

  static const double _strictAccuracy = 10.0;
  static const double _relaxedAccuracy = 20.0;

  int _consecutiveGoodFixes = 0;
  static const int _goodFixStreak = 5;

  static const double _maxSpeedMs = 12.0;

  Position? _lastEmittedPos;

  Stream<Position> get rawStream => _ctrl.stream;
  bool get isStationary => _isStationary;
  Position? get lastPosition => _lastEmittedPos;

  Future<bool> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }
    if (perm == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<Position?> getCurrent() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        return null;
      }
    }
  }

  void start({bool resetKalman = false}) {
    _sub?.cancel();
    _fixesSinceStart = 0;
    _consecutiveGoodFixes = 0;

    if (resetKalman) {
      _kVariance = -1;
      _lastKalmanTimestamp = null;
      _lastEmittedPos = null;
      _recentPositions.clear();
      _isStationary = false;
    }

    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: false,
        intervalDuration: const Duration(milliseconds: 500),
      );
    }

    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((raw) {
      final filtered = _processPosition(raw);
      if (filtered != null && !_ctrl.isClosed) {
        _ctrl.add(filtered);
      }
    });
  }

  Position? _processPosition(Position raw) {
    _fixesSinceStart++;

    if (_fixesSinceStart <= _warmupFixCount) return null;

    final threshold = _consecutiveGoodFixes >= _goodFixStreak
        ? _relaxedAccuracy
        : _strictAccuracy;

    if (raw.accuracy > threshold) {
      _consecutiveGoodFixes = 0;
      return null;
    }
    _consecutiveGoodFixes++;

    final filtered = _applyKalman(raw);

    if (_lastEmittedPos != null) {
      final dist = Geolocator.distanceBetween(
        _lastEmittedPos!.latitude,
        _lastEmittedPos!.longitude,
        filtered.latitude,
        filtered.longitude,
      );
      final timeDiff = filtered.timestamp
          .difference(_lastEmittedPos!.timestamp)
          .inMilliseconds
          .clamp(100, 60000)
          .toDouble() /
          1000.0;
      if (dist / timeDiff > _maxSpeedMs) return null;
    }

    _recentPositions.add(filtered);
    if (_recentPositions.length > _stationaryWindowSize) {
      _recentPositions.removeAt(0);
    }
    _updateStationaryStatus();

    _lastEmittedPos = filtered;
    return filtered;
  }

  void _updateStationaryStatus() {
    if (_recentPositions.length < _stationaryWindowSize) return;
    double maxDist = 0;
    for (int i = 0; i < _recentPositions.length; i++) {
      for (int j = i + 1; j < _recentPositions.length; j++) {
        final d = Geolocator.distanceBetween(
          _recentPositions[i].latitude,
          _recentPositions[i].longitude,
          _recentPositions[j].latitude,
          _recentPositions[j].longitude,
        );
        if (d > maxDist) maxDist = d;
      }
    }
    _isStationary = maxDist < 6.0;
  }

  Position _applyKalman(Position pos) {
    final accuracy = pos.accuracy.clamp(1.0, 50.0);
    final now = pos.timestamp;

    double q;
    final speed = pos.speed < 0 ? 0.0 : pos.speed;

    if (_lastKalmanTimestamp != null) {
      final dt =
          now.difference(_lastKalmanTimestamp!).inMilliseconds / 1000.0;
      final dtClamped = dt.clamp(0.1, 2.0);

      if (speed < 0.3) {
        q = 0.05 * dtClamped;
      } else if (speed < 1.4) {
        q = 0.5 * dtClamped;
      } else {
        q = 1.5 * dtClamped;
      }
    } else {
      q = 1.5;
    }
    _lastKalmanTimestamp = now;

    if (_kVariance < 0) {
      _kLat = pos.latitude;
      _kLng = pos.longitude;
      _kVariance = accuracy * accuracy;
    } else {
      _kVariance += q;
      final k = _kVariance / (_kVariance + accuracy * accuracy);
      _kLat += k * (pos.latitude - _kLat);
      _kLng += k * (pos.longitude - _kLng);
      _kVariance *= (1.0 - k);
    }

    return Position(
      latitude: _kLat,
      longitude: _kLng,
      accuracy: sqrt(_kVariance),
      altitude: pos.altitude,
      altitudeAccuracy: pos.altitudeAccuracy,
      heading: pos.heading,
      headingAccuracy: pos.headingAccuracy,
      speed: speed,
      speedAccuracy: pos.speedAccuracy,
      timestamp: pos.timestamp,
    );
  }

  double metersBetween(Position a, Position b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    if (!_ctrl.isClosed) _ctrl.close();
  }
}
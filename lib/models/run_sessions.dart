import 'dart:convert';
import 'package:latlong2/latlong.dart';

class RunSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  List<LatLng> routePoints;
  double distanceKm;
  Duration elapsed;
  double pacePerKm;
  String? photoPath;

  RunSession({
    required this.id,
    required this.startTime,
    this.endTime,
    List<LatLng>? routePoints,
    this.distanceKm = 0,
    Duration? elapsed,
    this.pacePerKm = 0,
    this.photoPath,
  })  : routePoints = routePoints ?? [],
        elapsed = elapsed ?? Duration.zero;

  String get formattedPace {
    if (pacePerKm <= 0) return '--:--';
    final mins = (pacePerKm / 60).floor();
    final secs = (pacePerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get formattedTime {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String get formattedDistance => distanceKm.toStringAsFixed(2);

  String get estimatedCalories => '${(distanceKm * 62).round()} kcal';

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'distanceKm': distanceKm,
    'elapsedSeconds': elapsed.inSeconds,
    'pacePerKm': pacePerKm,
    'photoPath': photoPath,
    'routePoints': routePoints
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList(),
  };

  factory RunSession.fromJson(Map<String, dynamic> j) => RunSession(
    id: j['id'],
    startTime: DateTime.parse(j['startTime']),
    endTime: j['endTime'] != null ? DateTime.parse(j['endTime']) : null,
    distanceKm: (j['distanceKm'] as num).toDouble(),
    elapsed: Duration(seconds: j['elapsedSeconds'] as int),
    pacePerKm: (j['pacePerKm'] as num).toDouble(),
    photoPath: j['photoPath'],
    routePoints: (j['routePoints'] as List)
        .map((p) => LatLng(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble()))
        .toList(),
  );
}
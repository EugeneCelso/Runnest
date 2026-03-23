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
  int steps;

  RunSession({
    required this.id,
    required this.startTime,
    this.endTime,
    List<LatLng>? routePoints,
    this.distanceKm = 0,
    Duration? elapsed,
    this.pacePerKm = 0,
    this.photoPath,
    this.steps = 0,
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

  String get formattedSteps {
    if (steps >= 1000) return '${(steps / 1000).toStringAsFixed(1)}k';
    return '$steps';
  }

  String get formattedCadence {
    if (elapsed.inSeconds < 10 || steps == 0) return '--';
    final spm = (steps / (elapsed.inSeconds / 60)).round();
    return '$spm spm';
  }

  String get formattedAvgSpeed {
    if (elapsed.inSeconds == 0) return '0.0 km/h';
    final kmh = distanceKm / (elapsed.inSeconds / 3600);
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'distanceKm': distanceKm,
    'elapsedSeconds': elapsed.inSeconds,
    'pacePerKm': pacePerKm,
    'photoPath': photoPath,
    'steps': steps,
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
    steps: (j['steps'] as num?)?.toInt() ?? 0,
    routePoints: (j['routePoints'] as List)
        .map((p) => LatLng(
      (p['lat'] as num).toDouble(),
      (p['lng'] as num).toDouble(),
    ))
        .toList(),
  );
}
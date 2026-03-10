import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../models/run_sessions.dart';
import 'package:latlong2/latlong.dart';

class PhotoOverlayService {
  Future<String?> burnOverlay(String photoPath, RunSession session) async {
    try {
      final file = File(photoPath);
      if (!await file.exists()) return photoPath;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      final w = srcImage.width.toDouble();
      final h = srcImage.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // Draw source image
      canvas.drawImage(srcImage, Offset.zero, Paint());

      // Dark gradient at bottom for readability
      final gradPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.88)],
        ).createShader(Rect.fromLTWH(0, h * 0.42, w, h * 0.58));
      canvas.drawRect(Rect.fromLTWH(0, h * 0.42, w, h * 0.58), gradPaint);

      // Route mini-map — transparent background, just the polyline
      if (session.routePoints.length > 1) {
        _drawMiniPolyline(canvas, session.routePoints, w, h);
      }

      // Stats text
      _drawStats(canvas, session, w, h);

      // Watermark
      _drawWatermark(canvas, w, h);

      final picture = recorder.endRecording();
      final img = await picture.toImage(srcImage.width, srcImage.height);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes == null) return photoPath;

      final dir = await path_provider.getApplicationDocumentsDirectory();
      final outPath =
          '${dir.path}/overlay_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(pngBytes.buffer.asUint8List());
      return outPath;
    } catch (e) {
      debugPrint('PhotoOverlayService error: $e');
      return photoPath;
    }
  }

  void _drawMiniPolyline(
      Canvas canvas, List<LatLng> points, double w, double h) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final mapW = w * 0.28;
    final mapH = h * 0.20;
    final mapLeft = (w - mapW) / 2;
    final mapTop = h * 0.05;
    const padding = 18.0;

    final latRange = (maxLat - minLat).abs() < 1e-6 ? 0.001 : (maxLat - minLat).abs();
    final lngRange = (maxLng - minLng).abs() < 1e-6 ? 0.001 : (maxLng - minLng).abs();

    Offset toOffset(LatLng p) {
      final x = mapLeft + padding + ((p.longitude - minLng) / lngRange) * (mapW - padding * 2);
      final y = mapTop + padding + ((maxLat - p.latitude) / latRange) * (mapH - padding * 2);
      return Offset(x, y);
    }

    // NO background pill — fully transparent behind the route line.
    // A very subtle dark blur-shadow is drawn under the line for visibility
    // against both light and dark parts of the photo.

    // Build the route path
    final routePath = ui.Path();
    routePath.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      routePath.lineTo(toOffset(p).dx, toOffset(p).dy);
    }

    // Wide, semi-transparent dark shadow for contrast on any background
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.45)
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(routePath, shadowPaint);

    // White route line
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = w * 0.005
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(routePath, linePaint);

    // Start dot (white filled)
    canvas.drawCircle(
      toOffset(points.first),
      w * 0.012,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(toOffset(points.first), w * 0.010, Paint()..color = Colors.white);

    // End dot (grey)
    canvas.drawCircle(
      toOffset(points.last),
      w * 0.012,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(toOffset(points.last), w * 0.010, Paint()..color = Colors.grey.shade400);
  }

  void _drawStats(Canvas canvas, RunSession session, double w, double h) {
    final statY = h * 0.73;
    final colW = w / 3;
    final valueSize = w * 0.054;
    final labelSize = w * 0.028;

    _drawText(canvas, 'DISTANCE', colW * 0, statY, colW, labelSize, Colors.white54);
    _drawText(canvas, '${session.formattedDistance} km', colW * 0,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    _drawText(canvas, 'PACE', colW * 1, statY, colW, labelSize, Colors.white54);
    _drawText(canvas, '${session.formattedPace} /km', colW * 1,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    _drawText(canvas, 'TIME', colW * 2, statY, colW, labelSize, Colors.white54);
    _drawText(canvas, session.formattedTime, colW * 2,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    // Dividers
    final divPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(Offset(colW, statY - 8), Offset(colW, h * 0.89), divPaint);
    canvas.drawLine(Offset(colW * 2, statY - 8), Offset(colW * 2, h * 0.89), divPaint);
  }

  void _drawText(
      Canvas canvas,
      String text,
      double x,
      double y,
      double maxW,
      double fontSize,
      Color color, {
        bool bold = false,
      }) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ))
      ..addText(text);
    final para = pb.build()..layout(ui.ParagraphConstraints(width: maxW));
    canvas.drawParagraph(para, Offset(x, y));
  }

  void _drawWatermark(Canvas canvas, double w, double h) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: w * 0.024,
    ))
      ..pushStyle(ui.TextStyle(
        color: Colors.white70,
        fontSize: w * 0.024,
        fontWeight: FontWeight.bold,
      ))
      ..addText('RUNNE\$T');
    final para = pb.build()..layout(ui.ParagraphConstraints(width: w));
    canvas.drawParagraph(para, Offset(0, h * 0.93));
  }
}
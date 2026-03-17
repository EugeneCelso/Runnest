import 'dart:io';
import 'dart:math' as math;
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

      canvas.drawImage(srcImage, Offset.zero, Paint());

      // Dark gradient at bottom
      final gradPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.88)],
        ).createShader(Rect.fromLTWH(0, h * 0.42, w, h * 0.58));
      canvas.drawRect(Rect.fromLTWH(0, h * 0.42, w, h * 0.58), gradPaint);

      if (session.routePoints.length > 1) {
        _drawMiniPolyline(canvas, session.routePoints, w, h);
      }

      _drawStats(canvas, session, w, h);
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
    // ── Bounding box ───────────────────────────────────────────────
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Drawing area — centred at top of image
    final mapW = w * 0.38;
    final mapH = h * 0.28;
    final mapLeft = (w - mapW) / 2;
    final mapTop = h * 0.04;
    const padding = 20.0;

    final innerW = mapW - padding * 2;
    final innerH = mapH - padding * 2;

    final latRange =
    (maxLat - minLat).abs() < 1e-6 ? 0.001 : (maxLat - minLat).abs();
    final lngRange =
    (maxLng - minLng).abs() < 1e-6 ? 0.001 : (maxLng - minLng).abs();

    // ── Convert to metres so both axes are comparable ──────────────
    // 1° lat ≈ 111 000 m (constant everywhere)
    // 1° lng ≈ 111 000 * cos(latitude) m
    final midLat = (minLat + maxLat) / 2;
    final latMetres = latRange * 111000.0;
    final lngMetres = lngRange * 111000.0 * math.cos(midLat * math.pi / 180);

    // ── Uniform scale — fit the LARGER dimension, preserve shape ───
    final scaleX = lngMetres > 0 ? innerW / lngMetres : 1.0;
    final scaleY = latMetres > 0 ? innerH / latMetres : 1.0;
    final scale = math.min(scaleX, scaleY);

    final routePixelW = lngMetres * scale;
    final routePixelH = latMetres * scale;

    // Centre the route in the box
    final offsetX = mapLeft + padding + (innerW - routePixelW) / 2;
    final offsetY = mapTop + padding + (innerH - routePixelH) / 2;

    Offset toOffset(LatLng p) {
      final dx = ((p.longitude - minLng) / lngRange) * lngMetres * scale;
      final dy = ((maxLat - p.latitude) / latRange) * latMetres * scale;
      return Offset(offsetX + dx, offsetY + dy);
    }

    // ── Draw path ──────────────────────────────────────────────────
    final routePath = ui.Path();
    routePath.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (final p in points.skip(1)) {
      routePath.lineTo(toOffset(p).dx, toOffset(p).dy);
    }

    // Shadow
    canvas.drawPath(
      routePath,
      Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..strokeWidth = w * 0.012
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // White line
    canvas.drawPath(
      routePath,
      Paint()
        ..color = Colors.white.withOpacity(0.92)
        ..strokeWidth = w * 0.005
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // Start dot
    canvas.drawCircle(
      toOffset(points.first), w * 0.012,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
        toOffset(points.first), w * 0.010, Paint()..color = Colors.white);

    // End dot
    canvas.drawCircle(
      toOffset(points.last), w * 0.012,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(toOffset(points.last), w * 0.010,
        Paint()..color = Colors.grey.shade400);
  }

  void _drawStats(Canvas canvas, RunSession session, double w, double h) {
    final statY = h * 0.73;
    final colW = w / 3;
    final valueSize = w * 0.054;
    final labelSize = w * 0.028;

    _drawText(canvas, 'DISTANCE', colW * 0, statY, colW, labelSize,
        Colors.white54);
    _drawText(canvas, '${session.formattedDistance} km', colW * 0,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    _drawText(
        canvas, 'PACE', colW * 1, statY, colW, labelSize, Colors.white54);
    _drawText(canvas, '${session.formattedPace} /km', colW * 1,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    _drawText(
        canvas, 'TIME', colW * 2, statY, colW, labelSize, Colors.white54);
    _drawText(canvas, session.formattedTime, colW * 2,
        statY + labelSize * 1.6, colW, valueSize, Colors.white, bold: true);

    final divPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(colW, statY - 8), Offset(colW, h * 0.89), divPaint);
    canvas.drawLine(
        Offset(colW * 2, statY - 8), Offset(colW * 2, h * 0.89), divPaint);
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
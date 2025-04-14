import 'package:flutter/material.dart';

class DetectionPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size previewSize;
  final Size screenSize;

  DetectionPainter({
    required this.detections,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.red;

    final Paint textBgPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.red.withOpacity(0.7);

    final textStyle = const TextStyle(color: Colors.white, fontSize: 14.0);

    for (final detection in detections) {
      // 调整检测框坐标到屏幕大小
      final double xmin =
          detection['xmin'] * screenSize.width / previewSize.width;
      final double ymin =
          detection['ymin'] * screenSize.height / previewSize.height;
      final double xmax =
          detection['xmax'] * screenSize.width / previewSize.width;
      final double ymax =
          detection['ymax'] * screenSize.height / previewSize.height;

      final Rect rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);

      // 绘制边界框
      canvas.drawRect(rect, paint);

      // 绘制标签
      final String label =
          "${detection['name']} ${(detection['confidence'] * 100).toStringAsFixed(1)}%";
      final textSpan = TextSpan(text: label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // 绘制文本背景
      canvas.drawRect(
        Rect.fromLTWH(
          xmin,
          ymin - textPainter.height,
          textPainter.width,
          textPainter.height,
        ),
        textBgPaint,
      );

      // 绘制文本
      textPainter.paint(canvas, Offset(xmin, ymin - textPainter.height));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:puck/src/core/theme.dart';
import 'package:puck/src/data/models/context.dart';
import 'package:puck/src/features/puck/widgets/appear_in.dart';

/// The single-tap card: one fact, its provenance, nothing else.
///
/// The label ("NEXT UP", "BATTERY") is doing real work -- it tells you why
/// Puck interrupted you before you have read the sentence.
class ContextCard extends StatelessWidget {
  const ContextCard({required this.item, super.key});

  final ContextItem item;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AppearIn(
        child: PuckCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _ContextGlyph(kind: item.kind),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(item.label, style: PuckType.label),
                    const SizedBox(height: 6),
                    Text(
                      item.headline,
                      style: PuckType.primary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.detail != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        item.detail!,
                        style: PuckType.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four 16px monochrome marks. Drawn rather than imported: an icon font would
/// cost more than the four shapes it provides.
class _ContextGlyph extends StatelessWidget {
  const _ContextGlyph({required this.kind});

  final ContextKind kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(painter: _GlyphPainter(kind)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.kind);

  final ContextKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = PuckPalette.textSec;

    const double s = 16;
    final Rect box = const Offset(1.5, 1.5) & const Size(s - 3, s - 3);

    switch (kind) {
      case ContextKind.calendar:
        final RRect rrect =
            RRect.fromRectAndRadius(box, const Radius.circular(2.5));
        canvas.drawRRect(rrect, stroke);
        canvas.drawLine(
          const Offset(1.5, 5.5),
          const Offset(s - 1.5, 5.5),
          stroke,
        );
        canvas.drawPoints(
          PointMode.points,
          const <Offset>[Offset(5, 9.5), Offset(11, 9.5)],
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = PuckPalette.textSec,
        );

      case ContextKind.battery:
        final RRect body = RRect.fromRectAndRadius(
          const Offset(1.5, 4.5) & const Size(s - 6, s - 9),
          const Radius.circular(2),
        );
        canvas.drawRRect(body, stroke);
        canvas.drawRect(
          const Offset(s - 3.5, 7) & const Size(2, 4),
          Paint()..color = PuckPalette.textSec,
        );
        canvas.drawRect(
          const Offset(3.5, 6.5) & const Size((s - 9) * 0.45, s - 13),
          Paint()..color = PuckPalette.textPrim.withValues(alpha: 0.85),
        );

      case ContextKind.weather:
        // Cloud arc.
        canvas.drawArc(
          const Offset(3, 4) & const Size(7, 7),
          3.14159,
          3.14159,
          true,
          stroke,
        );
        canvas.drawArc(
          const Offset(6.5, 5.5) & const Size(6, 6),
          3.14159,
          3.14159,
          true,
          stroke,
        );
        canvas.drawLine(
          const Offset(2.5, 11.5),
          const Offset(13.5, 11.5),
          stroke,
        );
        // Two rain ticks.
        canvas.drawLine(const Offset(5, 12.5), const Offset(4, 14.5), stroke);
        canvas.drawLine(
          const Offset(10, 12.5),
          const Offset(9, 14.5),
          stroke,
        );

      case ContextKind.time:
        canvas.drawCircle(size.center(Offset.zero), s / 2 - 2, stroke);
        canvas.drawLine(
          size.center(Offset.zero),
          size.center(Offset.zero) + const Offset(0, -4),
          stroke,
        );
        canvas.drawLine(
          size.center(Offset.zero),
          size.center(Offset.zero) + const Offset(3, 1.5),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind;
}

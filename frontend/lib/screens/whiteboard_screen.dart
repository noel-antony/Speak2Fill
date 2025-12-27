import 'package:flutter/material.dart';

/// WhiteboardScreen - Visual guidance for where and what to write
///
/// Refined modern UI with side panel layout.
class WhiteboardScreen extends StatelessWidget {
  /// The text the user should write in this field
  final String textToWrite;

  /// Bounding box from OCR: [x1, y1, x2, y2] in image coordinates
  final List<double> boundingBox;

  /// Original image width from OCR (for coordinate scaling)
  final double imageWidth;

  /// Original image height from OCR (for coordinate scaling)
  final double imageHeight;

  /// Label of the field (e.g., "Name", "Date of Birth")
  final String fieldLabel;

  const WhiteboardScreen({
    super.key,
    required this.textToWrite,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Writing Guide'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent, // Let theme handle it
      ),
      body: Column(
        children: [
          // 1. Guide Panel (Top, Fixed Height or Flexible)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.edit_note_rounded,
                            size: 28,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Instruction',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              RichText(
                                text: TextSpan(
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Write '),
                                    TextSpan(
                                      text: textToWrite,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' in the box labeled "$fieldLabel"',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Action Button (Compact)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('I WROTE IT'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Canvas area (Remaining space)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface, // Matches card/surface in dark mode
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2), // Subtle shadow
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      painter: WhiteboardPainter(
                        textToWrite: textToWrite,
                        boundingBox: boundingBox,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        fieldLabel: fieldLabel,
                        // Pass theme colors to painter
                        overlayColor: Colors.black.withOpacity(0.85),
                        highlightColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        borderColor: Theme.of(context).colorScheme.secondary,
                        labelColor: Theme.of(context).colorScheme.primary,
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter implementation remains the same logic-wise, 
/// but using colours passed or defined here for consistency.
class WhiteboardPainter extends CustomPainter {
  final String textToWrite;
  final List<double> boundingBox;
  final double imageWidth;
  final double imageHeight;
  final String fieldLabel;

  final Color overlayColor;
  final Color highlightColor;
  final Color borderColor;
  final Color labelColor;

  WhiteboardPainter({
    required this.textToWrite,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
    this.overlayColor = Colors.black54,
    this.highlightColor = const Color(0xFFFFF9C4),
    this.borderColor = Colors.orange,
    this.labelColor = const Color(0xFF6C63FF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFormBackground(canvas, size);

    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    final double x1 = boundingBox[0] * scaleX;
    final double y1 = boundingBox[1] * scaleY;
    final double x2 = boundingBox[2] * scaleX;
    final double y2 = boundingBox[3] * scaleY;

    final Rect rect = Rect.fromLTRB(x1, y1, x2, y2);

    _drawDimmedOverlay(canvas, size, rect);
    _drawHighlightBox(canvas, rect);
    _drawFieldLabel(canvas, rect);
    _drawGuideText(canvas, rect);
  }

  void _drawFormBackground(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (double y = 40; y < size.height; y += 40) {
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), linePaint);
    }
  }

  void _drawDimmedOverlay(Canvas canvas, Size size, Rect activeRect) {
    final overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        activeRect.inflate(10),
        const Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);
  }

  void _drawHighlightBox(Canvas canvas, Rect rect) {
    // Glow
    final glowPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      glowPaint,
    );

    // Fill
    final fillPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      fillPaint,
    );

    // Border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    // Dashed effect simulation (simple)
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      borderPaint,
    );
  }

  void _drawFieldLabel(Canvas canvas, Rect rect) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: fieldLabel.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final offset = Offset(rect.left, rect.top - textPainter.height - 12);
    
    // Background tag
    final labelBgPaint = Paint()
      ..color = labelColor
      ..style = PaintingStyle.fill;
      
    final labelRect = Rect.fromLTWH(
      offset.dx, offset.dy,
      textPainter.width + 16, textPainter.height + 8,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
      labelBgPaint,
    );

    textPainter.paint(canvas, offset + const Offset(8, 4));
  }

  void _drawGuideText(Canvas canvas, Rect rect) {
    final fontSize = _calculateFontSize(rect);
    final textPainter = TextPainter(
      text: TextSpan(
        text: textToWrite,
        style: TextStyle(
          color: Colors.black.withOpacity(0.2),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 4.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: rect.width - 8);

    final offset = Offset(
      rect.left + (rect.width - textPainter.width) / 2,
      rect.top + (rect.height - textPainter.height) / 2,
    );

    textPainter.paint(canvas, offset);
  }

  double _calculateFontSize(Rect rect) {
    final heightBasedSize = rect.height * 0.55;
    return heightBasedSize.clamp(14.0, 36.0);
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.textToWrite != textToWrite ||
        oldDelegate.boundingBox != boundingBox;
  }
}

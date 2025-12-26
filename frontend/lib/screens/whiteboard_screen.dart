import 'package:flutter/material.dart';

/// WhiteboardScreen - Visual guidance for where and what to write
/// Shows the form with a highlighted bounding box and guide text
/// User writes on the physical paper form following this guidance
class WhiteboardScreen extends StatelessWidget {
  final String textToWrite;
  final List<int> boundingBox; // [x1, y1, x2, y2]

  const WhiteboardScreen({
    super.key,
    required this.textToWrite,
    required this.boundingBox,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write Here'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 32,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Write this in the highlighted box on your form:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  textToWrite,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          // Canvas area showing the form with highlighted box
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: WhiteboardPainter(
                    textToWrite: textToWrite,
                    boundingBox: boundingBox,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          // Done button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('Done - I have written it'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that draws the bounding box and guide text
class WhiteboardPainter extends CustomPainter {
  final String textToWrite;
  final List<int> boundingBox;

  WhiteboardPainter({
    required this.textToWrite,
    required this.boundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw a mock form background with lines
    _drawFormBackground(canvas, size);

    // Scale bounding box to fit canvas
    // Original bbox assumes a certain image size, we scale it to canvas
    final double scaleX = size.width / 400; // Assume original width 400
    final double scaleY = size.height / 500; // Assume original height 500

    final double x1 = boundingBox[0] * scaleX;
    final double y1 = boundingBox[1] * scaleY;
    final double x2 = boundingBox[2] * scaleX;
    final double y2 = boundingBox[3] * scaleY;

    final Rect rect = Rect.fromLTRB(x1, y1, x2, y2);

    // Draw highlight box with animation-like glow effect
    _drawHighlightBox(canvas, rect);

    // Draw dotted guide text
    _drawGuideText(canvas, rect, textToWrite);
  }

  void _drawFormBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    // Draw horizontal lines to simulate form lines
    for (double y = 50; y < size.height; y += 40) {
      canvas.drawLine(
        Offset(20, y),
        Offset(size.width - 20, y),
        paint,
      );
    }

    // Draw some mock labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final labels = ['Name:', 'Date of Birth:', 'Phone:', 'Address:', 'Signature:'];
    double yPos = 60;

    for (final label in labels) {
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(25, yPos));
      yPos += 80;
    }
  }

  void _drawHighlightBox(Canvas canvas, Rect rect) {
    // Draw filled highlight background
    final fillPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      borderPaint,
    );

    // Draw corner markers for emphasis
    _drawCornerMarkers(canvas, rect);
  }

  void _drawCornerMarkers(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const double markerLength = 15;

    // Top-left
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft.translate(markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft.translate(0, markerLength),
      paint,
    );

    // Top-right
    canvas.drawLine(
      rect.topRight,
      rect.topRight.translate(-markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight.translate(0, markerLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft.translate(0, -markerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(-markerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight.translate(0, -markerLength),
      paint,
    );
  }

  void _drawGuideText(Canvas canvas, Rect rect, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: rect.width - 10);

    // Center text in the box
    final offset = Offset(
      rect.left + (rect.width - textPainter.width) / 2,
      rect.top + (rect.height - textPainter.height) / 2,
    );

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.textToWrite != textToWrite ||
        oldDelegate.boundingBox != boundingBox;
  }
}

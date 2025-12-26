import 'package:flutter/material.dart';

/// WhiteboardScreen - Visual guidance for where and what to write
/// 
/// Shows the form with a highlighted bounding box and guide text.
/// User writes on the physical paper form following this guidance.
/// 
/// Coordinate System:
/// - OCR returns bbox in image-space coordinates (pixels of original image)
/// - We normalize these to canvas space using imageWidth/imageHeight
/// - scaleX = canvasWidth / imageWidth
/// - scaleY = canvasHeight / imageHeight
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
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        title: const Text('Write Here'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Instructions panel at top
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 36,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Write this in the "$fieldLabel" box:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                // The text to write - displayed prominently
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    textToWrite,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Canvas area - shows form with highlighted box
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      painter: WhiteboardPainter(
                        textToWrite: textToWrite,
                        boundingBox: boundingBox,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight,
                        fieldLabel: fieldLabel,
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  },
                ),
              ),
            ),
          ),
          
          // Helper text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Write exactly as shown in the highlighted area',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
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
                    textStyle: const TextStyle(fontSize: 16),
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

/// CustomPainter that draws the whiteboard overlay
/// 
/// Renders:
/// 1. Dimmed background overlay
/// 2. Highlighted rectangle at the scaled bounding box position
/// 3. Field label above the rectangle
/// 4. Guide text inside the rectangle
class WhiteboardPainter extends CustomPainter {
  final String textToWrite;
  final List<double> boundingBox; // [x1, y1, x2, y2] in image coordinates
  final double imageWidth;
  final double imageHeight;
  final String fieldLabel;

  WhiteboardPainter({
    required this.textToWrite,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Step 1: Draw mock form background
    _drawFormBackground(canvas, size);
    
    // Step 2: Calculate scale factors for coordinate normalization
    // This maps OCR image coordinates to canvas coordinates
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    // Step 3: Scale bounding box from image space to canvas space
    final double x1 = boundingBox[0] * scaleX;
    final double y1 = boundingBox[1] * scaleY;
    final double x2 = boundingBox[2] * scaleX;
    final double y2 = boundingBox[3] * scaleY;

    final Rect rect = Rect.fromLTRB(x1, y1, x2, y2);

    // Step 4: Draw dimmed overlay with cutout for active field
    _drawDimmedOverlay(canvas, size, rect);
    
    // Step 5: Draw the highlighted bounding box
    _drawHighlightBox(canvas, rect);
    
    // Step 6: Draw field label above the box
    _drawFieldLabel(canvas, rect);

    // Step 7: Draw guide text inside the box
    _drawGuideText(canvas, rect);
  }

  /// Draw a mock form background with lines to simulate a paper form
  void _drawFormBackground(Canvas canvas, Size size) {
    // White background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    
    // Draw horizontal lines to simulate form rows
    final linePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (double y = 40; y < size.height; y += 35) {
      canvas.drawLine(
        Offset(15, y),
        Offset(size.width - 15, y),
        linePaint,
      );
    }
  }

  /// Draw a semi-transparent overlay with a clear cutout for the active field
  void _drawDimmedOverlay(Canvas canvas, Size size, Rect activeRect) {
    // Draw dimmed overlay over entire canvas
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    
    // Create a path that covers everything except the active rectangle
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        activeRect.inflate(4), // Slightly larger cutout
        const Radius.circular(6),
      ))
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, overlayPaint);
  }

  /// Draw the highlighted bounding box with high contrast
  void _drawHighlightBox(Canvas canvas, Rect rect) {
    // Glow effect (outer shadow)
    final glowPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      glowPaint,
    );
    
    // Filled highlight background
    final fillPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );

    // Solid border
    final borderPaint = Paint()
      ..color = Colors.orange.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      borderPaint,
    );

    // Corner markers for extra emphasis
    _drawCornerMarkers(canvas, rect);
  }

  /// Draw corner markers to make the target area more visible
  void _drawCornerMarkers(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.red.shade600
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double markerLength = 12;

    // Top-left corner
    canvas.drawLine(
      rect.topLeft.translate(-2, -2),
      rect.topLeft.translate(markerLength, -2),
      paint,
    );
    canvas.drawLine(
      rect.topLeft.translate(-2, -2),
      rect.topLeft.translate(-2, markerLength),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      rect.topRight.translate(2, -2),
      rect.topRight.translate(-markerLength, -2),
      paint,
    );
    canvas.drawLine(
      rect.topRight.translate(2, -2),
      rect.topRight.translate(2, markerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      rect.bottomLeft.translate(-2, 2),
      rect.bottomLeft.translate(markerLength, 2),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft.translate(-2, 2),
      rect.bottomLeft.translate(-2, -markerLength),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      rect.bottomRight.translate(2, 2),
      rect.bottomRight.translate(-markerLength, 2),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight.translate(2, 2),
      rect.bottomRight.translate(2, -markerLength),
      paint,
    );
  }

  /// Draw the field label above the bounding box
  void _drawFieldLabel(Canvas canvas, Rect rect) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: fieldLabel,
        style: TextStyle(
          color: Colors.blue.shade800,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    
    // Position label above the box
    final offset = Offset(
      rect.left,
      rect.top - textPainter.height - 6,
    );

    // Draw background for label
    final labelBgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx - 4,
          offset.dy - 2,
          textPainter.width + 8,
          textPainter.height + 4,
        ),
        const Radius.circular(4),
      ),
      labelBgPaint,
    );

    textPainter.paint(canvas, offset);
  }

  /// Draw the guide text inside the bounding box
  void _drawGuideText(Canvas canvas, Rect rect) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: textToWrite,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontSize: _calculateFontSize(rect),
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: rect.width - 12);

    // Center text in the box
    final offset = Offset(
      rect.left + (rect.width - textPainter.width) / 2,
      rect.top + (rect.height - textPainter.height) / 2,
    );

    textPainter.paint(canvas, offset);
  }

  /// Calculate appropriate font size based on box dimensions
  double _calculateFontSize(Rect rect) {
    // Scale font size based on box height, with min/max limits
    final heightBasedSize = rect.height * 0.5;
    return heightBasedSize.clamp(14.0, 28.0);
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.textToWrite != textToWrite ||
        oldDelegate.boundingBox != boundingBox ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.fieldLabel != fieldLabel;
  }
}

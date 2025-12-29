import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

const String backendBaseUrl = 'http://localhost:8000';

/// WhiteboardScreen - Visual guidance for where and what to write
///
/// Uses device + orientation specific FIXED image dimensions to avoid bbox drift.
class WhiteboardScreen extends StatefulWidget {
  /// The text the user should write in this field
  final String textToWrite;

  /// Bounding box from backend response: [x1, y1, x2, y2] in image coordinates
  final List<double> boundingBox;

  /// Original image width from backend /analyze-form
  final double imageWidth;

  /// Original image height from backend /analyze-form
  final double imageHeight;

  /// Field label from backend response
  final String fieldLabel;

  /// Session ID for fetching the original image via GET /session/{session_id}/image
  final String sessionId;

  const WhiteboardScreen({
    super.key,
    required this.textToWrite,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
    required this.sessionId,
  });

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    // Explicitly fetch the image from backend when screen opens
    _imageFuture = _fetchSessionImage();
  }

  /// Determine fixed image width based on device and orientation rules
  double _fixedWidth(bool isPortrait) {
    if (kIsWeb) {
      return isPortrait ? 600.0 : 900.0;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return isPortrait ? 360.0 : 420.0;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return isPortrait ? 420.0 : 600.0;
      case TargetPlatform.fuchsia:
        // Treat like desktop defaults
        return isPortrait ? 420.0 : 600.0;
    }
  }

  Future<Uint8List?> _fetchSessionImage() async {
    final url = '$backendBaseUrl/session/${widget.sessionId}/image';
    debugPrint('DEBUG: Fetching image from: $url');
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        debugPrint('DEBUG: Image fetched successfully, size: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        debugPrint('DEBUG: Image fetch failed with status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('DEBUG: Image fetch error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Top button bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
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
            ),
            
            // Image + Instructions area (fixed size, orientation-aware)
            FutureBuilder<Uint8List?>(
              future: _imageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                
                if (snapshot.hasError || snapshot.data == null) {
                  debugPrint('DEBUG: Image load error or null data');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Failed to load image\n${snapshot.error}', textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }

                final isPortrait = widget.imageWidth <= widget.imageHeight;
                final fixedWidth = _fixedWidth(isPortrait);
                final aspectRatio = widget.imageWidth / widget.imageHeight;
                final fixedHeight = fixedWidth / aspectRatio;

                debugPrint('DEBUG: Layout - isPortrait=$isPortrait, fixedWidth=$fixedWidth, fixedHeight=$fixedHeight');

                final imageBox = SizedBox(
                  width: fixedWidth,
                  height: fixedHeight,
                  child: Stack(
                    children: [
                      // Image rendered at fixed size
                      Image.memory(
                        snapshot.data!,
                        width: fixedWidth,
                        height: fixedHeight,
                        fit: BoxFit.fill,
                      ),
                      // Bbox overlay (same fixed size)
                      CustomPaint(
                        size: Size(fixedWidth, fixedHeight),
                        painter: SimpleBboxPainter(
                          boundingBox: widget.boundingBox,
                          imageWidth: widget.imageWidth,
                          imageHeight: widget.imageHeight,
                          fieldLabel: widget.fieldLabel,
                        ),
                      ),
                    ],
                  ),
                );

                final instructionsPanel = Container(
                  padding: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    // Panel width: for portrait, match image width; for landscape, cap to 360
                    maxWidth: isPortrait ? fixedWidth : 360.0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Instruction',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          children: [
                            const TextSpan(text: 'Write '),
                            TextSpan(
                              text: widget.textToWrite.isEmpty ? '(any value)' : widget.textToWrite,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              ),
                            ),
                            TextSpan(text: ' in the box labeled '),
                            TextSpan(
                              text: '"${widget.fieldLabel}"',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                if (isPortrait) {
                  // Vertical layout: Instructions above Image
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        instructionsPanel,
                        const SizedBox(height: 16),
                        imageBox,
                      ],
                    ),
                  );
                } else {
                  // Horizontal layout: Image | Instructions
                  return Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        imageBox,
                        const SizedBox(width: 24),
                        instructionsPanel,
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple painter that draws only a bbox highlight and label on top of image
class SimpleBboxPainter extends CustomPainter {
  final List<double> boundingBox;
  final double imageWidth;
  final double imageHeight;
  final String fieldLabel;

  SimpleBboxPainter({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boundingBox.length < 4) {
      debugPrintStack(label: 'SimpleBboxPainter: boundingBox has ${boundingBox.length} elements, expected 4');
      return;
    }

    // Scale bbox coordinates from image space to canvas space
    // Since we use fixed dimensions, this scale factor is constant
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;
    
    debugPrint('DEBUG: BboxPainter - Canvas size: ${size.width}x${size.height}');
    debugPrint('DEBUG: BboxPainter - Image size: ${imageWidth}x${imageHeight}');
    debugPrint('DEBUG: BboxPainter - Scale factors: scaleX=$scaleX, scaleY=$scaleY');
    debugPrint('DEBUG: BboxPainter - Original bbox: $boundingBox');

    final double x1 = boundingBox[0] * scaleX;
    final double y1 = boundingBox[1] * scaleY;
    final double x2 = boundingBox[2] * scaleX;
    final double y2 = boundingBox[3] * scaleY;

    final Rect rect = Rect.fromLTRB(x1, y1, x2, y2);
    
    debugPrint('DEBUG: BboxPainter - Scaled bbox rect: $rect');

    // Draw dimmed overlay outside bbox
    _drawDimmedOverlay(canvas, size, rect);
    
    // Draw highlight box
    _drawHighlightBox(canvas, rect);
    
    // Draw field label tag
    _drawFieldLabel(canvas, rect);
  }

  void _drawDimmedOverlay(Canvas canvas, Size size, Rect activeRect) {
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    // Draw path that covers entire canvas except the bbox
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
    // Glow effect
    final glowPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      glowPaint,
    );

    // Fill (light yellow)
    final fillPaint = Paint()
      ..color = const Color(0xFFFFF9C4).withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      fillPaint,
    );

    // Border (orange/secondary)
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
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
    
    // Background tag (orange)
    final labelBgPaint = Paint()
      ..color = Colors.orange
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

  @override
  bool shouldRepaint(covariant SimpleBboxPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox || oldDelegate.fieldLabel != fieldLabel;
  }
}

/// (Deprecated) Old WhiteboardPainter - kept for reference but no longer used
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
    // Guard: ensure bbox has 4 elements
    if (boundingBox.length < 4) {
      debugPrintStack(label: 'WhiteboardPainter: boundingBox has ${boundingBox.length} elements, expected 4');
      final paint = Paint()..color = Colors.grey[300]!;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      return;
    }

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
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
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


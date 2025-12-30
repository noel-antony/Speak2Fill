import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

const String backendBaseUrl = 'https://speak2fill.onrender.com';

/// WhiteboardScreen - Shows form image with highlighted field bbox
class WhiteboardScreen extends StatefulWidget {
  final String textToWrite;
  final List<double> boundingBox;
  final double imageWidth;
  final double imageHeight;
  final String fieldLabel;
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
    _imageFuture = _fetchSessionImage();
  }

  Future<Uint8List?> _fetchSessionImage() async {
    final url = '$backendBaseUrl/session/${widget.sessionId}/image';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Image fetch error: $e');
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
            // Top button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('I WROTE IT'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
            
            // Image area
            Expanded(
              child: FutureBuilder<Uint8List?>(
                future: _imageFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (snapshot.hasError || snapshot.data == null) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 48),
                          SizedBox(height: 16),
                          Text('Failed to load image'),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInstructionCard(),
                            const SizedBox(height: 16),
                            _buildImageWithBbox(snapshot.data!),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 600),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Instruction',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyLarge,
              children: [
                const TextSpan(text: 'Write '),
                TextSpan(
                  text: widget.textToWrite.isEmpty
                      ? '(any value)'
                      : widget.textToWrite,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const TextSpan(text: ' in the '),
                TextSpan(
                  text: '"${widget.fieldLabel}"',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' box'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWithBbox(Uint8List imageBytes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate display size
        final maxWidth = constraints.maxWidth;
        final aspectRatio = widget.imageWidth / widget.imageHeight;
        final displayWidth = maxWidth.clamp(300.0, 1200.0);
        final displayHeight = displayWidth / aspectRatio;

        return Container(
          width: displayWidth,
          height: displayHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Image
                Image.memory(
                  imageBytes,
                  width: displayWidth,
                  height: displayHeight,
                  fit: BoxFit.contain,
                ),
                // Bbox overlay
                CustomPaint(
                  size: Size(displayWidth, displayHeight),
                  painter: BboxPainter(
                    boundingBox: widget.boundingBox,
                    imageWidth: widget.imageWidth,
                    imageHeight: widget.imageHeight,
                    fieldLabel: widget.fieldLabel,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Simple bbox painter - scales bbox from original image coordinates to display coordinates
class BboxPainter extends CustomPainter {
  final List<double> boundingBox;
  final double imageWidth;
  final double imageHeight;
  final String fieldLabel;

  BboxPainter({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.fieldLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boundingBox.length < 4) return;

    // Scale bbox from original image coordinates to display coordinates
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final x1 = boundingBox[0] * scaleX;
    final y1 = boundingBox[1] * scaleY;
    final x2 = boundingBox[2] * scaleX;
    final y2 = boundingBox[3] * scaleY;

    final rect = Rect.fromLTRB(x1, y1, x2, y2);

    // Draw dimmed overlay outside bbox
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect.inflate(8), const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // Draw highlight box
    final highlightPaint = Paint()
      ..color = Colors.orange.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      highlightPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      borderPaint,
    );

    // Draw label
    _drawLabel(canvas, rect);
  }

  void _drawLabel(Canvas canvas, Rect rect) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: fieldLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final labelWidth = textPainter.width + 16;
    final labelHeight = textPainter.height + 8;
    final labelTop = rect.top - labelHeight - 8;

    // Label background
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left, labelTop, labelWidth, labelHeight),
      const Radius.circular(8),
    );

    final bgPaint = Paint()..color = Colors.orange;

    canvas.drawRRect(bgRect, bgPaint);

    // Label text
    textPainter.paint(
      canvas,
      Offset(
        rect.left + 8,
        labelTop + 4,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BboxPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox ||
        oldDelegate.fieldLabel != fieldLabel;
  }
}
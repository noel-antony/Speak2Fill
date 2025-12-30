import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/tts_service.dart';
import '../services/stt_service.dart';

/// Whiteboard-only screen for voice-driven form filling
/// NO CHAT UI - Only form image + highlight + 2 buttons
/// Voice is handled by backend-only STT/TTS via Sarvam
class FormFillingScreen extends StatefulWidget {
  final String sessionId;
  final String backendUrl;
  final int imageWidth;
  final int imageHeight;

  const FormFillingScreen({
    Key? key,
    required this.sessionId,
    required this.backendUrl,
    required this.imageWidth,
    required this.imageHeight,
  }) : super(key: key);

  @override
  State<FormFillingScreen> createState() => _FormFillingScreenState();
}

class _FormFillingScreenState extends State<FormFillingScreen> {
  final TtsService _tts = TtsService();
  final SttService _stt = SttService();

  bool _isRecording = false;
  bool _isProcessing = false;
  String _instructionText = "Tap Speak to answer";
  String? _currentPhase; // "ASK_INPUT" or "AWAIT_CONFIRMATION"
  DrawGuideAction? _currentAction;
  Future<Uint8List>? _formImageFuture;
  Uint8List? _cachedImage;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize TTS and STT services
    await _tts.initialize();
    await _stt.initialize();

    _formImageFuture = _loadFormImage();

    // Start form filling
    _startFormFilling();
  }

  @override
  void dispose() {
    _tts.dispose();
    _stt.dispose();
    super.dispose();
  }

  Future<void> _startFormFilling() async {
    // Trigger first instruction by sending empty CONFIRM_DONE
    // Backend will respond with first field instruction
    setState(() {
      _isProcessing = true;
      _instructionText = "Loading...";
    });

    try {
      final response = await _sendChatRequest(event: "CONFIRM_DONE");
      await _handleChatResponse(response);
    } catch (e) {
      _showError("Error while starting: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _sendChatRequest({
    required String event,
    String? userText,
  }) async {
    final url = Uri.parse('${widget.backendUrl}/chat');
    final body = {
      'session_id': widget.sessionId,
      'event': event,
      if (userText != null) 'user_text': userText,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Chat API error: ${response.statusCode}');
    }

    return jsonDecode(response.body);
  }

  Future<void> _handleChatResponse(Map<String, dynamic> response) async {
    final assistantText = response['assistant_text'] as String;
    final action = response['action'] as Map<String, dynamic>?;

    setState(() {
      _instructionText = assistantText;
      _currentAction = action != null ? DrawGuideAction.fromJson(action) : null;
      _currentPhase = action != null ? "AWAIT_CONFIRMATION" : "ASK_INPUT";
    });

    // Speak instruction using backend TTS
    await _tts.speak(
      assistantText,
      backendUrl: widget.backendUrl,
      sessionId: widget.sessionId,
    );
  }

  Future<void> _onMicTapped() async {
    if (_isProcessing) return;

    if (!_isRecording) {
      final started = await _stt.startRecording(
        backendUrl: widget.backendUrl,
        sessionId: widget.sessionId,
      );
      if (started) {
        setState(() {
          _isRecording = true;
          _instructionText = "Listening... tap again to stop";
        });
      } else {
        _showError("Microphone is unavailable");
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _instructionText = "Processing your answer...";
    });

    try {
      final transcript = await _stt.stopAndTranscribe();
      setState(() => _isRecording = false);

      if (transcript == null || transcript.isEmpty) {
        _showError("We did not catch that. Please try again.");
        setState(() => _instructionText = "Tap Speak and try again");
        return;
      }

      await _processUserInput(transcript);
    } catch (e) {
      _showError("Recording failed: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _processUserInput(String transcript) async {
    setState(() {
      _isProcessing = true;
      _instructionText = "Processing...";
    });

    try {
      final chatResponse = await _sendChatRequest(
        event: "USER_SPOKE",
        userText: transcript,
      );

      await _handleChatResponse(chatResponse);
    } catch (e) {
      _showError("Processing error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _onConfirmPressed() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _instructionText = "Moving to the next field...";
    });

    try {
      final response = await _sendChatRequest(event: "CONFIRM_DONE");
      await _handleChatResponse(response);
    } catch (e) {
      _showError("Confirmation failed: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _onSkipPressed() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _instructionText = "Skipping this field...";
    });

    try {
      final response = await _sendChatRequest(event: "SKIP_FIELD");
      await _handleChatResponse(response);
    } catch (e) {
      _showError("Skip failed: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Stack(
          children: [
            // Form image with highlight overlay
            Column(
              children: [
                // Instruction text overlay
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black87,
                  width: double.infinity,
                  child: Text(
                    _instructionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Form image with highlight
                Expanded(
                  child: Center(
                    child: _buildFormImageWithHighlight(),
                  ),
                ),

                // Action buttons at bottom
                _buildActionButtons(),
              ],
            ),

            // Processing overlay
            if (_isProcessing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormImageWithHighlight() {
    return FutureBuilder<Uint8List>(
      future: _formImageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        }

        if (!snapshot.hasData) {
          return const Text(
            "Failed to load form image",
            style: TextStyle(color: Colors.white),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final aspect = widget.imageWidth / widget.imageHeight;
            double displayWidth = constraints.maxWidth;
            double displayHeight = displayWidth / aspect;

            if (displayHeight > constraints.maxHeight) {
              displayHeight = constraints.maxHeight;
              displayWidth = displayHeight * aspect;
            }

            return Center(
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (_currentAction != null)
                      CustomPaint(
                        size: Size(displayWidth, displayHeight),
                        painter: HighlightPainter(
                          bbox: _currentAction!.bbox,
                          imageWidth: widget.imageWidth,
                          imageHeight: widget.imageHeight,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Uint8List> _loadFormImage() async {
    if (_cachedImage != null) return _cachedImage!;

    final url = Uri.parse('${widget.backendUrl}/session/${widget.sessionId}/image');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      _cachedImage = response.bodyBytes;
      return _cachedImage!;
    }

    throw Exception('Failed to load image');
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentPhase == "ASK_INPUT" || _currentPhase == null)
            _buildSpeakButton(),
          if (_currentPhase == "AWAIT_CONFIRMATION") ...[
            _buildConfirmButton(),
            const SizedBox(width: 12),
            _buildSkipButton(),
          ],
          if (_currentPhase == "ASK_INPUT") ...[
            const SizedBox(width: 12),
            _buildSkipButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeakButton() {
    return FilledButton.icon(
      onPressed: _isProcessing ? null : _onMicTapped,
      icon: Icon(
        _isRecording ? Icons.stop_circle : Icons.mic,
        size: 28,
      ),
      label: Text(
        _isRecording ? "Stop" : "Speak",
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _isRecording ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 6,
        shadowColor: Colors.black26,
      ),
    );
  }

  Widget _buildConfirmButton() {
    return FilledButton.icon(
      onPressed: _isProcessing ? null : _onConfirmPressed,
      icon: const Icon(Icons.check_circle, size: 24),
      label: const Text(
        "Done writing",
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF10B981),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 4,
      ),
    );
  }

  Widget _buildSkipButton() {
    return OutlinedButton.icon(
      onPressed: _isProcessing ? null : _onSkipPressed,
      icon: const Icon(Icons.skip_next_rounded),
      label: const Text("Skip field"),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class DrawGuideAction {
  final String type;
  final String fieldId;
  final String textToWrite;
  final List<int> bbox;
  final int imageWidth;
  final int imageHeight;

  DrawGuideAction({
    required this.type,
    required this.fieldId,
    required this.textToWrite,
    required this.bbox,
    required this.imageWidth,
    required this.imageHeight,
  });

  factory DrawGuideAction.fromJson(Map<String, dynamic> json) {
    return DrawGuideAction(
      type: json['type'] as String,
      fieldId: json['field_id'] as String,
      textToWrite: json['text_to_write'] as String,
      bbox: List<int>.from(json['bbox']),
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
    );
  }
}

class HighlightPainter extends CustomPainter {
  final List<int> bbox;
  final int imageWidth;
  final int imageHeight;

  HighlightPainter({
    required this.bbox,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final rect = Rect.fromLTRB(
      bbox[0] * scaleX,
      bbox[1] * scaleY,
      bbox[2] * scaleX,
      bbox[3] * scaleY,
    );

    // Draw semi-transparent fill
    final fillPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    canvas.drawRect(rect, fillPaint);

    // Draw yellow border
    final borderPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRect(rect, borderPaint);

    // Draw corner markers
    const cornerSize = 20.0;
    final cornerPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Top-left corner
    canvas.drawLine(
      Offset(rect.left, rect.top + cornerSize),
      Offset(rect.left, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + cornerSize, rect.top),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(rect.right - cornerSize, rect.top),
      Offset(rect.right, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + cornerSize),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left, rect.bottom - cornerSize),
      Offset(rect.left, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + cornerSize, rect.bottom),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right - cornerSize, rect.bottom),
      Offset(rect.right, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - cornerSize),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

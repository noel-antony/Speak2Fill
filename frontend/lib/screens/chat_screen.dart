import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'whiteboard_screen.dart';
const String backendBaseUrl = 'https://speak2fill.onrender.com';

/// ChatScreen - Conversational interface with the AI assistant
///
/// Drives the form filling process:
/// 1. Asks question for current field
/// 2. Accepts user voice/text input
/// 3. Shows "Draw" action (navigates to Whiteboard)
/// 4. Advances to next field
class ChatScreen extends StatefulWidget {
  final String sessionId;
  final double imageWidth;
  final double imageHeight;
  final List<dynamic> fields;

  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.imageWidth,
    required this.imageHeight,
    required this.fields,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Chat messages history
  final List<Map<String, dynamic>> _messages = [];

  bool _isTyping = false;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    // Start the flow after a brief delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startFormFlow();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startFormFlow() {
    setState(() {
      _hasStarted = true;
    });
    _sendChatMessage("");
  }

  void _askCurrentQuestion() {}

  void _addAssistantMessage(String content) {
    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': content,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _addUserMessage(String content) {
    setState(() {
      _messages.add({
        'role': 'user',
        'content': content,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _handleUserResponse(String text) async {
    _addUserMessage(text);
    _messageController.clear();
    await _sendChatMessage(text);
  }

  Future<void> _sendChatMessage(String userMessage) async {
    setState(() => _isTyping = true);
    try {
      final uri = Uri.parse('$backendBaseUrl/chat');
      final payload = {
        'session_id': widget.sessionId,
        'user_message': userMessage,
      };
      final resp = await http.post(uri, headers: {
        'Content-Type': 'application/json',
      }, body: json.encode(payload));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        debugPrint('DEBUG: Chat response: $data');
        
        final assistantText = data['assistant_text'] as String?;
        if (assistantText != null && assistantText.isNotEmpty) {
          _addAssistantMessage(assistantText);
        }

        final action = data['action'] as Map<String, dynamic>?;
        debugPrint('DEBUG: action object: $action');
        
        if (action != null && action['type'] == 'DRAW_GUIDE') {
          // Backend response has action.type, action.field_label, action.text_to_write, action.bbox, etc.
          final textToWrite = (action['text_to_write'] ?? '').toString();
          final bboxList = action['bbox'] as List<dynamic>?;
          final fieldLabel = (action['field_label'] ?? '').toString();
          
          debugPrint('DEBUG: DRAW_GUIDE action extracted:');
          debugPrint('  text_to_write: $textToWrite');
          debugPrint('  field_label: $fieldLabel');
          debugPrint('  bbox: $bboxList');
          
          List<double> bbox = [];
          if (bboxList != null && bboxList.isNotEmpty) {
            bbox = bboxList.map((e) => (e as num).toDouble()).toList();
            debugPrint('DEBUG: converted bbox to doubles: $bbox (length=${bbox.length})');
          } else {
            debugPrint('DEBUG: bboxList is null or empty!');
          }

          setState(() {
            _messages.add({
              'role': 'system_action',
              'content': 'Tap to write on form',
              'action_label': 'OPEN WRITING GUIDE',
              'text_to_write': textToWrite,
              'bbox': bbox,
              'field_label': fieldLabel,
            });
          });
          _scrollToBottom();
        }
      } else {
        debugPrint('Chat failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('Chat error: $e');
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _openWhiteboard(String valueToWrite, List<double> bbox, String fieldLabel) async {
    debugPrint('DEBUG: Opening whiteboard with session_id=${widget.sessionId}');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhiteboardScreen(
          textToWrite: valueToWrite,
          boundingBox: bbox,
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          fieldLabel: fieldLabel,
          sessionId: widget.sessionId,
        ),
      ),
    );

    // When they return, confirm to backend
    await _sendChatMessage('done');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: const Color(0xFFF1F4F9), // Removed to use theme default
      appBar: AppBar(
        title: const Text('Form Assistant'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingIndicator();
                }

                final msg = _messages[index];
                if (msg['role'] == 'system_action') {
                  return _ActionBubble(
                    label: msg['action_label'],
                    onPressed: () => _openWhiteboard(
                      msg['text_to_write'] ?? '',
                      (msg['bbox'] as List<double>? ?? const []),
                      msg['field_label'] ?? '',
                    ),
                  );
                }

                return _ChatBubble(
                  message: msg['content'],
                  isUser: msg['role'] == 'user',
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Type your answer...',
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24, 
                    vertical: 16
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) _handleUserResponse(val.trim());
                },
              ),
            ),
            const SizedBox(width: 12),
            DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF22C55E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x406366F1),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  final val = _messageController.text.trim();
                  if (val.isNotEmpty) _handleUserResponse(val);
                },
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                iconSize: 24,
                padding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;

  const _ChatBubble({required this.message, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAssistant = !isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isAssistant) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                ),
                child: Icon(Icons.smart_toy_outlined, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
            ],
            
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isUser 
                      ? theme.colorScheme.primary 
                      : theme.cardColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(24),
                    topRight: const Radius.circular(24),
                    bottomLeft: Radius.circular(isUser ? 24 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    color: isUser ? Colors.white : theme.colorScheme.onSurface,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBubble extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ActionBubble({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 44, bottom: 20),
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.secondary,
                  const Color(0xFF26A69A), // slightly darker teal
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20, left: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(),
            const SizedBox(width: 4),
            _dot(),
            const SizedBox(width: 4),
            _dot(),
          ],
        ),
      ),
    );
  }

  Widget _dot() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        shape: BoxShape.circle,
      ),
    );
  }
}

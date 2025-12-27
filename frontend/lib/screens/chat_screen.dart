import 'package:flutter/material.dart';
import '../mocks/mock_data.dart';
import 'whiteboard_screen.dart';

/// ChatScreen - Conversational interface with the AI assistant
///
/// Drives the form filling process:
/// 1. Asks question for current field
/// 2. Accepts user voice/text input
/// 3. Shows "Draw" action (navigates to Whiteboard)
/// 4. Advances to next field
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Chat messages history
  final List<Map<String, dynamic>> _messages = [];

  // Current state
  int _currentFieldIndex = 0;
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
      _askCurrentQuestion();
    });
  }

  void _askCurrentQuestion() {
    if (_currentFieldIndex >= MockData.formFields.length) {
      _addAssistantMessage(
        'All done! You have successfully filled the form. Great job!',
      );
      return;
    }

    final field = MockData.formFields[_currentFieldIndex];
    _addAssistantMessage(field['question']);
  }

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

    if (_currentFieldIndex >= MockData.formFields.length) return;

    // Simulate thinking
    setState(() => _isTyping = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _isTyping = false);

    final field = MockData.formFields[_currentFieldIndex];
    
    String valueToWrite = text.toUpperCase();
    if (valueToWrite.length < 2) {
       // Demo fallback
       valueToWrite = (field['example'] as String).toUpperCase();
    }

    _addAssistantMessage(field['response']);
    
    setState(() {
      _messages.add({
        'role': 'system_action',
        'content': 'Tap to write on form',
        'action_label': 'OPEN WRITING GUIDE',
        'field_data': field,
        'value_to_write': valueToWrite,
      });
    });
    _scrollToBottom();
  }

  Future<void> _openWhiteboard(Map<String, dynamic> field, String valueToWrite) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhiteboardScreen(
          textToWrite: valueToWrite,
          boundingBox: List<double>.from(field['bbox']),
          imageWidth: MockData.imageWidth,
          imageHeight: MockData.imageHeight,
          fieldLabel: field['label'],
        ),
      ),
    );

    // When they return, we assume they wrote it.
    // Advance to next field
    if (!mounted) return;
    
    setState(() {
      _currentFieldIndex++;
    });
    
    // Ask next question
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _askCurrentQuestion();
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
                      msg['field_data'], 
                      msg['value_to_write']
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
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
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
                padding: const EdgeInsets.all(12),
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

import 'package:flutter/material.dart';
import 'whiteboard_screen.dart';

/// ChatScreen - Conversational interface with the AI assistant
/// The assistant asks questions and guides the user on what to write.
/// When a DRAW_GUIDE action is received, navigates to WhiteboardScreen.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Chat messages: each message has 'role' (user/assistant) and 'content'
  final List<Map<String, String>> _messages = [];

  // Track if we've shown the initial greeting
  bool _hasShownGreeting = false;

  // Mock field index to simulate multiple form fields
  int _currentFieldIndex = 0;

  // Mock form fields for demonstration
  final List<Map<String, dynamic>> _mockFields = [
    {
      'question': 'I will help you fill this form. What is your name?',
      'response': 'Please write your name in the highlighted box.',
      'action': {
        'type': 'DRAW_GUIDE',
        'text': 'RAVI KUMAR',
        'bbox': [50, 100, 300, 150],
      },
    },
    {
      'question': 'Great! Now, what is your date of birth?',
      'response': 'Please write your date of birth in the highlighted box.',
      'action': {
        'type': 'DRAW_GUIDE',
        'text': '15/08/1990',
        'bbox': [50, 180, 250, 230],
      },
    },
    {
      'question': 'What is your phone number?',
      'response': 'Please write your phone number in the highlighted box.',
      'action': {
        'type': 'DRAW_GUIDE',
        'text': '9876543210',
        'bbox': [50, 260, 280, 310],
      },
    },
  ];

  @override
  void initState() {
    super.initState();
    // Show initial greeting after a brief delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_hasShownGreeting) {
        _showAssistantGreeting();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Show the initial assistant greeting
  void _showAssistantGreeting() {
    setState(() {
      _hasShownGreeting = true;
      if (_currentFieldIndex < _mockFields.length) {
        _messages.add({
          'role': 'assistant',
          'content': _mockFields[_currentFieldIndex]['question'],
        });
      }
    });
    _scrollToBottom();
  }

  /// Handle sending a message
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      // Add user message
      _messages.add({
        'role': 'user',
        'content': text,
      });
    });

    _messageController.clear();
    _scrollToBottom();

    // Simulate assistant response after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _handleAssistantResponse(text);
    });
  }

  /// Generate mock assistant response
  void _handleAssistantResponse(String userMessage) {
    if (_currentFieldIndex >= _mockFields.length) {
      // All fields completed
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              'Congratulations! You have completed filling the form. Well done!',
        });
      });
      _scrollToBottom();
      return;
    }

    final currentField = _mockFields[_currentFieldIndex];
    final action = currentField['action'] as Map<String, dynamic>;

    // Update the action text with what user typed
    action['text'] = userMessage.toUpperCase();

    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': currentField['response'],
      });
    });

    _scrollToBottom();

    // Navigate to whiteboard if action is DRAW_GUIDE
    if (action['type'] == 'DRAW_GUIDE') {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _navigateToWhiteboard(
          textToWrite: action['text'],
          bbox: List<int>.from(action['bbox']),
        );
      });
    }
  }

  /// Navigate to WhiteboardScreen
  void _navigateToWhiteboard({
    required String textToWrite,
    required List<int> bbox,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhiteboardScreen(
          textToWrite: textToWrite,
          boundingBox: bbox,
        ),
      ),
    );

    // After returning from whiteboard, move to next field
    if (!mounted) return;
    setState(() {
      _currentFieldIndex++;
    });

    // Ask next question if there are more fields
    if (_currentFieldIndex < _mockFields.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': _mockFields[_currentFieldIndex]['question'],
          });
        });
        _scrollToBottom();
      });
    } else {
      // All fields done
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content':
                'Congratulations! You have completed filling all the fields. Well done!',
          });
        });
        _scrollToBottom();
      });
    }
  }

  /// Scroll chat to bottom
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Assistant'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Chat messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                return _ChatBubble(
                  message: message['content'] ?? '',
                  isUser: isUser,
                );
              },
            ),
          ),
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type your answer...',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  IconButton.filled(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat bubble widget for displaying messages
class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;

  const _ChatBubble({
    required this.message,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isUser
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

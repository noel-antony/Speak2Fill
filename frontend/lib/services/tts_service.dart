import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

class TtsService {
  static final TtsService _instance = TtsService._internal();
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;

  TtsService._internal();

  factory TtsService() {
    return _instance;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
    } catch (e) {
      print('TTS initialization error: $e');
    }
  }

  /// Request TTS from backend and play the returned audio bytes.
  Future<void> speak(
    String text, {
    required String backendUrl,
    String language = "ml",
    String? sessionId,
    String voice = "default",
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      final url = Uri.parse('$backendUrl/tts');
      final resp = await http.post(
        url,
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode({
          'text': text,
          'language': language,
          if (sessionId != null) 'session_id': sessionId,
          'voice': voice,
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception('TTS request failed: ${resp.statusCode}');
      }

      // Play audio bytes
      if (kIsWeb) {
        // On web, use data URL for audio
        final base64Audio = base64Encode(resp.bodyBytes);
        final dataUrl = 'data:audio/mpeg;base64,$base64Audio';
        await _player.play(UrlSource(dataUrl));
      } else {
        await _player.play(BytesSource(resp.bodyBytes));
      }
    } catch (e) {
      print('TTS speak error: $e');
    }
  }

  /// Stop speaking
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      print('TTS stop error: $e');
    }
  }

  /// Pause speaking
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      print('TTS pause error: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _player.stop();
    } catch (e) {
      print('TTS dispose error: $e');
    }
  }
}

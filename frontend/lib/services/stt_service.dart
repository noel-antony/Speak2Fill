import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Directory, File; // Only used on mobile/desktop
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:record/record.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  late final AudioRecorder _record;
  bool _isInitialized = false;
  String? _pendingBackendUrl;
  String _pendingLanguage = "ml";
  String? _pendingSessionId;

  SttService._internal();

  factory SttService() {
    return _instance;
  }

  /// Initialize speech to text
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _record = AudioRecorder();
      final hasPermission = await _record.hasPermission();
      _isInitialized = hasPermission ?? false;
      return _isInitialized;
    } catch (e) {
      print('STT initialization error: $e');
      return false;
    }
  }

  /// Start recording until stopped. Call [stopAndTranscribe] to finish.
  Future<bool> startRecording({
    required String backendUrl,
    String language = "ml",
    String? sessionId,
  }) async {
    try {
      if (!_isInitialized) {
        final initialized = await initialize();
        if (!initialized) {
          print('STT not available');
          return false;
        }
      }

      final tmpPath = kIsWeb
          ? 'dummy'
          : '${Directory.systemTemp.path}/s2f_rec_${DateTime.now().millisecondsSinceEpoch}.wav';

      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _record.start(config, path: tmpPath);
      _pendingBackendUrl = backendUrl;
      _pendingLanguage = language;
      _pendingSessionId = sessionId;
      return true;
    } catch (e) {
      print('STT startRecording error: $e');
      return false;
    }
  }

  /// Stop recording and send to backend /stt, returning the transcript.
  Future<String?> stopAndTranscribe() async {
    try {
      final backendUrl = _pendingBackendUrl;
      if (backendUrl == null) {
        print('STT stop called without an active recording backend URL');
        return null;
      }

      final path = await _record.stop();
      if (path == null) {
        print('STT recording returned null path');
        return null;
      }

      final bytes = await _readBytes(path);
      if (bytes == null || bytes.isEmpty) {
        print('STT could not read recorded audio');
        return null;
      }

      final url = Uri.parse('$backendUrl/stt');
      final request = http.MultipartRequest('POST', url)
        ..fields['language'] = _pendingLanguage
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            bytes,
            filename: 'audio.wav',
            contentType: MediaType('audio', 'wav'),
          ),
        );

      if (_pendingSessionId != null) {
        request.fields['session_id'] = _pendingSessionId!;
      }

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200) {
        print('STT backend error: ${resp.statusCode} ${resp.body}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final transcript = data['transcript'] as String?;
      return (transcript == null || transcript.isEmpty) ? null : transcript;
    } catch (e) {
      print('STT stopAndTranscribe error: $e');
      return null;
    } finally {
      _pendingBackendUrl = null;
      _pendingSessionId = null;
    }
  }

  /// Stop listening
  Future<void> stop() async {
    try {
      if (await _record.isRecording()) {
        await _record.stop();
      }
    } catch (e) {
      print('STT stop error: $e');
    }
  }

  /// Check if currently recording
  Future<bool> get isListening async => await _record.isRecording();

  /// Check if available
  bool get isAvailable => _isInitialized;

  /// Dispose resources
  Future<void> dispose() async {
    try {
      if (await _record.isRecording()) {
        await _record.stop();
      }
    } catch (e) {
      print('STT dispose error: $e');
    }
  }

  /// Platform-safe helper to read recorded bytes (supports web blob URLs).
  Future<Uint8List?> _readBytes(String path) async {
    if (kIsWeb) {
      try {
        final uri = Uri.parse(path);
        final resp = await http.get(uri);
        if (resp.statusCode != 200) {
          print('STT fetch blob failed: ${resp.statusCode}');
          return null;
        }
        return resp.bodyBytes;
      } catch (e) {
        print('STT blob read error: $e');
        return null;
      }
    }

    try {
      return await File(path).readAsBytes();
    } catch (e) {
      print('STT file read error: $e');
      return null;
    }
  }
}

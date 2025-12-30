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

  /// Record audio once and send to backend /stt, return transcript.
  /// [language] defaults to "ml".
  /// [duration] is the max recording duration in seconds.
  Future<String?> listenOnce({
    required String backendUrl,
    String language = "ml",
    int duration = 5,
  }) async {
    try {
      if (!_isInitialized) {
        bool initialized = await initialize();
        if (!initialized) {
          print('STT not available');
          return null;
        }
      }

      // Start recording; on web we let the plugin pick the storage and fetch via blob URL
      final tmpPath = kIsWeb
          ? 'dummy'  // Web ignores path and uses blob
          : '${Directory.systemTemp.path}/s2f_rec_${DateTime.now().millisecondsSinceEpoch}.wav';

      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 44100,
      );
      
      await _record.start(config, path: tmpPath);

      await Future.delayed(Duration(seconds: duration));

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

      // Send to backend /stt
      final url = Uri.parse('$backendUrl/stt');
      final request = http.MultipartRequest('POST', url)
        ..fields['language'] = language
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            bytes,
            filename: 'audio.wav',
            contentType: MediaType('audio', 'wav'),
          ),
        );

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
      print('STT listen error: $e');
      return null;
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

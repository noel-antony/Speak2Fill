import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../main.dart';
import 'form_filling_screen.dart';

const String backendBaseUrl = 'https://speak2fill.onrender.com';

/// UploadScreen - Entry point of the app
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 1),
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_fix_high,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Speak2Fill',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The easiest way to fill complex forms.\nJust upload and speak.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(flex: 2),
                  _buildActionButton(
                    context,
                    icon: Icons.upload_file,
                    label: 'Upload Form Image',
                    subtitle: 'Select from gallery',
                    onPressed: () => _pickImage(context, ImageSource.gallery),
                    isPrimary: true,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    context,
                    icon: Icons.camera_alt_outlined,
                    label: 'Take a Photo',
                    subtitle: 'Use camera to scan',
                    onPressed: () => _pickImage(context, ImageSource.camera),
                    isPrimary: false,
                  ),
                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
          
          // Theme Toggle Button
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IconButton(
                  onPressed: () {
                    Speak2FillApp.of(context)?.toggleTheme();
                  },
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark 
                        ? Icons.light_mode 
                        : Icons.dark_mode,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary 
              ? theme.colorScheme.primary 
              : theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary 
              ? null 
              : Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200, 
                  width: 2
                ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPrimary 
                    ? Colors.white.withOpacity(0.2) 
                    : theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isPrimary 
                    ? Colors.white 
                    : theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isPrimary ? Colors.white : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isPrimary 
                          ? Colors.white.withOpacity(0.8) 
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isPrimary 
                  ? Colors.white.withOpacity(0.5) 
                  : theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: source, imageQuality: 100);
      if (image != null && context.mounted) {
        // Send to /analyze-form (multipart/form-data, field name 'file')
        final uri = Uri.parse('$backendBaseUrl/analyze-form');
        final request = http.MultipartRequest('POST', uri);

        if (kIsWeb) {
          // On web, use bytes since dart:io is not available
          final bytes = await image.readAsBytes();
          final filename = image.name.isNotEmpty ? image.name : 'upload.jpg';

          // Infer mime type from filename extension (basic)
          String lower = filename.toLowerCase();
          String mimeMain = 'jpeg';
          if (lower.endsWith('.png')) mimeMain = 'png';
          else if (lower.endsWith('.webp')) mimeMain = 'webp';

          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: MediaType('image', mimeMain),
            ),
          );
        } else {
          request.files.add(await http.MultipartFile.fromPath('file', image.path));
        }

        debugPrint('Uploading image to $uri');
        final streamed = await request.send();
        final resp = await http.Response.fromStream(streamed);

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final sessionId = data['session_id'] as String?;
          final imageWidth = (data['image_width'] as num?)?.toInt();
          final imageHeight = (data['image_height'] as num?)?.toInt();

          if (sessionId != null && imageWidth != null && imageHeight != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FormFillingScreen(
                  sessionId: sessionId,
                  backendUrl: backendBaseUrl,
                  imageWidth: imageWidth,
                  imageHeight: imageHeight,
                ),
              ),
            );
          } else {
            debugPrint('Invalid analyze-form response: $data');
            _showError(context, 'Invalid analyze response');
          }
        } else {
          debugPrint('Analyze-form failed: ${resp.statusCode} ${resp.body}');
          _showError(context, 'Upload failed (${resp.statusCode})');
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (context.mounted) {
        _showError(context, 'Image selection failed');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

import 'package:flutter/material.dart';
import 'chat_screen.dart';

/// UploadScreen - Entry point of the app
/// User uploads/captures a form image here.
/// For now, we mock the upload and navigate directly to ChatScreen.
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speak2Fill'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon/logo placeholder
            Icon(
              Icons.document_scanner_outlined,
              size: 120,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            const Text(
              'Upload your form',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Take a photo or upload an image of the form you need help filling',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Upload button - mocked for now
            FilledButton.icon(
              onPressed: () => _onUploadPressed(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Form'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Camera button - mocked for now
            OutlinedButton.icon(
              onPressed: () => _onUploadPressed(context),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take Photo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mock upload: directly navigate to ChatScreen
  void _onUploadPressed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChatScreen()),
    );
  }
}

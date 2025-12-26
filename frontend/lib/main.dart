/// Speak2Fill - Voice-First AI Assistant for Filling Paper Forms
///
/// This app helps low-literacy users fill physical paper forms by guiding them
/// step-by-step using voice and visual writing guidance (whiteboard).
///
/// Flow: UploadScreen → ChatScreen ↔ WhiteboardScreen
library;

import 'package:flutter/material.dart';
import 'screens/upload_screen.dart';

void main() {
  runApp(const Speak2FillApp());
}

class Speak2FillApp extends StatelessWidget {
  const Speak2FillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak2Fill',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const UploadScreen(),
    );
  }
}

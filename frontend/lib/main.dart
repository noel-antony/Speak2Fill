// We are building the Flutter frontend for Speak2Fill.

// Context:
// - The backend returns OCR results with real bounding boxes from PaddleOCR.
// - Bounding boxes are relative to the original scanned form image size.
// - The frontend must render a whiteboard overlay that aligns exactly with the form layout.

// Current OCR format example:
// {
//   "text": "Name(s) of A/c Holder(s)",
//   "bbox": [604, 279, 866, 307],
//   "image_width": 1200,
//   "image_height": 800
// }

// Goal:
// Improve the WhiteboardScreen so it correctly maps OCR bounding boxes
// to the Flutter canvas and visually guides the user where to write.

// Requirements:

// 1) Coordinate Normalization
// - Treat OCR bbox as image-space coordinates
// - Accept imageWidth and imageHeight as inputs
// - Scale bbox to current canvas size using:
//   scaleX = canvasWidth / imageWidth
//   scaleY = canvasHeight / imageHeight
// - Draw the rectangle at the scaled position

// 2) Whiteboard Rendering
// - Use CustomPainter
// - Draw:
//   - A dimmed background overlay
//   - A highlighted rectangle for the active field
//   - Dotted guide text inside the rectangle
// - Rectangle should be visually clear and high contrast

// 3) Field Context
// - Display field label text above the rectangle (e.g., "Name")
// - Display helper text below:
//   "Write exactly as shown"

// 4) Inputs to WhiteboardScreen
// WhiteboardScreen should accept:
// - textToWrite (String)
// - boundingBox (List<double> [x1, y1, x2, y2])
// - imageWidth (double)
// - imageHeight (double)
// - fieldLabel (String)

// 5) Constraints
// - Hackathon project
// - Keep code simple and readable
// - No backend calls
// - No state management libraries
// - No animations
// - No image picker yet (background image optional)

// 6) Code Structure
// - Update WhiteboardScreen to support scaled OCR coordinates
// - Keep logic well-commented
// - Assume data is passed correctly from ChatScreen (mock for now)

// Outcome:
// The whiteboard must visually align with real form fields
// and clearly show the user where and what to write.

// Now update the Flutter WhiteboardScreen implementation accordingly.

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

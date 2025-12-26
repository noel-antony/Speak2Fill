# Speak2Fill Frontend

Flutter mobile app for guiding users to fill paper forms step-by-step using voice and visual guidance.

## Prerequisites

- Flutter SDK 3.10.4 or higher
- Dart SDK (comes with Flutter)
- Android Studio / Xcode / Chrome (depending on target platform)

## Getting Started

### 1. Install Dependencies

```bash
cd frontend
flutter pub get
```

### 2. Run the App

#### On Chrome (Web)
```bash
flutter run -d chrome
```

#### On Android Emulator
```bash
flutter run -d android
```

#### On iOS Simulator (macOS only)
```bash
flutter run -d ios
```

#### On Windows
```bash
flutter run -d windows
```

### 3. List Available Devices
```bash
flutter devices
```

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── screens/
│   ├── upload_screen.dart       # Form upload/capture
│   ├── chat_screen.dart         # AI assistant chat
│   └── whiteboard_screen.dart   # Visual writing guidance
├── services/                     # API and business logic (future)
├── widgets/                      # Reusable components (future)
├── models/                       # Data models (future)
└── constants/                    # App constants (future)
```

## Features

- Upload or capture form images
- Interactive chat interface with AI assistant
- Visual guidance showing where and what to write on forms
- Mock data for testing the complete flow

## Development

### Hot Reload
While the app is running, save your changes or press `r` in the terminal to hot reload.

### Hot Restart
Press `R` in the terminal for a full restart.

### Build for Release

#### Android APK
```bash
flutter build apk --release
```

#### iOS
```bash
flutter build ios --release
```

#### Web
```bash
flutter build web --release
```

## Notes

- Currently using mock data for demonstration
- Backend integration will be added in next phase
- Voice features will be implemented after core flow is complete

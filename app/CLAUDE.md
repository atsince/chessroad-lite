# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ChessRoad (棋路) is a Chinese Chess (Xiangqi) application built with Flutter. It features:
- Chinese Chess gameplay with AI engine (Pikafish)
- Board recognition via floating overlay window
- Cloud engine integration
- Real-time screen capture and analysis on Android

## Development Commands

### Build & Run
```bash
flutter pub get                    # Install dependencies
flutter run                        # Run on connected device
flutter run -d android             # Run on Android
flutter run -d ios                 # Run on iOS
flutter build apk                  # Build Android APK
flutter build appbundle            # Build Android App Bundle
flutter build ios                  # Build iOS
```

### Testing & Linting
```bash
flutter test                       # Run tests
flutter analyze                    # Analyze code
```

## Architecture

### Core Directories
- **lib/cchess/** - Chinese chess game logic (Position, FEN parsing, move validation, rules)
- **lib/engine/** - AI engine integration (Pikafish native engine, cloud engine, hybrid engine)
- **lib/game/** - Game state management (BoardState, PageState using Provider)
- **lib/overlay/** - Floating overlay window implementation for board recognition
- **lib/services/** - Platform services (audio, overlay communication, board recognition)
- **lib/routes/** - App navigation and screens
- **lib/ui/** - Reusable UI components

### Key Components

**Position & Game Logic** (lib/cchess/)
- `Position`: Core chess position representation with move validation
- `Fen`: FEN notation parsing/generation for position serialization
- `ChessRules`: Move validation and game rules enforcement
- `MoveRecorder`: Move history tracking

**Engine System** (lib/engine/)
- `HybridEngine`: Facade combining cloud and native engines with fallback
- `PikafishEngine`: Native Pikafish chess engine integration
- `CloudEngine`: Remote engine API calls
- Engine uses callback pattern for async move analysis

**State Management**
- Uses Provider for state management
- `BoardState`: Chess position, move selection, piece animation
- `PageState`: UI navigation and screen state
- `LocalData`: Persistent app settings and configuration

**Overlay System** (lib/overlay/, lib/services/)
- `OverlayService`: Main app isolate managing overlay lifecycle
- `FloatingOverlay`: Overlay UI with board capture and analysis
- Uses `FlutterOverlayWindow` and `MediaProjectionScreenshot` for Android screen capture
- Isolate communication via `IsolateNameServer` and `SendPort`/`ReceivePort`
- Board recognition sends screenshots to API endpoint for FEN detection

**Entry Points**
- `main()`: Standard app entry
- `overlayMain()`: Floating overlay entry point (Android system overlay)
- `overlayMain2()`: Simple floating widget entry

### Platform-Specific

**Android**
- Application ID: `cn.mdevs.apps.chessroad`
- Min SDK: 23, Target SDK: 34
- Requires permissions: screen capture, overlay window

**Assets**
- Pikafish NNUE file: `assets/pikafish.nnue` (neural network evaluation)
- Audio files in `assets/audios/`
- Custom fonts: ZhongSan, QiTi, XiaoLi

## Development Notes

- Pikafish engine integration uses FFI for native communication
- Local package dependency: `media_projection_screenshot-master/`
- Board recognition API endpoint configured in `OverlayService` (line 58)
- App uses portrait orientation only
- Audio managed through `Audios` singleton with lifecycle awareness
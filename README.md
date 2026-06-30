# Irisesce iOS ArtCNN Player

Phase 1 validates this path:

```text
AVPlayer -> AVPlayerItemVideoOutput -> Core ML ArtCNN -> FlutterTexture -> Flutter UI
```

The first screen is a Flutter `Stack` with a `Texture`, basic controls, an ArtCNN switch, diagnostics, and a test danmaku overlay.

## Local Setup

This repository contains the phase-1 source scaffold. If the Flutter iOS project files have not been generated yet, run:

```bash
bash scripts/bootstrap_flutter_ios.sh
flutter pub get
dart run pigeon --input pigeons/player_api.dart
```

Then run on iOS:

```bash
flutter run -d ios
```

## ArtCNN Model

The ONNX model can live at the repository root:

```text
ArtCNN_C4F16_DN.onnx
```

CI converts it into a fixed 640x360 -> 1280x720 grayscale Core ML model. You can also place a prepared model inside the local iOS plugin resources:

```text
packages/artcnn_player_ios/ios/Resources/ArtCNN_C4F16.mlmodel
```

or commit the compiled bundle:

```text
packages/artcnn_player_ios/ios/Resources/ArtCNN_C4F16.mlmodelc/
```

The plugin pod includes `ios/Resources/**/*` as resources. The Swift runtime looks for `ArtCNN_C4F16.mlmodelc` in the app and plugin bundles. When a `.mlmodel` is included as an iOS resource, Xcode compiles it into that bundle form during build.

Prepare the model locally with:

```bash
python3 -m pip install --index-url https://pypi.org/simple coremltools onnx numpy
python3 scripts/prepare_artcnn_model.py --require
```

## Generated Files

Pigeon generates:

```text
packages/artcnn_player_ios/lib/src/artcnn_player_api.dart
packages/artcnn_player_ios/ios/Classes/ArtCnnPlayerApi.g.swift
```

Do not send per-frame data through Dart. Dart polls playback state at a coarse interval while video frames stay inside the native texture path.

## CI

`.github/workflows/ios-artcnn-phase1.yml` runs:

- Flutter iOS bootstrap
- `flutter pub get`
- Pigeon generation
- optional ONNX -> Core ML model preparation
- `flutter analyze`
- Core ML model validation when a model exists
- unsigned iOS simulator build

Manual workflow dispatch exposes switches:

- `include_artcnn_model`: convert and bundle the ONNX ArtCNN model
- `require_artcnn_model`: fail when model preparation fails
- `artcnn_enabled_by_default`: set the app Info.plist default flag for the sample player

## Current Limits

- iOS only
- AVPlayer-supported SDR MP4 streams first
- No FFmpeg, libmpv, Rust, Zig, or custom Metal shader
- One Core ML inference in flight at a time
- Slow inference drops video frames without blocking audio playback

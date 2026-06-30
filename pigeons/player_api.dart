import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'packages/artcnn_player_ios/lib/src/artcnn_player_api.dart',
    dartOptions: DartOptions(),
    swiftOut: 'packages/artcnn_player_ios/ios/Classes/ArtCnnPlayerApi.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
class CreatedPlayer {
  CreatedPlayer({
    required this.playerId,
    required this.textureId,
  });

  int playerId;
  int textureId;
}

class PlayerState {
  PlayerState({
    required this.isPlaying,
    required this.isBuffering,
    required this.positionMs,
    required this.durationMs,
    required this.artCnnEnabled,
    required this.processedFrames,
    required this.skippedFrames,
    this.width,
    this.height,
    this.frameRate,
    this.lastInferenceMs,
    this.sourcePath,
    this.diagnostics,
    this.debugLog,
    this.error,
  });

  bool isPlaying;
  bool isBuffering;
  int positionMs;
  int durationMs;
  bool artCnnEnabled;
  int processedFrames;
  int skippedFrames;
  int? width;
  int? height;
  double? frameRate;
  double? lastInferenceMs;
  String? sourcePath;
  String? diagnostics;
  String? debugLog;
  String? error;
}

@HostApi()
abstract class PlayerHostApi {
  CreatedPlayer createPlayer();
  void load(int playerId, String uri);
  String loadFirstDocumentVideo(int playerId);
  void play(int playerId);
  void pause(int playerId);
  void seek(int playerId, int positionMs);
  void setArtCNNEnabled(int playerId, bool enabled);
  PlayerState getState(int playerId);
  void dispose(int playerId);
}

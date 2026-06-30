import 'dart:async';

import 'package:flutter/material.dart';
import 'package:artcnn_player_ios/artcnn_player_ios.dart';

class ArtCnnPlayerPage extends StatefulWidget {
  const ArtCnnPlayerPage({super.key});

  @override
  State<ArtCnnPlayerPage> createState() => _ArtCnnPlayerPageState();
}

class _ArtCnnPlayerPageState extends State<ArtCnnPlayerPage> {
  static const _artCnnEnabledByDefault = bool.fromEnvironment(
    'ART_CNN_ENABLED_BY_DEFAULT',
  );

  final PlayerHostApi _api = PlayerHostApi();
  int? _playerId;
  int? _textureId;
  PlayerState _state = PlayerState(
    isPlaying: false,
    isBuffering: false,
    positionMs: 0,
    durationMs: 0,
    artCnnEnabled: _artCnnEnabledByDefault,
    processedFrames: 0,
    skippedFrames: 0,
  );
  String? _error;
  String? _loadedVideoName;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    unawaited(_create());
  }

  @override
  void dispose() {
    _poller?.cancel();
    final playerId = _playerId;
    if (playerId != null) {
      unawaited(_api.dispose(playerId));
    }
    super.dispose();
  }

  Future<void> _create() async {
    try {
      final created = await _api.createPlayer();
      setState(() {
        _playerId = created.playerId;
        _textureId = created.textureId;
      });
      if (_artCnnEnabledByDefault) {
        await _api.setArtCNNEnabled(created.playerId, true);
      }
      await _loadDocumentVideo(created.playerId, true);
      _poller = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(_refreshState());
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _loadDocumentVideo([int? existingPlayerId, bool autoplay = false]) async {
    final playerId = existingPlayerId ?? _playerId;
    if (playerId == null) {
      return;
    }
    try {
      final videoName = await _api.loadFirstDocumentVideo(playerId);
      if (autoplay) {
        await _api.play(playerId);
      }
      if (mounted) {
        setState(() {
          _loadedVideoName = videoName;
          _error = null;
        });
      }
      await _refreshState();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _refreshState() async {
    final playerId = _playerId;
    if (playerId == null) {
      return;
    }
    try {
      final state = await _api.getState(playerId);
      if (mounted) {
        setState(() {
          _state = state;
          _error = state.error;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _togglePlayback() async {
    final playerId = _playerId;
    if (playerId == null) {
      return;
    }
    if (_state.isPlaying) {
      await _api.pause(playerId);
    } else {
      await _api.play(playerId);
    }
    await _refreshState();
  }

  Future<void> _seek(double value) async {
    final playerId = _playerId;
    if (playerId == null) {
      return;
    }
    await _api.seek(playerId, value.round());
    await _refreshState();
  }

  Future<void> _setArtCnn(bool enabled) async {
    final playerId = _playerId;
    if (playerId == null) {
      return;
    }
    await _api.setArtCNNEnabled(playerId, enabled);
    await _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    final textureId = _textureId;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (textureId == null)
            const Center(child: CircularProgressIndicator())
          else
            Texture(textureId: textureId),
          const _TestDanmakuLayer(),
          if (_state.isBuffering)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          _PlayerControls(
            state: _state,
            loadedVideoName: _loadedVideoName,
            onLoad: () => unawaited(_loadDocumentVideo()),
            onPlayPause: _togglePlayback,
            onSeek: _seek,
            onArtCnnChanged: _setArtCnn,
          ),
        ],
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.state,
    required this.loadedVideoName,
    required this.onLoad,
    required this.onPlayPause,
    required this.onSeek,
    required this.onArtCnnChanged,
  });

  final PlayerState state;
  final String? loadedVideoName;
  final VoidCallback onLoad;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final ValueChanged<bool> onArtCnnChanged;

  @override
  Widget build(BuildContext context) {
    final duration = state.durationMs <= 0 ? 1.0 : state.durationMs.toDouble();
    final position = state.positionMs.clamp(0, state.durationMs).toDouble();
    final hasAiStats = state.processedFrames > 0 || state.skippedFrames > 0;
    final aiDetail = !state.artCnnEnabled
        ? null
        : hasAiStats
            ? 'done ${state.processedFrames} skip ${state.skippedFrames}'
            : 'waiting frames';
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: position,
                max: duration,
                onChanged: onSeek,
              ),
              if (loadedVideoName != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      loadedVideoName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: state.isPlaying ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                    color: Colors.white,
                  ),
                  IconButton(
                    tooltip: 'Load first Documents video',
                    onPressed: onLoad,
                    icon: const Icon(Icons.video_file),
                    color: Colors.white,
                  ),
                  const Spacer(),
                  Text(
                    '${_formatMs(state.positionMs)} / ${_formatMs(state.durationMs)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    state.artCnnEnabled ? 'ArtCNN on' : 'ArtCNN off',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (aiDetail != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      aiDetail,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Switch(
                    value: state.artCnnEnabled,
                    onChanged: onArtCnnChanged,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMs(int value) {
    final duration = Duration(milliseconds: value);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _TestDanmakuLayer extends StatelessWidget {
  const _TestDanmakuLayer();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 72,
              left: 24,
              child: Text(
                'ArtCNN texture overlay test',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  shadows: [Shadow(blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

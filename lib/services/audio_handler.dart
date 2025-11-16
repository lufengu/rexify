import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_player_service.dart';

/// Handler que conecta audio_service con reproductor
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayerService _player = AudioPlayerService();

  MyAudioHandler() {
    // Escucha del estado de reproducción (playerStateStream) para actualizar controles y estado playing
    try {
      _player.playerStateStream.listen((ps) {
        try {
          final playing = ps.playing;
          final processingState = _mapProcessingState(ps.processingState);
          final prev = playbackState.valueOrNull;
          final newState = (prev ?? PlaybackState()).copyWith(
            controls: [
              MediaControl.skipToPrevious,
              if (playing) MediaControl.pause else MediaControl.play,
              MediaControl.stop,
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            androidCompactActionIndices: const [0, 1, 3],
            playing: playing,
            processingState: processingState,
            updatePosition: Duration.zero,
          );
          playbackState.add(newState);
        } catch (_) {}
      });
    } catch (_) {}

    // Escucha de posición para refrescar updatePosition sin alterar otros campos
    try {
      _player.positionStream.listen((position) {
        final prev = playbackState.valueOrNull;
        if (prev == null) return;
        playbackState.add(prev.copyWith(updatePosition: position));
      });
    } catch (_) {}
  }

  // Permite que la UI actualice el MediaItem directamente (e.g., cuando reproduce una canción local)
  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    try {
      this.mediaItem.add(mediaItem);
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    try { await _player.play(); } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try { await _player.pause(); } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try { await _player.seek(position); } catch (_) {}
  }

  @override
  Future<void> skipToNext() async {
  try { await _player.playNext(); } catch (_) {}
  }

  @override
  Future<void> skipToPrevious() async {
  try { await _player.playPrevious(); } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    await super.stop();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    try {
      LoopMode mode;
      switch (repeatMode) {
        case AudioServiceRepeatMode.one: mode = LoopMode.one; break;
        case AudioServiceRepeatMode.all: mode = LoopMode.all; break;
        case AudioServiceRepeatMode.none:
        default: mode = LoopMode.off; break;
      }
      await _player.setLoopMode(mode);
    } catch (_) {}
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    try {
      final shouldEnable = shuffleMode != AudioServiceShuffleMode.none;
      if (shouldEnable != _player.isShuffleEnabled) {
        await _player.toggleShuffle();
      }
    } catch (_) {}
  }

  // Helper: mapear estados de just_audio a AudioProcessingState
  AudioProcessingState _mapProcessingState(ProcessingState ps) {
    switch (ps) {
      case ProcessingState.idle: return AudioProcessingState.idle;
      case ProcessingState.loading: return AudioProcessingState.loading;
      case ProcessingState.buffering: return AudioProcessingState.buffering;
      case ProcessingState.ready: return AudioProcessingState.ready;
      case ProcessingState.completed: return AudioProcessingState.completed;
    }
  }
}

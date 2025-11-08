import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'audio_player_service.dart';

/// Handler que conecta audio_service con reproductor
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayerService();

  MyAudioHandler() {
    // Listener para actualizar el estado de reproducción
    _player.playerStateStream.listen((playerState) {
      final playing = playerState.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[playerState.processingState]!,
          playing: playing,
        ),
      );
    });

    // Listener para actualizar la posición
    _player.positionStream.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });
  }

  /// Actualizar información de la canción actual en la notificación
  void setMediaItem(SongModel song) {
    mediaItem.add(
      MediaItem(
        id: song.id.toString(),
        album: song.album ?? 'Desconocido',
        title: song.title,
        artist: song.artist ?? 'Artista Desconocido',
        duration: Duration(milliseconds: song.duration ?? 0),
        artUri: song.uri != null ? Uri.parse(song.uri!) : null,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (!_player.isPlaying) {
      await _player.togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    if (_player.isPlaying) {
      await _player.togglePlayPause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _player.playNext();
    final currentSong = _player.currentSong;
    if (currentSong != null) {
      setMediaItem(currentSong);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.playPrevious();
    final currentSong = _player.currentSong;
    if (currentSong != null) {
      setMediaItem(currentSong);
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      default:
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode == AudioServiceShuffleMode.all;
    if (enable != _player.isShuffleEnabled) {
      await _player.toggleShuffle();
    }
  }
}

import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'dart:math';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  List<SongModel> _playlist = [];
  List<SongModel> _originalPlaylist = [];
  int _currentIndex = 0;
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  // Getters
  AudioPlayer get audioPlayer => _audioPlayer;
  OnAudioQuery get audioQuery => _audioQuery;
  List<SongModel> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  SongModel? get currentSong =>
      _playlist.isEmpty ? null : _playlist[_currentIndex];
  bool get isShuffleEnabled => _isShuffleEnabled;
  LoopMode get loopMode => _loopMode;

  Stream<Duration> get positionStream => _audioPlayer.positionStream;
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream;
  Stream<ProcessingState> get processingStateStream =>
      _audioPlayer.processingStateStream;
  Stream<LoopMode> get loopModeStream => _audioPlayer.loopModeStream;

  bool get isPlaying => _audioPlayer.playing;
  Duration get position => _audioPlayer.position;
  Duration? get duration => _audioPlayer.duration;

  // Initialize service
  Future<void> init() async {
    // Setup audio session for background playback
    _audioPlayer.setLoopMode(LoopMode.off);

    // Listen to player completion to play next song
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playNext();
      }
    });
  }

  // Load all songs from device
  Future<List<SongModel>> loadSongs() async {
    try {
      _playlist = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      _originalPlaylist = List.from(_playlist);
      return _playlist;
    } catch (e) {
      print('Error loading songs: $e');
      return [];
    }
  }

  // Play a song
  Future<void> playSong(SongModel song, int index) async {
    try {
      _currentIndex = index;
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.uri!)));
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing song: $e');
    }
  }

  // Play/Pause toggle
  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  // Play next song
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;

    _currentIndex = (_currentIndex + 1) % _playlist.length;
    await playSong(_playlist[_currentIndex], _currentIndex);
  }

  // Play previous song
  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;

    if (_audioPlayer.position.inSeconds > 3) {
      // If more than 3 seconds, restart current song
      await _audioPlayer.seek(Duration.zero);
    } else {
      // Otherwise go to previous song
      _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
      await playSong(_playlist[_currentIndex], _currentIndex);
    }
  }

  // Seek to position
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  // Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  // Stop playback
  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  // Toggle shuffle mode
  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;

    if (_isShuffleEnabled) {
      // Save current song
      final currentSong = _playlist[_currentIndex];

      // Shuffle playlist
      final random = Random();
      _playlist.shuffle(random);

      // Move current song to the beginning
      final newIndex = _playlist.indexOf(currentSong);
      if (newIndex != -1 && newIndex != 0) {
        final temp = _playlist[0];
        _playlist[0] = currentSong;
        _playlist[newIndex] = temp;
      }
      _currentIndex = 0;
    } else {
      // Restore original order
      final currentSong = _playlist[_currentIndex];
      _playlist = List.from(_originalPlaylist);
      _currentIndex = _playlist.indexOf(currentSong);
      if (_currentIndex == -1) _currentIndex = 0;
    }
  }

  // Toggle loop mode (off -> all -> one -> off)
  Future<void> toggleLoopMode() async {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        await _audioPlayer.setLoopMode(LoopMode.all);
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        await _audioPlayer.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        await _audioPlayer.setLoopMode(LoopMode.off);
        break;
    }
  }

  // Set loop mode directly
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _audioPlayer.setLoopMode(mode);
  }

  // Get loop mode icon
  String getLoopModeText() {
    switch (_loopMode) {
      case LoopMode.off:
        return 'Sin repetir';
      case LoopMode.all:
        return 'Repetir todo';
      case LoopMode.one:
        return 'Repetir una';
    }
  }

  // Dispose
  void dispose() {
    _audioPlayer.dispose();
  }
}

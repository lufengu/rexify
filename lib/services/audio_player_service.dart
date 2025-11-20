import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async'; // <-- añadido
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';

class AudioPlayerService {
  // Singleton para evitar múltiples reproductores
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    // Lanzamos la inicialización asincrónica y guardamos el Future para poder esperarlo desde fuera.
    _initFuture = _init();
  }

  final AudioPlayer _player = AudioPlayer();
  final OnAudioQuery _audioQuery = OnAudioQuery();

  // Playlist de archivos (descargas locales sueltas)
  List<String> _filePlaylist = [];
  int _fileIndex = -1;
  String? _currentPath;

  // Playlist basada en SongModel (biblioteca de música del dispositivo)
  List<SongModel> _songPlaylist = [];
  List<SongModel> _originalSongPlaylist = [];
  int _songIndex = -1;

  // Estado de modos
  bool _isShuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  // Streams y getters que usa la UI
  bool get isPlaying => _player.playing;
  AudioPlayer get audioPlayer => _player;
  OnAudioQuery get audioQuery => _audioQuery;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  PlayerState get playerState => _player.playerState;
  bool get isShuffleEnabled => _isShuffleEnabled;
  LoopMode get loopMode => _loopMode;
  // Accesores de canción actual (SongModel) y archivo actual (path)
  SongModel? get currentSong => _songPlaylist.isEmpty || _songIndex < 0 ? null : _songPlaylist[_songIndex];
  int get currentSongIndex => _songIndex;
  String? get currentPath => _currentPath;
  int get currentFileIndex => _fileIndex;
  List<String> get filePlaylist => List.unmodifiable(_filePlaylist);

  /// Exponer playlist de SongModel pública (solo lectura)
  List<SongModel> get songPlaylist => List.unmodifiable(_songPlaylist);

  /// Fallback: construir lista de MediaItem desde la playlist interna (sin esperar IO)
  /// Útil cuando audioHandler.queue está vacío o no disponible.
  List<MediaItem> get queueSync {
    if (_songPlaylist.isNotEmpty) {
      return _songPlaylist.map((s) {
        return MediaItem(
          id: s.id.toString(),
          album: s.album ?? '',
          title: s.title,
          artist: s.artist,
          duration: s.duration != null ? Duration(milliseconds: s.duration!) : null,
          extras: {'path': s.data},
        );
      }).toList(growable: false);
    }
    if (_filePlaylist.isNotEmpty) {
      return _filePlaylist.map((p) {
        return MediaItem(
          id: p,
          album: '',
          title: p.split(Platform.pathSeparator).last,
          extras: {'path': p},
        );
      }).toList(growable: false);
    }
    return const <MediaItem>[];
  }

  Box? _stateBox; // Hive para persistencia de última pista y posición
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _initFuture; // Permite exponer init() público y evitar doble init.

  /// Método público para inicializar el servicio y poder hacer `await` en `main.dart`.
  /// Si ya se está inicializando o terminó, simplemente retorna el mismo Future.
  Future<void> init() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    // Registrar canal para recibir acciones nativas enviadas desde NotificationActionReceiver
    try {
      const MethodChannel _actionChannel = MethodChannel('rexify/media_actions');
      _actionChannel.setMethodCallHandler((call) async {
        if (call.method == 'onMediaAction') {
          try {
            final args = call.arguments as Map<dynamic, dynamic>?;
            final action = args?['action'] as String? ?? '';
            switch (action) {
              case 'togglePlayPause':
                await togglePlayPause();
                break;
              case 'playNext':
                await playNext();
                break;
              case 'playPrevious':
                await playPrevious();
                break;
              case 'pause':
                await pause();
                break;
              case 'play':
                await play();
                break;
              default:
                break;
            }
          } catch (_) {}
        }
      });
    } catch (_) {}
    // Abrir box Hive para estado persistente
    try { _stateBox = await Hive.openBox('player_state'); } catch (_) {}

    // Restaurar última pista si existe
    try {
      final lastPath = _stateBox?.get('last_path') as String?;
      final lastPosMs = _stateBox?.get('last_position_ms') as int?;
      if (lastPath != null && File(lastPath).existsSync()) {
        _currentPath = lastPath;
        _filePlaylist = [lastPath];
        _fileIndex = 0;
        try {
          await _player.setAudioSource(AudioSource.uri(Uri.file(lastPath)));
          if (lastPosMs != null && lastPosMs > 0) {
            await _player.seek(Duration(milliseconds: lastPosMs));
          }
          // MediaItem inicial (no autoplay)
          final media = MediaItem(
            id: lastPath,
            album: '',
            title: lastPath.split(Platform.pathSeparator).last,
            artUri: await _placeholderArtUri('resume'),
            extras: {'path': lastPath, 'resumed': true},
          );
          await audioHandler.updateMediaItem(media);
        } catch (_) {}
      }
    } catch (_) {}

    // Escuchar cambio de posición para persistir (throttle cada 5s) y actualizar notificación custom (cada ~2s)
    DateTime _lastNotif = DateTime.fromMillisecondsSinceEpoch(0);
    _player.positionStream.listen((pos) async {
      if (_currentPath == null) return;
      if (!_player.playing) return; // guardar sólo mientras reproduce
      final now = DateTime.now();
      // Persistencia
      if (now.difference(_lastPersist) >= const Duration(seconds: 5)) {
        _lastPersist = now;
        try {
          _stateBox?.put('last_path', _currentPath);
          _stateBox?.put('last_position_ms', pos.inMilliseconds);
        } catch (_) {}
      }
      // Notificación custom
      if (now.difference(_lastNotif) >= const Duration(seconds: 2)) {
        _lastNotif = now;
        try {
          final media = await audioHandler.mediaItem.firstWhere((_) => true, orElse: () => null);
          _sendCustomNotification(media, positionOverride: pos);
        } catch (_) {}
      }
    });

    // Procesamiento adicional
    _player.processingStateStream.listen((state) {
      // Auto-advance cuando una pista termina.
      try {
        if (state == ProcessingState.completed) {
          // Si hay una playlist de archivos, avanzar por ella (descargas/locales).
          if (_filePlaylist.isNotEmpty) {
            unawaited(playNextInFilePlaylist());
            return;
          }
          // Si hay una playlist de SongModel (biblioteca), usar playNext().
          if (_songPlaylist.isNotEmpty) {
            unawaited(playNext());
            return;
          }
          // Si no hay playlists, simplemente detener el player.
          try {
            _player.stop();
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  Future<void> setVolume(double v) => _player.setVolume(v);

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (_) {}
  }

  /// Reproduce un archivo local (descarga). Evita reiniciar si ya está reproduciéndose la misma ruta.
  /// Genera MediaItem con posible artwork (placeholder si no hay).
  Future<void> playFile(File file, {String? title, String? artist}) async {
    final path = file.path;
    // Si la misma pista está sonando, no la reiniciamos
    if (_currentPath != null && _currentPath == path) {
      if (_player.playing) return; // ya reproducida
      // si está pausada, simplemente reanudar
      if (_player.processingState == ProcessingState.ready || _player.processingState == ProcessingState.completed) {
        await _player.play();
        return;
      }
    }

    _currentPath = path;
    // Actualizar índice en playlist de archivos si existe
    final idx = _filePlaylist.indexOf(path);
    if (idx >= 0) {
      _fileIndex = idx;
    } else {
      _filePlaylist.add(path);
      _fileIndex = _filePlaylist.length - 1;
    }
    try {
      await _player.setFilePath(path);
      await _player.play();
      // Persistir inicio de nueva pista
      try {
        _stateBox?.put('last_path', path);
        _stateBox?.put('last_position_ms', 0);
      } catch (_) {}
      // Artwork placeholder (no metadata para archivos sueltos)
      Uri? art = await _placeholderArtUri(path);
      // Push MediaItem para notificación persistente
      try {
        final media = MediaItem(
          id: path,
          album: '',
          title: title ?? path.split(Platform.pathSeparator).last,
          artist: artist,
          duration: _player.duration,
          artUri: art,
          extras: {'path': path},
        );
  await audioHandler.updateMediaItem(media);
  _sendCustomNotification(media);

        // PUBLICAR COLA: asegurar que audioHandler.queue refleja la playlist de archivos
        try {
          final q = <MediaItem>[];
          for (final p in _filePlaylist) {
            q.add(MediaItem(
              id: p,
              album: '',
              title: p.split(Platform.pathSeparator).last,
              artUri: await _placeholderArtUri(p),
              extras: {'path': p},
            ));
          }
          await audioHandler.updateQueue(q);
        } catch (_) {}
      } catch (_) {}
    } catch (e) {
      rethrow;
    }
  }

  /// Establece una playlist de archivos y reproduce el índice inicial.
  Future<void> setFilePlaylistAndPlay(List<String> paths, int startIndex) async {
    if (paths.isEmpty) return;
    _filePlaylist = List.of(paths);
    _fileIndex = startIndex.clamp(0, _filePlaylist.length - 1);
    // publicar cola de archivos antes de reproducir
    try {
      final q = <MediaItem>[];
      for (final p in _filePlaylist) {
        q.add(MediaItem(id: p, album: '', title: p.split(Platform.pathSeparator).last, artUri: await _placeholderArtUri(p), extras: {'path': p}));
      }
      await audioHandler.updateQueue(q);
    } catch (_) {}
    await playFile(File(_filePlaylist[_fileIndex]));
  }

  Future<void> playNextInFilePlaylist() async {
    if (_filePlaylist.isEmpty) return;
    _fileIndex = (_fileIndex + 1) % _filePlaylist.length;
    await playFile(File(_filePlaylist[_fileIndex]));
  }

  Future<void> playPreviousInFilePlaylist() async {
    if (_filePlaylist.isEmpty) return;
    _fileIndex = (_fileIndex - 1 + _filePlaylist.length) % _filePlaylist.length;
    await playFile(File(_filePlaylist[_fileIndex]));
  }

  // -------- Canciones (SongModel) --------
  Future<List<SongModel>> loadSongs() async {
    try {
      _songPlaylist = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      _originalSongPlaylist = List.from(_songPlaylist);
      // PUBLICAR COLA en audioHandler para que la UI (NowPlaying/_showQueue) la vea
      try {
        final q = <MediaItem>[];
        for (final s in _songPlaylist) {
          q.add(MediaItem(
            id: s.id.toString(),
            album: s.album ?? '',
            title: s.title,
            artist: s.artist,
            duration: s.duration != null ? Duration(milliseconds: s.duration!) : null,
            artUri: await _placeholderArtUri('song_${s.id}'),
            extras: {'path': s.data},
          ));
        }
        await audioHandler.updateQueue(q);
      } catch (_) {}
      return _songPlaylist;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading songs: $e');
      return [];
    }
  }

  Future<void> playSong(SongModel song, int index) async {
    try {
      final current = currentSong;
      if (current != null && current.id == song.id) {
        if (_player.playing) return; // evitar reinicio
        await _player.play();
        return;
      }
      _songIndex = index;
      final uri = song.uri ?? song.data;
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
      await _player.play();
      // Persistir pista
      try {
        _stateBox?.put('last_path', song.data);
        _stateBox?.put('last_position_ms', 0);
      } catch (_) {}
      // Actualizar MediaItem para notificación
      try {
        Uint8List? artworkBytes;
        try { artworkBytes = await _audioQuery.queryArtwork(song.id, ArtworkType.AUDIO); } catch (_) {}
        Uri? artUri;
        if (artworkBytes != null && artworkBytes.isNotEmpty) {
          artUri = await _writeArtworkBytes(artworkBytes, 'song_${song.id}');
        } else {
          artUri = await _placeholderArtUri('song_${song.id}');
        }
        final media = MediaItem(
          id: song.id.toString(),
          album: song.album ?? '',
          title: song.title,
          artist: song.artist,
          duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
          artUri: artUri,
          extras: {'path': song.data},
        );
  await audioHandler.updateMediaItem(media);
  _sendCustomNotification(media);

        // PUBLICAR COLA: playlist basada en SongModel
        try {
          final q = <MediaItem>[];
          for (final s in _songPlaylist) {
            q.add(MediaItem(
              id: s.id.toString(),
              album: s.album ?? '',
              title: s.title,
              artist: s.artist,
              duration: s.duration != null ? Duration(milliseconds: s.duration!) : null,
              artUri: await _placeholderArtUri('song_${s.id}'),
              extras: {'path': s.data},
            ));
          }
          await audioHandler.updateQueue(q);
        } catch (_) {}
      } catch (_) {}
    } catch (e) {
      // ignore: avoid_print
      print('Error playing song: $e');
    }
  }

  Future<void> playNext() async {
    if (_songPlaylist.isNotEmpty) {
      _songIndex = (_songIndex + 1) % _songPlaylist.length;
      await playSong(_songPlaylist[_songIndex], _songIndex);
    } else {
      await playNextInFilePlaylist();
    }
  }

  Future<void> playPrevious() async {
    if (_songPlaylist.isNotEmpty) {
      if (_player.position.inSeconds > 3) {
        await _player.seek(Duration.zero);
        return;
      }
      _songIndex = (_songIndex - 1 + _songPlaylist.length) % _songPlaylist.length;
      await playSong(_songPlaylist[_songIndex], _songIndex);
    } else {
      await playPreviousInFilePlaylist();
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    // actualizar notificación al cambiar estado
    try {
      final media = await audioHandler.mediaItem.firstWhere((_) => true, orElse: () => null);
      _sendCustomNotification(media);
    } catch (_) {}
  }

  Future<void> toggleLoopMode() async {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        await _player.setLoopMode(LoopMode.all);
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        await _player.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        await _player.setLoopMode(LoopMode.off);
        break;
    }
  }

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

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    try { await _player.setLoopMode(mode); } catch (_) {}
  }

  Future<void> toggleShuffle() async {
    _isShuffleEnabled = !_isShuffleEnabled;
    try { await _player.setShuffleModeEnabled(_isShuffleEnabled); } catch (_) {}
    // Si la playlist principal es SongModel, barajar manteniendo la canción actual al inicio
    if (_songPlaylist.isNotEmpty) {
      final current = currentSong;
      if (current == null) return;
      if (_isShuffleEnabled) {
        final rand = _songPlaylist.toList();
        rand.shuffle();
        // mover canción actual al índice 0
        final idx = rand.indexWhere((s) => s.id == current.id);
        if (idx > 0) {
          final tmp = rand[0];
          rand[0] = current;
          rand[idx] = tmp;
        }
        _songPlaylist = rand;
        _songIndex = 0;
        // actualizar cola en audioHandler tras barajar
        try {
          final q = <MediaItem>[];
          for (final s in _songPlaylist) {
            q.add(MediaItem(id: s.id.toString(), album: s.album ?? '', title: s.title, artist: s.artist, duration: s.duration != null ? Duration(milliseconds: s.duration!) : null, artUri: await _placeholderArtUri('song_${s.id}'), extras: {'path': s.data}));
          }
          await audioHandler.updateQueue(q);
        } catch (_) {}
      } else {
        // restaurar orden original ubicando la actual
        final idx = _originalSongPlaylist.indexWhere((s) => s.id == current.id);
        _songPlaylist = List.from(_originalSongPlaylist);
        _songIndex = idx >= 0 ? idx : 0;
        // actualizar cola al restaurar orden
        try {
          final q = <MediaItem>[];
          for (final s in _songPlaylist) {
            q.add(MediaItem(id: s.id.toString(), album: s.album ?? '', title: s.title, artist: s.artist, duration: s.duration != null ? Duration(milliseconds: s.duration!) : null, artUri: await _placeholderArtUri('song_${s.id}'), extras: {'path': s.data}));
          }
          await audioHandler.updateQueue(q);
        } catch (_) {}
      }
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  // ---------------- Artwork Helpers ----------------
  Future<Uri?> _placeholderArtUri(String id) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/rexify_art_placeholder_$id.png');
      if (!await f.exists()) {
        // PNG 1x1 transparente (base64)
        const b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';
        final bytes = base64Decode(b64);
        await f.writeAsBytes(bytes, flush: true);
      }
      return Uri.file(f.path);
    } catch (_) { return null; }
  }

  Future<Uri?> _writeArtworkBytes(Uint8List bytes, String id) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/rexify_art_$id.png');
      await f.writeAsBytes(bytes, flush: true);
      return Uri.file(f.path);
    } catch (_) { return null; }
  }

  /// Reproduce el ítem de la cola por índice.
  /// Decide si es una canción (SongModel) o un archivo local y llama al método adecuado.
  Future<void> playQueueIndex(int index) async {
    // Si coincide con la playlist de SongModel
    if (_songPlaylist.isNotEmpty && index >= 0 && index < _songPlaylist.length) {
      await playSong(_songPlaylist[index], index);
      return;
    }
    // Si coincide con la playlist de archivos
    if (_filePlaylist.isNotEmpty && index >= 0 && index < _filePlaylist.length) {
      await playFile(File(_filePlaylist[index]));
      return;
    }

    // Intentar leer la cola expuesta por audioHandler y reproducir por 'extras.path' si existe
    try {
      final q = await audioHandler.queue.first;
      if (index >= 0 && index < q.length) {
        final mi = q[index];
        final path = mi.extras?['path'] as String?;
        if (path != null) {
          // file:// URIs o rutas absolutas
          if (path.startsWith('file://')) {
            final fp = Uri.parse(path).toFilePath();
            await playFile(File(fp));
            return;
          }
          if (path.contains(Platform.pathSeparator) || path.startsWith('/')) {
            await playFile(File(path));
            return;
          }
        }
        // Fallback: pedir al audioHandler que salte al índice
        try { await audioHandler.skipToQueueItem(index); } catch (_) {}
      }
    } catch (_) {}
  }

  // ---------------- Notificación personalizada (canal nativo) ----------------
  static const MethodChannel _notifChannel = MethodChannel('rexify/custom_notif');

  void _sendCustomNotification(MediaItem? media, {Duration? positionOverride}) {
    if (kIsWeb) return; // no en web
    if (!(Platform.isAndroid)) return; // sólo Android
    final playing = _player.playing;
    final title = media?.title ?? (currentSong?.title ?? currentPath?.split(Platform.pathSeparator).last ?? '—');
    final artist = media?.artist ?? currentSong?.artist ?? '';
    final durationMs = media?.duration?.inMilliseconds ?? _player.duration?.inMilliseconds ?? 0;
    final pos = positionOverride ?? _player.position;
    final positionMs = pos.inMilliseconds;
    String? artworkPath;
    final artUri = media?.artUri;
    if (artUri != null && artUri.scheme == 'file') {
      artworkPath = artUri.toFilePath();
    }
    _notifChannel.invokeMethod('update', {
      'title': title,
      'artist': artist,
      'artworkPath': artworkPath,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'playing': playing,
    }).catchError((_) {});
  }
}

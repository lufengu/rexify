import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:intl/intl.dart';
import 'package:audio_service/audio_service.dart';
import '../widgets/glass_card.dart';
import '../services/permission_utils.dart';
import 'package:open_file/open_file.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import 'now_playing_screen.dart';
import '../main.dart';

class DownloadsLibraryScreen extends StatefulWidget {
  const DownloadsLibraryScreen({super.key});

  @override
  State<DownloadsLibraryScreen> createState() => _DownloadsLibraryScreenState();
}

class _ItemMeta {
  _ItemMeta({
    required this.file,
    required this.size,
    required this.modified,
    required this.ext,
    this.audioId,
    this.title,
    this.artist,
  });
  final File file;
  final int size;
  final DateTime modified;
  final String ext;
  final int? audioId;
  final String? title;
  final String? artist;
  Duration? duration;
}

enum _LibraryTab { all, favorites, recent }

class _DownloadsLibraryScreenState extends State<DownloadsLibraryScreen> with TickerProviderStateMixin {
  final AudioPlayerService _audioService = AudioPlayerService();
  late final AudioPlayer _player = _audioService.audioPlayer;
  final List<_ItemMeta> _items = [];
  List<_ItemMeta> _filteredItems = [];
  bool _loading = true;
  int _currentIndex = -1;
  double _volume = 1.0;
  MediaItem? _currentMedia;
  bool _isPlaying = false;
  StreamSubscription<MediaItem?>? _mediaSub;
  StreamSubscription<PlayerState>? _stateSub;

  // Watchers & debounce
  final List<StreamSubscription<FileSystemEvent>> _dirWatchers = [];
  Timer? _debounceTimer;

  // Selection multi
  final Set<int> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  // Filter / tabs
  _LibraryTab _activeTab = _LibraryTab.all;
  // Cache favorites to avoid many async calls on build
  final Map<String, bool> _favCache = {};

  @override
  void initState() {
    super.initState();
    _init();
    _mediaSub = audioHandler.mediaItem.listen((item) {
      _currentMedia = item;
      _syncSelectionWithMedia();
    });
    _stateSub = _audioService.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
    });
    _isPlaying = _player.playing;
    _volume = _player.volume;
  }

  Future<void> _init() async {
    final ok = await PermissionUtils.ensureLibraryPermissions();
    if (!ok) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permisos de acceso a audio denegados')));
      return;
    }
    await _loadFiles();
    await _startWatchers();
  }

  Future<void> _startWatchers() async {
    // Watch the app internal Rexify folder and external candidates to auto-refresh library on changes
    Future<void> watchDirIfExists(Directory? dir) async {
      if (dir == null) return;
      try {
        if (await dir.exists()) {
          final sub = dir.watch().listen((event) {
            // Debounce rapid events
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 600), () {
              if (mounted) _loadFiles();
            });
          });
          _dirWatchers.add(sub);
        }
      } catch (_) {}
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      await watchDirIfExists(Directory('${docs.path}/Rexify'));
    } catch (_) {}
    try {
      final extDownloads = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      final extMusic = await getExternalStorageDirectories(type: StorageDirectory.music);
      final candidates = <Directory?>[
        extDownloads != null && extDownloads.isNotEmpty ? Directory('${extDownloads.first.path}/Rexify') : null,
        extMusic != null && extMusic.isNotEmpty ? Directory('${extMusic.first.path}/Rexify') : null,
      ];
      for (final d in candidates) await watchDirIfExists(d);
    } catch (_) {}
  }

  Future<void> _stopWatchers() async {
    for (final s in _dirWatchers) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    _dirWatchers.clear();
    _debounceTimer?.cancel();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final List<_ItemMeta> list = [];
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/Rexify');
      if (await d.exists()) list.addAll(await _collectFromDir(d));
    } catch (_) {}
    try {
      final extDownloads = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      final extMusic = await getExternalStorageDirectories(type: StorageDirectory.music);
      final candidates = <Directory?>[
        extDownloads != null && extDownloads.isNotEmpty ? Directory('${extDownloads.first.path}/Rexify') : null,
        extMusic != null && extMusic.isNotEmpty ? Directory('${extMusic.first.path}/Rexify') : null,
      ];
      for (final dir in candidates.whereType<Directory>()) {
        if (await dir.exists()) {
          list.addAll(await _collectFromDir(dir));
        }
      }

      final audioQuery = OnAudioQuery();
      final songs = await audioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      for (final s in songs) {
        final path = s.data;
        final lower = path.toLowerCase();
        if (lower.contains('/music/rexify/') || lower.contains('/download/rexify/') || lower.contains('/downloads/rexify/')) {
          try {
            final f = File(path);
            if (await f.exists() && _looksLikeAudio(path)) {
              final stat = await f.stat();
              list.add(_ItemMeta(
                file: f,
                size: stat.size,
                modified: stat.modified,
                ext: _extOf(path),
                audioId: s.id,
                title: s.title,
                artist: s.artist,
              ));
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    list.sort((a, b) => b.modified.compareTo(a.modified));
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(list);
      _loading = false;
    });
    await _applyFiltersAndCacheFavorites();
    _syncSelectionWithMedia(force: true);
  }

  Future<void> _applyFiltersAndCacheFavorites() async {
    _favCache.clear();
    // Preload favorite states for items to speed up filtering
    for (final it in _items) {
      try {
        final fav = await LibraryService.instance.isFavorite(it.file.path);
        _favCache[it.file.path] = fav;
      } catch (_) {
        _favCache[it.file.path] = false;
      }
    }
    _computeFilteredItems();
  }

  void _computeFilteredItems() {
    List<_ItemMeta> res;
    switch (_activeTab) {
      case _LibraryTab.favorites:
        res = _items.where((i) => _favCache[i.file.path] == true).toList();
        break;
      case _LibraryTab.recent:
        // recents: archivos modificados en los últimos 7 días
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        res = _items.where((i) => i.modified.isAfter(cutoff)).toList();
        break;
      case _LibraryTab.all:
      default:
        res = List.from(_items);
    }
    setState(() => _filteredItems = res);
  }

  void _syncSelectionWithMedia({bool force = false}) {
    if (!mounted) return;
    final path = _currentMedia?.extras?['path'] as String? ?? _audioService.currentPath;
    final idx = path == null ? -1 : _items.indexWhere((e) => e.file.path == path);
    if (!force && idx == _currentIndex) return;
    setState(() => _currentIndex = idx);
  }

  static const _audioExts = ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac', '.mp4', '.opus', '.webm'];

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    return i >= 0 ? path.substring(i).toLowerCase() : '';
  }

  bool _looksLikeAudio(String path) {
    final ext = _extOf(path);
    return _audioExts.contains(ext);
  }

  Future<List<_ItemMeta>> _collectFromDir(Directory dir) async {
    final list = <_ItemMeta>[];
    try {
      final entries = await dir.list(recursive: false, followLinks: false).toList();
      for (final e in entries) {
        if (e is File) {
          final name = e.path.split(Platform.pathSeparator).last;
          final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')).toLowerCase() : '';
          if (!_audioExts.contains(ext)) continue;
          final stat = await e.stat();
          list.add(_ItemMeta(file: e, size: stat.size, modified: stat.modified, ext: ext));
        }
      }
    } catch (_) {}
    return list;
  }

  Future<void> _calcDuration(_ItemMeta item) async {
    if (item.duration != null) return;
    final p = AudioPlayer();
    try {
      final dur = await p.setFilePath(item.file.path);
      item.duration = dur;
    } catch (_) {
      item.duration = null;
    } finally {
      await p.dispose();
    }
    if (mounted) setState(() {});
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    final paths = _items.map((e) => e.file.path).toList(growable: false);
    try {
      final needsSet = _audioService.filePlaylist.length != paths.length ||
          _audioService.filePlaylist.asMap().entries.any((e) => e.value != paths[e.key]);
      if (needsSet) {
        await _audioService.setFilePlaylistAndPlay(paths, index);
      } else {
        await _audioService.playFile(File(paths[index]), title: _items[index].title, artist: _items[index].artist);
      }
      try {
        await LibraryService.instance.addHistory(paths[index], title: _items[index].title, artist: _items[index].artist);
      } catch (_) {}
      _syncSelectionWithMedia(force: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo reproducir: $e')));
    }
  }

  Future<void> _playNext() async {
    if (_items.isEmpty) return;
    try {
      await _audioService.playNextInFilePlaylist();
      _syncSelectionWithMedia(force: true);
    } catch (_) {}
  }

  Future<void> _playPrev() async {
    if (_items.isEmpty) return;
    try {
      await _audioService.playPreviousInFilePlaylist();
      _syncSelectionWithMedia(force: true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    _stateSub?.cancel();
    _stopWatchers();
    super.dispose();
  }

  // Preview 5s
  Future<void> _previewFile(File f) async {
    final p = AudioPlayer();
    try {
      await p.setFilePath(f.path);
      await p.play();
      // Stop after 5 seconds
      await Future.delayed(const Duration(seconds: 5));
      await p.stop();
    } catch (_) {
      // ignore
    } finally {
      await p.dispose();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar archivos'),
        content: Text('Eliminar ${_selected.length} archivo(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final toDelete = _selected.map((i) => _filteredItems[i]).toList(growable: false);
    for (final it in toDelete) {
      try {
        await it.file.delete();
      } catch (_) {}
    }
    _selected.clear();
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return DefaultTabController(
      length: 3,
      initialIndex: _activeTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Música descargada'),
          bottom: TabBar(
            onTap: (i) {
              setState(() {
                _activeTab = _LibraryTab.values[i];
                _computeFilteredItems();
              });
            },
            tabs: const [
              Tab(text: 'Todo'),
              Tab(text: 'Favoritos'),
              Tab(text: 'Recientes'),
            ],
          ),
          actions: [
            if (_selectionMode)
              IconButton(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Eliminar selección',
              ),
            IconButton(
              onPressed: _loadFiles,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filteredItems.isEmpty
                ? Center(
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: const Text('No se encontraron descargas en Rexify'),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadFiles,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: ListView.separated(
                              key: ValueKey(_activeTab),
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredItems.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final it = _filteredItems[i];
                                final name = it.title ?? it.file.path.split(Platform.pathSeparator).last;
                                final playing = it.file.path == (_currentMedia?.extras?['path'] as String? ?? _audioService.currentPath) && _isPlaying;
                                _calcDuration(it);
                                return _SongTile(
                                  key: ValueKey(it.file.path),
                                  playing: playing,
                                  item: it,
                                  dateFmt: df,
                                  selected: _selected.contains(i),
                                  onTap: () async {
                                    // tap -> play
                                    final globalIndex = _items.indexWhere((e) => e.file.path == it.file.path);
                                    if (globalIndex != -1) {
                                      await _playAt(globalIndex);
                                      if (!mounted) return;
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
                                    }
                                  },
                                  onLongPress: () async {
                                    // long press -> preview or start selection mode
                                    if (_selectionMode) {
                                      setState(() {
                                        if (_selected.contains(i)) _selected.remove(i);
                                        else _selected.add(i);
                                      });
                                      return;
                                    }
                                    // start a 5s preview
                                    _previewFile(it.file);
                                  },
                                  onSelectToggle: () {
                                    setState(() {
                                      if (_selected.contains(i)) _selected.remove(i);
                                      else _selected.add(i);
                                    });
                                  },
                                  onMore: () => _showActions(it, displayName: name),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      // Mini-player persistent
                      _buildMiniPlayer(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    final media = _currentMedia;
    if (media == null) return const SizedBox.shrink();
    final title = media.title ?? 'Sin título';
    final subtitle = (media.artist ?? '') + (media.extras?['path'] != null ? '' : '');
    return SafeArea(
      top: false,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NowPlayingScreen())),
          child: Row(
            children: [
              // tiny artwork if available
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: media.extras?['artworkFile'] is String
                      ? Image.file(File(media.extras!['artworkFile']), fit: BoxFit.cover)
                      : const Icon(Icons.music_note_rounded, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: 'Anterior',
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _playPrev,
              ),
              StreamBuilder<PlayerState>(
                stream: _audioService.playerStateStream,
                builder: (context, snap) {
                  final state = snap.data;
                  final playing = state?.playing ?? _isPlaying;
                  return IconButton(
                    tooltip: playing ? 'Pausa' : 'Reproducir',
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: () async {
                      if (playing) await _audioService.pause();
                      else await _audioService.play();
                    },
                  );
                },
              ),
              IconButton(
                tooltip: 'Siguiente',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _playNext,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(_ItemMeta it, {required String displayName}) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Reproducir'),
              onTap: () {
                Navigator.pop(ctx);
                final globalIndex = _items.indexWhere((e) => e.file.path == it.file.path);
                if (globalIndex != -1) _playAt(globalIndex);
              },
            ),
            FutureBuilder<bool>(
              future: LibraryService.instance.isFavorite(it.file.path),
              builder: (context, snap) {
                final isFav = snap.data ?? (_favCache[it.file.path] ?? false);
                return ListTile(
                  leading: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? Theme.of(context).colorScheme.primary : null),
                  title: Text(isFav ? 'Quitar de favoritos' : 'Añadir a favoritos'),
                  onTap: () async {
                    await LibraryService.instance.toggleFavorite(it.file.path);
                    if (mounted) {
                      _favCache[it.file.path] = !(isFav);
                      _computeFilteredItems();
                      Navigator.pop(ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Abrir con otra app'),
              onTap: () async {
                Navigator.pop(ctx);
                await OpenFile.open(it.file.path);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Eliminar archivo'),
                    content: Text('¿Eliminar "$displayName"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    await it.file.delete();
                  } catch (_) {}
                  if (mounted) _loadFiles();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    super.key,
    required this.item,
    required this.playing,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.onSelectToggle,
    required this.selected,
    required this.dateFmt,
  });

  final _ItemMeta item;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onSelectToggle;
  final bool selected;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final title = item.title ?? _basename(item.file.path);
    final subtitle = StringBuffer()
      ..write(item.ext.replaceFirst('.', '').toUpperCase())
      ..write(' • ')
      ..write(_fmtBytes(item.size))
      ..write(' • ')
      ..write(dateFmt.format(item.modified));

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            // Artwork (si hay id de MediaStore), si no, avatar con icono
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: item.audioId != null
                    ? QueryArtworkWidget(
                        id: item.audioId!,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: _placeholderArt(context),
                      )
                    : _placeholderArt(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle.toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              IconButton(
                tooltip: 'Seleccionado',
                icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
                onPressed: onSelectToggle,
              )
            else
              IconButton(
                tooltip: playing ? 'Reproduciendo' : 'Reproducir',
                icon: Icon(playing ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                    color: playing ? Theme.of(context).colorScheme.tertiary : null),
                onPressed: onTap,
              ),
            IconButton(
              tooltip: 'Más',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderArt(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.2), c.tertiary.withValues(alpha: 0.2)]),
      ),
      child: const Center(child: Icon(Icons.music_note_rounded)),
    );
  }

  String _basename(String p) => p.split(Platform.pathSeparator).last;
  String _fmtBytes(int b) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double s = b.toDouble();
    int i = 0;
    while (s >= 1024 && i < units.length - 1) {
      s /= 1024; i++;
    }
    return '${s.toStringAsFixed(s >= 100 ? 0 : 1)} ${units[i]}';
  }
}

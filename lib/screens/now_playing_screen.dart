import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../main.dart';

/// Pantalla "Ahora suena" — layout tipo "player" con artwork grande,
/// controles centrales y acceso a cola/acciones.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final AudioPlayerService _player = AudioPlayerService();
  late final AudioPlayer _audioPlayer = _player.audioPlayer;

  Future<void> _toggleShuffle() async {
    await _player.toggleShuffle();
    if (mounted) setState(() {});
  }

  Future<void> _cycleRepeat() async {
    await _player.toggleLoopMode();
    if (mounted) setState(() {});
  }

  Future<void> _showQueue() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return StreamBuilder<List<MediaItem>>(
          stream: audioHandler.queue,
          builder: (c, snap) {
            final q = snap.data ?? [];
            if (q.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(
                    child: Text('Cola vacía',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
              );
            }
            return SafeArea(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: q.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) {
                  final it = q[i];
                  return ListTile(
                    leading: it.artUri != null
                        ? (it.artUri!.scheme == 'file'
                            ? Image.file(File(it.artUri!.toFilePath()),
                                width: 48, height: 48, fit: BoxFit.cover)
                            : Image.network(it.artUri.toString(),
                                width: 48, height: 48, fit: BoxFit.cover))
                        : Container(
                            width: 48,
                            height: 48,
                            color: Colors.white10,
                            child: const Icon(Icons.music_note_rounded)),
                    title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle:
                        Text(it.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await audioHandler.skipToQueueItem(i);
                      } catch (_) {}
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showActions(MediaItem? item) async {
    final path = item?.extras?['path'] as String? ?? _player.currentPath;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.favorite_border_rounded),
                title: const Text('Añadir/Quitar favorito'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (path != null) {
                    await LibraryService.instance.toggleFavorite(path);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Compartir'),
                onTap: () {
                  Navigator.pop(ctx);
                  // implementar share si se desea (share_plus)
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Mostrar ruta'),
                subtitle: Text(path ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bigArtwork(MediaItem? item) {
    final artUri = item?.artUri;
    if (artUri == null) {
      return Container(
        color: Colors.white10,
        child: const Center(
            child: Icon(Icons.music_note_rounded, size: 120, color: Colors.white70)),
      );
    }
    return artUri.scheme == 'file'
        ? Image.file(File(artUri.toFilePath()), fit: BoxFit.cover)
        : Image.network(artUri.toString(), fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return StreamBuilder<MediaItem?>(stream: audioHandler.mediaItem, builder: (context, snap) {
      final item = snap.data;
      final title = item?.title ?? _fallbackTitle();
      final artist = item?.artist ?? '';
      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.expand_more),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            _FavoriteToggle(path: item?.extras?['path'] as String? ?? _player.currentPath),
            IconButton(icon: const Icon(Icons.queue_music_rounded), onPressed: () { _showQueue(); }),
            IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () { _showActions(item); }),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0B102D),
                const Color(0xFF121637),
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Hero(
                            tag: item?.id ?? _player.currentPath ?? 'rexify_artwork',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 32,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: _bigArtwork(item),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          artist.isEmpty ? 'Artista desconocido' : artist,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        _TagsRow(path: item?.extras?['path'] as String? ?? _player.currentPath),
                        const SizedBox(height: 24),
                        _TrackInfoCard(item: item, player: _player),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProgressSection(player: _player, accent: accent),
                      const SizedBox(height: 18),
                      _PrimaryControls(
                        player: _player,
                        accent: accent,
                        onToggleShuffle: () { _toggleShuffle(); },
                        onToggleRepeat: () { _cycleRepeat(); },
                      ),
                      const SizedBox(height: 18),
                      _VolumeRow(audioPlayer: _audioPlayer),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _fallbackTitle() {
    final path = _player.currentPath;
    if (path == null) return '—';
    return path.split(Platform.pathSeparator).last;
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.player, required this.accent});
  final AudioPlayerService player;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnap) {
            final pos = positionSnap.data ?? Duration.zero;
            return Column(
              children: [
                ProgressBar(
                  progress: pos,
                  total: total,
                  onSeek: (d) => player.seek(d),
                  barHeight: 6,
                  thumbRadius: 8,
                  timeLabelLocation: TimeLabelLocation.none,
                  baseBarColor: Colors.white12,
                  progressBarColor: accent,
                  thumbColor: accent,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmtDuration(pos), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    Text(_fmtDuration(total), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _fmtDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PrimaryControls extends StatelessWidget {
  const _PrimaryControls({
    required this.player,
    required this.accent,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  final AudioPlayerService player;
  final Color accent;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  @override
  Widget build(BuildContext context) {
    final audioPlayer = player.audioPlayer;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: audioPlayer.shuffleModeEnabledStream,
          initialData: player.isShuffleEnabled,
          builder: (context, snap) {
            final enabled = snap.data ?? false;
            return _CircleIconButton(
              icon: Icons.shuffle_rounded,
              active: enabled,
              accent: accent,
              onPressed: onToggleShuffle,
            );
          },
        ),
        _CircleIconButton(
          icon: Icons.skip_previous_rounded,
          accent: accent,
          onPressed: () { player.playPrevious(); },
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return GestureDetector(
              onTap: () { player.togglePlayPause(); },
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        _CircleIconButton(
          icon: Icons.skip_next_rounded,
          accent: accent,
          onPressed: () { player.playNext(); },
        ),
        StreamBuilder<LoopMode>(
          stream: audioPlayer.loopModeStream,
          initialData: player.loopMode,
          builder: (context, snap) {
            final loopMode = snap.data ?? LoopMode.off;
            final icon = loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded;
            final active = loopMode != LoopMode.off;
            return _CircleIconButton(
              icon: icon,
              active: active,
              accent: accent,
              onPressed: onToggleRepeat,
            );
          },
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : Colors.white70;
    return InkResponse(
      onTap: onPressed,
      radius: 30,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? accent.withValues(alpha: 0.18) : Colors.white10,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.audioPlayer});
  final AudioPlayer audioPlayer;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: audioPlayer.volumeStream,
      initialData: audioPlayer.volume,
      builder: (context, snap) {
        final value = (snap.data ?? audioPlayer.volume).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Volumen', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(value <= 0.01 ? Icons.volume_off_rounded : Icons.volume_down_rounded, color: Colors.white70),
                Expanded(
                  child: Slider(
                    value: value,
                    onChanged: (v) => audioPlayer.setVolume(v),
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Colors.white24,
                  ),
                ),
                const Icon(Icons.volume_up_rounded, color: Colors.white70),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TrackInfoCard extends StatelessWidget {
  const _TrackInfoCard({required this.item, required this.player});
  final MediaItem? item;
  final AudioPlayerService player;

  @override
  Widget build(BuildContext context) {
    final path = item?.extras?['path'] as String? ?? player.currentPath;
    final buffer = <String>[];
    if (item?.album?.isNotEmpty == true) buffer.add(item!.album!);
    if (item?.artist?.isNotEmpty == true) buffer.add(item!.artist!);
    final subtitle = buffer.isEmpty ? '—' : buffer.join(' • ');
    return Container(
      decoration: BoxDecoration(
  color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detalles', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
          if (path != null) ...[
            const SizedBox(height: 12),
            Text(
              path,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _FavoriteToggle extends StatefulWidget {
  const _FavoriteToggle({required this.path});
  final String? path;

  @override
  State<_FavoriteToggle> createState() => _FavoriteToggleState();
}

class _FavoriteToggleState extends State<_FavoriteToggle> {
  bool? _isFav;

  @override
  void didUpdateWidget(covariant _FavoriteToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null) {
      setState(() => _isFav = null);
      return;
    }
    final fav = await LibraryService.instance.isFavorite(path);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _toggle() async {
    final path = widget.path;
    if (path == null) return;
    final fav = await LibraryService.instance.toggleFavorite(path);
    if (mounted) setState(() => _isFav = fav);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path == null) {
      return const SizedBox(width: 48);
    }
    final fav = _isFav ?? false;
    return IconButton(
      icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: fav ? Theme.of(context).colorScheme.secondary : Colors.white70),
      onPressed: () { _toggle(); },
      tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
    );
  }
}

class _TagsRow extends StatefulWidget {
  const _TagsRow({required this.path});
  final String? path;

  @override
  State<_TagsRow> createState() => _TagsRowState();
}

class _TagsRowState extends State<_TagsRow> {
  List<String> _tags = const [];

  @override
  void didUpdateWidget(covariant _TagsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.path == null) return;
    final t = await LibraryService.instance.getTags(widget.path!);
    if (mounted) setState(() => _tags = t);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        ..._tags.map((e) => Chip(label: Text(e))),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Etiqueta'),
          onPressed: () async {
            final newTag = await _askTag(context);
            if (newTag == null || newTag.trim().isEmpty) return;
            final next = {..._tags, newTag.trim()}.toList();
            await LibraryService.instance.setTags(widget.path!, next);
            _load();
          },
        )
      ],
    );
  }

  Future<String?> _askTag(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nueva etiqueta'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'p. ej. gym, chill, favorito')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
  }
}

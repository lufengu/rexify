import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
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

class _NowPlayingScreenState extends State<NowPlayingScreen> with SingleTickerProviderStateMixin {
  final AudioPlayerService _player = AudioPlayerService();
  late final AudioPlayer _audioPlayer = _player.audioPlayer;

  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

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
          builder: (c, qSnap) {
            final q = qSnap.data ?? [];

            // Anidamos otro StreamBuilder para obtener el item actual y calcular índice
            return StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              builder: (c2, curSnap) {
                final current = curSnap.data;
                int curIndex = -1;

                // Si audioHandler.queue está vacío, intentamos usar la playlist interna como fallback
                var queueList = q;
                if (queueList.isEmpty) {
                  queueList = AudioPlayerService().queueSync;
                }
                if (current != null) {
                  curIndex = queueList.indexWhere((m) {
                    final curPath = current.extras?['path'] as String?;
                    final mPath = m.extras?['path'] as String?;
                    if (curPath != null && mPath != null) return curPath == mPath;
                    return m.id == current.id;
                  });
                }

                if (queueList.isEmpty) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Text('Cola vacía', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    ),
                  );
                }

                // Controller para desplazar la lista y centrar la canción actual si existe
                final controller = ScrollController(
                  initialScrollOffset: (curIndex > 0) ? (curIndex * 72.0 - 72.0).clamp(0.0, double.infinity) : 0.0,
                );

                return SafeArea(
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: queueList.length,
                    separatorBuilder: (_, __) => const Divider(height: 8, thickness: 1),
                    itemBuilder: (ctx, i) {
                      final it = queueList[i];
                      final isCurrent = i == curIndex;
                      final isPrev = curIndex != -1 && i < curIndex;
                      final isNext = curIndex != -1 && i > curIndex;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        tileColor: isCurrent ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : null,
                        leading: it.artUri != null
                            ? (it.artUri!.scheme == 'file'
                                ? Image.file(File(it.artUri!.toFilePath()), width: 48, height: 48, fit: BoxFit.cover)
                                : Image.network(it.artUri.toString(), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded)))
                            : Container(width: 48, height: 48, color: Colors.white10, child: const Icon(Icons.music_note_rounded)),
                        title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(it.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: isCurrent
                            ? const Icon(Icons.play_circle_fill_rounded, color: Colors.white70)
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isPrev) const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white54),
                                  if (isNext) const Icon(Icons.arrow_downward_rounded, size: 18, color: Colors.white54),
                                ],
                              ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await audioHandler.skipToQueueItem(i);
                          } catch (_) {}
                          try {
                            await AudioPlayerService().playQueueIndex(i);
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

      // Nuevo diseño estilo "Uiverse" — tarjeta compacta
      return Scaffold(
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final safeBottom = MediaQuery.of(context).viewPadding.bottom;
              final width = constraints.maxWidth;
              final height = (constraints.maxHeight - safeBottom).clamp(0.0, double.infinity);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Tarjeta principal que ahora ocupa todo el área disponible
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          // vidrio con sutil gradiente para dar un toque original
                          gradient: LinearGradient(
                            colors: [Colors.white.withOpacity(0.48), accent.withOpacity(0.04)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                          boxShadow: [
                            // ligero relieve exterior
                            BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 28, offset: const Offset(0, 12)),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 6),
                              // etiqueta 'Music' con efecto neumórfico suave
                              Container(
                                width: 92,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withOpacity(0.06),
                                  boxShadow: [
                                    BoxShadow(color: Colors.white.withOpacity(0.02), offset: const Offset(-6, -6), blurRadius: 12),
                                    BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(6, 6), blurRadius: 12),
                                  ],
                                ),
                                child: const Center(
                                  child: Text('Music', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF666464))),
                                ),
                              ),
                               const SizedBox(height: 16),
                                // Artwork con anillo luminoso y brillo interior
                                SizedBox(
                                  width: math.min(width * 0.6, 340),
                                  height: math.min(height * 0.36, 340),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // anillo glow detrás del artwork
                                      Container(
                                        width: math.min(width * 0.45, 260),
                                        height: math.min(width * 0.45, 260),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: [accent.withOpacity(0.18), Colors.transparent],
                                            stops: const [0.0, 0.8],
                                          ),
                                          boxShadow: [
                                            BoxShadow(color: accent.withOpacity(0.14), blurRadius: 40, spreadRadius: 12),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: math.min(width * 0.52, 300),
                                        height: math.min(width * 0.52, 300),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(28),
                                          color: const Color(0xFFD8D4D4).withOpacity(0.6),
                                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10)),
                                            BoxShadow(color: Colors.white.withOpacity(0.02), blurRadius: 6, offset: const Offset(-4, -4)),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(24),
                                          child: item?.artUri != null
                                              ? (item!.artUri!.scheme == 'file'
                                                  ? Image.file(File(item.artUri!.toFilePath()), fit: BoxFit.cover)
                                                  : Image.network(item.artUri.toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded)))
                                              : const Center(child: Icon(Icons.music_note_rounded, size: 88, color: Colors.black54)),
                                        ),
                                      ),
                                      // sutil brillo superior
                                      Positioned(
                                        top: 14,
                                        child: Container(
                                          width: math.min(width * 0.48, 280),
                                          height: 40,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            gradient: LinearGradient(colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.02)]),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                 const SizedBox(height: 18),
                                 // Título y artista
                                 Padding(
                                   padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                   child: Column(
                                     children: [
                                       Text(title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF323133))),
                                       const SizedBox(height: 8),
                                       Text(artist.isEmpty ? 'Desconhecido' : artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF323133))),
                                     ],
                                   ),
                                 ),
                                 const SizedBox(height: 18),
                                 // Controles principales
                                 Row(
                                   mainAxisAlignment: MainAxisAlignment.center,
                                   children: [
                                     IconButton(
                                       icon: const Icon(Icons.fast_rewind_rounded, size: 26, color: Color(0xFF52504F)),
                                       onPressed: () { _player.playPrevious(); },
                                       tooltip: 'Anterior',
                                     ),
                                     const SizedBox(width: 8),
                                     SizedBox(
                                       width: 86,
                                       height: 86,
                                       child: StreamBuilder<PlayerState>(
                                         stream: _player.playerStateStream,
                                         builder: (c, sSnap) {
                                           final playing = sSnap.data?.playing ?? false;
                                           return GestureDetector(
                                             onTap: () { _player.togglePlayPause(); },
                                             child: Container(
                                               decoration: BoxDecoration(
                                                 shape: BoxShape.circle,
                                                 gradient: LinearGradient(
                                                   colors: [accent, accent.withOpacity(0.75)],
                                                   begin: Alignment.topLeft,
                                                   end: Alignment.bottomRight,
                                                 ),
                                                 boxShadow: [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10))],
                                               ),
                                               child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38, color: Colors.white),
                                             ),
                                           );
                                         },
                                       ),
                                     ),
                                     const SizedBox(width: 8),
                                     IconButton(
                                       icon: const Icon(Icons.fast_forward_rounded, size: 26, color: Color(0xFF52504F)),
                                       onPressed: () { _player.playNext(); },
                                       tooltip: 'Siguiente',
                                     ),
                                   ],
                                 ),
 const SizedBox(height: 18),
// Progress + pequeño visualizador animado
_ProgressSection(player: _player, accent: accent),
const SizedBox(height: 12),
// visualizador estilizado
SizedBox(width: double.infinity, height: 48, child: _AnimatedWave(animation: _animController, color: accent)),
 const SizedBox(height: 12),
                                 Padding(
                                   padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                   child: Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       StreamBuilder<bool>(
                                         stream: _player.audioPlayer.shuffleModeEnabledStream,
                                         initialData: _player.isShuffleEnabled,
                                         builder: (c, s) {
                                           final on = s.data ?? false;
                                           return IconButton(
                                             icon: Icon(Icons.shuffle_rounded, size: 18, color: on ? Colors.black : const Color(0xFF1D1C1C)),
                                             onPressed: () => _toggleShuffle(),
                                           );
                                         },
                                       ),
                                       IconButton(icon: const Icon(Icons.playlist_play_rounded, size: 18, color: Color(0xFF1D1C1C)), onPressed: () => _showQueue()),
                                       IconButton(icon: Icon(item != null || _player.currentPath != null ? Icons.favorite_border_rounded : Icons.favorite_border_rounded, size: 18, color: const Color(0xFF1D1C1C)), onPressed: () async {
                                        final path = item?.extras?['path'] as String? ?? _player.currentPath;
                                        if (path != null) await LibraryService.instance.toggleFavorite(path);
                                      }),
                                      IconButton(icon: const Icon(Icons.arrow_right_alt_rounded, size: 18, color: Color(0xFF1D1C1C)), onPressed: () {}),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Esferas animadas ahora posicionadas en proporción a la pantalla (evitan overflow)
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (ctx, _) {
                      final t = _animController.value;
                      final p1x = (width * 0.05) + (width * 0.15) * math.cos(2 * math.pi * t);
                      final p1y = (height * 0.08) + (height * 0.12) * math.sin(2 * math.pi * t);
                      final p2x = (width * 0.55) + (width * 0.12) * math.cos(2 * math.pi * (t + 0.5));
                      final p2y = (height * 0.35) + (height * 0.12) * math.sin(2 * math.pi * (t + 0.5));

                      return Stack(
                        children: [
                          Positioned(
                            left: p1x.clamp(-80.0, width - 10.0),
                            top: p1y.clamp(-80.0, height - 10.0),
                            child: Container(
                              width: math.min(120, width * 0.30),
                              height: math.min(120, width * 0.30),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8319A3).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [BoxShadow(color: const Color(0xFF8319A3).withOpacity(0.5), blurRadius: 30, spreadRadius: 10)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: p2x.clamp(-80.0, width - 10.0),
                            top: p2y.clamp(-80.0, height - 10.0),
                            child: Container(
                              width: math.min(140, width * 0.35),
                              height: math.min(140, width * 0.35),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DD195).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(100),
                                boxShadow: [BoxShadow(color: const Color(0xFF1DD195).withOpacity(0.5), blurRadius: 30, spreadRadius: 10)],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
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
                    colors: [accent, accent.withOpacity(0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10)),
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
          color: active ? accent.withOpacity(0.18) : Colors.white10,
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
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

// Visualizador simple, controlado por el AnimationController existente.
// Dibuja una onda sinusoidal suave que se mueve con el tiempo.
class _AnimatedWave extends StatelessWidget {
  const _AnimatedWave({required this.animation, required this.color});
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return CustomPaint(
          painter: _WavePainter(animation.value, color),
          size: Size.infinite,
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [color.withOpacity(0.9), color.withOpacity(0.4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height / 2;
    final amplitude = size.height * 0.28;
    final freq = 2.2; // número de ciclos
    final samples = 120;
    for (var i = 0; i <= samples; i++) {
      final x = (i / samples) * size.width;
      final phase = (t * 2 * math.pi);
      final y = midY + math.sin((i / samples) * freq * 2 * math.pi + phase) * amplitude * (0.6 + 0.4 * math.sin(phase * 0.7));
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }

    // capa sutil difusa (glow)
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = color.withOpacity(0.06)
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t || old.color != color;
}

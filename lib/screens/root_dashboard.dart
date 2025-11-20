import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_player_service.dart';
import 'downloads_library_screen.dart';
import 'y2mate_dashboard.dart';
import 'youtube_dashboard.dart';
import 'now_playing_screen.dart';
import 'settings_screen.dart';
import '../main.dart';
import 'download_hub.dart';
import 'xx_access_gate.dart';

/// Dashboard raíz con navegación inferior.
/// Abre por defecto en "Reproductor" para cumplir con el flujo solicitado.
class RootDashboard extends StatefulWidget {
  const RootDashboard({super.key});

  @override
  State<RootDashboard> createState() => _RootDashboardState();
}

class _RootDashboardState extends State<RootDashboard> {
  // 0: YouTube, 1: Hub descargas, 2: Reproductor, 3: Biblioteca, 4: Ajustes
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      YouTubeDashboard(),
      DownloadHub(),
      NowPlayingScreen(),
      DownloadsLibraryScreen(),
      SettingsScreen(),
    ];

    // Si hay reproducción activa, abrir directamente el reproductor (índice 2)
    final service = AudioPlayerService();
    if (service.isPlaying || service.currentPath != null) {
      _index = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navChildren = <Widget>[];

    // Mini-player visible en todas las pestañas excepto cuando estamos en la pantalla completa del reproductor (index 2)
    if (_index != 2) {
      navChildren.add(_MiniPlayer());
    }

    navChildren.add(_AdaptiveBottomBar(
      selectedIndex: _index,
      onSelect: (i) {
        if (i == 5) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const XXAccessGate()));
          return;
        }
        // Si el usuario elige la pestaña reproductor (índice 2) forzamos scroll/estado
        setState(() => _index = i);
      },
    ));

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: navChildren,
        ),
      ),
    );
  }
}

/// Mini-player persistente que muestra carátula, título/artist y controles básicos.
/// Al tocar abre la pantalla completa (NowPlayingScreen).
class _MiniPlayer extends StatefulWidget {
  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  final _player = AudioPlayerService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snap) {
        final item = snap.data;
        final title = item?.title ?? _player.currentPath?.split(Platform.pathSeparator).last ?? '—';
        final artist = item?.artist ?? '';
        final artUri = item?.artUri;

        return Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 8,
          child: InkWell(
            onTap: () {
              // abrir reproductor completo
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Barra de progreso compacta
                  StreamBuilder<Duration?>(
                    stream: _player.durationStream,
                    builder: (context, dSnap) {
                      final total = dSnap.data ?? Duration.zero;
                      return StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, pSnap) {
                          final pos = pSnap.data ?? Duration.zero;
                          final value = total.inMilliseconds > 0 ? pos.inMilliseconds / total.inMilliseconds : null;
                          return LinearProgressIndicator(value: value?.clamp(0.0, 1.0));
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Artwork
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: artUri != null
                              ? (artUri.isScheme('file')
                                  ? Image.file(File(artUri.toFilePath()), fit: BoxFit.cover)
                                  : Image.network(artUri.toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded)))
                              : Container(color: Colors.white10, child: const Icon(Icons.music_note_rounded)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title / artist
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      // Controls
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, sSnap) {
                          final playing = sSnap.data?.playing ?? false;
                          return Row(
                            children: [
                              IconButton(icon: const Icon(Icons.skip_previous_rounded), onPressed: _player.playPrevious),
                              IconButton(
                                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                onPressed: () => _player.togglePlayPause(),
                              ),
                              IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: _player.playNext),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Barra inferior adaptativa: muestra iconos y, si hay ancho suficiente, etiquetas bajo cada icono.
/// El sexto elemento (índice 5) abre el flujo XX sin cambiar pestaña.
class _AdaptiveBottomBar extends StatelessWidget {
  const _AdaptiveBottomBar({required this.selectedIndex, required this.onSelect});
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _items = <Map<String, dynamic>>[
    {'icon': Icons.play_circle_fill_rounded, 'label': 'YouTube', 'badge': 'YT', 'color': Color(0xFFCC0000)},
    {'icon': Icons.cloud_download_rounded, 'label': 'Descargas'},
    {'icon': Icons.play_circle_fill_rounded, 'label': 'Reproductor'},
    {'icon': Icons.library_music_rounded, 'label': 'Biblioteca'},
    {'icon': Icons.settings_rounded, 'label': 'Ajustes'},
    {'icon': Icons.lock_rounded, 'label': 'XX'},
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final showLabels = constraints.maxWidth > 480;
          final itemWidth = (constraints.maxWidth / _items.length).clamp(56.0, 140.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_items.length, (i) {
              final it = _items[i];
              final selected = i == selectedIndex;
              final color = selected ? Theme.of(context).colorScheme.primary : Colors.white70;
              return SizedBox(
                width: itemWidth,
                child: InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: it['label'] as String,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: it.containsKey('color') ? (it['color'] as Color).withOpacity(0.12) : Colors.transparent,
                            child: Icon(
                              it['icon'] as IconData,
                              size: 18,
                              color: color,
                            ),
                          ),
                        ),
                        if (showLabels) ...[
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              it['label'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                color: selected ? Theme.of(context).colorScheme.primary : Colors.white70,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }
}

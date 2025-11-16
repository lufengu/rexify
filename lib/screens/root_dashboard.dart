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

/// Dashboard raíz con navegación inferior.
/// Abre por defecto en "Reproductor" para cumplir con el flujo solicitado.
class RootDashboard extends StatefulWidget {
  const RootDashboard({super.key});

  @override
  State<RootDashboard> createState() => _RootDashboardState();
}

class _RootDashboardState extends State<RootDashboard> {
  // 0: YouTube, 1: Descargas (Downloader/Web), 2: Reproductor, 3: Biblioteca, 4: Ajustes
  int _index = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      YouTubeDashboard(),
      Y2MateDashboard(),
      NowPlayingScreen(),
      DownloadsLibraryScreen(),
      SettingsScreen(),
    ];
    // Si hay reproducción activa, abrir directamente el reproductor (index 1)
    final service = AudioPlayerService();
    if (service.isPlaying || service.currentPath != null) {
      // ahora Reproductor está en el índice 2
      _index = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navChildren = <Widget>[];
    // Mini-player visible en todas las pestañas excepto cuando estamos en la pantalla completa del reproductor (index 1)
    if (_index != 1) {
      navChildren.add(_MiniPlayer());
    }
    navChildren.add(
      NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          // YouTube quick access
          NavigationDestination(
            icon: CircleAvatar(radius: 12, backgroundColor: Color(0xFFCC0000), child: Text('YT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
            label: 'YouTube',
          ),
          // Re-add Y2Mate/Downloader as a dedicated "Descargas" entry
          NavigationDestination(icon: Icon(Icons.cloud_download_rounded), label: 'Descargas'),
          NavigationDestination(icon: Icon(Icons.play_circle_fill_rounded), label: 'Reproductor'),
          NavigationDestination(icon: Icon(Icons.library_music_rounded), label: 'Biblioteca'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Ajustes'),
        ],
      ),
    );

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
                              ? (artUri.scheme == 'file'
                                  ? Image.file(File(artUri.toFilePath()), fit: BoxFit.cover)
                                  : Image.network(artUri.toString(), fit: BoxFit.cover))
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

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:ui';
import '../services/audio_player_service.dart';
import '../main.dart';
import '../widgets/glass_card.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  List<SongModel> _songs = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadSongs();
  }

  Future<void> _requestPermissionAndLoadSongs() async {
    // Request permission for Android (audio) or older versions (storage)
    PermissionStatus status;

    // Try audio permission first
    if (await Permission.audio.isGranted) {
      status = PermissionStatus.granted;
    } else {
      status = await Permission.audio.request();

      // Fallback to storage permission for older Android versions
      if (status.isDenied || status.isPermanentlyDenied) {
        if (await Permission.storage.isGranted) {
          status = PermissionStatus.granted;
        } else {
          status = await Permission.storage.request();
        }
      }
    }

    if (status.isGranted) {
      setState(() => _hasPermission = true);
      await _loadSongs();
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSongs() async {
    setState(() => _isLoading = true);

    final songs = await _audioService.loadSongs();

    setState(() {
      _songs = songs;
      _isLoading = false;
    });
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null) return '0:00';

    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0A0E27),
            const Color(0xFF1A1F3A),
            Theme.of(context).primaryColor.withOpacity(0.3),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text(
            'Mis Canciones',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            GlassIconButton(
              icon: Icons.refresh_rounded,
              onPressed: _loadSongs,
              size: 48,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildMiniPlayer(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_hasPermission) {
      return Center(
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_off_rounded,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 24),
              const Text(
                'Se requiere permiso para leer archivos de audio',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              GlassButton(
                onPressed: _requestPermissionAndLoadSongs,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.settings, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Otorgar permiso',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Center(
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Escaneando canciones...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Center(
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 24),
              const Text(
                'No se encontraron canciones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: ListView.builder(
        itemCount: _songs.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final song = _songs[index];
          final isCurrentSong = _audioService.currentSong?.id == song.id;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              opacity: isCurrentSong ? 0.25 : 0.15,
              borderColor: isCurrentSong
                  ? Theme.of(context).primaryColor.withOpacity(0.5)
                  : Colors.white.withOpacity(0.2),
              borderWidth: isCurrentSong ? 2 : 1.5,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).colorScheme.secondary,
                        ],
                      ),
                    ),
                    child: QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      nullArtworkWidget: Icon(
                        Icons.music_note_rounded,
                        size: 30,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      artworkBorder: BorderRadius.zero,
                      artworkFit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isCurrentSong
                        ? FontWeight.bold
                        : FontWeight.w600,
                    color: isCurrentSong
                        ? Theme.of(context).primaryColor
                        : Colors.white,
                  ),
                ),
                subtitle: Text(
                  '${song.artist ?? "Artista desconocido"} • ${_formatDuration(song.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                trailing: isCurrentSong
                    ? Icon(
                        Icons.equalizer_rounded,
                        color: Theme.of(context).primaryColor,
                      )
                    : null,
                onTap: () {
                  _audioService.playSong(song, index);
                  // Actualizar notificación con la canción actual
                  audioHandler.setMediaItem(song);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PlayerScreen(),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        final currentSong = _audioService.currentSong;

        if (currentSong == null) {
          return const SizedBox.shrink();
        }

        final isPlaying = snapshot.data?.playing ?? false;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
          child: Container(
            height: 90,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.25),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Artwork con efecto glass
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                              ),
                            ),
                            child: QueryArtworkWidget(
                              id: currentSong.id,
                              type: ArtworkType.AUDIO,
                              nullArtworkWidget: _buildMiniVinyl(isPlaying),
                              artworkBorder: BorderRadius.zero,
                              artworkFit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      // Song info
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentSong.artist ?? 'Artista desconocido',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Controls
                      GlassIconButton(
                        icon: Icons.skip_previous_rounded,
                        onPressed: _audioService.playPrevious,
                        size: 44,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                        onPressed: _audioService.togglePlayPause,
                        size: 52,
                        color: Theme.of(context).primaryColor,
                        iconSize: 36,
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: Icons.skip_next_rounded,
                        onPressed: _audioService.playNext,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniVinyl(bool isPlaying) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isPlaying ? 1.0 : 0.0),
      duration: const Duration(seconds: 2),
      builder: (context, value, child) {
        return Transform.rotate(
          angle: value * 2 * 3.14159 * (isPlaying ? 100 : 0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Disco de vinilo mini
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.black, Colors.grey[900]!, Colors.black],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              // Etiqueta con dinosaurio
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: Center(
                  child: Transform.scale(
                    scale: isPlaying ? 1.0 : 0.9,
                    child: const Text('🦕', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

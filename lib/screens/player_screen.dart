import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import '../services/audio_player_service.dart';
import '../widgets/glass_card.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayerService _audioService = AudioPlayerService();
  late AnimationController _animationController;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _volume = _audioService.audioPlayer.volume;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = _audioService.currentSong;

    if (currentSong == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reproductor')),
        body: const Center(child: Text('No hay canción seleccionada')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0A0E27),
            const Color(0xFF1A1F3A),
            Theme.of(context).colorScheme.secondary.withOpacity(0.3),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text(
            'Reproduciendo',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          leading: GlassIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: () => Navigator.pop(context),
            size: 48,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // Album artwork
                  _buildArtwork(currentSong),

                  const SizedBox(height: 20),

                  // Song info
                  _buildSongInfo(currentSong),

                  const SizedBox(height: 20),

                  // Progress bar
                  _buildProgressBar(),

                  const SizedBox(height: 20),

                  // Playback controls
                  _buildControls(),

                  const SizedBox(height: 15),

                  // Shuffle and Repeat controls
                  _buildPlaybackModes(),

                  const SizedBox(height: 15),

                  // Volumen control
                  _buildVolumeControl(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(SongModel song) {
    return StreamBuilder<bool>(
      stream: _audioService.playerStateStream.map((state) => state.playing),
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        if (isPlaying && !_animationController.isAnimating) {
          _animationController.repeat();
        } else if (!isPlaying && _animationController.isAnimating) {
          _animationController.stop();
        }

        return Hero(
          tag: 'artwork_${song.id}',
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: FutureBuilder<Uint8List?>(
                      future: OnAudioQuery().queryArtwork(
                        song.id,
                        ArtworkType.AUDIO,
                      ),
                      builder: (context, snapshot) {
                        // Si hay portada, mostrarla circular y girando
                        if (snapshot.hasData && snapshot.data != null) {
                          return Center(
                            child: RotationTransition(
                              turns: _animationController,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.6),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        // Si no hay portada, mostrar el vinilo
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).colorScheme.secondary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Vinilo giratorio
                                RotationTransition(
                                  turns: _animationController,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Disco de vinilo negro
                                      Container(
                                        width: 180,
                                        height: 180,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.6,
                                              ),
                                              blurRadius: 20,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Surcos del vinilo
                                      ...List.generate(12, (index) {
                                        return Container(
                                          width: 75.0 + (index * 8.5),
                                          height: 75.0 + (index * 8.5),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.grey[800]!
                                                  .withOpacity(0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                        );
                                      }),
                                      // Luces del vinilo
                                      ...List.generate(2, (index) {
                                        final startAngle =
                                            (index * 180.0) * (math.pi / 180);
                                        return CustomPaint(
                                          size: const Size(180, 180),
                                          painter: LightSectorPainter(
                                            startAngle: startAngle,
                                            sweepAngle: 60 * (math.pi / 180),
                                          ),
                                        );
                                      }),
                                      // Etiqueta central blanca del disco (encima de las luces)
                                      Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: Image.asset(
                                            'assets/images/dinosaurio_bailando.gif',
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            color: isPlaying
                                                ? null
                                                : Colors.grey.withOpacity(0.5),
                                            colorBlendMode: isPlaying
                                                ? null
                                                : BlendMode.saturation,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongInfo(SongModel song) {
    return GlassCard(
      borderRadius: 25,
      opacity: 0.15,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Text(
            song.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            song.artist ?? 'Artista desconocido',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            song.album ?? 'Álbum desconocido',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _audioService.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: _audioService.durationStream,
          builder: (context, durationSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = durationSnapshot.data ?? Duration.zero;

            return ProgressBar(
              progress: position,
              total: duration,
              buffered: duration,
              onSeek: (duration) {
                _audioService.seek(duration);
              },
              barHeight: 6,
              thumbRadius: 8,
              thumbColor: Theme.of(context).primaryColor,
              thumbGlowRadius: 20,
              progressBarColor: Theme.of(context).primaryColor,
              baseBarColor: Colors.white.withOpacity(0.2),
              bufferedBarColor: Colors.white.withOpacity(0.3),
              timeLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildControls() {
    return StreamBuilder<bool>(
      stream: _audioService.playerStateStream.map((state) => state.playing),
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Previous button
            GlassIconButton(
              icon: Icons.skip_previous_rounded,
              onPressed: _audioService.playPrevious,
              size: 58,
            ),

            // Play/Pause button
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withOpacity(0.6),
                    blurRadius: 25,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: GlassIconButton(
                icon: isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                onPressed: _audioService.togglePlayPause,
                size: 72,
                color: Theme.of(context).primaryColor,
                iconSize: 44,
              ),
            ),

            // Next button
            GlassIconButton(
              icon: Icons.skip_next_rounded,
              onPressed: _audioService.playNext,
              size: 58,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackModes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle button
        GlassIconButton(
          icon: Icons.shuffle_rounded,
          onPressed: () {
            setState(() {
              _audioService.toggleShuffle();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.black.withOpacity(0.8),
                content: Text(
                  _audioService.isShuffleEnabled
                      ? 'Modo aleatorio activado'
                      : 'Modo aleatorio desactivado',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          size: 56,
          color: _audioService.isShuffleEnabled
              ? Theme.of(context).primaryColor
              : Colors.white,
        ),
        const SizedBox(width: 30),
        // Repeat button
        GlassIconButton(
          icon: _audioService.loopMode == LoopMode.off
              ? Icons.repeat_rounded
              : _audioService.loopMode == LoopMode.all
              ? Icons.repeat_rounded
              : Icons.repeat_one_rounded,
          onPressed: () {
            setState(() {
              _audioService.toggleLoopMode();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.black.withOpacity(0.8),
                content: Text(
                  _audioService.getLoopModeText(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          size: 56,
          color: _audioService.loopMode == LoopMode.off
              ? Colors.white
              : Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildVolumeControl() {
    return GlassCard(
      borderRadius: 20,
      opacity: 0.15,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(
            _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: Theme.of(context).primaryColor,
                inactiveTrackColor: Colors.white.withOpacity(0.2),
                thumbColor: Theme.of(context).primaryColor,
                overlayColor: Theme.of(context).primaryColor.withOpacity(0.2),
              ),
              child: Slider(
                value: _volume,
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  setState(() => _volume = value);
                  _audioService.setVolume(value);
                },
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Text(
              '${(_volume * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Painter para los sectores de luz en el vinilo
class LightSectorPainter extends CustomPainter {
  final double startAngle;
  final double sweepAngle;

  LightSectorPainter({required this.startAngle, required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Color sólido con blur para efecto de luz constante
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    // Crear sector circular que no sobrepase el disco
    final path = Path();
    path.moveTo(center.dx, center.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius - 1),
      startAngle,
      sweepAngle,
      false,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(LightSectorPainter oldDelegate) =>
      oldDelegate.startAngle != startAngle ||
      oldDelegate.sweepAngle != sweepAngle;
}

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lottie/lottie.dart';
import '../widgets/glass_card.dart';
import 'y2mate_dashboard.dart';

class DownloadHub extends StatefulWidget {
  const DownloadHub({super.key});

  @override
  State<DownloadHub> createState() => _DownloadHubState();
}

class _DownloadHubState extends State<DownloadHub> {
  int? _pressedIndex;
  final Map<String, bool> _lottieReady = {};

  // 'status': 'ready' | 'dev'
  final List<Map<String, String>> _services = [
    {
      'id': 'y2mate',
      'title': 'Y2Mate',
      'subtitle': 'Conversor rápido',
      'url': '',
      'status': 'ready',
      'lottie': 'https://assets9.lottiefiles.com/packages/lf20_tfb3estd.json',
      'image': 'https://via.placeholder.com/80?text=Y2M',
    },
    {
      'id': 'instasaved',
      'title': 'InstaSaved',
      'subtitle': 'Guardar Reels y Stories',
      'url': 'https://instasaved.net/es/save-video',
      'status': 'ready',
      'lottie': 'https://assets9.lottiefiles.com/packages/lf20_q5pk6p1k.json',
      'image': 'https://via.placeholder.com/80?text=IG',
    },
    {
      'id': 'fdown',
      'title': 'FDown',
      'subtitle': 'Descargas desde fdown.net',
      'url': 'https://www.fdown.net/',
      'status': 'ready',
      'lottie': 'https://assets9.lottiefiles.com/packages/lf20_jtbfg2nb.json',
      'image': 'https://via.placeholder.com/80?text=FD',
    },
    {
      'id': 'ssstik',
      'title': 'SSSTik',
      'subtitle': 'TikTok downloader',
      'url': 'https://ssstik.io/es',
      'status': 'ready', // cambiado a 'ready'
      'lottie': 'https://assets9.lottiefiles.com/packages/lf20_mjlh3hgp.json',
      'image': 'https://via.placeholder.com/80?text=TT',
    },
  ];

  @override
  void initState() {
    super.initState();
    // inicializar flags de Lottie
    for (final s in _services) {
      _lottieReady[s['id']!] = false;
    }
  }

  Color _colorForId(String id) {
    switch (id) {
      case 'instasaved':
        return const Color(0xFF5B8CFF);
      case 'fdown':
        return const Color(0xFF6EE7B7);
      case 'ssstik':
        return const Color(0xFF9B6CFF);
      default:
        return const Color(0xFF7C4DFF);
    }
  }

  void _open(BuildContext context, Map<String, String> svc) {
    final status = svc['status'] ?? 'ready';
    final url = svc['url'] ?? '';
    if (status != 'ready') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${svc['title']} está en desarrollo')),
      );
      return;
    }

    if (svc['id'] == 'y2mate') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const Y2MateDashboard()));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SimpleWebView(initialUrl: url, title: svc['title'] ?? 'Web'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = 16.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const Text(
                '¿Desde dónde quieres descargar?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Selecciona una fuente. Puedes añadir más servicios en cualquier momento.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  final cross = constraints.maxWidth > 700 ? 3 : 2;
                  return GridView.count(
                    crossAxisCount: cross,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                    children: List.generate(_services.length, (i) {
                      final svc = _services[i];
                      final color = _colorForId(svc['id']!);
                      final pressed = _pressedIndex == i;
                      final isDev = (svc['status'] ?? 'ready') != 'ready';
                      return Semantics(
                        button: true,
                        label: '${svc['title']}, ${svc['subtitle']}',
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _pressedIndex = i),
                          onTapCancel: () => setState(() => _pressedIndex = null),
                          onTapUp: (_) {
                            setState(() => _pressedIndex = null);
                            _open(context, svc);
                          },
                          child: AnimatedScale(
                            scale: pressed ? 0.98 : 1.0,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            child: GlassCard(
                              padding: const EdgeInsets.all(16),
                              borderRadius: 14,
                              color: null,
                              child: Stack(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          color.withOpacity(0.12),
                                          color.withOpacity(0.06),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.12),
                                          blurRadius: pressed ? 6 : 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: pressed ? color.withOpacity(0.18) : Colors.transparent,
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 56,
                                          width: 56,
                                          child: ClipOval(
                                            child: Container(
                                              color: color.withOpacity(0.06),
                                              child: Center(
                                                child: _buildAnimatedIcon(svc),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(svc['title'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 6),
                                        Text(
                                          svc['subtitle'] ?? '',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isDev)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.95),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text('En desarrollo',
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon(Map<String, String> svc) {
    final id = svc['id']!;
    final lottieUrl = svc['lottie'];
    final imageUrl = svc['image'];
    // Si no hay Lottie definido, mostrar imagen o icono
    if (lottieUrl == null || lottieUrl.isEmpty) {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return Image.network(imageUrl, width: 46, height: 46, fit: BoxFit.cover);
      }
      return Icon(_iconForId(id), color: _colorForId(id), size: 28);
    }

    // Mostrar fallback (imagen) hasta que Lottie notifique carga (onLoaded)
    return Stack(
      alignment: Alignment.center,
      children: [
        // fallback imagen estática (se ve hasta que Lottie se cargue)
        if (imageUrl != null && imageUrl.isNotEmpty)
          Image.network(imageUrl, width: 46, height: 46, fit: BoxFit.cover),
        // Lottie encima — cuando termina de cargar, se vuelve visible
        Opacity(
          opacity: _lottieReady[id]! ? 1.0 : 0.0,
          child: Lottie.network(
            lottieUrl,
            width: 46,
            height: 46,
            fit: BoxFit.contain,
            onLoaded: (composition) {
              // marca como lista para mostrar
              if (!mounted) return;
              setState(() {
                _lottieReady[id] = true;
              });
            },
          ),
        ),
      ],
    );
  }

  IconData _iconForId(String id) {
    switch (id) {
      case 'instasaved':
        return Icons.image;
      case 'fdown':
        return Icons.link;
      case 'ssstik':
        return Icons.movie;
      default:
        return Icons.cloud_download_rounded;
    }
  }
}

class _SimpleWebView extends StatefulWidget {
  const _SimpleWebView({required this.initialUrl, required this.title, Key? key}) : super(key: key);
  final String initialUrl;
  final String title;

  @override
  State<_SimpleWebView> createState() => _SimpleWebViewState();
}

class _SimpleWebViewState extends State<_SimpleWebView> {
  InAppWebViewController? _controller;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_progress < 1.0)
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(value: _progress),
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () async {
              final url = await _controller?.getUrl();
              if (url != null) {
                // copiar o abrir externo según prefieras
              }
            },
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            cacheEnabled: true,
          ),
        ),
        onWebViewCreated: (c) => _controller = c,
        onProgressChanged: (_, p) => setState(() => _progress = p / 100.0),
      ),
    );
  }
}
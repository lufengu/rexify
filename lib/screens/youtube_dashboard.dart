import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/glass_card.dart';
import '../services/permission_utils.dart';

/// Dashboard dedicado a YouTube: envuelve la web brindando experiencia tipo app.
/// NO modifica el dashboard existente de Y2Mate.
class YouTubeDashboard extends StatefulWidget {
  const YouTubeDashboard({super.key, this.initialUrl = 'https://www.youtube.com/'});
  final String initialUrl;

  @override
  State<YouTubeDashboard> createState() => _YouTubeDashboardState();
}

class _YouTubeDashboardState extends State<YouTubeDashboard> {
  InAppWebViewController? _controller;
  final TextEditingController _searchCtrl = TextEditingController();

  double _progress = 0;
  String _currentUrl = '';
  bool _uiHidden = false; // se oculta al hacer scroll down para efecto inmersivo
  bool _desktopMode = true; // user-agent modo escritorio
  bool _loading = true;
  bool _cleanInjected = false;
  bool _permissionsOk = true;

  // Estado de barra de acciones/contextual
  bool _showActions = true;
  // (Se eliminaron variables y lógica relacionadas con reproducir/descarga simulada)

  static const String _desktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.6668.100 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _ensurePermissions();
  }

  Future<void> _ensurePermissions() async {
    final ok = await PermissionUtils.ensureDownloadPermissions(publicTarget: true, isVideo: true);
    if (!mounted) return;
    setState(() => _permissionsOk = ok);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _goHome() => _load(widget.initialUrl);
  void _goBack() async { if (await _controller?.canGoBack() ?? false) _controller?.goBack(); }
  void _goForward() async { if (await _controller?.canGoForward() ?? false) _controller?.goForward(); }
  void _reload() => _controller?.reload();

  void _toggleUA() async {
    _desktopMode = !_desktopMode;
    await _controller?.setSettings(settings: InAppWebViewSettings(userAgent: _desktopMode ? _desktopUA : null));
    if (_currentUrl.isNotEmpty) _load(_currentUrl);
    setState(() {});
  }

  void _load(String url) async {
    if (url.trim().isEmpty) return;
    final normalized = _normalizeUrl(url.trim());
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
  }

  String _normalizeUrl(String input) {
    final lower = input.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return input;
    if (lower.contains('.') && !lower.contains(' ')) return 'https://$input';
    final encoded = Uri.encodeComponent(input);
    return 'https://www.youtube.com/results?search_query=$encoded';
  }

  Future<void> _onSearchSubmit() async {
    final text = _searchCtrl.text.trim();
    if (text.isEmpty) return;
    _load(text);
    setState(() { _showActions = true; });
  }

  String? _intentToHttps(String url) {
    try {
      final start = 'intent://';
      final idx = url.indexOf('#Intent');
      if (!url.startsWith(start) || idx == -1) return null;
      final path = url.substring(start.length, idx);
      final frag = url.substring(idx + '#Intent'.length);
      final schemeMatch = RegExp(r'scheme=([^;]+)').firstMatch(frag);
      final scheme = schemeMatch?.group(1) ?? 'https';
      return '$scheme://$path';
    } catch (_) { return null; }
  }

  Future<void> _maybeInjectCleaner() async {
    if (_cleanInjected) return;
    _cleanInjected = true;
    final js = """(function(){try{document.querySelectorAll('ytd-promoted-video-renderer, ytd-ad-slot-renderer, #ad-container').forEach(e=>e.remove());}catch(e){}})();""";
    try { await _controller?.evaluateJavascript(source: js); } catch (_) {}
  }

  Future<void> _captureUrlToClipboard() async {
    final data = _currentUrl;
    if (data.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copiada al portapapeles')));
  }

  Future<void> _savePageSnapshot() async {
    try {
      final shot = await _controller?.takeScreenshot();
      if (shot == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/youtube_snapshot_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(shot);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Snapshot guardado')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            _buildWebView(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                offset: _uiHidden ? const Offset(0, -1) : Offset.zero,
                child: _buildTopBar(cs),
              ),
            ),
            if (_progress < 1.0 && _loading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    if (!_permissionsOk) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text('Permisos de almacenamiento rechazados. Algunas funciones podrían limitarse.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    return Listener(
      onPointerSignal: (signal) {},
      child: InAppWebView(
        initialSettings: InAppWebViewSettings(
          userAgent: _desktopUA,
          javaScriptEnabled: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
        onWebViewCreated: (c) => _controller = c,
        onLoadStart: (c, url) {
          setState(() {
            _currentUrl = url?.toString() ?? '';
            _loading = true;
          });
        },
        onLoadStop: (c, url) async {
          setState(() {
            _currentUrl = url?.toString() ?? _currentUrl;
            _loading = false;
            _progress = 1.0;
          });
          await _maybeInjectCleaner();
        },
        onProgressChanged: (c, progress) {
          setState(() => _progress = progress / 100.0);
        },
        shouldOverrideUrlLoading: (c, navAction) async {
          final requestUrl = navAction.request.url?.toString() ?? '';
          if (requestUrl.startsWith('intent://')) {
            final https = _intentToHttps(requestUrl);
            if (https != null) {
              _load(https);
              return NavigationActionPolicy.CANCEL;
            }
          }
          return NavigationActionPolicy.ALLOW;
        },
        onScrollChanged: (c, x, y) {
          final hide = y > 120;
          if (hide != _uiHidden) {
            setState(() => _uiHidden = hide);
          }
        },
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    // Encabezado completamente mínimo (sin botón de cierre ni controles)
    return const SizedBox.shrink();
  }
}

/// Nota: Para integrar este dashboard en la app sin modificar el RootDashboard aún,
/// puedes hacer: Navigator.push(context, MaterialPageRoute(builder: (_) => const YouTubeDashboard()));
/// desde cualquier parte (por ejemplo, añadiendo un botón en la pantalla de Inicio).
/// Si en el futuro deseas agregarlo a NavigationBar, añade la instancia a la lista _pages
/// y un NavigationDestination, cuidando no alterar la lógica previa.

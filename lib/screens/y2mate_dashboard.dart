import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
// Reemplazamos webview_flutter por flutter_inappwebview para mayor compatibilidad tipo Chrome
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import '../services/backend_client.dart';
import '../widgets/glass_card.dart';
import '../services/download_logger.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';
import '../services/permission_utils.dart';
import '../services/audio_player_service.dart';
import 'settings_screen.dart';
import 'now_playing_screen.dart';

class Y2MateDashboard extends StatefulWidget {
  const Y2MateDashboard({super.key, this.backendBaseUrl = 'http://192.168.2.82:5000'});
  final String backendBaseUrl;

  @override
  State<Y2MateDashboard> createState() => _Y2MateDashboardState();
}

class _Y2MateDashboardState extends State<Y2MateDashboard> {
  late final BackendClient _client;
  InAppWebViewController? _inappController; // controlador avanzado

  // Capturas y estado
  final _capturedCtrl = TextEditingController();
  String _currentPage = '';
  bool _downloading = false;
  int _received = 0;
  int _total = -1;
  String? _status;
  File? _lastFile;
  final _player = AudioPlayer(); // reproductor interno sólo para previews rápidas
  final AudioPlayerService _globalPlayer = AudioPlayerService();
  bool _savePublic = true;
  bool _cleanMode = true; // modo limpio para ocultar anuncios/popups

  @override
  void initState() {
    super.initState();
    _client = BackendClient(baseUrl: widget.backendBaseUrl);
  }

  // User-Agent tipo Chrome desktop (ayuda contra bloqueos de sitios que detectan WebView móvil)
  static const String _desktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.6668.100 Safari/537.36';

  // Helper para cargar URL con controlador si ya existe
  Future<void> _load(String url) async {
    final c = _inappController;
    if (c == null) return;
    await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  @override
  void dispose() {
    _player.dispose();
    _capturedCtrl.dispose();
    super.dispose();
  }

  // Convierte un intent://...#Intent;scheme=https;...;end a https://...
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
    } catch (_) {
      return null;
    }
  }

  // Inyecta CSS/JS para ocultar anuncios y prevenir popups intrusivos.
  Future<void> _injectCleaner({int delayMs = 0}) async {
    final js = '''(function(){
      try {
        const run = ()=>{ 
          const style = document.getElementById('rexify-clean-style') || (function(){
            const s = document.createElement('style');
            s.id='rexify-clean-style';
            s.textContent = `
              /* Ocultar bloques típicos de anuncios */
              iframe[src*="ads"], iframe[id*="ads"],
              [class*="ad" i], [id*="ad" i],
              .ads, .adsbox, .ad-container, .ad, .banner, .popup, .pop, .modal-backdrop,
              div[style*="z-index: 9999"],
              [class*="overlay" i], [id*="overlay" i]
              {display:none !important; visibility:hidden !important; opacity:0 !important;}
              body {overflow-y:auto !important;}
            `;
            document.head.appendChild(s);
            return s;
          })();
          // Remover atributos inline que bloqueen scroll
          document.body.style.position='static';
          document.body.style.overflow='auto';
          // Eliminar nodos intrusivos existentes
          const selectors=['iframe','div','section','aside'];
          selectors.forEach(sel=>{
            document.querySelectorAll(sel).forEach(el=>{
              try{
                const cl = (el.className||'').toLowerCase();
                const id = (el.id||'').toLowerCase();
                const suspicious = ['ad','ads','banner','popup','overlay','modal'];
                if(suspicious.some(k=>cl.includes(k) || id.includes(k))){ el.remove(); }
              }catch(e){}
            });
          });
          // Bloquear funciones popup
          const noop = function(){};
          window.open = function(){ return null; };
          window.alert = noop; window.confirm = noop; window.prompt = noop;
          // MutationObserver para remover nuevos anuncios
          if(!window.__rexifyObserver){
            window.__rexifyObserver = new MutationObserver(muts=>{
              muts.forEach(m=>{
                m.addedNodes && m.addedNodes.forEach(n=>{
                  if(n.nodeType===1){
                    const cl=(n.className||'').toLowerCase();
                    const id=(n.id||'').toLowerCase();
                    const suspicious=['ad','ads','banner','popup','overlay','modal'];
                    if(suspicious.some(k=>cl.includes(k) || id.includes(k))){
                      n.remove();
                    }
                  }
                });
              });
            });
            window.__rexifyObserver.observe(document.documentElement,{childList:true,subtree:true});
          }
        };
        if(${delayMs}>0) setTimeout(run, ${delayMs}); else run();
      } catch(e){}
    })();''';
    try { await _inappController?.evaluateJavascript(source: js); } catch (_) {}
  }

  // Intenta leer el valor del input de la página para capturar el enlace/consulta
  Future<void> _captureFromPage() async {
    try {
      final js = '''
        (function(){
          function looksLikeUrl(v){
            if(!v) return false;
            v = v.trim();
            return /^https?:\/\//i.test(v) || /youtube\.com|youtu\.be|y2mate/i.test(v);
          }
          const selects = [
            'input[name="k_query"]',
            'input[name="search_query"]',
            '#txt-url', '#txtUrl', '#url',
            'input[type="url"]', 'input[type="text"]'
          ];
          for (const sel of selects) {
            const el = document.querySelector(sel);
            if (el && looksLikeUrl(el.value)) { return el.value; }
          }
          const inputs = Array.from(document.querySelectorAll('input'));
          for (const el of inputs) { if (looksLikeUrl(el.value)) return el.value; }
          return '';
        })();
      ''';
      final raw = await _inappController?.evaluateJavascript(source: js);
      final value = (raw is String) ? raw : (raw?.toString() ?? '');
      if (value.isNotEmpty) {
        _capturedCtrl.text = value.trim();
        setState((){});
        await DownloadLogger.instance.logJson({'event': 'y2mate_capture_ok', 'value': value});
      } else {
        await DownloadLogger.instance.logJson({'event': 'y2mate_capture_empty'});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No pude detectar un enlace en la página. Pega uno manualmente.')),
          );
        }
      }
    } catch (e) {
      await DownloadLogger.instance.logJson({'event': 'y2mate_capture_error', 'error': e.toString()});
    }
  }

  Future<bool> _ensureExternalPermission({bool isVideo = false}) async {
    return PermissionUtils.ensureDownloadPermissions(publicTarget: _savePublic, isVideo: isVideo);
  }

  Future<void> _download({required bool video}) async {
    final q = _capturedCtrl.text.trim().isEmpty ? _currentPage : _capturedCtrl.text.trim();
    if (q.isEmpty) return;
    if (!await _ensureExternalPermission(isVideo: video)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso denegado para guardar en almacenamiento externo.')),
        );
      }
      return;
    }
    setState(() {
      _downloading = true;
      _received = 0;
      _total = -1;
      _status = 'Preparando descarga...';
    });
    try {
      final file = await _client.downloadSongMp3(
        q,
        saveToExternal: _savePublic,
        format: video ? 'mp4' : 'mp3',
        video: video,
        onProgress: (r, t) {
          if (!mounted) return;
          setState(() {
            _received = r;
            _total = t;
            _status = t > 0 ? 'Descargando ${(r * 100 / t).clamp(0, 100).toStringAsFixed(0)}%' : 'Descargando...';
          });
        },
      );
      _lastFile = file;
      await DownloadLogger.instance.logJson({'event': 'y2mate_web_download_ok', 'path': file.path, 'video': video});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Guardado: ${file.path.split(Platform.pathSeparator).last}')),
        );
      }
      // NO AUTOPLAY: no llamar a _player.play() ni a AudioPlayerService.playFile()
    } catch (e) {
      await DownloadLogger.instance.logJson({'event': 'y2mate_web_download_error', 'error': e.toString(), 'video': video});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _status = null; });
    }
  }

  double get _progress => (_total > 0 && _received >= 0) ? _received / _total : 0;

  // Descarga directa interceptada desde el navegador (cuando el sitio genera link directo)
  Future<void> _handleDirectDownload(String url, {String? contentDisposition}) async {
    if (!await _ensureExternalPermission(isVideo: url.toLowerCase().endsWith('.mp4'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso de almacenamiento denegado')));
      }
      return;
    }
    setState(() {
      _downloading = true;
      _received = 0;
      _total = -1;
      _status = 'Descargando archivo directo...';
    });
    HttpClient client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      // Headers para simular navegador real
      req.headers.set(HttpHeaders.userAgentHeader, _desktopUA);
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'es-ES,es;q=0.9,en;q=0.8');
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set('Sec-Fetch-Dest', 'document');
      req.headers.set('Sec-Fetch-Mode', 'navigate');
      req.headers.set('Sec-Fetch-Site', 'same-origin');
      final resp = await req.close();
      final cd = contentDisposition ?? resp.headers.value('content-disposition');
      String filename;
      if (cd != null && cd.contains('filename=')) {
        filename = cd.split('filename=').last.replaceAll('"', '').trim();
      } else {
        filename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'download.bin';
      }
      // Guardamos primero en documentos de la app para asegurar disponibilidad
      final saveDir = await getApplicationDocumentsDirectory();
      final file = File('${saveDir.path}/$filename');
      final sink = file.openWrite();
      int received = 0;
      final total = resp.contentLength;
      await for (final chunk in resp) {
        received += chunk.length;
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _received = received;
            _total = total;
            if (total > 0) {
              _status = 'Directo ${(received * 100 / total).clamp(0, 100).toStringAsFixed(0)}%';
            }
          });
        }
      }
      await sink.close();

      // Si el usuario eligió "Público", intentar registrar en MediaStore (Android) para hacerlo visible
      if (_savePublic && Platform.isAndroid) {
        try {
          const MethodChannel channel = MethodChannel('rexify/media_store');
          String mime;
          final lower = filename.toLowerCase();
          if (lower.endsWith('.mp3')) mime = 'audio/mpeg';
          else if (lower.endsWith('.m4a')) mime = 'audio/mp4';
          else if (lower.endsWith('.mp4')) mime = 'video/mp4';
          else mime = 'application/octet-stream';
          await channel.invokeMethod('saveToMediaStore', {
            'path': file.path,
            'displayName': filename,
            'mime': mime,
          });
          // Opcional: solicitar escaneo
          try { await channel.invokeMethod('scanFile', {'path': file.path}); } catch (_) {}
        } catch (_) {
          // Fallback: archivo queda en documentos
        }
      }

      _lastFile = file;
      await DownloadLogger.instance.logJson({'event': 'direct_download_ok', 'url': url, 'path': file.path});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descargado directo: $filename')));
      }
      // NO AUTOPLAY
    } catch (e) {
      await DownloadLogger.instance.logJson({'event': 'direct_download_error', 'url': url, 'error': e.toString()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error directo: $e')));
      }
    } finally {
      if (mounted) setState(() { _downloading = false; _status = null; });
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context),
              // Barra de progreso global/visible mientras se descarga un archivo
              if (_downloading)
                LinearProgressIndicator(
                  value: _total > 0 ? _progress.clamp(0.0, 1.0) : null,
                  minHeight: 4,
                  backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.3),
                ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri('https://y2mate.nu/es-ei28/')),
                    initialSettings: InAppWebViewSettings(
                      userAgent: _desktopUA,
                      javaScriptEnabled: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      useOnDownloadStart: true,
                      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      mediaPlaybackRequiresUserGesture: false,
                      cacheEnabled: true,
                      domStorageEnabled: true,
                      supportZoom: true,
                      builtInZoomControls: true,
                      transparentBackground: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                    onWebViewCreated: (controller) async {
                      _inappController = controller;
                      try {
                        await CookieManager.instance().setCookie(
                          url: WebUri('https://y2mate.nu'),
                          name: 'rexify_init',
                          value: DateTime.now().millisecondsSinceEpoch.toString(),
                        );
                      } catch (_) {}
                    },
                    onLoadStart: (controller, url) {
                      setState(() => _currentPage = url?.toString() ?? _currentPage);
                      if (_cleanMode) _injectCleaner(delayMs: 150);
                    },
                    onLoadStop: (controller, url) async {
                      setState(() => _currentPage = url?.toString() ?? _currentPage);
                      if (_cleanMode) _injectCleaner(delayMs: 0);
                    },
                    shouldOverrideUrlLoading: (controller, nav) async {
                      final url = nav.request.url?.toString() ?? '';
                      if (url.startsWith('intent://')) {
                        final redirect = _intentToHttps(url);
                        if (redirect != null) {
                          _load(redirect);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bloqueado intent://')));
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      final blockedSchemes = ['market://', 'tel:', 'mailto:', 'whatsapp:', 'vnd.'];
                      if (blockedSchemes.any((s) => url.startsWith(s))) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Esquema no soportado: $url')));
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onDownloadStartRequest: (controller, request) async {
                      final url = request.url.toString();
                      await DownloadLogger.instance.logJson({'event': 'webview_download_start', 'url': url});
                      _handleDirectDownload(url, contentDisposition: request.contentDisposition);
                    },
                    onJsAlert: (controller, jsAlertRequest) async {
                      if (_cleanMode) {
                        return JsAlertResponse(handledByClient: true, action: JsAlertResponseAction.CONFIRM);
                      }
                      return JsAlertResponse(handledByClient: false, action: JsAlertResponseAction.CONFIRM);
                    },
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: _lastFile != null ? 86 : 12,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _capturedCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Enlace / consulta para descargar',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _downloading ? null : () => _download(video: false),
                          icon: const Icon(Icons.music_note_rounded),
                          label: const Text('Audio MP3'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _downloading ? null : () => _download(video: true),
                          icon: const Icon(Icons.videocam_rounded),
                          label: const Text('Video MP4'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          const Text('Público', style: TextStyle(fontSize: 11)),
                          Transform.scale(
                            scale: 0.85,
                            child: Switch(
                              value: _savePublic,
                              onChanged: (v) => setState(() => _savePublic = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_downloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _total > 0 ? _progress : null),
                    if (_status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_status!, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_lastFile != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.file_download_done_rounded, color: Theme.of(context).colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastFile!.path.split(Platform.pathSeparator).last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          // Reproducción manual del archivo descargado usando el servicio global
                          await AudioPlayerService().playFile(_lastFile!);
                          // Abrir reproductor completo para control
                          if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen()));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se puede reproducir: $e')));
                        }
                      },
                      child: const Text('REPRODUCIR'),
                    ),
                    TextButton(
                      onPressed: () => OpenFile.open(_lastFile!.path),
                      child: const Text('ABRIR'),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<PlayerState>(
      stream: _globalPlayer.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return Container(
          padding: const EdgeInsets.only(top: 12, left: 16, right: 16, bottom: 10),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.85),
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const Icon(Icons.cloud_download_rounded, size: 28),
                const SizedBox(width: 8),
                const Text('Rexify Downloader', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: _currentPage.isEmpty ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _currentPage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Capturar enlace',
                  icon: const Icon(Icons.link_rounded),
                  onPressed: _captureFromPage,
                ),
                IconButton(
                  tooltip: 'Recargar',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _inappController?.reload(),
                ),
                Tooltip(
                  message: 'Modo limpio (oculta anuncios)',
                  child: Switch(
                    value: _cleanMode,
                    onChanged: (v) {
                      setState(() => _cleanMode = v);
                      if (v) _injectCleaner(delayMs: 50);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Ajustes',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
                IconButton(
                  tooltip: 'Ir al reproductor',
                  icon: Icon(playing ? Icons.equalizer_rounded : Icons.play_circle_fill_rounded),
                  color: playing ? cs.primary : null,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen())),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

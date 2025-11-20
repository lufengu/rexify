import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DashboardXX extends StatelessWidget {
  const DashboardXX({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_SiteInfo>[
      _SiteInfo(
        name: 'Xvideos',
        url: Uri.parse('https://www.xvideos.com'),
        icon: Icons.explicit_outlined,
        desc: 'Videos para adultos',
        color: const Color(0xFFE53935),
      ),
      _SiteInfo(
        name: 'Pornhub',
        url: Uri.parse('https://www.pornhub.com'),
        icon: Icons.explicit_outlined,
        desc: 'Contenido +18',
        color: const Color(0xFFff9900),
      ),
      _SiteInfo(
        name: 'XHamster',
        url: Uri.parse('https://xhamster.com'),
        icon: Icons.explicit_outlined,
        desc: 'Entretenimiento adulto',
        color: const Color(0xFF8E24AA),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard XX'),
        actions: [
          IconButton(
            tooltip: 'Cambiar tema (pendiente)',
            onPressed: () {},
            icon: const Icon(Icons.dark_mode_outlined),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.05,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final site = items[i];
            return _SiteCard(site: site, onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => XXWebViewScreen(site: site)),
              );
            });
          },
        ),
      ),
    );
  }
}

class _SiteInfo {
  final String name;
  final Uri url;
  final IconData icon;
  final String desc;
  final Color color;
  const _SiteInfo({required this.name, required this.url, required this.icon, required this.desc, required this.color});
}

class _SiteCard extends StatefulWidget {
  final _SiteInfo site;
  final VoidCallback onTap;
  const _SiteCard({required this.site, required this.onTap});

  @override
  State<_SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<_SiteCard> with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return MouseRegion(
      onEnter: (_) => setState(() => _scale = 0.98),
      onExit: (_) => setState(() => _scale = 1.0),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _scale,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _scale = 0.98),
          onTapUp: (_) => setState(() => _scale = 1.0),
          onTapCancel: () => setState(() => _scale = 1.0),
          onTap: widget.onTap,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: site.color.withOpacity(0.2),
                    child: Icon(site.icon, color: site.color, size: 28),
                  ),
                  const Spacer(),
                  Text(site.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(site.desc, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class XXWebViewScreen extends StatefulWidget {
  final _SiteInfo site;
  const XXWebViewScreen({super.key, required this.site});

  @override
  State<XXWebViewScreen> createState() => _XXWebViewScreenState();
}

class _XXWebViewScreenState extends State<XXWebViewScreen> {
  late final WebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
        ),
      )
      ..loadRequest(widget.site.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.site.name)),
      body: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(value: _progress),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

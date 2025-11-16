import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';

/// Pantalla de Ajustes (placeholder). Define espacio para futuras opciones:
/// - Calidad de descarga
/// - Ubicación de almacenamiento
/// - Preferencias de limpieza de anuncios
/// - Tema (oscuro/claro)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')), 
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Preferencias', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Reproductor',
            children: [
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('Modo aleatorio'),
                subtitle: Text(player.isShuffleEnabled ? 'Activado' : 'Desactivado'),
                trailing: Switch(
                  value: player.isShuffleEnabled,
                  onChanged: (_) async {
                    await player.toggleShuffle();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: const Text('Modo repetición'),
                subtitle: Text(player.getLoopModeText()),
                onTap: () async { await player.toggleLoopMode(); },
              ),
            ],
          ),
          _SectionCard(
            title: 'Descargas',
            children: const [
              ListTile(
                leading: Icon(Icons.folder_rounded),
                title: Text('Directorio público'),
                subtitle: Text('Configurar destino por defecto (Pendiente)'),
              ),
              ListTile(
                leading: Icon(Icons.high_quality_rounded),
                title: Text('Calidad preferida'),
                subtitle: Text('Automático (Pendiente)'),
              ),
            ],
          ),
          _SectionCard(
            title: 'Interfaz',
            children: const [
              ListTile(
                leading: Icon(Icons.dark_mode_rounded),
                title: Text('Tema oscuro'),
                subtitle: Text('Siempre oscuro (Pendiente toggle)'),
              ),
              ListTile(
                leading: Icon(Icons.color_lens_rounded),
                title: Text('Color de acento'),
                subtitle: Text('Morado (Pendiente selector)'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('v1.0.0 • Rexify', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54)),
          )
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/xx_auth_service.dart';
import 'xx_dashboard.dart';

/// Frame: CrearContraseñaPrivada
class CrearContrasenaPrivada extends StatefulWidget {
  const CrearContrasenaPrivada({super.key});

  @override
  State<CrearContrasenaPrivada> createState() => _CrearContrasenaPrivadaState();
}

class _CrearContrasenaPrivadaState extends State<CrearContrasenaPrivada> {
  final _auth = XXAuthService();
  final _pwdCtrl = TextEditingController();
  final _pwd2Ctrl = TextEditingController();
  bool _obscure = true;
  bool _remember = false;
  String? _message;
  bool _saving = false;

  int _score(String s) {
    int score = 0;
    if (s.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(s)) score++;
    if (RegExp(r'[a-z]').hasMatch(s)) score++;
    if (RegExp(r'[0-9]').hasMatch(s)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(s)) score++;
    return score; // 0..5
  }

  Color _scoreColor(int score) {
    switch (score) {
      case 0:
      case 1:
        return Colors.redAccent;
      case 2:
        return Colors.orangeAccent;
      case 3:
        return Colors.amber;
      case 4:
        return Colors.lightGreen;
      default:
        return Colors.green;
    }
  }

  Future<void> _save() async {
    final p1 = _pwdCtrl.text;
    final p2 = _pwd2Ctrl.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _message = 'Completa ambos campos.');
      return;
    }
    if (p1 != p2) {
      setState(() => _message = 'Las contraseñas no coinciden.');
      return;
    }
    if (_score(p1) < 3) {
      setState(() => _message = 'Contraseña débil. Usa 8+ caracteres, mayúsculas, números y símbolos.');
      return;
    }
    setState(() { _saving = true; _message = null; });
  await _auth.setPassword(p1);
  _auth.setSessionRemember(_remember);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardXX()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = _score(_pwdCtrl.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Contraseña privada')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 64),
                const SizedBox(height: 12),
                Text('Crea tu contraseña de acceso', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 20),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: _obscure,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwd2Ctrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (score / 5).clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(_scoreColor(score)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      ['Muy débil', 'Débil', 'Media', 'Buena', 'Fuerte', 'Excelente'][score],
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Recordar contraseña'),
                  subtitle: const Text('No solicitarla nuevamente en este dispositivo.'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Guardar'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

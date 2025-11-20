import 'package:flutter/material.dart';
import '../services/xx_auth_service.dart';
import 'xx_dashboard.dart';
import 'xx_age_verification.dart';

class XXLogin extends StatefulWidget {
  const XXLogin({super.key});

  @override
  State<XXLogin> createState() => _XXLoginState();
}

class _XXLoginState extends State<XXLogin> {
  final _auth = XXAuthService();
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _remember = false;
  bool _loading = false;
  String? _message;

  Future<void> _submit() async {
    final pwd = _ctrl.text;
    if (pwd.isEmpty) {
      setState(() => _message = 'Ingresa tu contraseña.');
      return;
    }
    setState(() { _loading = true; _message = null; });
    final ok = await _auth.verifyPassword(pwd);
    if (ok) {
  _auth.setSessionRemember(_remember);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardXX()),
      );
    } else {
      if (!mounted) return;
      setState(() { _loading = false; _message = 'Contraseña incorrecta.'; });
    }
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer acceso'),
        content: const Text(
          'Esto borrará tu contraseña y volverá a solicitar verificación de edad. ¿Deseas continuar?'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restablecer')),
        ],
      ),
    );
    if (confirm != true) return;
    await _auth.resetAll();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const VerificacionEdad()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso privado')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_person_outlined, size: 64),
                const SizedBox(height: 12),
                Text('Introduce tu contraseña', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Recordar contraseña'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Acceder'),
                ),
                TextButton(
                  onPressed: _loading ? null : _reset,
                  child: const Text('¿Olvidaste tu contraseña? Restablecer'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/xx_auth_service.dart';
import 'xx_create_password.dart';

/// Frame: VerificacionEdad
class VerificacionEdad extends StatefulWidget {
  const VerificacionEdad({super.key});

  @override
  State<VerificacionEdad> createState() => _VerificacionEdadState();
}

class _VerificacionEdadState extends State<VerificacionEdad> {
  final _auth = XXAuthService();
  DateTime? _dob;
  String? _message;
  bool _validating = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 18, now.month, now.day);
    final first = DateTime(now.year - 100);
    final last = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      builder: (context, child) {
        // Forzar modo oscuro coherente
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).colorScheme.primary,
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _message = null;
      });
    }
  }

  Future<void> _validate() async {
    if (_dob == null) {
      setState(() => _message = 'Por favor selecciona tu fecha de nacimiento.');
      return;
    }
    setState(() { _validating = true; _message = null; });
    final ok = await _auth.setBirthdate(_dob!);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _validating = false);
    if (ok) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CrearContrasenaPrivada()),
      );
    } else {
      setState(() {
        _message = 'Este contenido no está disponible para menores de edad.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _dob == null
        ? 'Selecciona fecha de nacimiento'
        : DateFormat.yMMMMd('es').format(_dob!);

    return Scaffold(
      appBar: AppBar(title: const Text('Verificación de edad')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.privacy_tip_outlined, size: 64),
                const SizedBox(height: 12),
                Text(
                  'Acceso a contenido para adultos',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Para continuar, verifica que tienes 18 años o más.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _validating ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(label),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _validating ? null : _validate,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _validating
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Validar edad'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 8),
                Text(
                  'Tu fecha se usa solo para validar tu mayoría de edad.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

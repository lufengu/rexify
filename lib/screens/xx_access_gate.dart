import 'package:flutter/material.dart';
import '../services/xx_auth_service.dart';
import 'xx_age_verification.dart';
import 'xx_create_password.dart';
import 'xx_login.dart';
import 'xx_dashboard.dart';

/// Punto de entrada al flujo privado del Dashboard XX.
/// Decide a dónde navegar según el estado actual (edad/contraseña/recordar).
class XXAccessGate extends StatefulWidget {
  const XXAccessGate({super.key});

  @override
  State<XXAccessGate> createState() => _XXAccessGateState();
}

class _XXAccessGateState extends State<XXAccessGate> {
  final _auth = XXAuthService();

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // Pequeño delay para permitir animación/splash del loader
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final verified = await _auth.isAgeVerified();
    if (!verified) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerificacionEdad()),
      );
      return;
    }

    final hasPwd = await _auth.hasPassword();
    if (!hasPwd) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CrearContrasenaPrivada()),
      );
      return;
    }

  final skip = _auth.shouldSkipPassword();
    if (skip) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardXX()),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const XXLogin()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

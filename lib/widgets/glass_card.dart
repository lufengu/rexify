import 'dart:ui';
import 'package:flutter/material.dart';

/// GlassCard minimalista — sin marcas de agua ni imágenes decorativas.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final BoxConstraints? constraints;
  final double opacity;

  const GlassCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 16.0,
    this.color,
    this.constraints,
    this.opacity = 0.06,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withOpacity(opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: cs.onSurface.withOpacity(0.06)),
      ),
      child: child,
    );
  }
}

class GlassButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double opacity;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = 15,
    this.padding,
    this.color,
    this.opacity = 0.12,
  });

  EdgeInsets _resolvePadding(BuildContext context) {
    // Queremos asegurar un EdgeInsets concreto para evitar conflictos de tipos.
    if (padding == null) return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
    if (padding is EdgeInsets) return padding as EdgeInsets;
    // Esto resuelve EdgeInsetsDirectional y otros EdgeInsetsGeometry a EdgeInsets
    return padding!.resolve(Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: GlassCard(
          borderRadius: borderRadius,
          padding: _resolvePadding(context),
          color: color,
          opacity: opacity,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final double size;
  final Color? color;
  final double? iconSize;
  final double blurSigma;

  const GlassIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 56,
    this.color,
    this.iconSize,
    this.blurSigma = 10,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.onSurface.withOpacity(0.08),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: color ?? cs.onSurface,
                  size: iconSize ?? (size * 0.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

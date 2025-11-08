import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final BorderRadius? customBorderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final double? borderWidth;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 10,
    this.opacity = 0.15,
    this.customBorderRadius,
    this.padding,
    this.borderColor,
    this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: customBorderRadius ?? BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius:
                customBorderRadius ?? BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.2),
              width: borderWidth ?? 1.5,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.05),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = 15,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: GlassCard(
          borderRadius: borderRadius,
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          opacity: 0.2,
          child: child,
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

  const GlassIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 56,
    this.color,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
              ),
              child: Icon(
                icon,
                color: color ?? Colors.white,
                size: iconSize ?? (size * 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

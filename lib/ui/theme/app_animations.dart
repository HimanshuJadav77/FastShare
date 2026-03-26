import 'package:flutter/material.dart';

class AppAnimations {
  /// Standard iOS Page Transition (Slide + Fade)
  static Route createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 0.05); // Subtle slide up
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        var slideAnimation = animation.drive(Tween(begin: begin, end: end).chain(CurveTween(curve: curve)));
        var fadeAnimation = animation.drive(Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve)));

        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }

  /// Reusable Scale-on-Tap effect for buttons
  static Widget scaleOnTap({
    required Widget child,
    required VoidCallback? onTap,
    double scale = 0.96,
  }) {
    return _ScaleOnTapWrapper(
      onTap: onTap,
      scale: scale,
      child: child,
    );
  }
}

class _ScaleOnTapWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const _ScaleOnTapWrapper({required this.child, this.onTap, required this.scale});

  @override
  State<_ScaleOnTapWrapper> createState() => _ScaleOnTapWrapperState();
}

class _ScaleOnTapWrapperState extends State<_ScaleOnTapWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.onTap != null ? _controller.forward() : null,
      onTapUp: (_) {
        if (widget.onTap != null) {
          _controller.reverse();
          widget.onTap!();
        }
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

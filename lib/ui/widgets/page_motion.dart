import 'package:flutter/material.dart';

class QParkPageTransitions extends PageTransitionsBuilder {
  const QParkPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved.drive(
          Tween(begin: const Offset(0, .025), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}

/// Animate the visible stack without replacing page states or scroll storage.
class PageMotion extends StatefulWidget {
  const PageMotion({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;
  @override
  State<PageMotion> createState() => _PageMotionState();
}

class _PageMotionState extends State<PageMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final Animation<double> opacity = controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  bool get reduced => MediaQuery.disableAnimationsOf(context);
  @override
  void didUpdateWidget(covariant PageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (reduced) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduced) controller.value = 1;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: opacity,
    child: IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(enabled: i == widget.index, child: widget.children[i]),
      ],
    ),
  );
}

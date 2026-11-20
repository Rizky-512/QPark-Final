import 'package:flutter/material.dart';
import '../common.dart';

/// InkWell supplies keyboard activation, focus and semantics as well as touch.
class InteractiveCard extends StatefulWidget {
  const InteractiveCard({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
  });
  final Widget child;
  final VoidCallback onTap;
  final bool selected;
  @override
  State<InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<InteractiveCard> {
  bool pressed = false, hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    return AnimatedScale(
      scale: pressed ? .98 : 1,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          color: widget.selected ? const Color(0xFFEAF5ED) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: focused || widget.selected
                ? AppColors.primary
                : hovered
                ? AppColors.muted
                : AppColors.border,
            width: focused ? 2 : 1,
          ),
          boxShadow: hovered
              ? const [
                  BoxShadow(
                    color: Color(0x12166534),
                    blurRadius: 18,
                    offset: Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTap,
            onHover: (v) => setState(() => hovered = v),
            onFocusChange: (v) => setState(() => focused = v),
            onHighlightChanged: (v) => setState(() => pressed = v),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

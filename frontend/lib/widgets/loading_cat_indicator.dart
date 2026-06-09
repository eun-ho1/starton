import 'package:flutter/material.dart';

class LoadingCatIndicator extends StatefulWidget {
  const LoadingCatIndicator({
    super.key,
    this.size = 112,
    this.floatDistance = 8,
  });

  final double size;
  final double floatDistance;

  @override
  State<LoadingCatIndicator> createState() => _LoadingCatIndicatorState();
}

class _LoadingCatIndicatorState extends State<LoadingCatIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _floatOffset = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size + widget.floatDistance,
      child: AnimatedBuilder(
        animation: _floatOffset,
        builder: (context, child) {
          final offset = (0.5 - _floatOffset.value) * widget.floatDistance;
          return Transform.translate(offset: Offset(0, offset), child: child);
        },
        child: Image.asset(
          'assets/loadingcat.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

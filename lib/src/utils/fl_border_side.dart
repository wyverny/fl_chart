import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum FlBorderStyle {
  none,
  solid,
  dotted,
}

@immutable
class FlBorderSide with EquatableMixin {
  const FlBorderSide({
    this.color = const Color(0xFF000000),
    this.width = 1.0,
    this.style = FlBorderStyle.solid,
    this.strokeAlign = -1.0,
  });

  static const FlBorderSide none = FlBorderSide(
    width: 0.0,
    style: FlBorderStyle.none,
  );

  final Color color;
  final double width;
  final FlBorderStyle style;
  final double strokeAlign;

  bool get isVisible =>
      style != FlBorderStyle.none && width != 0.0 && color.a != 0.0;

  static FlBorderSide lerp(FlBorderSide a, FlBorderSide b, double t) {
    return FlBorderSide(
      color: Color.lerp(a.color, b.color, t) ?? b.color,
      width: lerpDouble(a.width, b.width, t) ?? b.width,
      style: t < 0.5 ? a.style : b.style,
      strokeAlign: lerpDouble(a.strokeAlign, b.strokeAlign, t) ?? b.strokeAlign,
    );
  }

  @override
  List<Object?> get props => [
        color,
        width,
        style,
        strokeAlign,
      ];
}

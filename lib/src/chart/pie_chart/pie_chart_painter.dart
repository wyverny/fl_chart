import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/base/base_chart/base_chart_painter.dart';
import 'package:fl_chart/src/chart/base/line.dart';
import 'package:fl_chart/src/chart/pie_chart/pie_chart_data.dart';
import 'package:fl_chart/src/extensions/paint_extension.dart';
import 'package:fl_chart/src/extensions/path_extension.dart';
import 'package:fl_chart/src/utils/canvas_wrapper.dart';
import 'package:fl_chart/src/utils/utils.dart';
import 'package:flutter/material.dart';

/// Paints [PieChartData] in the canvas, it can be used in a [CustomPainter]
class PieChartPainter extends BaseChartPainter<PieChartData> {
  /// Paints [dataList] into canvas, it is the animating [PieChartData],
  /// [targetData] is the animation's target and remains the same
  /// during animation, then we should use it  when we need to show
  /// tooltips or something like that, because [dataList] is changing constantly.
  ///
  /// [textScale] used for scaling texts inside the chart,
  /// parent can use [MediaQuery.textScaleFactor] to respect
  /// the system's font size.
  PieChartPainter() : super() {
    _sectionPaint = Paint()..style = PaintingStyle.stroke;

    _sectionSaveLayerPaint = Paint();

    _sectionStrokePaint = Paint()..style = PaintingStyle.stroke;

    _centerSpacePaint = Paint()..style = PaintingStyle.fill;

    _clipPaint = Paint();
  }

  late Paint _sectionPaint;
  late Paint _sectionSaveLayerPaint;
  late Paint _sectionStrokePaint;
  late Paint _centerSpacePaint;
  late Paint _clipPaint;

  /// Paints [PieChartData] into the provided canvas.
  @override
  void paint(
    BuildContext context,
    CanvasWrapper canvasWrapper,
    PaintHolder<PieChartData> holder,
  ) {
    super.paint(context, canvasWrapper, holder);
    final data = holder.data;
    if (data.sections.isEmpty) {
      return;
    }

    final sectionsAngle = calculateSectionsAngle(data.sections, data.sumValue);
    final centerRadius = calculateCenterRadius(canvasWrapper.size, holder);

    drawCenterSpace(canvasWrapper, centerRadius, holder);
    drawSections(canvasWrapper, sectionsAngle, centerRadius, holder);
    drawTexts(context, canvasWrapper, holder, centerRadius);
  }

  @visibleForTesting
  List<double> calculateSectionsAngle(
    List<PieChartSectionData> sections,
    double sumValue,
  ) {
    if (sumValue == 0) {
      return List<double>.filled(sections.length, 0);
    }

    return sections.map((section) {
      return 360 * (section.value / sumValue);
    }).toList();
  }

  @visibleForTesting
  void drawCenterSpace(
    CanvasWrapper canvasWrapper,
    double centerRadius,
    PaintHolder<PieChartData> holder,
  ) {
    final data = holder.data;
    final viewSize = canvasWrapper.size;
    final centerX = viewSize.width / 2;
    final centerY = viewSize.height / 2;

    _centerSpacePaint.color = data.centerSpaceColor;
    canvasWrapper.drawCircle(
      Offset(centerX, centerY),
      centerRadius,
      _centerSpacePaint,
    );
  }

  @visibleForTesting
  void drawSections(
    CanvasWrapper canvasWrapper,
    List<double> sectionsAngle,
    double centerRadius,
    PaintHolder<PieChartData> holder,
  ) {
    final data = holder.data;
    final viewSize = canvasWrapper.size;

    final center = Offset(viewSize.width / 2, viewSize.height / 2);

    var tempAngle = data.startDegreeOffset;

    for (var i = 0; i < data.sections.length; i++) {
      final section = data.sections[i];
      if (section.value == 0) {
        continue;
      }
      final sectionDegree = sectionsAngle[i];

      if (sectionDegree == 360) {
        final radius = centerRadius + section.radius / 2;
        final rect = Rect.fromCircle(center: center, radius: radius);
        _sectionPaint
          ..setColorOrGradient(section.color, section.gradient, rect)
          ..strokeWidth = section.radius
          ..style = PaintingStyle.fill;

        final bounds = Rect.fromCircle(
          center: center,
          radius: centerRadius + section.radius,
        );
        canvasWrapper
          ..saveLayer(bounds, _sectionSaveLayerPaint)
          ..drawCircle(
            center,
            centerRadius + section.radius,
            _sectionPaint..blendMode = BlendMode.srcOver,
          )
          ..drawCircle(
            center,
            centerRadius,
            _sectionPaint..blendMode = BlendMode.srcOut,
          )
          ..restore();
        _sectionPaint.blendMode = BlendMode.srcOver;
        if (section.borderSide.isVisible) {
          final isInside = section.borderSide.strokeAlign < 0;
          _sectionStrokePaint
            ..strokeWidth = isInside
                ? section.borderSide.width * 2
                : section.borderSide.width
            ..color = section.borderSide.color
            ..strokeCap = section.borderSide.style == FlBorderStyle.dotted
                ? StrokeCap.round
                : StrokeCap.butt;
          final outerRadius = centerRadius + section.radius;
          final innerRadius = centerRadius;
          if (isInside) {
            final ringPath = Path()
              ..addOval(Rect.fromCircle(center: center, radius: outerRadius))
              ..addOval(Rect.fromCircle(center: center, radius: innerRadius))
              ..fillType = PathFillType.evenOdd;
            canvasWrapper
              ..saveLayer(bounds, _clipPaint)
              ..clipPath(ringPath);
          }
          if (section.borderSide.style == FlBorderStyle.dotted) {
            final dashArray = _dottedDashArray(section.borderSide.width);
            final outerPath = Path()
              ..addOval(Rect.fromCircle(center: center, radius: outerRadius));
            final innerPath = Path()
              ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
            canvasWrapper
              ..drawPath(outerPath.toDashedPath(dashArray), _sectionStrokePaint)
              ..drawPath(
                  innerPath.toDashedPath(dashArray), _sectionStrokePaint);
          } else {
            // Outer
            canvasWrapper
              ..drawCircle(
                center,
                outerRadius,
                _sectionStrokePaint,
              )
              // Inner
              ..drawCircle(
                center,
                innerRadius,
                _sectionStrokePaint,
              );
          }
          if (isInside) {
            canvasWrapper.restore();
          }
        }
        return;
      }

      final sectionPath = generateSectionPath(
        section,
        data.sectionsSpace,
        tempAngle,
        sectionDegree,
        center,
        centerRadius,
        roundedEdges: data.roundedEdges,
      );

      drawSection(
        section,
        sectionPath,
        canvasWrapper,
        data.sectionsSpace,
        tempAngle,
        sectionDegree,
        center,
        centerRadius,
        data.roundedEdges,
      );
      drawSectionStroke(
        section,
        sectionPath,
        canvasWrapper,
        viewSize,
        data.sectionsSpace,
        tempAngle,
        sectionDegree,
        center,
        centerRadius,
        data.roundedEdges,
      );
      tempAngle += sectionDegree;
    }
  }

  /// Generates a path around a section
  @visibleForTesting
  Path generateSectionPath(
    PieChartSectionData section,
    double sectionSpace,
    double tempAngle,
    double sectionDegree,
    Offset center,
    double centerRadius, {
    bool roundedEdges = false,
  }) {
    final sectionRadiusRect = Rect.fromCircle(
      center: center,
      radius: centerRadius + section.radius,
    );

    final centerRadiusRect = Rect.fromCircle(
      center: center,
      radius: centerRadius,
    );

    final startRadians = Utils().radians(tempAngle);
    final sweepRadians = Utils().radians(sectionDegree);
    final endRadians = startRadians + sweepRadians;

    final startLineDirection = Offset(
      math.cos(startRadians),
      math.sin(startRadians),
    );

    final startLineFrom = center + startLineDirection * centerRadius;
    final startLineTo = startLineFrom + startLineDirection * section.radius;
    final startLine = Line(startLineFrom, startLineTo);

    final endLineDirection = Offset(math.cos(endRadians), math.sin(endRadians));

    final endLineFrom = center + endLineDirection * centerRadius;
    final endLineTo = endLineFrom + endLineDirection * section.radius;
    final endLine = Line(endLineFrom, endLineTo);

    var sectionPath = Path();

    // First create the basic section path (without rounding)
    sectionPath = Path()
      ..moveTo(startLine.from.dx, startLine.from.dy)
      ..lineTo(startLine.to.dx, startLine.to.dy)
      ..arcTo(sectionRadiusRect, startRadians, sweepRadians, false)
      ..lineTo(endLine.from.dx, endLine.from.dy)
      ..arcTo(centerRadiusRect, endRadians, -sweepRadians, false)
      ..moveTo(startLine.from.dx, startLine.from.dy)
      ..close();

    /// First apply section space separators to the basic path
    if (sectionSpace != 0) {
      final startLineSeparatorPath = createRectPathAroundLine(
        Line(startLineFrom, startLineTo),
        sectionSpace,
      );
      try {
        sectionPath = Path.combine(
          PathOperation.difference,
          sectionPath,
          startLineSeparatorPath,
        );
      } catch (_) {
        /// It's a flutter engine issue with [Path.combine] in web-html renderer
        /// https://github.com/imaNNeo/fl_chart/issues/955
      }

      final endLineSeparatorPath = createRectPathAroundLine(
        Line(endLineFrom, endLineTo),
        sectionSpace,
      );
      try {
        sectionPath = Path.combine(
          PathOperation.difference,
          sectionPath,
          endLineSeparatorPath,
        );
      } catch (_) {
        /// It's a flutter engine issue with [Path.combine] in web-html renderer
        /// https://github.com/imaNNeo/fl_chart/issues/955
      }
    }

    // Then apply border radius to the resulting separated path
    if (section.cornerRadius > 0 || roundedEdges) {
      // Get the bounds of the separated path
      final pathBounds = sectionPath.getBounds();
      if (!pathBounds.isEmpty) {
        // We need to calculate new angles for the separated section
        // to apply rounding correctly to the actual shape we have

        // Calculate effective angles after separation
        final separatorAngleReduction = sectionSpace != 0
            ? math.atan2(sectionSpace, centerRadius + section.radius / 2)
            : 0.0;

        final effectiveStartRadians = startRadians + separatorAngleReduction;
        final effectiveSweepRadians =
            sweepRadians - (2 * separatorAngleReduction);

        if (effectiveSweepRadians > 0) {
          // Create new rects for the adjusted geometry
          final effectiveSectionRadiusRect = Rect.fromCircle(
            center: center,
            radius: centerRadius + section.radius,
          );

          final effectiveCenterRadiusRect = Rect.fromCircle(
            center: center,
            radius: centerRadius,
          );

          // Generate rounded path with the effective angles
          sectionPath = generateRoundedSectionPath(
            section,
            effectiveStartRadians,
            effectiveSweepRadians,
            center,
            centerRadius,
            effectiveSectionRadiusRect,
            effectiveCenterRadiusRect,
            roundedEdges,
          );
        }
      }
    }

    return sectionPath;
  }

  /// Generates a Path for a pie-section with rounded corners.
  ///
  /// This method builds a path that rounds section ends using the middle
  /// radius (center radius + half of section thickness). The path is
  /// generated as a single closed shape, so it can be painted in one pass.
  ///
  /// Important behaviors / notes:
  /// - If `cornerRadius <= 1` the method returns a standard (non-rounded)
  ///   section path for performance and to avoid tiny visual artifacts.
  /// - When `centerRadius > 0`, the rounded ends are constructed from
  ///   half-circle caps at the mid radius, and the outer/inner arcs are
  ///   connected to those caps.
  /// - For `centerRadius == 0` (fully filled pie), the method falls back to
  ///   the standard section path to avoid degenerate rounded geometry.
  /// - For `centerRadius > 0` (donut), the inner corners are rounded as well.
  /// - `sectionsSpace` trimming is applied later by subtracting separator
  ///   rectangles from the resulting path (see `generateSectionPath`).
  /// - There are known platform/engine caveats when using `Path.combine` on
  ///   web-html renderer; the subtraction steps are guarded with try/catch
  ///   where used.
  @visibleForTesting
  Path generateRoundedSectionPath(
    PieChartSectionData section,
    double startRadians,
    double sweepRadians,
    Offset center,
    double centerRadius,
    Rect sectionRadiusRect,
    Rect centerRadiusRect,
    bool roundedEdges,
  ) {
    final endRadians = startRadians + sweepRadians;
    final outerRadius = centerRadius + section.radius;
    // User-provided corner radius (used as a rounding enable threshold).
    final cornerRadius = section.cornerRadius;

    final path = Path();

    if (cornerRadius <= 1 && !roundedEdges) {
      // if corner radius is too small, return standard section path
      final innerStart = center +
          Offset(math.cos(startRadians), math.sin(startRadians)) * centerRadius;
      final outerStart = center +
          Offset(math.cos(startRadians), math.sin(startRadians)) * outerRadius;
      final innerEnd = center +
          Offset(math.cos(endRadians), math.sin(endRadians)) * centerRadius;

      path
        ..moveTo(innerStart.dx, innerStart.dy)
        ..lineTo(outerStart.dx, outerStart.dy)
        ..arcTo(sectionRadiusRect, startRadians, sweepRadians, false)
        ..lineTo(innerEnd.dx, innerEnd.dy)
        ..arcTo(centerRadiusRect, endRadians, -sweepRadians, false)
        ..close();
    } else {
      // Use mid radius for rounding and build the section path in one pass.
      if (centerRadius <= 0 || sweepRadians <= 0) {
        final innerStart = center +
            Offset(math.cos(startRadians), math.sin(startRadians)) *
                centerRadius;
        final outerStart = center +
            Offset(math.cos(startRadians), math.sin(startRadians)) *
                outerRadius;
        final innerEnd = center +
            Offset(math.cos(endRadians), math.sin(endRadians)) * centerRadius;

        path
          ..moveTo(innerStart.dx, innerStart.dy)
          ..lineTo(outerStart.dx, outerStart.dy)
          ..arcTo(sectionRadiusRect, startRadians, sweepRadians, false)
          ..lineTo(innerEnd.dx, innerEnd.dy)
          ..arcTo(centerRadiusRect, endRadians, -sweepRadians, false)
          ..close();
        return path;
      }

      final halfThickness = section.radius / 2;
      final midRadius = centerRadius + halfThickness;

      var trimmedStartRadians = startRadians;
      var trimmedEndRadians = endRadians;
      var trimmedSweepRadians = sweepRadians;
      if (roundedEdges) {
        final arcLength = sweepRadians * midRadius;
        var reducedLength = arcLength - section.radius;
        if (reducedLength < 0) {
          reducedLength = 1;
        }
        final reducedSweepRadians = math.min(
          sweepRadians,
          reducedLength / midRadius,
        );
        final trimAngle = (sweepRadians - reducedSweepRadians) / 2;
        trimmedStartRadians = startRadians + trimAngle;
        trimmedEndRadians = endRadians - trimAngle;
        trimmedSweepRadians = trimmedEndRadians - trimmedStartRadians;
      }

      final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
      final innerRect = Rect.fromCircle(center: center, radius: centerRadius);

      final startMid = center +
          Offset(math.cos(trimmedStartRadians), math.sin(trimmedStartRadians)) *
              midRadius;
      final endMid = center +
          Offset(math.cos(trimmedEndRadians), math.sin(trimmedEndRadians)) *
              midRadius;

      final startCapRect = Rect.fromCircle(
        center: startMid,
        radius: halfThickness,
      );
      final endCapRect = Rect.fromCircle(
        center: endMid,
        radius: halfThickness,
      );

      final outerStart = center +
          Offset(math.cos(trimmedStartRadians), math.sin(trimmedStartRadians)) *
              outerRadius;

      path
        ..moveTo(outerStart.dx, outerStart.dy)
        ..arcTo(
          outerRect,
          trimmedStartRadians,
          trimmedSweepRadians,
          false,
        )
        ..arcTo(endCapRect, trimmedEndRadians, math.pi, false)
        ..arcTo(
          innerRect,
          trimmedEndRadians,
          -trimmedSweepRadians,
          false,
        )
        ..arcTo(startCapRect, trimmedStartRadians + math.pi, math.pi, false)
        ..close();
    }

    return path;
  }

  /// Creates a rect around a narrow line
  @visibleForTesting
  Path createRectPathAroundLine(Line line, double width) {
    width = width / 2;
    final normalized = line.normalize();

    final verticalAngle = line.direction() + (math.pi / 2);
    final verticalDirection = Offset(
      math.cos(verticalAngle),
      math.sin(verticalAngle),
    );

    final startPoint1 = Offset(
      line.from.dx -
          (normalized * (width / 2)).dx -
          (verticalDirection * width).dx,
      line.from.dy -
          (normalized * (width / 2)).dy -
          (verticalDirection * width).dy,
    );

    final startPoint2 = Offset(
      line.to.dx +
          (normalized * (width / 2)).dx -
          (verticalDirection * width).dx,
      line.to.dy +
          (normalized * (width / 2)).dy -
          (verticalDirection * width).dy,
    );

    final startPoint3 = Offset(
      startPoint2.dx + (verticalDirection * (width * 2)).dx,
      startPoint2.dy + (verticalDirection * (width * 2)).dy,
    );

    final startPoint4 = Offset(
      startPoint1.dx + (verticalDirection * (width * 2)).dx,
      startPoint1.dy + (verticalDirection * (width * 2)).dy,
    );

    return Path()
      ..moveTo(startPoint1.dx, startPoint1.dy)
      ..lineTo(startPoint2.dx, startPoint2.dy)
      ..lineTo(startPoint3.dx, startPoint3.dy)
      ..lineTo(startPoint4.dx, startPoint4.dy)
      ..lineTo(startPoint1.dx, startPoint1.dy);
  }

  @visibleForTesting
  void drawSection(
    PieChartSectionData section,
    Path sectionPath,
    CanvasWrapper canvasWrapper,
    double sectionSpace,
    double tempAngle,
    double sectionDegree,
    Offset center,
    double centerRadius,
    bool roundedEdges,
  ) {
    final fillPath = section.borderSide.isVisible
        ? () {
            final strokeAlign = section.borderSide.strokeAlign;
            final inset = math.max(
              0.0,
              section.borderSide.width * (0.5 - (strokeAlign / 2)),
            );
            final adjustedCenterRadius = centerRadius + inset;
            final adjustedSectionRadius =
                math.max(0.0, section.radius - (inset * 2));
            final adjustedSectionSpace = math.max(
              0.0,
              sectionSpace - (strokeAlign * section.borderSide.width),
            );
            if (adjustedSectionRadius == 0) {
              return null;
            }
            final alignedSection =
                section.copyWith(radius: adjustedSectionRadius);
            return generateSectionPath(
              alignedSection,
              adjustedSectionSpace,
              tempAngle,
              sectionDegree,
              center,
              adjustedCenterRadius,
              roundedEdges: roundedEdges,
            );
          }()
        : sectionPath;
    _sectionPaint
      ..setColorOrGradient(
        section.color,
        section.gradient,
        (fillPath ?? sectionPath).getBounds(),
      )
      ..style = PaintingStyle.fill;
    if (fillPath != null) {
      canvasWrapper.drawPath(fillPath, _sectionPaint);
    }
  }

  @visibleForTesting
  void drawSectionStroke(
    PieChartSectionData section,
    Path sectionPath,
    CanvasWrapper canvasWrapper,
    Size viewSize,
    double sectionSpace,
    double tempAngle,
    double sectionDegree,
    Offset center,
    double centerRadius,
    bool roundedEdges,
  ) {
    if (section.borderSide.isVisible) {
      final strokeAlign = section.borderSide.strokeAlign;
      final strokeWidth = section.borderSide.width;
      final alignedPath = strokeAlign == 0.0
          ? sectionPath
          : () {
              final inset = -strokeAlign * strokeWidth / 2;
              final adjustedCenterRadius = math.max(0.0, centerRadius + inset);
              final adjustedSectionRadius = math.max(
                0.0,
                section.radius - (inset * 2),
              );
              final adjustedSectionSpace = sectionSpace +
                  (section.borderSide.width * strokeAlign.abs() / 2);
              if (adjustedSectionRadius == 0) {
                return null;
              }
              final alignedSection =
                  section.copyWith(radius: adjustedSectionRadius);
              return generateSectionPath(
                alignedSection,
                adjustedSectionSpace,
                tempAngle,
                sectionDegree,
                center,
                adjustedCenterRadius,
                roundedEdges: roundedEdges,
              );
            }();
      if (alignedPath == null) {
        return;
      }
      final strokePath = section.borderSide.style == FlBorderStyle.dotted
          ? alignedPath.toDashedPath(_dottedDashArray(section.borderSide.width))
          : alignedPath;
      _sectionStrokePaint
        ..strokeWidth = strokeWidth
        ..color = section.borderSide.color
        ..strokeCap = section.borderSide.style == FlBorderStyle.dotted
            ? StrokeCap.round
            : StrokeCap.butt;
      canvasWrapper.drawPath(strokePath, _sectionStrokePaint);
    }
  }

  List<int> _dottedDashArray(double strokeWidth) {
    final dotLength = math.max(1, strokeWidth.round());
    final gapLength = math.max(1, (strokeWidth * 1.5).round());
    return [dotLength, gapLength];
  }

  /// Calculates layout of overlaying elements, includes:
  /// - title text
  /// - badge widget positions
  @visibleForTesting
  void drawTexts(
    BuildContext context,
    CanvasWrapper canvasWrapper,
    PaintHolder<PieChartData> holder,
    double centerRadius,
  ) {
    final data = holder.data;
    final viewSize = canvasWrapper.size;
    final center = Offset(viewSize.width / 2, viewSize.height / 2);

    var tempAngle = data.startDegreeOffset;

    for (var i = 0; i < data.sections.length; i++) {
      final section = data.sections[i];
      if (section.value == 0) {
        continue;
      }
      final startAngle = tempAngle;
      final sweepAngle = 360 * (section.value / data.sumValue);
      final sectionCenterAngle = startAngle + (sweepAngle / 2);

      double? rotateAngle;
      if (data.titleSunbeamLayout) {
        if (sectionCenterAngle >= 90 && sectionCenterAngle <= 270) {
          rotateAngle = sectionCenterAngle - 180;
        } else {
          rotateAngle = sectionCenterAngle;
        }
      }

      Offset sectionCenter(double percentageOffset) =>
          center +
          Offset(
            math.cos(Utils().radians(sectionCenterAngle)) *
                (centerRadius + (section.radius * percentageOffset)),
            math.sin(Utils().radians(sectionCenterAngle)) *
                (centerRadius + (section.radius * percentageOffset)),
          );

      final sectionCenterOffsetTitle = sectionCenter(
        section.titlePositionPercentageOffset,
      );

      if (section.showTitle) {
        final span = TextSpan(
          style: Utils().getThemeAwareTextStyle(context, section.titleStyle),
          text: section.title,
        );
        final tp = TextPainter(
          text: span,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          textScaler: holder.textScaler,
        )..layout();

        canvasWrapper.drawText(
          tp,
          sectionCenterOffsetTitle - Offset(tp.width / 2, tp.height / 2),
          rotateAngle,
        );
      }

      tempAngle += sweepAngle;
    }
  }

  /// Calculates center radius based on the provided sections radius
  @visibleForTesting
  double calculateCenterRadius(
    Size viewSize,
    PaintHolder<PieChartData> holder,
  ) {
    final data = holder.data;
    if (data.centerSpaceRadius.isFinite) {
      return data.centerSpaceRadius;
    }
    final maxRadius =
        data.sections.reduce((a, b) => a.radius > b.radius ? a : b).radius;
    return (viewSize.shortestSide - (maxRadius * 2)) / 2;
  }

  /// Makes a [PieTouchedSection] based on the provided [localPosition]
  ///
  /// Processes [localPosition] and checks
  /// the elements of the chart that are near the offset,
  /// then makes a [PieTouchedSection] from the elements that has been touched.
  PieTouchedSection handleTouch(
    Offset localPosition,
    Size viewSize,
    PaintHolder<PieChartData> holder,
  ) {
    final data = holder.data;
    final sectionsAngle = calculateSectionsAngle(data.sections, data.sumValue);
    final centerRadius = calculateCenterRadius(viewSize, holder);

    final center = Offset(viewSize.width / 2, viewSize.height / 2);

    final touchedPoint2 = localPosition - center;

    final touchX = touchedPoint2.dx;
    final touchY = touchedPoint2.dy;

    final touchR = math.sqrt(math.pow(touchX, 2) + math.pow(touchY, 2));
    var touchAngle = Utils().degrees(math.atan2(touchY, touchX));
    touchAngle = touchAngle < 0 ? (180 - touchAngle.abs()) + 180 : touchAngle;

    PieChartSectionData? foundSectionData;
    var foundSectionDataPosition = -1;

    var tempAngle = data.startDegreeOffset;
    for (var i = 0; i < data.sections.length; i++) {
      final section = data.sections[i];
      final sectionAngle = sectionsAngle[i];

      if (sectionAngle == 360) {
        final distance = math.sqrt(
          math.pow(localPosition.dx - center.dx, 2) +
              math.pow(localPosition.dy - center.dy, 2),
        );
        if (distance >= centerRadius &&
            distance <= section.radius + centerRadius) {
          foundSectionData = section;
          foundSectionDataPosition = i;
        }
        break;
      }

      final sectionPath = generateSectionPath(
        section,
        data.sectionsSpace,
        tempAngle,
        sectionAngle,
        center,
        centerRadius,
        roundedEdges: data.roundedEdges,
      );

      if (sectionPath.contains(localPosition)) {
        foundSectionData = section;
        foundSectionDataPosition = i;
        break;
      }

      tempAngle += sectionAngle;
    }

    return PieTouchedSection(
      foundSectionData,
      foundSectionDataPosition,
      touchAngle,
      touchR,
    );
  }

  /// Exposes offset for laying out the badge widgets upon the chart.
  Map<int, Offset> getBadgeOffsets(
    Size viewSize,
    PaintHolder<PieChartData> holder,
  ) {
    final data = holder.data;
    final center = viewSize.center(Offset.zero);
    final badgeWidgetsOffsets = <int, Offset>{};

    if (data.sections.isEmpty) {
      return badgeWidgetsOffsets;
    }

    var tempAngle = data.startDegreeOffset;

    final sectionsAngle = calculateSectionsAngle(data.sections, data.sumValue);
    for (var i = 0; i < data.sections.length; i++) {
      final section = data.sections[i];
      final startAngle = tempAngle;
      final sweepAngle = sectionsAngle[i];
      final sectionCenterAngle = startAngle + (sweepAngle / 2);
      final centerRadius = calculateCenterRadius(viewSize, holder);

      Offset sectionCenter(double percentageOffset) =>
          center +
          Offset(
            math.cos(Utils().radians(sectionCenterAngle)) *
                (centerRadius + (section.radius * percentageOffset)),
            math.sin(Utils().radians(sectionCenterAngle)) *
                (centerRadius + (section.radius * percentageOffset)),
          );

      final sectionCenterOffsetBadgeWidget = sectionCenter(
        section.badgePositionPercentageOffset,
      );

      badgeWidgetsOffsets[i] = sectionCenterOffsetBadgeWidget;

      tempAngle += sweepAngle;
    }

    return badgeWidgetsOffsets;
  }
}

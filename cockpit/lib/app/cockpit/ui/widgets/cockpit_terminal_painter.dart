// Fork of xterm's `TerminalPainter` (`src/ui/painter.dart`) so Cockpit controls
// cell painting, the final piece previously owned by the package. Reuse xterm's
// `palette_builder`, `paragraph_cache`, and procedural `builtin_glyphs` through
// implementation imports while keeping only customized logic here.
//
// Difference from upstream: Cockpit draws underlines itself. xterm applies
// `underline: true` to a per-character Paragraph, producing thick segmented
// strokes that obscure links and headings. Paint undecorated glyphs, then draw a
// crisp (`isAntiAlias=false`) hairline at the cell bottom, extending one pixel to
// join adjacent cells.
//
// ignore_for_file: implementation_imports
import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/builtin_glyphs.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class CockpitTerminalPainter {
  CockpitTerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required double devicePixelRatio,
  }) : _textStyle = textStyle,
       _theme = theme,
       _textScaler = textScaler,
       _devicePixelRatio = devicePixelRatio;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  /// Update physical display density when a window moves between monitors.
  ///
  /// [cellSize] snaps to this grid through [_snapToDevicePixel]. Paragraph glyphs
  /// are DPR-independent, so only cell measurement changes; the paragraph cache
  /// remains valid.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _cellSize = _measureCharSize();
  }

  /// Snap a logical dimension to the nearest physical pixel.
  ///
  /// This makes cell width times DPR integral, placing every cell origin on a
  /// device pixel as iTerm2 and Ghostty do. Without snapping, xterm's fractional
  /// metrics lose coverage and produce pale seams and blur.
  double _snapToDevicePixel(double logical) {
    final dpr = _devicePixelRatio;
    if (dpr <= 0) return logical;
    final snapped = (logical * dpr).roundToDouble() / dpr;
    return snapped <= 0 ? logical : snapped;
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(textStyle.getTextStyle(textScaler: _textScaler));
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      _snapToDevicePixel(paragraph.maxIntrinsicWidth / test.length),
      _snapToDevicePixel(paragraph.height),
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset = offset.translate(
      length * _cellSize.width,
      _cellSize.height,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromPoints(offset, endOffset), paint);
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(Canvas canvas, Offset offset, BufferLine line) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      final cellOffset = offset.translate(i * cellWidth, 0);

      paintCell(canvas, cellOffset, cellData);

      if (charWidth == 2) {
        i++;
      }
    }
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    final cellFlags = cellData.flags;
    final underlined = cellFlags & CellFlags.underline != 0;

    // Paint nothing for an unwritten cell, including no underline beyond text.
    // Real spaces (0x20) have nonzero content and follow the normal path so an
    // underline can join across words.
    if (charCode == 0) return;

    if (paintBuiltinGlyph(
      canvas,
      offset,
      _cellSize,
      charCode,
      _resolveForegroundColor(cellData),
    )) {
      if (underlined) _paintUnderline(canvas, offset, cellData);
      return;
    }

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final color = _resolveForegroundColor(cellData);

      // Deliberately omit `underline:` because [_paintUnderline] draws the thin,
      // continuous stroke. The upstream 0x20→0xA0 workaround is no longer needed.
      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
      );

      final char = String.fromCharCode(charCode);

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);

    if (underlined) _paintUnderline(canvas, offset, cellData);
  }

  /// Draw a crisp, continuous hairline at the bottom of a cell.
  ///
  /// Replaces thick segmented font decoration. Extending width by one pixel joins
  /// the next cell, while `isAntiAlias=false` preserves a sharp one-pixel line.
  @pragma('vm:prefer-inline')
  void _paintUnderline(Canvas canvas, Offset offset, CellData cellData) {
    final thickness = (_cellSize.height / 14).clamp(1.0, 2.0).floorToDouble();
    final paint = Paint()
      ..color = _resolveForegroundColor(cellData)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + _cellSize.height - thickness,
        _cellSize.width + 1,
        thickness,
      ),
      paint,
    );
  }

  /// The effective foreground color of [cellData], honoring the inverse and
  /// faint flags. Shared by the font and the procedural ([paintBuiltinGlyph])
  /// rendering paths.
  Color _resolveForegroundColor(CellData cellData) {
    final cellFlags = cellData.flags;
    var color = cellFlags & CellFlags.inverse == 0
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);
    if (cellFlags & CellFlags.faint != 0) {
      color = color.withValues(alpha: 0.5);
    }
    return color;
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}

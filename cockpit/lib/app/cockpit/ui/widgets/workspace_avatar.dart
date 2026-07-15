import 'dart:io';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Render a workspace avatar from an image or its color and initial.
///
/// PNG, JPG, and SVG images are clipped to the configured shape. A missing,
/// unreadable, or corrupt image falls back to an error placeholder rather than
/// breaking the surrounding UI.
class WorkspaceAvatar extends StatelessWidget {
  const WorkspaceAvatar({
    super.key,
    required this.imagePath,
    required this.colorValue,
    required this.initial,
    this.size = 30,
    this.radius = 7,
  });

  /// Absolute image path, or `null` to use the color-and-initial fallback.
  final String? imagePath;
  final int colorValue;
  final String initial;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null && path.isNotEmpty) {
      final isSvg = path.toLowerCase().endsWith('.svg');
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // Both loaders use the same fallback for moved, deleted, or corrupt files.
        child: isSvg
            ? SvgPicture.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => _errorBox(context),
              )
            : Image.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => _errorBox(context),
              ),
      );
    }
    // Without an image, show the workspace color and initial.
    return _box(
      context,
      child: Text(
        initial,
        style: context.typo.title.copyWith(
          fontSize: size * 0.43,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context) => _box(
    context,
    child: Icon(
      Icons.broken_image_outlined,
      size: size * 0.5,
      color: Colors.white,
    ),
  );

  Widget _box(BuildContext context, {required Widget child}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(colorValue),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

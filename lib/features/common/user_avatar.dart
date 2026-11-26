import 'package:material_ui/material_ui.dart';

/// Round profile picture that falls back to the first letter of [name]
/// when there is no photo or it fails to load.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String name;
  final String? url;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final hasPhoto = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? scheme.primaryContainer,
      foregroundImage: hasPhoto ? NetworkImage(url!) : null,
      onForegroundImageError: hasPhoto ? (_, _) {} : null,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: foregroundColor ?? scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

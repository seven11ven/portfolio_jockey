import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/app/theme.dart';

/// Gives every screen access to the [AppController].
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({required AppController controller, required super.child, super.key}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For event handlers, which mustn't subscribe to changes.
  static AppController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

const String comingLater = 'Coming in a later version';

/// A greyed-out control for a feature a later plan phase adds.
Widget comingSoon(Widget child) => Tooltip(message: comingLater, child: child);

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = unit == 0 || value >= 10 ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Changed today", "Changed yesterday", "Changed Oct 19", "Changed Oct 19, 2025".
String formatChanged(DateTime changedAt, {DateTime? now}) {
  final local = changedAt.toLocal();
  final today = now ?? DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final days = DateTime(today.year, today.month, today.day).difference(day).inDays;
  if (days <= 0) {
    return 'Changed today';
  }
  if (days == 1) {
    return 'Changed yesterday';
  }
  final date = '${_months[local.month - 1]} ${local.day}';
  return local.year == today.year ? 'Changed $date' : 'Changed $date, ${local.year}';
}

String plural(int count, String one, [String? many]) => '$count ${count == 1 ? one : many ?? '${one}s'}';

/// A project's cover image, or a gradient with its first letter.
class CoverView extends StatelessWidget {
  const CoverView({required this.name, this.image, this.height = 120, this.width, super.key});

  final String name;
  final Uint8List? image;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final bytes = image;
    // FNV-1a, so similar names still spread over the five gradients.
    final hash = name.codeUnits.fold(0x811c9dc5, (h, c) => ((h ^ c) * 0x01000193) & 0xffffffff);
    final gradient = coverGradients[hash % coverGradients.length];
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: bytes == null
            ? placeholder
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}

/// What kind of file a name looks like, for the file grid's badge.
({String label, IconData icon, Color color}) fileKind(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg', 'tif', 'tiff'};
  const videos = {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'};
  const audio = {'mp3', 'm4a', 'wav', 'flac', 'ogg', 'opus', 'aac'};
  final label = ext.isEmpty ? 'FILE' : ext.toUpperCase();
  if (images.contains(ext)) {
    return (label: label, icon: Icons.image_outlined, color: const Color(0xFF3B82F6));
  }
  if (videos.contains(ext)) {
    return (label: label, icon: Icons.movie_outlined, color: const Color(0xFF8B5CF6));
  }
  if (audio.contains(ext)) {
    return (label: label, icon: Icons.music_note_outlined, color: const Color(0xFF10B981));
  }
  if (ext == 'pdf') {
    return (label: label, icon: Icons.picture_as_pdf_outlined, color: const Color(0xFFEF4444));
  }
  return (label: label, icon: Icons.description_outlined, color: const Color(0xFF64748B));
}

class TypeBadge extends StatelessWidget {
  const TypeBadge({required this.fileName, super.key});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final kind = fileKind(fileName);
    return DecoratedBox(
      decoration: BoxDecoration(color: kind.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.icon, color: kind.color, size: 28),
            const SizedBox(height: 4),
            Text(kind.label, style: TextStyle(color: kind.color, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A tag. Tappable when [onTap] is set; highlighted when [selected].
class TagChip extends StatelessWidget {
  const TagChip(this.label, {this.selected = false, this.onTap, this.small = false, this.check = true, this.icon, super.key});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool small;

  /// Show a check mark when selected (toggles); filter chips only highlight.
  final bool check;

  /// A leading icon, e.g. the plus of "New tag".
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = PjColors.of(context);
    return Material(
      color: selected ? extra.accentSoft : extra.surface2,
      shape: StadiumBorder(side: BorderSide(color: selected ? scheme.primary : extra.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 2 : 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              if (icon case final leading?) Icon(leading, size: small ? 12 : 15),
              Text(
                label,
                style: TextStyle(fontSize: small ? 11 : 13, color: selected ? scheme.primary : null, fontWeight: selected ? FontWeight.w600 : null),
              ),
              // Icons, not ✓ characters: not every font has them.
              if (selected && check && onTap != null) Icon(Icons.check, size: small ? 12 : 15, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grey box that sums up what a confirmation will do.
class SummaryBox extends StatelessWidget {
  const SummaryBox({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: extra.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: extra.border)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: children),
      ),
    );
  }
}

/// A warning (amber) or error (red) message.
class Notice extends StatelessWidget {
  const Notice(this.text, {this.danger = false, super.key});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final extra = PjColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: danger ? extra.dangerSoft : extra.warnSoft, borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: TextStyle(color: danger ? scheme.error : extra.warn)),
      ),
    );
  }
}

/// The frame every confirm/cancel dialog uses, as in the mockups.
class PjDialog extends StatelessWidget {
  const PjDialog({required this.title, required this.content, required this.actions, this.danger = false, this.width = 480, super.key});

  final String title;
  final List<Widget> content;
  final List<Widget> actions;
  final bool danger;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Row(
                spacing: 10,
                children: [
                  if (danger)
                    DecoratedBox(
                      decoration: BoxDecoration(color: PjColors.of(context).dangerSoft, shape: BoxShape.circle),
                      child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.delete_outline, color: scheme.error)),
                    ),
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                ],
              ),
              ...content,
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small muted text line.
class Muted extends StatelessWidget {
  const Muted(this.text, {this.small = true, this.textAlign, super.key});

  final String text;
  final bool small;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: textAlign, style: TextStyle(color: PjColors.of(context).muted, fontSize: small ? 12.5 : null));
}

/// “Old” → “New”, with the arrow drawn as an icon: not every font has →.
class ChangeArrow extends StatelessWidget {
  const ChangeArrow(this.from, this.to, {this.prefix = '', super.key});

  final String from;
  final String to;
  final String prefix;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$prefix“$from” '),
        const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.arrow_forward, size: 16)),
        TextSpan(text: ' “$to”'),
      ],
    ),
  );
}

/// Monospace for paths, with fallbacks: not every system has a "monospace" alias.
const TextStyle pathStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['DejaVu Sans Mono', 'Liberation Mono', 'Noto Sans Mono', 'Roboto'],
  fontSize: 13,
);

/// A field label, as in the mockups.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
  );
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

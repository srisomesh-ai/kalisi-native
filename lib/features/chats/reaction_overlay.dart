import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../theme/colors.dart';
import '../../util/mask.dart';
import '../../data/db/database.dart';

/// Floating reaction picker that appears over the message you long-pressed,
/// with the rest of the chat dimmed — the WhatsApp arrangement.
///
/// Returns an action string: 'reply' | 'copy' | 'delete', or an emoji.
class ReactionOverlay {
  static const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  static Future<String?> show({
    required BuildContext context,
    required Message message,
    required Rect anchor,
    required bool mine,
    String? current,
    bool actionsEnabled = true,
  }) {
    return Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.30),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (ctx, anim, __) => _ReactionSheet(
          message: message,
          anchor: anchor,
          mine: mine,
          current: current,
          anim: anim,
          actionsEnabled: actionsEnabled,
        ),
      ),
    );
  }
}

class _ReactionSheet extends StatelessWidget {
  final Message message;
  final Rect anchor;
  final bool mine;
  final String? current;
  final Animation<double> anim;
  final bool actionsEnabled;

  const _ReactionSheet({
    required this.message,
    required this.anchor,
    required this.mine,
    required this.current,
    required this.anim,
    this.actionsEnabled = true,
  });

  /// Small faithful preview of the message being acted on.
  Widget _preview(KScheme s) {
    if (message.kind == 'img') {
      final bytes = _decode(message.body);
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      }
      return Text('📷 Photo', style: TextStyle(color: s.text, fontSize: 15));
    }
    if (message.kind == 'voice') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, color: KColors.teal, size: 22),
          const SizedBox(width: 8),
          Icon(Icons.graphic_eq_rounded, color: s.muted, size: 20),
          const SizedBox(width: 8),
          Text('Voice', style: TextStyle(color: s.muted, fontSize: 13)),
        ],
      );
    }
    // Masked here as well — long-press must not reveal what the bubble hides.
    return Text(
      Mask.sensitive(message.body ?? ''),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: s.text, fontSize: 15.5, height: 1.4),
    );
  }

  static Uint8List? _decode(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final i = url.indexOf(',');
      return base64Decode(i >= 0 ? url.substring(i + 1) : url);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = KScheme.of(context);

    // Put the picker above the message when there's room, else below.
    const pickerH = 60.0;
    const gap = 10.0;
    final above = anchor.top > pickerH + gap + 40;
    final pickerTop =
        above ? anchor.top - pickerH - gap : anchor.bottom + gap;

    // Action card goes on the opposite side of the message.
    final actionsTop = above ? anchor.bottom + gap : null;
    final actionsBottom =
        above ? null : size.height - (anchor.top - gap);

    final left = (anchor.left).clamp(12.0, size.width - 300.0);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // tap anywhere to dismiss
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),

          // the message itself, kept lit above the dim
          if (actionsEnabled)
            Positioned(
              left: anchor.left,
              top: anchor.top,
              width: anchor.width,
              // never taller than the real bubble, and never huge
              height: anchor.height.clamp(0.0, 260.0),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: mine ? s.mine : s.theirs,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(15),
                      topRight: const Radius.circular(15),
                      bottomLeft: Radius.circular(mine ? 15 : 5),
                      bottomRight: Radius.circular(mine ? 5 : 15),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  padding: message.kind == 'img'
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.fromLTRB(13, 9, 13, 7),
                  child: _preview(s),
                ),
              ),
            ),

          // emoji bar
          Positioned(
            left: left,
            top: pickerTop,
            child: _Picker(anim: anim, current: current),
          ),

          // actions card
          if (actionsEnabled)
            Positioned(
              left: left,
              top: actionsTop,
              bottom: actionsBottom,
              child: _Actions(anim: anim, mine: mine, message: message),
            ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  final Animation<double> anim;
  final String? current;
  const _Picker({required this.anim, required this.current});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
      alignment: Alignment.bottomLeft,
      child: FadeTransition(
        opacity: anim,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ReactionOverlay.quick.length; i++)
                _Emoji(
                  emoji: ReactionOverlay.quick[i],
                  index: i,
                  anim: anim,
                  selected: current == ReactionOverlay.quick[i],
                ),
              // "+" opens the full emoji keyboard
              _Rise(
                index: ReactionOverlay.quick.length,
                anim: anim,
                child: GestureDetector(
                  onTap: () async {
                    final picked = await _pickAny(context);
                    if (picked != null && context.mounted) {
                      Navigator.of(context).pop(picked);
                    }
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      color: s.panel2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_rounded, color: s.muted, size: 21),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickAny(BuildContext context) {
    final s = KScheme.of(context);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (cat, e) => Navigator.of(ctx).pop(e.emoji),
          config: Config(
            height: 320,
            emojiViewConfig: EmojiViewConfig(
              backgroundColor: s.panel,
              columns: 8,
              emojiSizeMax: 28,
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: s.panel,
              indicatorColor: KColors.teal,
              iconColorSelected: KColors.teal,
              backspaceColor: KColors.teal,
            ),
            bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
            searchViewConfig: SearchViewConfig(backgroundColor: s.panel),
          ),
        ),
      ),
    );
  }
}

/// One emoji that rises into place, slightly after the one before it.
class _Emoji extends StatelessWidget {
  final String emoji;
  final int index;
  final Animation<double> anim;
  final bool selected;
  const _Emoji({
    required this.emoji,
    required this.index,
    required this.anim,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return _Rise(
      index: index,
      anim: anim,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(emoji),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: selected
              ? const BoxDecoration(
                  color: KColors.tealSoft, shape: BoxShape.circle)
              : null,
          child: Text(emoji,
              style: TextStyle(fontSize: selected ? 32 : 29)),
        ),
      ),
    );
  }
}

/// Staggered rise-and-scale for each item in the bar.
class _Rise extends StatelessWidget {
  final int index;
  final Animation<double> anim;
  final Widget child;
  const _Rise({
    required this.index,
    required this.anim,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.07).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: anim,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (_, c) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curve.value)),
          child: Transform.scale(scale: curve.value.clamp(0.0, 1.0), child: c),
        ),
      ),
      child: child,
    );
  }
}

class _Actions extends StatelessWidget {
  final Animation<double> anim;
  final bool mine;
  final Message message;
  const _Actions({
    required this.anim,
    required this.mine,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final canCopy = message.kind == 'text' && (message.body ?? '').isNotEmpty;

    return ScaleTransition(
      scale: CurvedAnimation(
        parent: anim,
        curve: const Interval(0.08, 1, curve: Curves.easeOutBack),
      ),
      alignment: Alignment.topLeft,
      child: FadeTransition(
        opacity: anim,
        child: Container(
          constraints: const BoxConstraints(minWidth: 196),
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Item(
                icon: Icons.reply_rounded,
                label: 'Reply',
                onTap: () => Navigator.of(context).pop('reply'),
              ),
              if (canCopy)
                _Item(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () => Navigator.of(context).pop('copy'),
                ),
              _Item(
                icon: Icons.delete_outline_rounded,
                label: mine ? 'Delete for everyone' : 'Delete for me',
                danger: true,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final c = danger ? KColors.danger : s.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: danger ? KColors.danger : KColors.teal),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 14.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

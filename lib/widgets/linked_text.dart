import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/colors.dart';

/// Renders message text with phone numbers, emails and links picked out,
/// underlined and tappable — the way WhatsApp does it.
class LinkedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;

  const LinkedText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor = KColors.teal,
  });

  // Indian and international numbers: +91 98765 43210, 09876543210,
  // 98765-43210, (040) 2345 6789 …
  static final _phone = RegExp(
      r'(?:(?:\+|00)\d{1,3}[\s.-]?)?(?:\(\d{2,5}\)[\s.-]?)?\d(?:[\d\s.-]{7,13})\d');
  static final _email =
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+', caseSensitive: false);
  static final _url = RegExp(
      r'(?:https?://|www\.)[^\s<>"]+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final spans = _build(context);
    if (spans.length == 1 && spans.first is TextSpan) {
      final only = spans.first as TextSpan;
      if (only.recognizer == null) {
        return Text(text, style: style);
      }
    }
    return Text.rich(TextSpan(children: spans), style: style);
  }

  List<InlineSpan> _build(BuildContext context) {
    final matches = <_Hit>[];

    void collect(RegExp re, _Kind kind) {
      for (final m in re.allMatches(text)) {
        final value = m.group(0)!;
        // a "phone number" needs enough digits to be real
        if (kind == _Kind.phone) {
          final digits = value.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 8 || digits.length > 15) continue;
        }
        // don't let a phone match sit inside an email or url
        if (matches.any((h) => m.start < h.end && m.end > h.start)) continue;
        matches.add(_Hit(m.start, m.end, value, kind));
      }
    }

    // order matters: urls and emails first, so digits inside them are safe
    collect(_url, _Kind.url);
    collect(_email, _Kind.email);
    collect(_phone, _Kind.phone);
    matches.sort((a, b) => a.start.compareTo(b.start));

    if (matches.isEmpty) return [TextSpan(text: text)];

    final spans = <InlineSpan>[];
    var i = 0;
    for (final h in matches) {
      if (h.start > i) {
        spans.add(TextSpan(text: text.substring(i, h.start)));
      }
      spans.add(TextSpan(
        text: h.value,
        style: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _onTap(context, h),
      ));
      i = h.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return spans;
  }

  void _onTap(BuildContext context, _Hit hit) {
    switch (hit.kind) {
      case _Kind.phone:
        _phoneSheet(context, hit.value);
        break;
      case _Kind.email:
        _open('mailto:${hit.value}');
        break;
      case _Kind.url:
        final u = hit.value.startsWith('http')
            ? hit.value
            : 'https://${hit.value}';
        _open(u);
        break;
    }
  }

  /// Tapping a number offers to call, message or copy it.
  void _phoneSheet(BuildContext context, String number) {
    final s = KScheme.of(context);
    final clean = number.replaceAll(RegExp(r'[^\d+]'), '');
    showModalBottomSheet(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(number,
                  style: TextStyle(
                      color: s.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ),
            Divider(height: 1, color: s.line),
            ListTile(
              leading: const Icon(Icons.call_rounded, color: KColors.teal),
              title: Text('Call', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                _open('tel:$clean');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sms_rounded, color: KColors.teal),
              title: Text('Send SMS', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                _open('sms:$clean');
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: KColors.teal),
              title: Text('Copy number', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: number));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied'),
                      duration: Duration(seconds: 1)),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String uri) async {
    try {
      final u = Uri.parse(uri);
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}

enum _Kind { phone, email, url }

class _Hit {
  final int start;
  final int end;
  final String value;
  final _Kind kind;
  _Hit(this.start, this.end, this.value, this.kind);
}

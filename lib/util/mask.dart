/// Masks phone numbers and email addresses in message text so contact details
/// aren't exposed on screen.
///
/// Display-only: the original text stays in the encrypted payload and is
/// stored unchanged — masking happens when the message is drawn. This mirrors
/// js/filters.js in the web app exactly so both sides look the same.
class Mask {
  /// email → first char + ***** @ + domain first char + ****
  static final _email = RegExp(
    r'\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9])[A-Za-z0-9.-]*\.[A-Za-z]{2,}\b',
  );

  /// phone → run of digits (spaces, +, -, brackets allowed)
  static final _phone = RegExp(r'(\+?\d[\d\s\-()]{8,}\d)');

  static String sensitive(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    var t = text;

    t = t.replaceAllMapped(_email, (m) {
      final a = m.group(1)!;
      final b = m.group(2)!;
      return '$a${'*' * 5}@$b${'*' * 4}';
    });

    t = t.replaceAllMapped(_phone, (m) {
      final whole = m.group(0)!;
      final digits = whole.replaceAll(RegExp(r'\D'), '');
      // too short or too long to be a phone number — leave it alone
      if (digits.length < 10 || digits.length > 15) return whole;
      // keep the last 3 digits, mask the rest
      return '${'*' * (digits.length - 3)}${digits.substring(digits.length - 3)}';
    });

    return t;
  }
}

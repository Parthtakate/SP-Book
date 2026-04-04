/// Utility to safely render any string from local storage.
/// Strips or replaces any invalid UTF-8 / non-printable characters that
/// would cause a _NativeParagraphBuilder.addText crash in Flutter's text engine.
///
/// Also strips lone UTF-16 surrogate codeunits (0xD800–0xDFFF) which cause
/// the "string is not well-formed UTF-16" fatal crash seen in Crashlytics.
String safeText(String? value, {String fallback = ''}) {
  if (value == null || value.isEmpty) return fallback;
  try {
    final units = value.codeUnits;
    final filtered = <int>[];
    int i = 0;
    while (i < units.length) {
      final c = units[i];
      // High surrogate — must be followed by a low surrogate
      if (c >= 0xD800 && c <= 0xDBFF) {
        if (i + 1 < units.length) {
          final next = units[i + 1];
          if (next >= 0xDC00 && next <= 0xDFFF) {
            // Valid surrogate pair — keep both
            filtered.add(c);
            filtered.add(next);
            i += 2;
            continue;
          }
        }
        // Lone high surrogate — drop it
        i++;
        continue;
      }
      // Lone low surrogate — drop it
      if (c >= 0xDC00 && c <= 0xDFFF) {
        i++;
        continue;
      }
      // Keep printable characters and standard whitespace
      if (c >= 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        filtered.add(c);
      }
      i++;
    }
    final result = String.fromCharCodes(filtered);
    return result.isEmpty ? fallback : result;
  } catch (_) {
    return fallback;
  }
}


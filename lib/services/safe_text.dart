/// Utility to safely render any string from local storage.
/// Strips or replaces any invalid UTF-8 / non-printable characters that
/// would cause a _NativeParagraphBuilder.addText crash in Flutter's text engine.
String safeText(String? value, {String fallback = ''}) {
  if (value == null || value.isEmpty) return fallback;
  try {
    // Re-encode through UTF-8 to strip any malformed byte sequences
    final bytes = value.codeUnits;
    return String.fromCharCodes(
      bytes.where((c) => c >= 0x20 || c == 0x09 || c == 0x0A || c == 0x0D),
    );
  } catch (_) {
    return fallback;
  }
}

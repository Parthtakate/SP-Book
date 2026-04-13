void main() {
  String input = '₹🐂 Indra 🐂 and Jdhrusjcbsji❤️🌅🐥🙂😘🫂😘🫂 123 !@#₹ ₹500';
  String clean = input.replaceAll(RegExp(r'[^\p{L}\p{N}\p{P}\p{Z}\p{Sc}\p{M}]', unicode: true), '');
  print('Regex 2: $clean');
}

class PasswordValidationState {
  final bool minLength;
  final bool upper;
  final bool lower;
  final bool number;
  final bool special;
  final bool match;

  const PasswordValidationState({
    required this.minLength,
    required this.upper,
    required this.lower,
    required this.number,
    required this.special,
    required this.match,
  });

  bool get allValid =>
      minLength && upper && lower && number && special && match;
}

class PasswordValidator {
  static PasswordValidationState validate({
    required String password,
    required String confirm,
  }) {
    final p = password;
    return PasswordValidationState(
      minLength: p.length >= 8,
      upper: RegExp(r'[A-Z]').hasMatch(p),
      lower: RegExp(r'[a-z]').hasMatch(p),
      number: RegExp(r'[0-9]').hasMatch(p),
      special: RegExp(r'[^A-Za-z0-9]').hasMatch(p),
      match: confirm.isNotEmpty && p == confirm,
    );
  }
}

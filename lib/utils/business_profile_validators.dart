class BusinessProfileValidators {
  static const int maximumTeamSize = 100000;

  static String? requiredText(
    String? value,
    String label, {
    int minimumLength = 2,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    if (text.length < minimumLength) {
      return '$label must be at least $minimumLength characters.';
    }
    if (!RegExp(
      r'[A-Za-z\u00C0-\u02AF\u0370-\u052F\u0621-\u064A\u066E-\u06D3\u0900-\u0D7F]',
    ).hasMatch(text)) {
      return '$label must contain at least one letter.';
    }
    return null;
  }

  static String? teamSize(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Team Size is required.';
    final size = int.tryParse(text);
    if (size == null || size < 1 || size > maximumTeamSize) {
      return 'Enter a whole number from 1 to $maximumTeamSize.';
    }
    return null;
  }

  static String? address(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Address is required.';
    if (text.length < 5) return 'Address must be at least 5 characters.';
    return null;
  }

  static String? phone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Phone is required.';
    if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(text)) {
      return 'Use only digits, +, spaces, hyphens, and parentheses.';
    }
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      return 'Enter a phone number with 7 to 15 digits.';
    }
    return null;
  }

  static String? email(String? value, {String expected = ''}) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return 'Work Email is required.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    final normalizedExpected = expected.trim().toLowerCase();
    if (normalizedExpected.isNotEmpty && text != normalizedExpected) {
      return 'Owner email must match your signed-in account.';
    }
    return null;
  }

  static String? website(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        !uri.host.contains('.')) {
      return 'Enter a valid http or https website address.';
    }
    return null;
  }
}

class BusinessInvoice {
  final String id;
  final String orgId;
  final String invoiceNumber;
  final double? amount;
  final String currency;
  final String? billingCycle;
  final DateTime? dueDate;
  final String status;
  final String? paymentReference;
  final DateTime? dateCreated;

  const BusinessInvoice({
    required this.id,
    required this.orgId,
    required this.invoiceNumber,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    required this.dueDate,
    required this.status,
    required this.paymentReference,
    required this.dateCreated,
  });

  factory BusinessInvoice.fromJson(Map<String, dynamic> json) {
    return BusinessInvoice(
      id: json['id']?.toString() ?? '',
      orgId: _extractId(json['org_id']) ?? '',
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      amount: _toDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'USD',
      billingCycle: json['billing_cycle']?.toString(),
      dueDate: _toDate(json['due_date']),
      status: json['status']?.toString() ?? '',
      paymentReference: json['payment_reference']?.toString(),
      dateCreated: _toDate(json['date_created']),
    );
  }

  static String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num) return value.toString();
    if (value is Map && value['id'] != null) {
      return value['id'].toString();
    }
    return null;
  }

  static DateTime? _toDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value);
    }
    return null;
  }
}

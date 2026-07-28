import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/request_service.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_cards.dart';
import '../widgets/state_views.dart';

class RequestDetailsScreen extends StatefulWidget {
  final String requestId;

  const RequestDetailsScreen({super.key, required this.requestId});

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() {
    return RequestService.instance.fetchRequestDetailsRaw(
      requestId: widget.requestId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: RefreshIndicator(
              color: AppColors.primarySoft,
              onRefresh: () async {
                final next = _load();
                setState(() => _future = next);
                await next;
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: FutureBuilder<Map<String, dynamic>?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SkeletonList();
                    }
                    if (snapshot.hasError) {
                      return StatusCard(
                        title: 'Request details unavailable',
                        message: snapshot.error.toString(),
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.highRisk,
                        actionText: 'Retry',
                        onAction: () {
                          setState(() => _future = _load());
                        },
                      );
                    }
                    final raw = snapshot.data;
                    if (raw == null || raw.isEmpty) {
                      return const EmptyStateCard(
                        title: 'Request not found',
                        message: 'No details returned from backend.',
                      );
                    }
                    return _RequestDetailsBody(raw: raw);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestDetailsBody extends StatelessWidget {
  final Map<String, dynamic> raw;

  const _RequestDetailsBody({required this.raw});

  @override
  Widget build(BuildContext context) {
    final status = _text(raw['response_status']) ?? _text(raw['status']) ?? '-';
    final target = _text(raw['Target']) ?? _text(raw['target']) ?? '-';
    final requiredState = _text(raw['required_state']) ?? '-';
    final timestamp =
        _text(raw['requested_at']) ?? _text(raw['timestamp']) ?? '-';
    final scanId = _extractId(raw['scan_id']) ?? '-';
    final requestedBy =
        _asMap(raw['requested_by_user']) ?? _asMap(raw['user_created']);
    final targetMember = _asMap(raw['target_member']);
    final requestedFor =
        _asMap(raw['requested_for_user']) ??
        _asMap(raw['requested_for']) ??
        _asMap(targetMember?['user']) ??
        targetMember;
    final business = _asMap(raw['business_profile']);
    final payload = raw['response_payload'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    raw['id']?.toString() ?? '-',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _statusChip(status),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _row('Target', target),
              _row('Required State', requiredState),
              _row('Response Status', status),
              _row('Timestamp', timestamp),
              _row('Scan ID', scanId),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Requested By',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _row('Name', _fullName(requestedBy)),
              _row('Email', _text(requestedBy?['email']) ?? '-'),
              _row('Phone', _text(requestedBy?['phone']) ?? '-'),
              _row(
                'User ID',
                _extractId(raw['requested_by_user']) ??
                    _extractId(raw['user_created']) ??
                    '-',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Requested For',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _row('Name', _fullName(requestedFor)),
              _row(
                'Email',
                _text(requestedFor?['email']) ??
                    _text(raw['requested_for_email']) ??
                    _text(raw['recipient_email']) ??
                    '-',
              ),
              _row(
                'Phone',
                _text(requestedFor?['phone']) ??
                    _text(raw['requested_for_phone']) ??
                    '-',
              ),
              _row(
                'User ID',
                _extractId(raw['requested_for_user']) ??
                    _extractId(raw['requested_for']) ??
                    _extractId(targetMember?['user']) ??
                    '-',
              ),
            ],
          ),
        ),
        if (business != null) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Business Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _row('Profile ID', _extractId(raw['business_profile']) ?? '-'),
                _row(
                  'Business Name',
                  _text(business['business_name']) ??
                      _text(business['company_name']) ??
                      '-',
                ),
                _row('Plan', _text(business['plan_code']) ?? '-'),
                _row(
                  'Billing Status',
                  _text(business['billing_status']) ?? '-',
                ),
              ],
            ),
          ),
        ],
        if (payload != null) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Response Payload',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundAlt.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SelectableText(
                    _prettyPayload(payload),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();
    Color color;
    switch (normalized) {
      case 'approved':
        color = AppColors.stable;
        break;
      case 'denied':
        color = AppColors.highRisk;
        break;
      case 'delayed':
        color = AppColors.elevated;
        break;
      default:
        color = AppColors.lowFocus;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _prettyPayload(dynamic payload) {
    if (payload == null) return '-';
    if (payload is String) return payload;
    try {
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
      return payload.toString();
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num) return value.toString();
    if (value is Map && value['id'] != null) return value['id'].toString();
    return null;
  }

  String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String _fullName(Map<String, dynamic>? map) {
    if (map == null) return '-';
    final first = _text(map['first_name']);
    final last = _text(map['last_name']);
    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    if (last != null) return last;
    return _text(map['email']) ?? _extractId(map) ?? '-';
  }
}

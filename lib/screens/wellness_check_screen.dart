import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/page_transition.dart';
import 'scan/scan_premium_components.dart';
import 'scan_flow_impl_normalized.dart';

class WellnessCheckScreen extends StatelessWidget {
  const WellnessCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumScanScaffold(
      stepLabel: 'Start check-in',
      onBack: () => Navigator.maybePop(context),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ready for your check-in?',
              style: GoogleFonts.spaceGrotesk(
                color: ScanTheme.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A quick readiness check using camera, voice, and focus signals.',
              style: GoogleFonts.inter(
                color: ScanTheme.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            const _OverviewHero(),
            const SizedBox(height: 18),
            const _ModuleCard(
              icon: Icons.face_retouching_natural_outlined,
              title: '1. Camera check',
              description: 'Keep your face centered while we record a short clip.',
              accent: ScanTheme.primaryBlue,
            ),
            const SizedBox(height: 12),
            const _ModuleCard(
              icon: Icons.graphic_eq_rounded,
              title: '2. Voice check',
              description: 'Speak clearly so we can review voice clarity and signal quality.',
              accent: ScanTheme.cyan,
            ),
            const SizedBox(height: 12),
            const _ModuleCard(
              icon: Icons.grid_view_rounded,
              title: '3. Focus task',
              description: 'Complete a quick reaction task while the assessment finishes preparing.',
              accent: ScanTheme.teal,
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: ScanTheme.cyan.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ScanTheme.cyan.withOpacity(0.28)),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: ScanTheme.cyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secure and private',
                          style: GoogleFonts.inter(
                            color: ScanTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your assessment is handled securely.',
                          style: GoogleFonts.inter(
                            color: ScanTheme.textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: Column(
        children: [
          ScanPrimaryButton(
            label: 'Start readiness check',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              Navigator.push(
                context,
                fadeSlideRoute(const ScanFlowScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          ScanSecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ScanTheme.primaryBlue.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Under 2 minutes',
                  style: GoogleFonts.inter(
                    color: ScanTheme.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const StatusPill(
                label: '3-step check',
                color: ScanTheme.teal,
                icon: Icons.radar_rounded,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Camera, voice, and focus signals come together in one guided assessment.',
            style: GoogleFonts.inter(
              color: ScanTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const ScanProgressBar(value: 0.18),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accent;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.32)),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

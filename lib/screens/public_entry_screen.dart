import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import 'invite_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

const _entryTeal = Color(0xFF12B892);
const _entryTealDeep = Color(0xFF0B7A63);

class PublicEntryScreen extends StatefulWidget {
  const PublicEntryScreen({super.key});

  @override
  State<PublicEntryScreen> createState() => _PublicEntryScreenState();
}

class _PublicEntryScreenState extends State<PublicEntryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _idleController;
  late final AnimationController _scanController;
  late final AnimationController _shineController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _brandFade;
  late final Animation<Offset> _brandSlide;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _idleScale;
  bool _reduceMotion = false;
  bool _motionPreferenceRead = false;
  bool _entranceStarted = false;
  bool _entranceCompleted = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    _logoFade = Tween<double>(begin: 0.01, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.62, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.62, curve: Curves.easeOutBack),
      ),
    );
    _brandFade = Tween<double>(begin: 0.01, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.17, 0.67, curve: Curves.easeOut),
      ),
    );
    _brandSlide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.17, 0.67, curve: Curves.easeOutCubic),
          ),
        );
    _cardFade = Tween<double>(begin: 0.01, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 0.80, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
          ),
        );
    _idleScale = Tween<double>(begin: 1, end: 1.025).animate(
      CurvedAnimation(parent: _idleController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldReduceMotion = MediaQuery.of(context).disableAnimations;
    if (!_motionPreferenceRead) {
      _motionPreferenceRead = true;
      _reduceMotion = shouldReduceMotion;
      if (shouldReduceMotion) {
        _entranceController.value = 1;
        _entranceCompleted = true;
      } else {
        _scanController.repeat();
        _shineController.repeat();
        _startEntrance();
      }
      return;
    }

    if (shouldReduceMotion == _reduceMotion) return;
    _reduceMotion = shouldReduceMotion;
    if (shouldReduceMotion) {
      _entranceController.stop();
      _entranceController.value = 1;
      _idleController.stop();
      _scanController.stop();
      _shineController.stop();
      _entranceCompleted = true;
    } else if (_entranceCompleted) {
      _scanController.repeat();
      _shineController.repeat();
      _idleController.repeat(reverse: true);
    } else if (!_entranceStarted) {
      _scanController.repeat();
      _shineController.repeat();
      _startEntrance();
    }
  }

  void _startEntrance() {
    if (_entranceStarted) return;
    _entranceStarted = true;
    _entranceController.forward().whenComplete(() {
      if (!mounted) return;
      _entranceCompleted = true;
      if (!_reduceMotion) _idleController.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _idleController.dispose();
    _scanController.dispose();
    _shineController.dispose();
    super.dispose();
  }

  void _openSignIn(BuildContext context) {
    Navigator.push(context, fadeSlideRoute(const LoginScreen()));
  }

  void _openStartOrganization(BuildContext context) {
    Navigator.push(context, fadeSlideRoute(const RegisterScreen()));
  }

  void _openInviteSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _InviteCodeSheet(
          controller: controller,
          onContinue: (token) {
            Navigator.of(sheetContext).pop();
            Navigator.push(context, fadeSlideRoute(InviteScreen(token: token)));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2424), Color(0xFF081521), Color(0xFF04060F)],
            stops: [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      _buildBrandBlock(),
                      const SizedBox(height: 36),
                      _reveal(
                        _buildEntryCard(context),
                        opacity: _cardFade,
                        slide: _cardSlide,
                      ),
                      const SizedBox(height: 28),
                      _buildFooter(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _reveal(
    Widget child, {
    required Animation<double> opacity,
    required Animation<Offset> slide,
  }) {
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: slide, child: child),
    );
  }

  Widget _buildBrandBlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _idleScale,
          child: FadeTransition(
            opacity: _logoFade,
            child: ScaleTransition(
              scale: _logoScale,
              child: SizedBox(
                width: 74,
                height: 74,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_reduceMotion)
                      AnimatedBuilder(
                        animation: _scanController,
                        builder: (context, child) => Transform.rotate(
                          angle: _scanController.value * 2 * 3.141592653589793,
                          child: child,
                        ),
                        child: CustomPaint(
                          size: const Size.square(74),
                          painter: _ScanningRingPainter(),
                        ),
                      ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_entryTeal, _entryTealDeep],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _entryTeal.withValues(alpha: 0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.monitor_heart_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          builder: (context, badge) => Transform.scale(
            scale: _reduceMotion ? 1 : _idleScale.value,
            child: badge,
          ),
        ),
        const SizedBox(height: 18),
        _reveal(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WISEBASE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 34,
                  letterSpacing: 6.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Workforce wellness intelligence',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
          opacity: _brandFade,
          slide: _brandSlide,
        ),
      ],
    );
  }

  Widget _buildEntryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1428),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E2B45)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to your workspace, or start your organization to begin using Wisebase.',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          _PrimaryEntryButton(
            label: 'Sign in',
            onTap: () => _openSignIn(context),
            shineController: _shineController,
            reduceMotion: _reduceMotion,
          ),
          const SizedBox(height: 12),
          _SecondaryEntryButton(
            label: 'Start organization',
            onTap: () => _openStartOrganization(context),
            shineController: _shineController,
            reduceMotion: _reduceMotion,
          ),
          const SizedBox(height: 8),
          Text(
            'For company owners',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 11.5,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _openInviteSheet(context),
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                ),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return const Color(0xFF56E1C1);
                  }
                  return _entryTeal;
                }),
                overlayColor: WidgetStatePropertyAll(
                  _entryTeal.withValues(alpha: 0.12),
                ),
                textStyle: WidgetStateProperty.resolveWith((states) {
                  final isInteractive =
                      states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused);
                  return GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                    decoration: isInteractive
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  );
                }),
                animationDuration: const Duration(milliseconds: 180),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Have an invite code?',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Opacity(
      opacity: 0.55,
      child: Text(
        'WORKFORCE WELLNESS INTELLIGENCE',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 10,
          letterSpacing: 3.2,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}

class _PrimaryEntryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final AnimationController? shineController;
  final bool reduceMotion;

  const _PrimaryEntryButton({
    required this.label,
    required this.onTap,
    this.shineController,
    this.reduceMotion = true,
  });

  @override
  State<_PrimaryEntryButton> createState() => _PrimaryEntryButtonState();
}

class _PrimaryEntryButtonState extends State<_PrimaryEntryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 130),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: SizedBox(
        height: 50,
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_entryTeal, _entryTealDeep],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _entryTeal.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: widget.onTap,
                      onHighlightChanged: (pressed) {
                        if (_pressed != pressed) {
                          setState(() => _pressed = pressed);
                        }
                      },
                      splashColor: Colors.white.withValues(alpha: 0.16),
                      highlightColor: Colors.white.withValues(alpha: 0.08),
                      hoverColor: _entryTeal.withValues(alpha: 0.08),
                      focusColor: _entryTeal.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: Text(
                          widget.label,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.reduceMotion && widget.shineController != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ButtonShinePainter(widget.shineController!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryEntryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final AnimationController? shineController;
  final bool reduceMotion;

  const _SecondaryEntryButton({
    required this.label,
    required this.onTap,
    this.shineController,
    this.reduceMotion = true,
  });

  @override
  State<_SecondaryEntryButton> createState() => _SecondaryEntryButtonState();
}

class _SecondaryEntryButtonState extends State<_SecondaryEntryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 130),
      curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
      child: SizedBox(
        height: 50,
        width: double.infinity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: _pressed
                ? _entryTeal.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed
                  ? _entryTeal.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  child: InkWell(
                    onTap: widget.onTap,
                    onHighlightChanged: (pressed) {
                      if (_pressed != pressed) {
                        setState(() => _pressed = pressed);
                      }
                    },
                    splashColor: _entryTeal.withValues(alpha: 0.12),
                    highlightColor: _entryTeal.withValues(alpha: 0.07),
                    hoverColor: _entryTeal.withValues(alpha: 0.08),
                    focusColor: _entryTeal.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    child: Center(
                      child: Text(
                        widget.label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!widget.reduceMotion && widget.shineController != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ButtonShinePainter(widget.shineController!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanningRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = const SweepGradient(
      colors: [
        Colors.transparent,
        Color(0x2212B892),
        Color(0xFF12B892),
        Color(0x2212B892),
        Colors.transparent,
      ],
      stops: [0, 0.30, 0.52, 0.74, 1],
    ).createShader(rect);
    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2 - 1,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanningRingPainter oldDelegate) => false;
}

class _ButtonShinePainter extends CustomPainter {
  final AnimationController controller;

  _ButtonShinePainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = controller.value;
    if (progress > 0.25 || size.isEmpty) return;
    final travel = progress / 0.25;
    final bandWidth = size.width * 0.30;
    final centerX = -bandWidth + (size.width + bandWidth * 2) * travel;
    final bandRect = Rect.fromCenter(
      center: Offset(centerX, size.height / 2),
      width: bandWidth,
      height: size.height * 1.8,
    );
    final shader = const LinearGradient(
      colors: [Colors.transparent, Color(0x2EFFFFFF), Colors.transparent],
      stops: [0, 0.5, 1],
    ).createShader(bandRect);
    final path = Path()
      ..moveTo(centerX - bandWidth / 2 + size.height * 0.34, 0)
      ..lineTo(centerX + bandWidth / 2 + size.height * 0.34, 0)
      ..lineTo(centerX + bandWidth / 2 - size.height * 0.34, size.height)
      ..lineTo(centerX - bandWidth / 2 - size.height * 0.34, size.height)
      ..close();
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
    );
    canvas.drawPath(path, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ButtonShinePainter oldDelegate) =>
      oldDelegate.controller != controller;
}

class _InviteCodeSheet extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String token) onContinue;

  const _InviteCodeSheet({required this.controller, required this.onContinue});

  @override
  State<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends State<_InviteCodeSheet> {
  String? _error;

  void _submit() {
    final token = widget.controller.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Enter your invite code to continue.');
      return;
    }
    widget.onContinue(token);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Enter your invite code',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the invite code your team shared with you.',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: widget.controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Invite code',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _entryTeal,
                        width: 1.4,
                      ),
                    ),
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                _PrimaryEntryButton(label: 'Continue', onTap: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

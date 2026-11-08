/// The handoff design (`docs/gatelog-handoff/design`) for the screens built to its rules: the
/// rider view, rider shift start, "Shuttle to the home", the CSO's Shuttle tab and Issue a card.
///
/// One job per screen, big icons and big words, Yes or No instead of lists, no typing, every
/// result read aloud. Charcoal with a fabric twill at night, sterile white by day, following the
/// estate's time of day. Inter for words, JetBrains Mono for data. The older guard and CSO
/// screens keep `theme.dart` until their redesign is approved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app.dart';

const inter = 'Inter';
const mono = 'JetBrainsMono';

/// The design tokens for night and day (design/README.md, "Tokens").
class Palette {
  const Palette._({
    required this.night,
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.no,
    required this.noText,
    required this.warn,
    required this.warnText,
    required this.blue,
  });

  final bool night;
  final Color bg;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;

  /// The primary button: inverted text colours.
  final Color accent;
  final Color onAccent;

  /// SOS and No.
  final Color no;
  final Color noText;

  /// Warning, offline, unverified.
  final Color warn;
  final Color warnText;

  /// Guard blue.
  final Color blue;

  static const nightP = Palette._(
    night: true,
    bg: Color(0xFF111111),
    surface: Color(0xFF1C1C1C),
    text: Color(0xFFF4F4F2),
    muted: Color(0xFFA8A8A6),
    line: Color(0x1AF4F4F2),
    accent: Color(0xFFF4F4F2),
    onAccent: Color(0xFF111111),
    no: Color(0xFFFF5A4E),
    noText: Color(0xFFFF5A4E),
    warn: Color(0xFFF5C542),
    warnText: Color(0xFFF5C542),
    blue: Color(0xFF5AA9FF),
  );

  static const dayP = Palette._(
    night: false,
    bg: Color(0xFFF2F2F0),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF141414),
    muted: Color(0xFF4A4A48),
    line: Color(0x1A141414),
    accent: Color(0xFF141414),
    onAccent: Color(0xFFFFFFFF),
    no: Color(0xFFD92D20),
    noText: Color(0xFFB42318),
    warn: Color(0xFFF5C542),
    warnText: Color(0xFF8A5A00),
    blue: Color(0xFF1D63C9),
  );

  /// Night from 19:00 to 06:59 in the estate's time zone.
  static Palette at(DateTime local) => local.hour >= 19 || local.hour < 7 ? nightP : dayP;

  /// Override for screenshots and tests: null follows the time of day.
  static bool? forceNight;

  static Palette of(BuildContext context) {
    final f = forceNight;
    if (f != null) return f ? nightP : dayP;
    return at(GateScope.of(context).time.now());
  }
}

// --- read aloud ----------------------------------------------------------------------------------

FlutterTts? _tts;

/// Reads [text] aloud, English. Replaced in tests. Never pass a phone number, a code or a UID.
Future<void> Function(String text) speak = (text) async {
  try {
    final tts = _tts ??= FlutterTts();
    await tts.setLanguage('en-GB');
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);
  } catch (_) {
    // No text-to-speech engine: the words are on the screen anyway.
  }
};

// --- surfaces --------------------------------------------------------------------------------------

/// The fabric twill on the night background.
class _Fabric extends CustomPainter {
  const _Fabric();
  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1;
    final dark = Paint()
      ..color = const Color(0x59000000)
      ..strokeWidth = 1;
    final n = (size.width + size.height) ~/ 3 + 1;
    for (var i = 0; i < n; i++) {
      final d = i * 3.0;
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), light);
      canvas.drawLine(Offset(d - size.height, 0), Offset(d, size.height), dark);
    }
  }

  @override
  bool shouldRepaint(_Fabric oldDelegate) => false;
}

/// A screen in the design: background, fabric at night, Inter in the text colour, 20 px padding.
class KitScaffold extends StatelessWidget {
  const KitScaffold({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: KitSurface(
        child: SafeArea(
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The background and type of the design, for a part of an older screen (the CSO's Shuttle tab).
class KitSurface extends StatelessWidget {
  const KitSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ColoredBox(
      color: p.bg,
      child: CustomPaint(
        painter: p.night ? const _Fabric() : null,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontFamily: inter, color: p.text, fontSize: 18),
          child: IconTheme.merge(
            data: IconThemeData(color: p.text),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A round 48 px button (back, read aloud, menu).
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.label, required this.onTap, this.size = 52});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: p.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: 26, color: p.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back, a small mono label, and the read-aloud button.
class KitTopBar extends StatelessWidget {
  const KitTopBar({super.key, this.label, this.sayAloud, this.back = true, this.trailing});
  final String? label;

  /// What the read-aloud button says: the screen's question and what it is about.
  final String? sayAloud;
  final bool back;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (back) RoundButton(icon: Icons.arrow_back, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
          if (back) const SizedBox(width: 12),
          Expanded(
            child: Text(
              (label ?? '').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: mono, fontSize: 13, letterSpacing: 1.6, color: p.muted, fontWeight: FontWeight.w500),
            ),
          ),
          if (sayAloud != null) RoundButton(icon: Icons.volume_up_outlined, label: 'Read aloud', onTap: () => speak(sayAloud!)),
          ?trailing,
        ],
      ),
    );
  }
}

/// The one question on the screen, with its speaker icon.
class Headline extends StatelessWidget {
  const Headline(this.text, {super.key, this.size = 30, this.center = false, this.color});
  final String text;
  final double size;
  final bool center;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontFamily: inter, fontSize: size, fontWeight: FontWeight.w700, height: 1.15, color: color ?? Palette.of(context).text),
    ),
  );
}

/// A big filled tile: an icon over a word, radius 28. [primary] uses the inverted colours.
class BigTile extends StatelessWidget {
  const BigTile({super.key, required this.label, required this.onTap, this.icon, this.primary = false, this.color, this.height = 120, this.sub});
  final String label;
  final String? sub;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;

  /// Text and icon colour on the surface (No is red).
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = primary ? p.accent : p.surface;
    final fg = primary ? p.onAccent : (color ?? p.text);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: onTap == null ? bg.withValues(alpha: 0.4) : bg,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, size: 40, color: fg),
                  if (icon != null) const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: inter, fontSize: 24, fontWeight: FontWeight.w700, color: fg),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: inter, fontSize: 15, color: fg),
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

/// The 120 px Yes / No pair of Guard-Call.
class YesNo extends StatelessWidget {
  const YesNo({super.key, required this.onYes, required this.onNo, this.yes = 'Yes', this.no = 'No'});
  final VoidCallback? onYes;
  final VoidCallback? onNo;
  final String yes;
  final String no;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        Expanded(
          child: BigTile(label: yes, icon: Icons.check, primary: true, onTap: onYes),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: BigTile(label: no, icon: Icons.close, color: p.no, onTap: onNo),
        ),
      ],
    );
  }
}

/// A 56 px pill with a thin line (secondary actions at the bottom).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.onTap, this.icon, this.color});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = color ?? p.text;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: p.line, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 24, color: fg), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w600, color: fg),
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

/// A surface card, radius 24.
class KitCard extends StatelessWidget {
  const KitCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: child,
    );
  }
}

/// A big result: a round icon and a few words (Code is correct, Taken by Ade).
class ResultMark extends StatelessWidget {
  const ResultMark({super.key, required this.icon, required this.text, this.bad = false, this.warn = false});
  final IconData icon;
  final String text;
  final bool bad;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = bad ? p.no : (warn ? p.warn : p.accent);
    final fg = bad ? Colors.white : (warn ? const Color(0xFF141414) : p.onAccent);
    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 56, color: fg),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: inter, fontSize: 28, fontWeight: FontWeight.w700, color: p.text),
        ),
      ],
    );
  }
}

/// Filled and empty dots for a PIN or a house code.
class Dots extends StatelessWidget {
  const Dots({super.key, required this.filled, required this.length, this.error = false});
  final int filled;
  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$filled of $length numbers entered',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? (error ? p.no : p.text) : null,
                border: i < filled ? null : Border.all(color: error ? p.no : p.muted, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 3 by 4 keypad of Guard-ShiftStart: digits, × clears, → goes on.
class KitKeypad extends StatelessWidget {
  const KitKeypad({super.key, required this.onDigit, required this.onClear, required this.onGo, this.enabled = true, this.keyHeight = 66});
  final void Function(String) onDigit;
  final VoidCallback onClear;
  final VoidCallback? onGo;
  final bool enabled;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget key(String label, VoidCallback? tap, {String? semantics, bool go = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Semantics(
          button: true,
          label: semantics ?? 'Number $label',
          excludeSemantics: true,
          child: Material(
            color: go ? p.accent : p.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: enabled ? tap : null,
              child: SizedBox(
                height: keyHeight,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(fontFamily: mono, fontSize: 28, fontWeight: FontWeight.w500, color: go ? p.onAccent : p.text),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in r) key(d, () => onDigit(d))]),
        Row(
          children: [
            key('×', onClear, semantics: 'Clear'),
            key('0', () => onDigit('0')),
            key('→', onGo, semantics: 'Go on', go: true),
          ],
        ),
      ],
    );
  }
}

/// Mono data, large (house numbers, times).
TextStyle monoStyle(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w600}) =>
    TextStyle(fontFamily: mono, fontSize: size, fontWeight: weight, color: color ?? Palette.of(context).text, letterSpacing: 0.5);

TextStyle mutedStyle(BuildContext context, [double size = 16]) => TextStyle(fontFamily: inter, fontSize: size, color: Palette.of(context).muted);

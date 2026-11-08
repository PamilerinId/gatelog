import 'package:flutter/material.dart';

/// High contrast, large targets: a cheap phone in a guardhouse, in sun or at night.
abstract final class GateColors {
  static const navy = Color(0xFF0B1F3A);
  static const ink = Color(0xFF0A0A0A);
  static const paper = Color(0xFFFFFFFF);
  static const wash = Color(0xFFF1F4F8);
  static const line = Color(0xFFC9D1DC);
  static const go = Color(0xFF0B7A3B);
  static const stop = Color(0xFFB3261E);
  static const warn = Color(0xFF8A5A00);
  static const warnWash = Color(0xFFFFF4D6);
  static const goWash = Color(0xFFE3F5EA);
  static const stopWash = Color(0xFFFCE4E2);
  static const info = Color(0xFF1749A8);
  static const infoWash = Color(0xFFE5EDFB);
}

ThemeData gateTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: GateColors.navy, primary: GateColors.navy, surface: GateColors.paper, error: GateColors.stop);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: GateColors.paper);
  const big = Size(64, 64);
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: GateColors.ink, displayColor: GateColors.ink).copyWith(
          bodyLarge: const TextStyle(fontSize: 18, color: GateColors.ink),
          bodyMedium: const TextStyle(fontSize: 16, color: GateColors.ink),
          titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: GateColors.ink),
          titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GateColors.ink),
        ),
    appBarTheme: const AppBarTheme(backgroundColor: GateColors.navy, foregroundColor: Colors.white, centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: big, textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: big,
        foregroundColor: GateColors.navy,
        side: const BorderSide(color: GateColors.navy, width: 2),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, contentTextStyle: TextStyle(fontSize: 17)),
  );
}

/// A full-width button with a colour that says what it does.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onPressed, this.color, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(68));
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : FilledButton.icon(style: style, onPressed: onPressed, icon: Icon(icon, size: 28), label: Text(label));
  }
}

/// A coloured box for a verdict: green for go, red for stop, amber for wait.
class Verdict extends StatelessWidget {
  const Verdict({super.key, required this.title, required this.color, required this.wash, this.icon, this.children = const []});
  final String title;
  final Color color;
  final Color wash;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: wash, border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, color: color, size: 30), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800))),
            ]),
            if (children.isNotEmpty) const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: GateColors.wash,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: GateColors.navy)),
      );
}

void toast(BuildContext context, String message, {VoidCallback? undo}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 6),
    action: undo == null ? null : SnackBarAction(label: 'UNDO', onPressed: undo),
  ));
}

/// Ask for a guest's name. Returns null on cancel.
Future<String?> askGuestName(BuildContext context, {String title = 'Guest name', String? initial, String action = 'OK'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 20),
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 52)),
          onPressed: () => c.text.trim().isEmpty ? null : Navigator.pop(ctx, c.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, {String? body, String yes = 'Yes', String no = 'Cancel'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 52)), onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

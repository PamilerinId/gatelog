import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/no_code.dart';
import '../core/estate_time.dart';
import '../data/models.dart';
import 'theme.dart';

/// Opens the native dialler. The full number appears only here, in the `tel:` URI.
/// Replaced in widget tests, where there is no dialler.
Future<bool> Function(String number) dial = (number) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: number.replaceAll(' ', '')));
  } catch (_) {
    return false;
  }
};

/// Six boxes with a gap after the third. [obscure] shows dots (PINs).
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({super.key, required this.digits, this.length = 6, this.obscure = false, this.error = false});
  final String digits;
  final int length;
  final bool obscure;
  final bool error;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // Fitted to narrow phones (320dp and up).
        final w = ((box.maxWidth - 18) / length - 6).clamp(30.0, length == 6 ? 48.0 : 60.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i == 3 && length == 6) const SizedBox(width: 18),
              Container(
                width: w,
                height: 62,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: GateColors.wash,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: error ? GateColors.stop : (i == digits.length ? GateColors.navy : GateColors.line),
                    width: i == digits.length || error ? 3 : 2,
                  ),
                ),
                child: i < digits.length
                    ? (obscure
                        ? const Icon(Icons.circle, size: 18, color: GateColors.ink)
                        : Text(digits[i], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)))
                    : null,
              ),
            ],
          ],
        );
      });
}

/// The big number pad. Fills whatever height it is given.
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onDigit, required this.onBack, required this.onClear, this.enabled = true});
  final void Function(String) onDigit;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback onTap, {IconData? icon, String? semantics}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Semantics(
              label: semantics ?? label,
              button: true,
              child: Material(
                color: icon == null ? GateColors.wash : GateColors.paper,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: GateColors.line, width: 1.5)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled ? onTap : null,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, size: 34, color: GateColors.navy)
                        : Text(label, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: GateColors.ink)),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget row(List<Widget> keys) => Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: keys));
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 4, 11, 4),
      child: Column(children: [
        for (final r in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          row([for (final d in r) key(d, () => onDigit(d))]),
        row([
          key('', onClear, icon: Icons.clear, semantics: 'Clear'),
          key('0', () => onDigit('0')),
          key('', onBack, icon: Icons.backspace_outlined, semantics: 'Delete'),
        ]),
      ]),
    );
  }
}

/// Optional vehicle plate, collapsed so it never slows a pedestrian. Shows "Registered to this
/// home" when the typed plate is one of the home's vehicles.
class PlateField extends StatefulWidget {
  const PlateField({super.key, required this.controller, this.home});
  final TextEditingController controller;
  final Home? home;

  @override
  State<PlateField> createState() => _PlateFieldState();
}

class _PlateFieldState extends State<PlateField> {
  late bool _open = widget.controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _open = true),
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Vehicle plate'),
        ),
      );
    }
    final match = widget.home?.vehicleFor(widget.controller.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: widget.controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 20,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2),
        decoration: const InputDecoration(labelText: 'Vehicle plate (optional)', hintText: 'LND 123 AB', counterText: '', prefixIcon: Icon(Icons.directions_car_outlined)),
      ),
      if (match != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.verified, color: GateColors.go, size: 22),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Registered to this home${match.description == null || match.description!.isEmpty ? '' : ': ${match.description}'}',
                style: const TextStyle(fontSize: 17, color: GateColors.go, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// After the call: what did the resident say? Null if the guard closed the sheet.
Future<CallOutcome?> askCallOutcome(BuildContext context, Resident r, PhoneNumber n) => showModalBottomSheet<CallOutcome>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Called ${r.name}, ${n.masked}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            const Text('What did they say?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            BigButton(label: 'Confirmed', icon: Icons.check, color: GateColors.go, onPressed: () => Navigator.pop(ctx, CallOutcome.confirmed)),
            const SizedBox(height: 10),
            BigButton(label: 'Said no', icon: Icons.block, color: GateColors.stop, onPressed: () => Navigator.pop(ctx, CallOutcome.saidNo)),
            const SizedBox(height: 10),
            BigButton(label: 'No answer', icon: Icons.phone_missed, color: GateColors.warn, onPressed: () => Navigator.pop(ctx, CallOutcome.noAnswer)),
          ]),
        ),
      ),
    );

/// Turn away, with an optional reason. Returns null on cancel, '' for no reason.
Future<String?> askTurnAwayReason(BuildContext context, {String? suggested}) {
  final c = TextEditingController(text: suggested);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Turn away'),
      content: TextField(
        controller: c,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 280,
        maxLines: 2,
        style: const TextStyle(fontSize: 19),
        decoration: const InputDecoration(labelText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: GateColors.stop, minimumSize: const Size(120, 52)),
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('Turn away'),
        ),
      ],
    ),
  );
}

/// About an hour, a few hours, overnight, or until a date. Null on cancel.
Future<(Stay, DateTime?)?> pickStay(BuildContext context) async {
  final stay = await showModalBottomSheet<Stay>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('How long are they staying?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final s in Stay.values) ...[
            OutlinedButton(onPressed: () => Navigator.pop(ctx, s), child: Text(s.label)),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    ),
  );
  if (stay == null || !context.mounted) return null;
  if (stay != Stay.date) return (stay, null);
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    firstDate: DateTime(now.year, now.month, now.day + 1),
    initialDate: DateTime(now.year, now.month, now.day + 1),
    lastDate: DateTime(now.year, now.month, now.day + 60),
    helpText: 'Staying until (18:00 that day)',
  );
  return day == null ? null : (stay, day);
}

/// A plain card with a thin border, the building block of the lists.
class LineCard extends StatelessWidget {
  const LineCard({super.key, required this.child, this.color, this.border});
  final Widget child;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? GateColors.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border ?? GateColors.line, width: 1.5),
        ),
        child: child,
      );
}

/// "until 18:00", "in 10:05": a time in the estate's zone relative to today.
String timeLabel(EstateTime t, DateTime at) => when(t.of(at), t.now());

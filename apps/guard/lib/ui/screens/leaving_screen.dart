import 'package:flutter/material.dart';

import '../../app/gate_view.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'no_code_screen.dart';

/// Leaving: tap the person (visits with an entry and no exit, by home), or re-enter their code
/// on the keypad. One action, works offline. Someone not on the list is recorded by name.
class LeavingScreen extends StatefulWidget {
  const LeavingScreen({super.key});
  @override
  State<LeavingScreen> createState() => _LeavingScreenState();
}

class _LeavingScreenState extends State<LeavingScreen> {
  final _plate = TextEditingController();

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  void _done(String message, String id) {
    GateScope.read(context).showNotice(message, undoId: id);
    Navigator.of(context).pop();
  }

  Future<void> _left(InsideGuest g) async {
    final id = await GateScope.read(context).recordExit(g, method: 'list_tap', plate: _plate.text);
    if (mounted) _done('Left: ${g.guestName}', id);
  }

  Future<void> _unlisted() async {
    final c = GateScope.read(context);
    final name = await askGuestName(context, title: 'Who is leaving?', action: 'They left');
    if (name == null || !mounted) return;
    final id = await c.exitUnlisted(name, plate: _plate.text);
    if (mounted) _done('Left: $name', id);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final groups = groupByHome(c.view.inside);
    return Scaffold(
      appBar: AppBar(title: const Text('Leaving')),
      body: SafeArea(
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Tap the person who is leaving, or type their code on the keypad.', style: TextStyle(fontSize: 18)),
              PlateField(controller: _plate),
            ]),
          ),
          if (groups.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nobody is inside.', style: TextStyle(fontSize: 20))),
          for (final e in groups.entries) ...[
            SectionHeader(c.snapshot?.home(e.key)?.displayAddress ?? 'Unknown home'),
            for (final g in e.value)
              InkWell(
                onTap: () => _left(g),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 76),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: GateColors.line))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.guestName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                        Text(
                          [
                            if (g.enteredAt != null) 'In ${timeLabel(t, g.enteredAt!)}',
                            if (g.expectedUntil != null) 'until ${timeLabel(t, g.expectedUntil!)}',
                          ].join(', '),
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (g.overstay) const Text('Past expected time', style: TextStyle(fontSize: 16, color: GateColors.stop, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: GateColors.info, borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.logout, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Left', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_off_outlined),
              label: const Text('Someone not on the list'),
              onPressed: _unlisted,
            ),
          ),
        ]),
      ),
    );
  }
}

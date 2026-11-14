/// Visitor leaving: big tiles of everyone inside, by house, the house number in mono. The name,
/// or "Voice clip" with a play button while the clip is still on the phone. Tap, then "Leaving
/// now?" Yes or No (`list_tap`). "Has a code": the keypad, then an exit by code.
library;

import 'package:flutter/material.dart';

import '../../app/admission.dart';
import '../../app/gate_view.dart';
import '../../sync/capture.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../words.dart';
import 'admit_screens.dart';
import 'code_screen.dart';
import 'shuttle_screens.dart';

class LeavingScreen extends StatefulWidget {
  const LeavingScreen({super.key});
  @override
  State<LeavingScreen> createState() => _LeavingScreenState();
}

class _LeavingScreenState extends State<LeavingScreen> {
  @override
  void initState() {
    super.initState();
    final n = GateScope.read(context).view.inside.length;
    say(n == 0 ? M.nobodyInside : M.whoIsLeaving);
  }

  Future<void> _tap(InsideGuest g) async {
    final c = GateScope.read(context);
    final home = c.snapshot?.home(g.homeId);
    if (home == null) return;
    final named = g.guestName != voiceClipName;
    final yes = await askYesNo(
      context,
      label: tr(M.visitorLeaving),
      question: tr(M.leavingNow),
      say: '${home.label.toUpperCase()}. ${named ? g.guestName : ''}. ${tr(M.leavingNow)}',
      about: HouseHero(home: home, name: named ? g.guestName : tr(M.voiceClip), voiceClip: !named),
    );
    if (yes != true || !mounted) return;
    final id = await c.recordExit(g, method: 'list_tap');
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => DoneScreen(outcome: Outcome.left, home: home, recordId: id, name: named ? g.guestName : null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final inside = c.view.inside;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: tr(M.insideCount, {'n': inside.length}), sayAloud: tr(inside.isEmpty ? M.nobodyInside : M.whoIsLeaving)),
          Headline(tr(inside.isEmpty ? M.nobodyInside : M.whoIsLeaving)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final g in inside)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InsideTile(guest: g, onTap: () => _tap(g)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Pill(
            label: tr(M.hasACode),
            icon: Icons.dialpad,
            onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const CodeScreen(leaving: true))),
          ),
        ],
      ),
    );
  }
}

class _InsideTile extends StatelessWidget {
  const _InsideTile({required this.guest, required this.onTap});
  final InsideGuest guest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final home = c.snapshot?.home(guest.homeId);
    final named = guest.guestName != voiceClipName;
    final refs = [guest.entryId, guest.visitId];
    final clip = !named && c.hasClip(refs);
    return Semantics(
      button: true,
      label: '${home?.label.toUpperCase() ?? ''} ${named ? guest.guestName : tr(M.voiceClip)}',
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 84),
                    child: Text(home?.label.toUpperCase() ?? '?', style: monoStyle(context, 32)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          named ? guest.guestName : tr(M.voiceClip),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: inter, fontSize: 20, fontWeight: FontWeight.w600, color: named ? p.text : p.muted),
                        ),
                        if (home != null) Text(home.street, maxLines: 1, overflow: TextOverflow.ellipsis, style: mutedStyle(context, 14)),
                      ],
                    ),
                  ),
                  if (clip)
                    RoundButton(
                      icon: Icons.play_arrow,
                      label: tr(M.play),
                      onTap: () async {
                        final v = await GateScope.read(context).clipOf(refs);
                        if (v != null) await playClip(v.bytes, v.contentType);
                      },
                    ),
                  if (guest.overstay) ...[const SizedBox(width: 8), Icon(Icons.schedule, color: p.warnText)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

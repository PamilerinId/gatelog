/// Home (Guard-Home), for the guard and the CSO alike: who is on and where, the network chip,
/// and the same three big buttons, always in the same place: Visitor has code, Phone call,
/// Visitor leaving. Emergency numbers below them. A small menu: Sync, End shift, Shuttle to the
/// home. The CSO's extras are one tap away, with a red count when something needs them.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../data/models.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../words.dart';
import 'call_screen.dart';
import 'code_screen.dart';
import 'cso_screens.dart';
import 'directory_screen.dart';
import 'leaving_screen.dart';
import 'shuttle_screens.dart';
import 'sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _cso;

  @override
  void initState() {
    super.initState();
    final c = GateScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Caller ID: asked once per pairing; refused, everything still works.
      unawaited(c.askForCallerIdOnce());
      if (c.isCso) unawaited(c.refreshCso());
    });
    // The CSO's red count stays fresh while the home shows.
    if (c.isCso) _cso = Timer.periodic(const Duration(minutes: 1), (_) => c.refreshCso());
  }

  @override
  void dispose() {
    _cso?.cancel();
    super.dispose();
  }

  Future<void> _menu() async {
    final c = GateScope.read(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.of(context).bg,
      builder: (ctx) => KitSurface(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.shuttle != null) ...[
                  Pill(label: tr(M.shuttleToHome), icon: Icons.two_wheeler, onTap: () => Navigator.pop(ctx, 'shuttle')),
                  const SizedBox(height: 10),
                ],
                Pill(label: tr(M.sync), icon: Icons.sync, onTap: () => Navigator.pop(ctx, 'sync')),
                const SizedBox(height: 10),
                Pill(label: tr(M.endShift), icon: Icons.logout, onTap: () => Navigator.pop(ctx, 'end')),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'shuttle':
        await openShuttleToHome(context);
      case 'sync':
        await pushScreen<void>(context, const SyncScreen());
      case 'end':
        await endShiftFlow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final inside = c.view.inside.length;
    final gate = (c.gateName ?? c.snapshot?.gateName(c.snapshot?.deviceGateId) ?? '').toUpperCase();
    final wide = MediaQuery.sizeOf(context).width >= 380;
    final csoButton = c.isCso
        ? CountBadge(
            count: csoNeedsCount(c),
            child: RoundButton(icon: Icons.shield_outlined, label: tr(M.csoView), onTap: () => pushScreen<void>(context, const CsoScreen())),
          )
        : null;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Avatar(size: 44, onSurface: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.guard?.name ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [gate, if (c.isCso) tr(M.roleCso)].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, 11, color: p.muted, weight: FontWeight.w500).copyWith(letterSpacing: 1.3),
                    ),
                  ],
                ),
              ),
              if (wide) ...[const NetworkChip(), const SizedBox(width: 8)],
              if (csoButton != null) ...[csoButton, const SizedBox(width: 8)],
              RoundButton(icon: Icons.more_vert, label: tr(M.menu), onTap: _menu),
            ],
          ),
          if (!wide) ...[const SizedBox(height: 8), const Align(alignment: Alignment.centerLeft, child: NetworkChip())],
          const SizedBox(height: 14),
          Expanded(
            child: HomeJob(
              label: tr(M.visitorHasCode),
              icon: Icons.dialpad,
              primary: true,
              onTap: () => pushScreen<void>(context, const CodeScreen()),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: HomeJob(label: tr(M.phoneCall), icon: Icons.call_outlined, onTap: () => pushScreen<void>(context, const PhoneCallStart())),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: HomeJob(
              label: tr(M.visitorLeaving),
              sub: tr(M.insideCount, {'n': inside}),
              icon: Icons.logout,
              onTap: () => pushScreen<void>(context, const LeavingScreen()),
            ),
          ),
          const SizedBox(height: 14),
          Pill(
            label: tr(M.emergencyNumbers),
            icon: Icons.warning_amber_rounded,
            iconColor: p.no,
            onTap: () => pushScreen<void>(context, const EmergencyNumbersScreen()),
          ),
        ],
      ),
    );
  }
}

/// "End your shift?" with what is handed over, then "Who is taking over?" as faces, or Nobody.
Future<void> endShiftFlow(BuildContext context) async {
  final c = GateScope.read(context);
  final h = c.handoverNow();
  final lines = [
    if (!c.isRider) tr(M.handoverInside, {'n': h.inside}),
    tr(M.handoverUnsent, {'n': h.unsynced}),
    if (c.snapshot?.rollup != null && !c.isRider) tr(M.handoverNight, {'n': h.nightListOpen}),
  ];
  final yes = await askYesNo(
    context,
    label: tr(M.endShift),
    question: tr(M.endShiftQ),
    say: tr(M.endShiftQ),
    about: KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final l in lines) Text(l, style: monoStyle(context, 18, weight: FontWeight.w500))],
      ),
    ),
  );
  if (yes != true || !context.mounted) return;
  final next = await pushScreen<_Takeover>(context, const _TakeoverScreen());
  if (next == null) return;
  await c.endShift(handedTo: next.guard?.id);
  say(M.shiftEnded);
}

class _Takeover {
  const _Takeover(this.guard);
  final Guard? guard;
}

class _TakeoverScreen extends StatefulWidget {
  const _TakeoverScreen();
  @override
  State<_TakeoverScreen> createState() => _TakeoverScreenState();
}

class _TakeoverScreenState extends State<_TakeoverScreen> {
  @override
  void initState() {
    super.initState();
    say(M.whoTakesOver);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final people = c.takeoverCandidates;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: tr(M.endShift), sayAloud: tr(M.whoTakesOver)),
          Headline(tr(M.whoTakesOver)),
          const SizedBox(height: 8),
          Expanded(
            child: FaceGrid(
              children: [
                for (final g in people)
                  FaceTile(
                    name: g.name,
                    tag: g.isCso ? tr(M.roleCso) : null,
                    onTap: () => Navigator.pop(context, _Takeover(g)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          BigTile(label: tr(M.nobody), icon: Icons.person_off_outlined, primary: true, height: 96, onTap: () => Navigator.pop(context, const _Takeover(null))),
        ],
      ),
    );
  }
}

/// How many things need the CSO now: the home said NO, guests past their time, the night list,
/// gate phones gone quiet, shuttle rides waiting.
int csoNeedsCount(GateController c) {
  final o = c.cso;
  final overdue = o == null ? 0 : o.overdue.where((g) => c.view.visits[g.visitId]?.state != 'left').length;
  return (o?.disputedToday.length ?? 0) +
      overdue +
      c.view.nightListOpen(c.snapshot?.rollup) +
      (o?.quietPhones.length ?? 0) +
      (c.shuttle == null ? 0 : o?.ridesWaiting.length ?? 0);
}

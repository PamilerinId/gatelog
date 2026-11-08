import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/positions.dart';
import '../../app/rides.dart';
import '../../core/estate_time.dart';
import '../../data/models.dart';
import '../../data/shuttle.dart';
import '../app.dart';
import '../kit.dart';
import 'directory_screen.dart';
import 'shuttle_screens.dart';
import 'sync_screen.dart';

/// The rider view, to the handoff's rules: one ride at a time. A ride waiting: "Take it?" Yes or
/// No. A ride taken: tap their card (or No card, then the home PIN). Under way: "Did they
/// arrive?" Yes or No. Refreshes `/state` every 15 seconds while it shows.
class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  Timer? _refresh;

  /// Rides this rider said No to, so the next one shows. Cleared by "See them again".
  final Set<String> _skipped = {};
  String? _spokenRide;
  String? _spokenNotice;

  @override
  void initState() {
    super.initState();
    final c = GateScope.read(context);
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => c.syncNow());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Says a thing once, when it first shows.
  void _announce(String key, String words, {bool notice = false}) {
    if (notice ? _spokenNotice == key : _spokenRide == key) return;
    notice ? _spokenNotice = key : _spokenRide = key;
    WidgetsBinding.instance.addPostFrameCallback((_) => speak(words));
  }

  Future<void> _newRide() async {
    final c = GateScope.read(context);
    final who = await askWhoRode(context, label: 'New ride');
    if (who == null || !mounted) return;
    final home = who.home;
    final stops = rideStops(c.snapshot!, home: home);
    final from = await askEach<RideStop>(
      context,
      items: stops,
      label: 'New ride',
      question: (s) => s.kind == 'home' ? 'Picking up at their house?' : 'Picking up at ${s.label}?',
      about: (s) => stopCard(home, s),
    );
    if (from == null || !mounted) return;
    if (from.value == null) {
      speak('Ask the CSO to book this ride.');
      return;
    }
    final to = await askEach<RideStop>(
      context,
      items: [
        for (final s in stops)
          if (!s.sameAs(from.value!)) s,
      ],
      label: 'New ride',
      question: (s) => s.kind == 'home' ? 'Going to their house?' : 'Going to ${s.label}?',
      about: (s) => stopCard(home, s),
    );
    if (to == null || !mounted) return;
    if (to.value == null) {
      speak('Ask the CSO to book this ride.');
      return;
    }
    await c.newFlagRide(home: home, pickup: from.value!, dropoff: to.value!, who: who.confirm);
    speak('Ride started.');
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
                Pill(label: 'Emergency numbers', icon: Icons.warning_amber_rounded, color: Palette.of(ctx).noText, onTap: () => Navigator.pop(ctx, 'numbers')),
                const SizedBox(height: 10),
                Pill(label: 'Sync', icon: Icons.sync, onTap: () => Navigator.pop(ctx, 'sync')),
                const SizedBox(height: 10),
                Pill(label: 'End my shift', icon: Icons.logout, onTap: () => Navigator.pop(ctx, 'end')),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || pick == null) return;
    final nav = Navigator.of(context);
    switch (pick) {
      case 'numbers':
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Emergency numbers')),
              body: const SafeArea(child: DirectoryScreen()),
            ),
          ),
        );
      case 'sync':
        nav.push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
      case 'end':
        await _end(c);
    }
  }

  /// "End your shift?" then, for each other rider, "Is Ade taking over?".
  Future<void> _end(GateController c) async {
    final open = c.myRides.where((r) => r.state == RideState.accepted).length;
    final yes = await askYesNo(
      context,
      label: 'End shift',
      question: 'End your shift?',
      say: open > 0 ? 'Rides you took and have not picked up go back to the queue. End your shift?' : 'End your shift?',
      about: open > 0 ? Text('Rides you took and have not picked up go back to the queue.', style: mutedStyle(context, 18)) : null,
    );
    if (yes != true || !mounted) return;
    final next = await askEach<Guard>(context, items: c.takeoverCandidates, label: 'End shift', question: (g) => 'Is ${g.name} taking over?');
    if (next == null) return;
    await c.endShift(handedTo: next.value?.id);
    speak('Shift ended.');
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final mine = c.myRides;
    final waiting = c.waitingRides;
    final queue = [
      for (final r in waiting)
        if (!_skipped.contains(r.id)) r,
    ];
    final bike = c.bike;
    final now = c.time.now();
    String wait(Ride r) => waitLabel(r.wantedAt, now, (d) => hhmm(c.time.of(d)));

    final Widget body;
    String aloud;
    if (c.rideNotice != null) {
      aloud = c.rideNotice!;
      _announce(aloud, aloud, notice: true);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResultMark(icon: Icons.close, bad: true, text: c.rideNotice!),
          const SizedBox(height: 20),
          BigTile(label: 'OK', icon: Icons.check, primary: true, height: 96, onTap: c.clearRideNotice),
        ],
      );
    } else if (mine.isNotEmpty) {
      final r = mine.first;
      aloud = '${rideWords(c.snapshot, r, wait(r))} ${_MyRide.question(r)}';
      _announce('${r.id}:${r.state}', _MyRide.question(r));
      body = _MyRide(key: ValueKey('${r.id}:${r.state}'), ride: r);
    } else if (queue.isNotEmpty) {
      final r = queue.first;
      aloud = '${rideWords(c.snapshot, r, wait(r))} Take it?';
      _announce(r.id, aloud);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RideSummary(ride: r, counter: '${waiting.indexOf(r) + 1} OF ${waiting.length}'),
          const SizedBox(height: 8),
          const Headline('Take it?', center: true),
          YesNo(
            onYes: () async {
              await c.acceptRide(r);
              speak('Ride taken.');
            },
            onNo: () => setState(() => _skipped.add(r.id)),
          ),
        ],
      );
    } else {
      aloud = waiting.isEmpty ? 'No rides now.' : 'No more rides.';
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.two_wheeler, size: 96, color: p.muted),
          Headline(aloud, center: true),
          if (waiting.isNotEmpty) Pill(label: 'See them again', icon: Icons.replay, onTap: () => setState(_skipped.clear)),
        ],
      );
    }

    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler, size: 24),
                ),
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
                        [bike?.label ?? 'SHUTTLE', if (c.lastError != null) 'NO NETWORK'].join(' · ').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(context, 12, color: c.lastError != null ? p.warnText : p.muted, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                RoundButton(icon: Icons.volume_up_outlined, label: 'Read aloud', onTap: () => speak(aloud)),
                const SizedBox(width: 8),
                RoundButton(icon: Icons.more_vert, label: 'Menu', onTap: _menu),
              ],
            ),
          ),
          if (c.locationProblem != null) _LocationStrip(problem: c.locationProblem!),
          if (c.notice != null && c.now().difference(c.notice!.at) < const Duration(seconds: 8))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(c.notice!.message, textAlign: TextAlign.center, style: mutedStyle(context, 16)),
            ),
          Expanded(
            child: Center(child: SingleChildScrollView(child: body)),
          ),
          const SizedBox(height: 10),
          Pill(label: 'New ride', icon: Icons.add, onTap: _newRide),
        ],
      ),
    );
  }
}

/// The rider's own ride: the one next step.
class _MyRide extends StatefulWidget {
  const _MyRide({super.key, required this.ride});
  final Ride ride;

  static String question(Ride r) =>
      r.state == RideState.accepted ? (r.isDelivery ? 'Got the parcel?' : 'Tap their card.') : (r.isDelivery ? 'Did the parcel arrive?' : 'Did they arrive?');

  @override
  State<_MyRide> createState() => _MyRideState();
}

class _MyRideState extends State<_MyRide> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dropOff(GateController c, Ride r) async {
    if (r.isDelivery) {
      final who = await askWhoRode(context, home: c.snapshot?.home(r.homeId), title: 'Tap their card', label: 'Who took the parcel');
      if (who == null) return;
      await c.dropOff(r, who: who.confirm);
    } else {
      await c.dropOff(r);
    }
    speak('Dropped off.');
    c.showNotice('Dropped off at ${r.dropoff.label}');
  }

  Future<void> _noShow(GateController c, Ride r) async {
    final yes = await askYesNo(context, label: 'Nobody came', question: 'Nobody came?', say: 'Nobody came? The ride closes.');
    if (yes == true) {
      await c.noShow(r);
      speak('Ride closed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final r = widget.ride;
    final home = c.snapshot?.home(r.homeId);
    final secondary = Row(
      children: [
        Expanded(
          child: Pill(
            label: 'Hand back',
            onTap: _busy
                ? null
                : () => _do(() async {
                    await c.releaseRide(r);
                    speak('Ride handed back.');
                  }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Pill(label: 'Nobody came', color: p.noText, onTap: _busy ? null : () => _do(() => _noShow(c, r))),
        ),
      ],
    );
    final children = <Widget>[RideSummary(ride: r), const SizedBox(height: 8)];
    if (r.state == RideState.accepted && !r.isDelivery) {
      children.addAll([
        WhoPanel(
          home: home,
          fromGate: r.source == 'gate',
          onDone: (who) => _do(() async {
            await c.pickUp(r, who: who.confirm);
            speak('Picked up.');
          }),
        ),
        const SizedBox(height: 10),
        secondary,
      ]);
    } else if (r.state == RideState.accepted) {
      children.addAll([
        const Headline('Got the parcel?', center: true),
        YesNo(
          onYes: _busy
              ? null
              : () => _do(() async {
                  await c.pickUp(r);
                  speak('Parcel collected.');
                }),
          onNo: () => speak('Tap Yes when you have the parcel.'),
        ),
        const SizedBox(height: 10),
        secondary,
      ]);
    } else {
      children.addAll([
        Headline(_MyRide.question(r), center: true),
        YesNo(onYes: _busy ? null : () => _do(() => _dropOff(c, r)), onNo: () => speak('Tap Yes when you get there.')),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _LocationStrip extends StatelessWidget {
  const _LocationStrip({required this.problem});
  final LocationAccess problem;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KitCard(
        border: p.warn,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.location_off, color: p.warnText, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                problem == LocationAccess.serviceOff ? 'Location is off' : 'Location not allowed',
                style: TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w700, color: p.warnText),
              ),
            ),
            Pill(label: 'Turn on', onTap: GateScope.read(context).retryLocation),
          ],
        ),
      ),
    );
  }
}

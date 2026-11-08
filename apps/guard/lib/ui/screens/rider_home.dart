import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/positions.dart';
import '../../app/rides.dart';
import '../../core/estate_time.dart';
import '../../data/shuttle.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'guard_home.dart';
import 'shuttle_screens.dart';

/// The rider view: the ride queue and one button for a flagged-down ride. Nothing else.
/// Refreshes `/state` every 15 seconds while it shows (a 304 when nothing changed).
class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  Timer? _refresh;

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

  Future<void> _newRide() async {
    final c = GateScope.read(context);
    final who = await askWhoRode(context);
    if (who == null || !mounted) return;
    final stops = rideStops(c.snapshot!, home: who.home);
    final from = await pickStop(context, title: 'Where are you picking them up?', stops: stops);
    if (from == null || !mounted) return;
    final to = await pickStop(context, title: 'Where are they going?', sub: 'From ${from.label}', stops: [for (final s in stops) if (!s.sameAs(from)) s]);
    if (to == null || !mounted) return;
    await c.newFlagRide(home: who.home, pickup: from, dropoff: to, who: who.confirm);
    c.showNotice('Picked up: ${from.label} to ${to.label}');
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final mine = c.myRides;
    final waiting = c.waitingRides;
    return Scaffold(
      appBar: const GateAppBar(),
      body: SafeArea(
        child: Column(children: [
          if (c.locationProblem != null) _LocationStrip(problem: c.locationProblem!),
          if (c.rideNotice != null) _TakenStrip(message: c.rideNotice!, onOk: c.clearRideNotice),
          const _RiderNotice(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: c.syncNow,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), children: [
                if (mine.isNotEmpty) ...[
                  _Section(mine.length == 1 ? 'Your ride' : 'Your rides (${mine.length})'),
                  for (final r in mine) RideCard(ride: r, mine: true),
                  const SizedBox(height: 6),
                ],
                _Section(waiting.isEmpty ? 'Waiting' : 'Waiting (${waiting.length})'),
                if (waiting.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No rides waiting.', style: TextStyle(fontSize: 20)),
                  ),
                for (final r in waiting) RideCard(ride: r, mine: false),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: GateColors.navy, minimumSize: const Size.fromHeight(76), textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              icon: const Icon(Icons.add, size: 32),
              label: const Text('New ride'),
              onPressed: _newRide,
            ),
          ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: GateColors.navy)),
      );
}

/// One ride: kind and how long it has waited, from, to, who or what, the note, and the one or
/// two things the rider can do next.
class RideCard extends StatefulWidget {
  const RideCard({super.key, required this.ride, required this.mine});
  final Ride ride;
  final bool mine;
  @override
  State<RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<RideCard> {
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

  Future<void> _pickUp(GateController c, Ride r) async {
    if (r.isDelivery) {
      await c.pickUp(r);
      c.showNotice('Parcel collected: ${r.passenger ?? r.dropoff.label}');
      return;
    }
    final who = await askWhoRode(context, home: c.snapshot?.home(r.homeId), fromGate: r.source == 'gate');
    if (who == null) return;
    await c.pickUp(r, who: who.confirm);
    c.showNotice('Picked up: ${r.pickup.label} to ${r.dropoff.label}');
  }

  Future<void> _dropOff(GateController c, Ride r) async {
    if (r.isDelivery) {
      final who = await askWhoRode(context, home: c.snapshot?.home(r.homeId), parcel: true);
      if (who == null) return;
      await c.dropOff(r, who: who.confirm);
    } else {
      await c.dropOff(r);
    }
    c.showNotice('Dropped off at ${r.dropoff.label}');
  }

  Future<void> _noShow(GateController c, Ride r) async {
    final ok = await confirm(context, 'Nobody came?', body: 'The ride closes as a no-show.', yes: 'No-show', no: 'Back');
    if (ok) await c.noShow(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final r = widget.ride;
    final t = c.time;
    final under = r.state == RideState.pickedUp;
    final wait = under ? 'Under way' : waitLabel(r.wantedAt, t.now(), (d) => hhmm(t.of(d)));
    final who = r.passenger ?? (r.residentId == null ? null : c.snapshot?.resident(r.residentId)?.name);
    Text place(String label, String text) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$label  ', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: GateColors.navy)),
            TextSpan(text: text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ]),
        );
    final actions = <Widget>[];
    if (!widget.mine) {
      actions.add(BigButton(label: 'Take it', icon: Icons.check, color: GateColors.go, onPressed: _busy ? null : () => _do(() => c.acceptRide(r))));
    } else if (r.state == RideState.accepted) {
      actions.addAll([
        BigButton(
          label: r.isDelivery ? 'Parcel collected' : 'Picked up',
          icon: Icons.two_wheeler,
          color: GateColors.go,
          onPressed: _busy ? null : () => _do(() => _pickUp(c, r)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: _busy ? null : () => _do(() => c.releaseRide(r)),
              child: const Text('Hand back'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64), foregroundColor: GateColors.stop, side: const BorderSide(color: GateColors.stop, width: 2)),
              onPressed: _busy ? null : () => _do(() => _noShow(c, r)),
              child: const Text('No-show'),
            ),
          ),
        ]),
      ]);
    } else {
      actions.add(BigButton(label: 'Dropped off', icon: Icons.flag, color: GateColors.go, onPressed: _busy ? null : () => _do(() => _dropOff(c, r))));
    }
    return LineCard(
      color: widget.mine ? GateColors.goWash : null,
      border: widget.mine ? GateColors.go : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(switch (r.kind) { RideKind.delivery => Icons.inventory_2_outlined, RideKind.guest => Icons.person_outline, _ => Icons.home_outlined }, size: 26, color: GateColors.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(rideKindLabel(r.kind), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: GateColors.navy))),
          Flexible(
            child: Text(wait, textAlign: TextAlign.end, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: under ? GateColors.go : GateColors.warn)),
          ),
        ]),
        const SizedBox(height: 6),
        place('From', r.pickup.label),
        place('To', r.dropoff.label),
        if (who != null && who.isNotEmpty) Text(r.isDelivery ? 'Parcel: $who' : who, style: const TextStyle(fontSize: 18)),
        if (r.note != null && r.note!.isNotEmpty) Text('Note: ${r.note}', style: const TextStyle(fontSize: 17, fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        ...actions,
      ]),
    );
  }
}

class _LocationStrip extends StatelessWidget {
  const _LocationStrip({required this.problem});
  final LocationAccess problem;

  @override
  Widget build(BuildContext context) => Container(
        color: GateColors.warnWash,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          const Icon(Icons.location_off, color: GateColors.warn, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              problem == LocationAccess.serviceOff ? 'Location is off on this phone.' : 'Location is not allowed. The estate cannot see the shuttle.',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: GateScope.read(context).retryLocation, child: const Text('Turn on')),
        ]),
      );
}

/// "Taken by Musa": the ride went to another rider.
class _TakenStrip extends StatelessWidget {
  const _TakenStrip({required this.message, required this.onOk});
  final String message;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) => Container(
        color: GateColors.stopWash,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          const Icon(Icons.info_outline, color: GateColors.stop, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: GateColors.stop))),
          TextButton(onPressed: onOk, child: const Text('OK')),
        ]),
      );
}

/// What was just recorded, for 8 seconds.
class _RiderNotice extends StatefulWidget {
  const _RiderNotice();
  @override
  State<_RiderNotice> createState() => _RiderNoticeState();
}

class _RiderNoticeState extends State<_RiderNotice> {
  static const _showFor = Duration(seconds: 8);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final n = c.notice;
    final left = n == null ? Duration.zero : _showFor - c.now().difference(n.at);
    if (n == null || left <= Duration.zero) return const SizedBox.shrink();
    _timer?.cancel();
    _timer = Timer(left, () {
      if (mounted) setState(() {});
    });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: GateColors.navy, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(n.message, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

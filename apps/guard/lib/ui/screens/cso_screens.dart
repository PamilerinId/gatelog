import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/rides.dart';
import '../../core/estate_time.dart';
import '../../data/cso.dart';
import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'directory_screen.dart';
import 'gate_screen.dart';
import 'guard_home.dart';
import 'no_code_screen.dart';
import 'shuttle_screens.dart';

/// The CSO view: the guard's gate plus Now, People, Shifts and Numbers, and Shuttle where the
/// estate runs one.
class CsoShell extends StatefulWidget {
  const CsoShell({super.key});
  @override
  State<CsoShell> createState() => _CsoShellState();
}

class _CsoShellState extends State<CsoShell> {
  int _tab = 1; // the CSO opens on Now

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final needs = _needsCount(c);
    final tabs = <(String, Widget, Widget)>[
      ('Gate', const Icon(Icons.dialpad, size: 28), const GateScreen()),
      ('Now', Badge(isLabelVisible: needs > 0, label: Text('$needs'), child: const Icon(Icons.notifications_active_outlined, size: 28)), const NowTab()),
      ('People', const Icon(Icons.groups_outlined, size: 28), const PeopleTab()),
      if (c.shuttle != null)
        (
          'Shuttle',
          Badge(
            isLabelVisible: (c.cso?.ridesWaiting.length ?? 0) > 0,
            label: Text('${c.cso?.ridesWaiting.length ?? 0}'),
            child: const Icon(Icons.two_wheeler, size: 28),
          ),
          const ShuttleTab(),
        ),
      ('Shifts', const Icon(Icons.badge_outlined, size: 28), const ShiftsTab()),
      ('Numbers', const Icon(Icons.call_outlined, size: 28), const DirectoryScreen()),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: const GateAppBar(),
      body: SafeArea(child: tabs[tab].$3),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        // Six tabs on a 320dp phone: show only the open tab's label.
        labelBehavior: tabs.length > 5 && MediaQuery.sizeOf(context).width < 400
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [for (final t in tabs) NavigationDestination(icon: t.$2, label: t.$1)],
      ),
    );
  }
}

int _needsCount(GateController c) {
  final o = c.cso;
  final overdue = o == null ? 0 : _openOverdue(c, o).length;
  return overdue + c.view.nightListOpen(c.snapshot?.rollup) + (o?.quietPhones.length ?? 0) + (c.shuttle == null ? 0 : o?.ridesWaiting.length ?? 0);
}

/// Overdue guests the CSO has not marked as left on this phone since the last fetch.
List<OverdueGuest> _openOverdue(GateController c, CsoOverview o) =>
    [for (final g in o.overdue) if (c.view.visits[g.visitId]?.state != 'left') g];

/// Fetched when it opens and every minute while it shows. With no network, the last copy.
class NowTab extends StatefulWidget {
  const NowTab({super.key});
  @override
  State<NowTab> createState() => _NowTabState();
}

class _NowTabState extends State<NowTab> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final c = GateScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.refreshCso());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => c.refreshCso());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final o = c.cso;
    final rollup = c.snapshot?.rollup;
    final overdue = o == null ? const <OverdueGuest>[] : _openOverdue(c, o);
    final nightOpen = c.view.nightListOpen(rollup);
    final ridesWaiting = c.shuttle == null || o == null ? const [] : o.ridesWaiting;
    final nothing = o != null &&
        overdue.isEmpty &&
        o.refusedToday.isEmpty &&
        o.walkInsToday.isEmpty &&
        o.quietPhones.isEmpty &&
        nightOpen == 0 &&
        ridesWaiting.isEmpty;

    return RefreshIndicator(
      onRefresh: c.refreshCso,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Updated(c),
          const SizedBox(height: 12),
          const _Title('Needs you'),
          if (o == null && c.csoLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (nothing) const Text('Nothing needs you right now.', style: TextStyle(fontSize: 18)),
          if (overdue.isNotEmpty) ...[
            _Sub('Past their time (${overdue.length})'),
            for (final g in overdue) _OverdueCard(guest: g),
          ],
          if (nightOpen > 0 || (rollup != null && rollup.items.isNotEmpty)) ...[
            _Sub('Night list: $nightOpen of ${rollup!.items.length} to check'),
            for (final item in rollup.items) _NightRow(item: item),
          ],
          if (ridesWaiting.isNotEmpty) ...[
            _Sub('Shuttle rides waiting over 10 minutes (${ridesWaiting.length})'),
            for (final w in ridesWaiting)
              LineCard(
                color: GateColors.warnWash,
                border: GateColors.warn,
                child: _Lines(
                  title: '${rideKindLabel(w.kind)}: ${w.from ?? '?'} to ${w.to ?? '?'}',
                  lines: [if (w.wantedAt != null) waitLabel(w.wantedAt, t.now(), (d) => hhmm(t.of(d)))],
                ),
              ),
          ],
          if (o != null && o.quietPhones.isNotEmpty) ...[
            _Sub('Gate phones not syncing (${o.quietPhones.length})'),
            for (final p in o.quietPhones)
              LineCard(
                color: GateColors.warnWash,
                border: GateColors.warn,
                child: _Lines(
                  title: [p.gate, p.label].whereType<String>().join(', '),
                  lines: [
                    p.lastSyncAt == null ? 'Never synced' : 'Last sync ${timeLabel(t, p.lastSyncAt!)}',
                    if (p.onDuty != null) 'On duty: ${p.onDuty}',
                  ],
                ),
              ),
          ],
          if (o != null && o.walkInsToday.isNotEmpty) ...[
            _Sub('Walk-ins today (${o.walkInsToday.length})'),
            for (final d in o.walkInsToday) _DecisionCard(d: d, verb: 'Let in on the decision of'),
          ],
          if (o != null && o.refusedToday.isNotEmpty) ...[
            _Sub('Turned away today (${o.refusedToday.length})'),
            for (final d in o.refusedToday) _DecisionCard(d: d, verb: 'Turned away by'),
          ],
          const SizedBox(height: 16),
          const _Title('On duty'),
          if (o != null && o.onDuty.isEmpty) const Text('Nobody has a shift open.', style: TextStyle(fontSize: 18)),
          if (o != null) ..._onDutyByGate(t, o.onDuty),
        ],
      ),
    );
  }

  List<Widget> _onDutyByGate(EstateTime t, List<OnDuty> all) {
    final byGate = <String, List<OnDuty>>{};
    for (final d in all) {
      byGate.putIfAbsent(d.gate ?? 'Gate', () => []).add(d);
    }
    return [
      for (final e in byGate.entries)
        LineCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.key, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: GateColors.navy)),
            for (final d in e.value) ...[
              const SizedBox(height: 4),
              Text('${d.guard ?? 'Unknown'}${d.role == 'cso' ? ' (CSO)' : ''}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              Text(
                [
                  if (d.since != null) 'Since ${timeLabel(t, d.since!)}',
                  d.phoneLastSyncAt == null ? 'phone never synced' : 'phone synced ${hhmm(t.of(d.phoneLastSyncAt!))}',
                ].join(', '),
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ]),
        ),
    ];
  }
}

class _Updated extends StatelessWidget {
  const _Updated(this.c);
  final GateController c;

  @override
  Widget build(BuildContext context) {
    final at = c.csoFetchedAt;
    final stamp = at == null ? 'Not loaded yet' : 'Updated ${hhmm(c.time.of(at))}';
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(stamp, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (c.csoError != null) Text(c.csoError!, style: const TextStyle(fontSize: 16, color: GateColors.warn, fontWeight: FontWeight.w600)),
        ]),
      ),
      c.csoLoading
          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))
          : IconButton(icon: const Icon(Icons.refresh, size: 30), tooltip: 'Refresh', onPressed: c.refreshCso),
    ]);
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)));
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GateColors.navy)),
      );
}

class _Lines extends StatelessWidget {
  const _Lines({required this.title, this.lines = const []});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        for (final l in lines) Text(l, style: const TextStyle(fontSize: 16)),
      ]);
}

/// A guest past their time: call the resident (numbers from the cached homes), or mark left.
class _OverdueCard extends StatelessWidget {
  const _OverdueCard({required this.guest});
  final OverdueGuest guest;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final home = c.snapshot?.home(guest.homeId);
    final resident = c.snapshot?.resident(guest.residentId) ?? (home != null && home.residents.isNotEmpty ? home.residents.first : null);
    final number = resident == null || resident.numbers.isEmpty ? null : resident.numbers.first;
    return LineCard(
      color: GateColors.stopWash,
      border: GateColors.stop,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Lines(title: guest.guestName, lines: [
          guest.address ?? home?.displayAddress ?? 'Unknown home',
          if (guest.expectedUntil != null) 'Expected to leave ${timeLabel(t, guest.expectedUntil!)}',
          if (resident != null) 'Resident: ${resident.name}${number == null ? '' : ', ${number.masked}'}',
        ]),
        const SizedBox(height: 8),
        Row(children: [
          if (number != null) ...[
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: GateColors.navy, minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.call),
                label: const Text('Call'),
                onPressed: () => dial(number.e164),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              icon: const Icon(Icons.logout),
              label: const Text('Mark left'),
              onPressed: () async {
                final id = await c.markLeft(guest.visitId, guest.guestName);
                if (context.mounted) toast(context, 'Left: ${guest.guestName}', undo: () => c.undo(id));
              },
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.d, required this.verb});
  final GateDecision d;
  final String verb;

  @override
  Widget build(BuildContext context) {
    final t = GateScope.of(context).time;
    return LineCard(
      child: _Lines(title: d.guestName, lines: [
        [d.address, d.gate].whereType<String>().join(', '),
        [if (d.who != null) '$verb ${d.who}', if (d.at != null) hhmm(t.of(d.at!))].join(', '),
        if (d.reason != null && d.reason!.isNotEmpty) 'Reason: ${d.reason}',
      ]),
    );
  }
}

/// One night list item, Left or Still inside. From /state, so it works offline.
class _NightRow extends StatelessWidget {
  const _NightRow({required this.item});
  final RollupItem item;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final v = c.view.visits[item.visitId];
    final result = c.view.rollupResults[item.id];
    final address = c.snapshot?.home(v?.homeId ?? item.homeId ?? '')?.displayAddress ?? item.address ?? '';
    return LineCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Lines(title: v?.guestName ?? item.guestName ?? 'Guest', lines: [address]),
        const SizedBox(height: 8),
        if (result != null)
          Text(result == 'left' ? 'Left' : 'Still inside',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: result == 'left' ? GateColors.go : GateColors.warn))
        else
          Row(children: [
            Expanded(child: BigButton(label: 'Left', color: GateColors.go, onPressed: () => c.rollupCheck(item.id, 'left'))),
            const SizedBox(width: 10),
            Expanded(child: BigButton(label: 'Still inside', color: GateColors.warn, onPressed: () => c.rollupCheck(item.id, 'still_inside'))),
          ]),
      ]),
    );
  }
}

enum _People { expected, inside, turnedAway }

/// Expected and inside at every gate (from /state, offline), and turned away today (live).
class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});
  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  _People _seg = _People.expected;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    String home(String id) => c.snapshot?.home(id)?.displayAddress ?? 'Unknown home';
    final rows = <Widget>[];
    switch (_seg) {
      case _People.expected:
        if (c.view.expected.isEmpty) rows.add(const Text('Nobody expected.', style: TextStyle(fontSize: 18)));
        for (final v in c.view.expected) {
          rows.add(LineCard(
            child: _Lines(title: v.guestName, lines: [
              home(v.homeId),
              v.codeIssued ? 'Has a code, from ${timeLabel(t, t.ofUnix(v.windowStart))}' : 'Confirmed by phone',
              if (v.expectedUntil != null) 'Staying until ${timeLabel(t, v.expectedUntil!)}',
            ]),
          ));
        }
      case _People.inside:
        final groups = groupByHome(c.view.inside);
        if (groups.isEmpty) rows.add(const Text('Nobody is inside.', style: TextStyle(fontSize: 18)));
        for (final e in groups.entries) {
          for (final g in e.value) {
            rows.add(LineCard(
              color: g.overstay ? GateColors.stopWash : null,
              border: g.overstay ? GateColors.stop : null,
              child: _Lines(title: g.guestName, lines: [
                home(g.homeId),
                [if (g.enteredAt != null) 'In ${timeLabel(t, g.enteredAt!)}', if (g.expectedUntil != null) 'until ${timeLabel(t, g.expectedUntil!)}'].join(', '),
                if (g.overstay) 'Past expected time',
              ]),
            ));
          }
        }
      case _People.turnedAway:
        final o = c.cso;
        if (o == null) {
          rows.add(Text(c.csoError ?? 'Open Now to load today\'s list.', style: const TextStyle(fontSize: 18)));
        } else {
          if (c.csoFetchedAt != null) {
            rows.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Updated ${hhmm(t.of(c.csoFetchedAt!))}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ));
          }
          if (o.refusedToday.isEmpty) rows.add(const Text('Nobody turned away today.', style: TextStyle(fontSize: 18)));
          for (final d in o.refusedToday) {
            rows.add(_DecisionCard(d: d, verb: 'Turned away by'));
          }
        }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        BigButton(label: 'Add a guest', icon: Icons.person_add_alt_1, color: GateColors.navy, onPressed: () => openAddGuest(context)),
        const SizedBox(height: 12),
        SegmentedButton<_People>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          segments: [
            ButtonSegment(value: _People.expected, label: Text('Expected ${c.view.expected.length}')),
            ButtonSegment(value: _People.inside, label: Text('Inside ${c.view.inside.length}')),
            const ButtonSegment(value: _People.turnedAway, label: Text('Turned away')),
          ],
          selected: {_seg},
          onSelectionChanged: (s) {
            setState(() => _seg = s.first);
            if (s.first == _People.turnedAway) c.refreshCso();
          },
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }
}

/// Today's shifts at every gate, with handovers.
class ShiftsTab extends StatefulWidget {
  const ShiftsTab({super.key});
  @override
  State<ShiftsTab> createState() => _ShiftsTabState();
}

class _ShiftsTabState extends State<ShiftsTab> {
  @override
  void initState() {
    super.initState();
    final c = GateScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.refreshCso());
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final o = c.cso;
    return RefreshIndicator(
      onRefresh: c.refreshCso,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Updated(c),
          const SizedBox(height: 8),
          const _Title("Today's shifts"),
          if (o != null && o.shiftsToday.isEmpty) const Text('No shifts yet today.', style: TextStyle(fontSize: 18)),
          for (final s in o?.shiftsToday.reversed ?? const <ShiftToday>[])
            LineCard(
              color: s.endedAt == null ? GateColors.goWash : null,
              border: s.endedAt == null ? GateColors.go : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.guard ?? 'Unknown', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  [
                    if (s.gate != null) s.gate!,
                    '${s.startedAt == null ? '?' : hhmm(t.of(s.startedAt!))} to ${s.endedAt == null ? 'now' : hhmm(t.of(s.endedAt!))}',
                  ].join(', '),
                  style: const TextStyle(fontSize: 17),
                ),
                if (s.endedAt != null) Text(_ending(s), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (s.handover != null) Text(_handover(s.handover!), style: const TextStyle(fontSize: 16)),
                Text(s.selfie ? 'Photo on file' : 'No photo', style: TextStyle(fontSize: 15, color: s.selfie ? GateColors.go : GateColors.warn)),
              ]),
            ),
        ],
      ),
    );
  }

  static String _ending(ShiftToday s) => switch (s.endReason) {
        'handover' => 'Handed over to ${s.handedTo ?? 'someone'}',
        'auto' => 'Ended by itself after 14 hours',
        _ => 'Ended, nobody took over',
      };

  static String _handover(Map<String, dynamic> h) {
    int n(String k) => (h[k] as num?)?.toInt() ?? 0;
    return [
      '${n('inside')} inside',
      '${n('unsynced')} not sent',
      if (h.containsKey('night_list_open')) '${n('night_list_open')} on the night list',
    ].join(', ');
  }
}

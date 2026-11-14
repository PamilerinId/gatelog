/// The CSO's extras, one tap from the home (the CSO is usually on the gate too): Now, People,
/// Shifts, Numbers, and Shuttle where the estate runs one. In the handoff's style; never a
/// desk-style first screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/admission.dart';
import '../../app/controller.dart';
import '../../core/estate_time.dart';
import '../../data/cso.dart';
import '../../data/models.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../widgets.dart' show dial;
import '../words.dart';
import 'call_screen.dart';
import 'directory_screen.dart';
import 'home_screen.dart' show csoNeedsCount;
import 'shuttle_screens.dart';

class CsoScreen extends StatefulWidget {
  const CsoScreen({super.key});
  @override
  State<CsoScreen> createState() => _CsoScreenState();
}

class _CsoScreenState extends State<CsoScreen> {
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final c = GateScope.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.refreshCso());
    // Live while it shows, every minute; with no network, the last copy.
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
    final tabs = <(M, IconData, int, Widget)>[
      (M.tabNow, Icons.notifications_active_outlined, csoNeedsCount(c), const NowTab()),
      (M.tabPeople, Icons.groups_outlined, 0, const PeopleTab()),
      (M.tabShifts, Icons.badge_outlined, 0, const ShiftsTab()),
      (M.tabNumbers, Icons.call_outlined, 0, const DirectoryList()),
      if (c.shuttle != null) (M.tabShuttle, Icons.two_wheeler, c.cso?.ridesWaiting.length ?? 0, const ShuttleTab()),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);
    final p = Palette.of(context);
    return KitScaffold(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: '${tr(M.roleCso)} · ${tr(tabs[tab].$1)}'),
          Expanded(child: tabs[tab].$4),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, t) in tabs.indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == tab,
                    label: tr(t.$1),
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        height: 64,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(color: i == tab ? p.accent : p.surface, borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CountBadge(
                              count: t.$3,
                              child: Icon(t.$2, size: 26, color: i == tab ? p.onAccent : p.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(t.$1),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(fontFamily: inter, fontSize: 12, fontWeight: FontWeight.w600, color: i == tab ? p.onAccent : p.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Overdue guests the CSO has not marked as left on this phone since the last fetch.
List<OverdueGuest> _openOverdue(GateController c, CsoOverview o) => [
  for (final g in o.overdue)
    if (c.view.visits[g.visitId]?.state != 'left') g,
];

String _name(String n) => n == voiceClipName ? tr(M.voiceClip) : n;

/// "Updated 14:05", or the last copy with no network, and refresh.
class _Updated extends StatelessWidget {
  const _Updated();

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final at = c.csoFetchedAt;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                at == null ? tr(M.notLoaded).toUpperCase() : tr(M.updated, {'time': hhmm(c.time.of(at))}).toUpperCase(),
                style: monoStyle(context, 13, color: p.muted, weight: FontWeight.w500),
              ),
              if (c.csoError != null) Text(tr(M.lastCopy), style: TextStyle(fontFamily: inter, fontSize: 15, color: p.warnText, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (c.csoLoading)
          const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)))
        else
          RoundButton(icon: Icons.refresh, label: tr(M.tryAgain), onTap: c.refreshCso),
      ],
    );
  }
}

/// A mono section label; red for the home's NO.
class _Section extends StatelessWidget {
  const _Section(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: monoStyle(context, 14, color: color ?? Palette.of(context).muted, weight: FontWeight.w600).copyWith(letterSpacing: 1.2),
    ),
  );
}

/// A card: the house number in mono, the name, a line or two.
class _Item extends StatelessWidget {
  const _Item({this.house, required this.title, this.lines = const [], this.border, this.tag, this.children = const []});
  final String? house;
  final String title;
  final List<String> lines;
  final Color? border;
  final String? tag;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KitCard(
        border: border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (house != null) ...[Text(house!, style: monoStyle(context, 28)), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w700)),
                      for (final l in lines) Text(l, style: mutedStyle(context, 15)),
                    ],
                  ),
                ),
                if (tag != null)
                  Text(
                    tag!,
                    style: monoStyle(context, 11, color: p.warnText, weight: FontWeight.w600),
                  ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

String? _houseOf(GateController c, String? homeId, String? address) {
  final h = homeId == null ? null : c.snapshot?.home(homeId);
  if (h != null) return h.label.toUpperCase();
  final a = address?.trim();
  return a == null || a.isEmpty ? null : a.split(' ').first.toUpperCase();
}

/// What needs the CSO: the home said NO (first, in red), guests past their time, the night
/// list, rides waiting, quiet phones, walk-ins and refusals today; then who is on duty.
class NowTab extends StatelessWidget {
  const NowTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final o = c.cso;
    final rollup = c.snapshot?.rollup;
    final overdue = o == null ? const <OverdueGuest>[] : _openOverdue(c, o);
    final nightOpen = rollup == null ? const <RollupItem>[] : [for (final i in rollup.items) if (!c.view.rollupResults.containsKey(i.id)) i];
    final ridesWaiting = c.shuttle == null || o == null ? const <WaitingRide>[] : o.ridesWaiting;
    final nothing = o != null &&
        o.disputedToday.isEmpty &&
        overdue.isEmpty &&
        nightOpen.isEmpty &&
        o.quietPhones.isEmpty &&
        ridesWaiting.isEmpty &&
        o.walkInsToday.isEmpty &&
        o.refusedToday.isEmpty;
    String at(DateTime? d) => d == null ? '' : hhmm(t.of(d));
    return RefreshIndicator(
      onRefresh: c.refreshCso,
      child: ListView(
        children: [
          const _Updated(),
          if (o == null && c.csoLoading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (nothing) Padding(padding: const EdgeInsets.only(top: 24), child: Headline(tr(M.nothingNeedsYou), center: true)),
          if (o != null && o.disputedToday.isNotEmpty) ...[
            _Section(tr(M.homeSaidNo), color: p.noText),
            for (final d in o.disputedToday)
              _Item(
                house: _houseOf(c, null, d.address),
                title: _name(d.guestName),
                border: p.no,
                lines: [
                  [?d.gate, at(d.at)].where((s) => s.isNotEmpty).join(' · '),
                  if (d.who != null) d.who!,
                ],
              ),
          ],
          if (overdue.isNotEmpty) ...[
            _Section(tr(M.pastTheirTime)),
            for (final g in overdue) _OverdueCard(guest: g),
          ],
          if (nightOpen.isNotEmpty) ...[
            _Section('${tr(M.nightList)} · ${nightOpen.length}'),
            for (final item in nightOpen) _NightCheck(item: item),
          ],
          if (ridesWaiting.isNotEmpty) ...[
            _Section(tr(M.ridesWaiting)),
            for (final w in ridesWaiting)
              _Item(
                title: '${rideKindLabel(w.kind)}: ${w.from ?? '?'} to ${w.to ?? '?'}',
                border: p.warn,
                lines: [if (w.wantedAt != null) waitLabel(w.wantedAt, t.now(), (d) => hhmm(t.of(d)))],
              ),
          ],
          if (o != null && o.quietPhones.isNotEmpty) ...[
            _Section(tr(M.phonesQuiet)),
            for (final q in o.quietPhones)
              _Item(
                title: [q.gate, q.label].whereType<String>().join(', '),
                border: p.warn,
                lines: [
                  q.lastSyncAt == null ? tr(M.neverSynced) : tr(M.lastSync, {'when': when(t.of(q.lastSyncAt!), t.now())}),
                  ?q.onDuty,
                ],
              ),
          ],
          if (o != null && o.walkInsToday.isNotEmpty) ...[
            _Section(tr(M.walkInsToday)),
            for (final d in o.walkInsToday)
              _Item(
                house: _houseOf(c, null, d.address),
                title: _name(d.guestName),
                tag: d.decidedAlone ? tr(M.decidedAloneTag) : null,
                lines: [
                  [?d.who, at(d.at)].where((s) => s.isNotEmpty).join(' · '),
                  ?d.reason,
                ],
              ),
          ],
          if (o != null && o.refusedToday.isNotEmpty) ...[
            _Section(tr(M.turnedAwayToday)),
            for (final d in o.refusedToday)
              _Item(
                house: _houseOf(c, null, d.address),
                title: _name(d.guestName),
                lines: [
                  [?d.who, at(d.at)].where((s) => s.isNotEmpty).join(' · '),
                  ?d.reason,
                ],
              ),
          ],
          _Section(tr(M.onDuty)),
          if (o != null && o.onDuty.isEmpty) Text(tr(M.nobodyOnDuty), style: mutedStyle(context, 17)),
          if (o != null)
            for (final d in o.onDuty)
              _Item(
                title: d.guard ?? '?',
                tag: d.role == 'cso' ? tr(M.roleCso) : null,
                lines: [
                  [?d.gate, if (d.since != null) tr(M.inSince, {'when': hhmm(t.of(d.since!))})].join(' · '),
                  d.phoneLastSyncAt == null ? tr(M.neverSynced) : tr(M.lastSync, {'when': hhmm(t.of(d.phoneLastSyncAt!))}),
                ],
              ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A guest past their time: call the resident (only the last 4 digits show), or mark left.
class _OverdueCard extends StatelessWidget {
  const _OverdueCard({required this.guest});
  final OverdueGuest guest;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final home = c.snapshot?.home(guest.homeId);
    final resident = c.snapshot?.resident(guest.residentId) ?? (home != null && home.residents.isNotEmpty ? home.residents.first : null);
    final number = resident == null || resident.numbers.isEmpty ? null : resident.numbers.first;
    return _Item(
      house: _houseOf(c, guest.homeId, guest.address),
      title: _name(guest.guestName),
      border: p.no,
      lines: [
        if (guest.expectedUntil != null) tr(M.until, {'when': when(t.of(guest.expectedUntil!), t.now())}),
        if (resident != null) '${resident.name}${number == null ? '' : '  ${number.masked}'}',
      ],
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            if (number != null) ...[
              Expanded(child: Pill(label: tr(M.call), icon: Icons.call_outlined, onTap: () => dial(number.e164))),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Pill(
                label: tr(M.markLeft),
                icon: Icons.logout,
                onTap: () async {
                  final yes = await askYesNo(context, label: tr(M.pastTheirTime), question: tr(M.hasLeftQ, {'name': _name(guest.guestName)}));
                  if (yes == true) await c.markLeft(guest.visitId, guest.guestName);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One night list item: "Has Tunde left?" Yes or No. From /state, so it works offline.
class _NightCheck extends StatelessWidget {
  const _NightCheck({required this.item});
  final RollupItem item;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final v = c.view.visits[item.visitId];
    final name = _name(v?.guestName ?? item.guestName ?? tr(M.visitor));
    return _Item(
      house: _houseOf(c, v?.homeId ?? item.homeId, item.address),
      title: name,
      children: [
        const SizedBox(height: 8),
        Text(tr(M.hasLeftQ, {'name': name}), style: const TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: BigTile(label: tr(M.yes), icon: Icons.check, primary: true, height: 72, onTap: () => c.rollupCheck(item.id, 'left')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BigTile(label: tr(M.no), sub: tr(M.stillInside), height: 72, onTap: () => c.rollupCheck(item.id, 'still_inside')),
            ),
          ],
        ),
      ],
    );
  }
}

enum _People { expected, inside }

/// Expected and inside at every gate, from /state, so it works offline. "Add a guest" is the
/// same phone call flow as at the gate (a resident rang the CSO).
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
    final p = Palette.of(context);
    final t = c.time;
    String? house(String id) => c.snapshot?.home(id)?.label.toUpperCase();
    Widget seg(_People s, String label) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: _seg == s ? p.accent : p.surface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _seg = s),
            child: SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(fontFamily: inter, fontSize: 16, fontWeight: FontWeight.w700, color: _seg == s ? p.onAccent : p.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final rows = <Widget>[];
    if (_seg == _People.expected) {
      if (c.view.expected.isEmpty) rows.add(Text(tr(M.nobodyExpected), style: mutedStyle(context, 17)));
      for (final v in c.view.expected) {
        rows.add(
          _Item(
            house: house(v.homeId),
            title: _name(v.guestName),
            lines: [
              v.codeIssued ? tr(M.hasCodeFrom, {'when': when(t.ofUnix(v.windowStart), t.now())}) : tr(M.byPhone),
              if (v.expectedUntil != null) tr(M.until, {'when': when(t.of(v.expectedUntil!), t.now())}),
            ],
          ),
        );
      }
    } else {
      if (c.view.inside.isEmpty) rows.add(Text(tr(M.nobodyInside), style: mutedStyle(context, 17)));
      for (final g in c.view.inside) {
        rows.add(
          _Item(
            house: house(g.homeId),
            title: _name(g.guestName),
            border: g.overstay ? p.no : null,
            lines: [
              [
                if (g.enteredAt != null) tr(M.inSince, {'when': when(t.of(g.enteredAt!), t.now())}),
                if (g.expectedUntil != null) tr(M.until, {'when': when(t.of(g.expectedUntil!), t.now())}),
              ].join(' · '),
            ],
          ),
        );
      }
    }
    return ListView(
      children: [
        BigTile(label: tr(M.addGuest), icon: Icons.person_add_alt_1_outlined, primary: true, height: 88, onTap: () => pushScreen<void>(context, const PhoneCallStart())),
        const SizedBox(height: 12),
        Row(
          children: [
            seg(_People.expected, '${tr(M.expected)} ${c.view.expected.length}'),
            seg(_People.inside, '${tr(M.inside)} ${c.view.inside.length}'),
          ],
        ),
        const SizedBox(height: 12),
        ...rows,
      ],
    );
  }
}

/// Today's shifts at every gate, with handovers. Whether a photo is on file, never the photo.
class ShiftsTab extends StatelessWidget {
  const ShiftsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final o = c.cso;
    String ending(ShiftToday s) => switch (s.endReason) {
      'handover' => tr(M.handedTo, {'name': s.handedTo ?? '?'}),
      'auto' => tr(M.endedAuto),
      _ => tr(M.endedNobody),
    };
    String handover(Map<String, dynamic> h) {
      int n(String k) => (h[k] as num?)?.toInt() ?? 0;
      return [
        tr(M.handoverInside, {'n': n('inside')}),
        tr(M.handoverUnsent, {'n': n('unsynced')}),
        if (h.containsKey('night_list_open')) tr(M.handoverNight, {'n': n('night_list_open')}),
      ].join(' · ');
    }

    return RefreshIndicator(
      onRefresh: c.refreshCso,
      child: ListView(
        children: [
          const _Updated(),
          _Section(tr(M.todaysShifts)),
          if (o != null && o.shiftsToday.isEmpty) Text(tr(M.noShiftsYet), style: mutedStyle(context, 17)),
          for (final s in o?.shiftsToday.reversed ?? const <ShiftToday>[])
            _Item(
              title: s.guard ?? '?',
              border: s.endedAt == null ? p.accent : null,
              lines: [
                [?s.gate, '${s.startedAt == null ? '?' : hhmm(t.of(s.startedAt!))} to ${s.endedAt == null ? tr(M.now) : hhmm(t.of(s.endedAt!))}'].join(' · '),
                if (s.endedAt != null) ending(s),
                if (s.handover != null) handover(s.handover!),
                s.selfie ? tr(M.photoOnFile) : tr(M.noPhoto),
              ],
            ),
        ],
      ),
    );
  }
}

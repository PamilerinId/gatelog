import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/gate_view.dart';
import '../../app/no_code.dart';
import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shuttle_screens.dart';

/// No code: a guest at the gate with no code, or a resident calling about a guest. One flow:
/// find the home, call a registered number, then in now, expected later, or stop.
void openNoCode(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FindHomeScreen()));

void openHome(BuildContext context, Home home) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HomeFlowScreen(home: home)));

/// House number (label) or surname, as the guard types it.
bool homeMatches(Home h, String q) {
  if (q.isEmpty) return true;
  final s = q.toLowerCase().trim();
  return h.label.toLowerCase().startsWith(s) ||
      h.displayAddress.toLowerCase().contains(s) ||
      h.residents.any((r) => r.surname.startsWith(s) || r.name.toLowerCase().contains(s));
}

class FindHomeScreen extends StatefulWidget {
  const FindHomeScreen({super.key, this.title = 'No code'});
  final String title;
  @override
  State<FindHomeScreen> createState() => _FindHomeScreenState();
}

class _FindHomeScreenState extends State<FindHomeScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final homes = (c.snapshot?.homes ?? const <Home>[]).where((h) => homeMatches(h, _q)).toList()..sort(compareHomes);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Find the home', hintText: 'House number or surname'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: homes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = homes[i];
                  final confirmed = c.view.confirmedFor(h.id).length;
                  return ListTile(
                    minTileHeight: 72,
                    title: Text(h.displayAddress, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [h.residents.map((r) => r.name).join(', '), if (confirmed > 0) '$confirmed already confirmed'].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 16),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => HomeFlowScreen(home: h))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One home: guests already confirmed (Let in), residents to call, then the outcome.
class HomeFlowScreen extends StatefulWidget {
  const HomeFlowScreen({super.key, required this.home});
  final Home home;

  @override
  State<HomeFlowScreen> createState() => _HomeFlowScreenState();
}

class _HomeFlowScreenState extends State<HomeFlowScreen> {
  late final NoCodeFlow _flow = NoCodeFlow(widget.home);
  final _plate = TextEditingController();
  String? _guestName;
  ConfirmedCall? _confirmedCall;
  bool _busy = false;

  /// Let in, on an estate with a shuttle: what was recorded and who, so the guard can book the
  /// shuttle to the home before leaving this screen.
  (String, String)? _letIn;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  void _finish(String message, {String? undoId, String? letIn}) {
    final c = GateScope.read(context);
    c.showNotice(message, undoId: undoId);
    // The CSO may be on People ("Add a guest"), where the gate's notice is not in view.
    if (c.isCso) toast(context, message, undo: undoId == null ? null : () => c.undo(undoId));
    if (letIn != null && c.shuttle != null) {
      setState(() {
        _busy = false;
        _letIn = (message, letIn);
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _call(Resident r, PhoneNumber n) async {
    final c = GateScope.read(context);
    _flow.call(r, n);
    final ok = await dial(n.e164);
    if (!mounted) return;
    if (!ok) toast(context, 'Could not open the dialler. Dial ${n.masked} by hand.');
    final outcome = await askCallOutcome(context, r, n);
    if (outcome == null || !mounted) {
      setState(() => _flow.calling = null);
      return;
    }
    setState(() => _flow.record(outcome));
    if (outcome == CallOutcome.confirmed) {
      // Recorded now, so the call is on file whatever happens next; "expect them" links the visit.
      _confirmedCall = await c.recordConfirmedCall(homeId: widget.home.id, numberId: n.id);
      if (!mounted) return;
      final name = await askGuestName(context, title: 'Who is the guest?', initial: _guestName, action: 'Next');
      if (!mounted) return;
      setState(() => _guestName = name);
    } else {
      await c.recordCallback(homeId: widget.home.id, numberId: n.id, outcome: outcome.api);
    }
  }

  Future<void> _letInNow() async {
    final c = GateScope.read(context);
    final name = _guestName ?? await askGuestName(context, title: 'Who is the guest?');
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    final id = await c.admitOnCallback(widget.home.id, name, plate: _plate.text);
    if (mounted) _finish('Let in: $name', undoId: id, letIn: name);
  }

  Future<void> _expectLater() async {
    final c = GateScope.read(context);
    final name = _guestName ?? await askGuestName(context, title: 'Who is the guest?');
    if (name == null || !mounted) return;
    final stay = await pickStay(context);
    if (stay == null || !mounted) return;
    setState(() => _busy = true);
    final (resident, _) = _flow.confirmedBy!;
    await c.expectLater(home: widget.home, residentId: resident.id, call: _confirmedCall!, guestName: name, stay: stay.$1, until: stay.$2);
    if (mounted) _finish('Expected: $name, ${widget.home.displayAddress}');
  }

  Future<void> _letInConfirmed(Visit v) async {
    final c = GateScope.read(context);
    final plate = await askLetIn(context, guestName: v.guestName, home: widget.home);
    if (plate == null || !mounted) return;
    final id = await c.admitExpected(v, plate: plate);
    if (mounted) _finish('Let in: ${v.guestName}', undoId: id, letIn: v.guestName);
  }

  Future<void> _turnAway() async {
    final c = GateScope.read(context);
    final name = _guestName ?? await askGuestName(context, title: 'Who is the guest?');
    if (name == null || !mounted) return;
    final reason = await askTurnAwayReason(context, suggested: _flow.stopReason);
    if (reason == null || !mounted) return;
    final id = await c.turnAway(homeId: widget.home.id, guestName: name, reason: reason);
    if (mounted) _finish('Turned away: $name', undoId: id);
  }

  Future<void> _walkIn() async {
    final c = GateScope.read(context);
    final r = await showModalBottomSheet<_WalkIn>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GateScope(
        controller: c,
        child: WalkInSheet(home: widget.home, guestName: _guestName),
      ),
    );
    if (r == null || !mounted) return;
    final id = await c.admitWalkIn(homeId: widget.home.id, guestName: r.guestName, decidedBy: r.decidedBy, reason: r.reason, plate: r.plate);
    if (mounted) _finish('Let in on the CSO\'s decision: ${r.guestName}', undoId: id, letIn: r.guestName);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final home = widget.home;
    final confirmed = c.view.confirmedFor(home.id);
    final step = _flow.step;
    // The confirmed call is recorded, but the guest is neither in nor expected until the guard
    // chooses: do not lose that to a stray Back.
    final letIn = _letIn;
    if (letIn != null) {
      return Scaffold(
        appBar: AppBar(title: Text(home.displayAddress)),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Verdict(
              title: letIn.$1,
              color: GateColors.go,
              wash: GateColors.goWash,
              icon: Icons.check_circle,
              children: [Text(home.displayAddress, style: const TextStyle(fontSize: 19))],
            ),
            const SizedBox(height: 16),
            BigButton(
              label: 'Shuttle to the home',
              icon: Icons.two_wheeler,
              color: GateColors.navy,
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await openShuttleToHome(context, home: home, guestName: letIn.$2)) nav.pop();
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ]),
        ),
      );
    }
    return PopScope(
      canPop: step != NoCodeStep.confirmed || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await confirm(
          context,
          'Leave without finishing?',
          body: '${_flow.confirmedBy!.$1.name} confirmed. The guest is not let in or expected until you choose one.',
          yes: 'Leave',
          no: 'Stay',
        );
        if (leave && mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(home.displayAddress)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (step == NoCodeStep.confirmed)
                _ConfirmedPanel(
                  by: _flow.confirmedBy!.$1.name,
                  guestName: _guestName,
                  plate: PlateField(controller: _plate, home: home),
                  busy: _busy,
                  onRename: () async {
                    final n = await askGuestName(context, title: 'Who is the guest?', initial: _guestName, action: 'OK');
                    if (n != null) setState(() => _guestName = n);
                  },
                  onNow: _letInNow,
                  onLater: _expectLater,
                )
              else if (step == NoCodeStep.stop)
                _StopPanel(
                  reason: _flow.stopReason,
                  policy: c.snapshot?.estate.walkInPolicy ?? '',
                  onTurnAway: _turnAway,
                  onWalkIn: c.csos.isEmpty ? null : _walkIn,
                )
              else ...[
                if (confirmed.isNotEmpty) ...[
                  const _Heading('Already confirmed'),
                  for (final v in confirmed) _ConfirmedGuest(visit: v, onLetIn: () => _letInConfirmed(v)),
                  const SizedBox(height: 12),
                ],
                _Heading(confirmed.isEmpty ? 'Call the home' : 'Someone else? Call the home'),
                if (home.callbackRequired)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'This home wants a call for every guest.',
                      style: TextStyle(fontSize: 16, color: GateColors.warn, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (step == NoCodeStep.tryAgain)
                  Verdict(
                    title: 'No answer',
                    color: GateColors.warn,
                    wash: GateColors.warnWash,
                    icon: Icons.phone_missed,
                    children: const [Text('Call again, or try another number.', style: TextStyle(fontSize: 18))],
                  ),
                if (step == NoCodeStep.tryAgain) const SizedBox(height: 12),
                if (home.residents.isEmpty) const Text('No residents with a number. Follow the walk-in rule.', style: TextStyle(fontSize: 18)),
                for (final r in home.residents) ResidentCallCard(resident: r, onCall: (n) => _call(r, n)),
                if (home.residents.isEmpty) ...[
                  const SizedBox(height: 12),
                  _StopPanel(
                    reason: 'Nobody at this home can be called',
                    policy: c.snapshot?.estate.walkInPolicy ?? '',
                    onTurnAway: _turnAway,
                    onWalkIn: c.csos.isEmpty ? null : _walkIn,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: GateColors.navy),
    ),
  );
}

class _ConfirmedGuest extends StatelessWidget {
  const _ConfirmedGuest({required this.visit, required this.onLetIn});
  final Visit visit;
  final VoidCallback onLetIn;

  @override
  Widget build(BuildContext context) {
    final t = GateScope.of(context).time;
    return LineCard(
      color: GateColors.goWash,
      border: GateColors.go,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.guestName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                if (visit.expectedUntil != null) Text('Staying until ${timeLabel(t, visit.expectedUntil!)}', style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GateColors.go, minimumSize: const Size(110, 60)),
            onPressed: onLetIn,
            child: const Text('Let in'),
          ),
        ],
      ),
    );
  }
}

/// A resident and their numbers, last 4 digits only, each with a Call button.
class ResidentCallCard extends StatelessWidget {
  const ResidentCallCard({super.key, required this.resident, required this.onCall});
  final Resident resident;
  final void Function(PhoneNumber) onCall;

  @override
  Widget build(BuildContext context) => LineCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(resident.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        if (resident.numbers.isEmpty) const Text('No number on file.', style: TextStyle(fontSize: 17)),
        for (final n in resident.numbers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(child: Text('${n.masked}${n.isPrimary ? '  (main)' : ''}', style: const TextStyle(fontSize: 20, letterSpacing: 1))),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: GateColors.navy, minimumSize: const Size(120, 60)),
                  icon: const Icon(Icons.call),
                  label: const Text('Call'),
                  onPressed: () => onCall(n),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ConfirmedPanel extends StatelessWidget {
  const _ConfirmedPanel({
    required this.by,
    required this.guestName,
    required this.plate,
    required this.busy,
    required this.onRename,
    required this.onNow,
    required this.onLater,
  });
  final String by;
  final String? guestName;
  final Widget plate;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onNow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Verdict(
        title: 'Confirmed by $by',
        color: GateColors.go,
        wash: GateColors.goWash,
        icon: Icons.check_circle,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(guestName ?? 'Guest name not given', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: onRename, child: Text(guestName == null ? 'Add name' : 'Change')),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      plate,
      const SizedBox(height: 8),
      BigButton(label: 'They are here: let them in', icon: Icons.login, color: GateColors.go, onPressed: busy ? null : onNow),
      const SizedBox(height: 10),
      OutlinedButton.icon(icon: const Icon(Icons.schedule), label: const Text('Coming later: expect them'), onPressed: busy ? null : onLater),
    ],
  );
}

/// Said no, or no answer twice: never admit on phone authority. The walk-in rule decides.
class _StopPanel extends StatelessWidget {
  const _StopPanel({required this.reason, required this.policy, required this.onTurnAway, required this.onWalkIn});
  final String reason;
  final String policy;
  final VoidCallback onTurnAway;
  final VoidCallback? onWalkIn;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Verdict(
        title: 'Do not let them in on the phone',
        color: GateColors.stop,
        wash: GateColors.stopWash,
        icon: Icons.block,
        children: [Text(reason, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))],
      ),
      const SizedBox(height: 12),
      LineCard(
        color: GateColors.wash,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Walk-in rule',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: GateColors.navy),
            ),
            const SizedBox(height: 4),
            Text(policy.isEmpty ? 'Turn the guest away unless the CSO decides otherwise.' : policy, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
      const SizedBox(height: 4),
      BigButton(label: 'Turn away', icon: Icons.block, color: GateColors.stop, onPressed: onTurnAway),
      const SizedBox(height: 10),
      OutlinedButton.icon(icon: const Icon(Icons.shield_outlined), label: const Text('CSO decided: let them in'), onPressed: onWalkIn),
      if (onWalkIn == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('No CSO is set up for this estate.', style: TextStyle(fontSize: 16)),
        ),
    ],
  );
}

class _WalkIn {
  const _WalkIn(this.guestName, this.decidedBy, this.reason, this.plate);
  final String guestName;
  final String decidedBy;
  final String reason;
  final String plate;
}

/// Record the CSO's decision to admit: who decided, and why (both required).
class WalkInSheet extends StatefulWidget {
  const WalkInSheet({super.key, required this.home, this.guestName});
  final Home home;
  final String? guestName;

  @override
  State<WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<WalkInSheet> {
  late final _name = TextEditingController(text: widget.guestName);
  final _reason = TextEditingController();
  final _plate = TextEditingController();
  String? _decidedBy;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    _plate.dispose();
    super.dispose();
  }

  bool get _ready => _decidedBy != null && _reason.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("The CSO's decision", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(widget.home.displayAddress, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(labelText: 'Guest name'),
            ),
            const SizedBox(height: 14),
            const Text('Who decided?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in c.csos)
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(g.name, style: const TextStyle(fontSize: 18)),
                    ),
                    selected: _decidedBy == g.id,
                    onSelected: (_) => setState(() => _decidedBy = g.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 280,
              maxLines: 2,
              style: const TextStyle(fontSize: 19),
              decoration: const InputDecoration(labelText: 'Reason (required)', hintText: 'Estate electrician, known to the CSO'),
            ),
            PlateField(controller: _plate, home: widget.home),
            const SizedBox(height: 10),
            BigButton(
              label: 'Let them in',
              icon: Icons.login,
              color: GateColors.go,
              onPressed: _ready ? () => Navigator.pop(context, _WalkIn(_name.text.trim(), _decidedBy!, _reason.text.trim(), _plate.text)) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Let in a guest already confirmed: name check and the optional plate. Returns the plate
/// ('' for none), or null on cancel.
Future<String?> askLetIn(BuildContext context, {required String guestName, Home? home}) {
  final plate = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(guestName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (home != null) Text(home.displayAddress, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          PlateField(controller: plate, home: home),
          const SizedBox(height: 8),
          BigButton(label: 'Let them in', icon: Icons.login, color: GateColors.go, onPressed: () => Navigator.pop(ctx, plate.text)),
        ],
      ),
    ),
  );
}

/// The CSO's "Add a guest": the same find-home, call and expect-later flow.
void openAddGuest(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FindHomeScreen(title: 'Add a guest')));

/// Inside guests for the People tab and the Leaving list, grouped by home in house order.
Map<String, List<InsideGuest>> groupByHome(List<InsideGuest> guests) {
  final groups = <String, List<InsideGuest>>{};
  for (final g in guests) {
    groups.putIfAbsent(g.homeId, () => []).add(g);
  }
  return groups;
}

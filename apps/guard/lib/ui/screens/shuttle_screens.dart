import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/gate_view.dart' show compareHomes;
import '../../app/rides.dart';
import '../../app/shift.dart';
import '../../core/card.dart';
import '../../core/estate_time.dart';
import '../../data/models.dart';
import '../../data/shuttle.dart';
import '../../sync/card_reader.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'no_code_screen.dart';

// --- building blocks (big targets: riders use these one-handed, outdoors, maybe in gloves) ----

/// A full-width outlined choice, at least 72 high.
class ChoiceButton extends StatelessWidget {
  const ChoiceButton({super.key, required this.label, required this.onPressed, this.sub, this.icon});
  final String label;
  final String? sub;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(72), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          onPressed: onPressed,
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 30), const SizedBox(width: 14)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: GateColors.ink)),
              ]),
            ),
          ]),
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.sub});
  final String text;
  final String? sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 18)),
        ]),
      );
}

Future<T?> _push<T>(BuildContext context, Widget screen) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen));

// --- pickers -------------------------------------------------------------------------------------

/// Find a home by house number or surname. Returns the home, or null on Back.
Future<Home?> pickHome(BuildContext context, {String title = 'Which home?'}) => _push<Home>(context, HomePickerScreen(title: title));

class HomePickerScreen extends StatefulWidget {
  const HomePickerScreen({super.key, required this.title});
  final String title;
  @override
  State<HomePickerScreen> createState() => _HomePickerScreenState();
}

class _HomePickerScreenState extends State<HomePickerScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final homes = (c.snapshot?.homes ?? const <Home>[]).where((h) => homeMatches(h, _q)).toList()..sort(compareHomes);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(children: [
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
                return ListTile(
                  minTileHeight: 72,
                  title: Text(h.displayAddress, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  subtitle: Text(h.residents.map((r) => r.name).join(', '), style: const TextStyle(fontSize: 16)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, h),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// One of [stops], or null on Back.
Future<RideStop?> pickStop(BuildContext context, {required String title, required List<RideStop> stops, String? sub}) =>
    _push<RideStop>(context, _StopPicker(title: title, sub: sub, stops: stops));

class _StopPicker extends StatelessWidget {
  const _StopPicker({required this.title, required this.stops, this.sub});
  final String title;
  final String? sub;
  final List<RideStop> stops;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New ride')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _Heading(title, sub: sub),
            for (final s in stops)
              ChoiceButton(
                label: s.kind == 'home' ? 'Their home' : s.label,
                sub: s.kind == 'home' ? s.label : null,
                icon: switch (s.kind) {
                  'home' => Icons.home_outlined,
                  'gate' => Icons.door_sliding_outlined,
                  _ => Icons.place_outlined,
                },
                onPressed: () => Navigator.pop(context, s),
              ),
          ]),
        ),
      );
}

/// Who it was, from the home's residents. Returns the resident id, '' for "someone else from
/// the home" (when [allowSomeoneElse]), or null on Back.
Future<String?> pickResident(BuildContext context, Home home, {bool allowSomeoneElse = true, String title = 'Who is it?'}) => _push<String>(
      context,
      Scaffold(
        appBar: AppBar(title: Text(home.displayAddress)),
        body: SafeArea(
          child: Builder(
            builder: (ctx) => ListView(padding: const EdgeInsets.all(16), children: [
              _Heading(title),
              for (final r in home.residents) ChoiceButton(label: r.name, icon: Icons.person_outline, onPressed: () => Navigator.pop(ctx, r.id)),
              if (home.residents.isEmpty) const Text('No residents are listed for this home.', style: TextStyle(fontSize: 18)),
              if (allowSomeoneElse) ChoiceButton(label: 'Someone else from this home', icon: Icons.group_outlined, onPressed: () => Navigator.pop(ctx, '')),
            ]),
          ),
        ),
      ),
    );

// --- estate card ---------------------------------------------------------------------------------

/// Hold the card to the phone. Returns the UID (kept in memory only, never shown), or null.
Future<String?> tapCard(BuildContext context, {String title = 'Estate card'}) => _push<String>(context, TapCardScreen(title: title));

class TapCardScreen extends StatefulWidget {
  const TapCardScreen({super.key, required this.title});
  final String title;
  @override
  State<TapCardScreen> createState() => _TapCardScreenState();
}

class _TapCardScreenState extends State<TapCardScreen> {
  CardReaderState? _state;
  late final CardReader _reader = GateScope.read(context).cardReader;
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final st = await _reader.state();
    if (!mounted) return;
    setState(() => _state = st);
    if (st != CardReaderState.ready) return;
    final uid = await _reader.read();
    if (!mounted || uid == null) return;
    Navigator.pop(context, uid);
  }

  @override
  void dispose() {
    unawaited(_reader.cancel());
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (st == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (st == CardReaderState.ready) ...[
            const Icon(Icons.contactless, size: 120, color: GateColors.navy),
            const Text('Hold the card flat on the back of the phone', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Center(child: CircularProgressIndicator()),
          ],
          if (st == CardReaderState.off)
            Verdict(
              title: 'NFC is off',
              color: GateColors.warn,
              wash: GateColors.warnWash,
              icon: Icons.contactless_outlined,
              children: const [Text('Turn on NFC in the phone settings, then try again. Or use the house code.', style: TextStyle(fontSize: 18))],
            ),
          if (st == CardReaderState.none)
            Verdict(
              title: 'This phone cannot read cards',
              color: GateColors.warn,
              wash: GateColors.warnWash,
              icon: Icons.contactless_outlined,
              children: const [Text('Use the house code instead.', style: TextStyle(fontSize: 18))],
            ),
          const SizedBox(height: 16),
          if (st == CardReaderState.off) BigButton(label: 'Try again', icon: Icons.refresh, color: GateColors.navy, onPressed: _start),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          // The emulator has no NFC. Debug builds only: kDebugMode is a compile-time constant, so
          // this is not in a release build at all.
          if (kDebugMode) ...[
            const SizedBox(height: 28),
            const Text('Test build only: type a card UID', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GateColors.warn)),
            const SizedBox(height: 6),
            TextField(
              controller: _typed,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(labelText: 'Card UID', hintText: '04:A2:1B:7C:55:80'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                if (isPlausibleUid(_typed.text)) Navigator.pop(context, normaliseUid(_typed.text));
              },
              child: const Text('Use this UID'),
            ),
          ],
        ]),
      ),
    );
  }
}

// --- house code ----------------------------------------------------------------------------------

/// The resident says their home's 4 digits. Returns true when they match.
Future<bool> askHouseCode(BuildContext context, Home home) async => await _push<bool>(context, HouseCodeScreen(home: home)) ?? false;

class HouseCodeScreen extends StatefulWidget {
  const HouseCodeScreen({super.key, required this.home});
  final Home home;
  @override
  State<HouseCodeScreen> createState() => _HouseCodeScreenState();
}

class _HouseCodeScreenState extends State<HouseCodeScreen> {
  String _digits = '';
  String? _message;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _press(String d) async {
    if (_busy || _digits.length >= 4) return;
    setState(() => _digits += d);
    if (_digits.length < 4) return;
    setState(() => _busy = true);
    final r = await GateScope.read(context).checkHouseCode(widget.home.id, _digits);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _digits = '';
    });
    switch (r) {
      case HouseCodeOk():
        Navigator.pop(context, true);
      case HouseCodeWrong(:final triesLeft):
        setState(() => _message = 'Wrong code. $triesLeft ${triesLeft == 1 ? 'try' : 'tries'} left.');
      case HouseCodeLocked():
        setState(() => _message = null);
      case HouseCodeNone():
        setState(() => _message = 'This home has no house code yet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final locked = c.houseCodeLockedUntil(widget.home.id);
    return Scaffold(
      appBar: AppBar(title: const Text('House code')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.home.displayAddress, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Text(locked != null ? 'Too many wrong tries' : 'Ask for the 4-digit house code', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              if (locked != null) Text('Try again at ${hhmm(c.time.of(locked))}, or use the card.', style: const TextStyle(fontSize: 18)),
              if (_message != null && locked == null)
                Text(_message!, style: const TextStyle(fontSize: 18, color: GateColors.stop, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              CodeBoxes(digits: _digits, length: 4, obscure: true, error: _message != null),
              SizedBox(height: 24, child: _busy ? const Center(child: LinearProgressIndicator()) : null),
            ]),
          ),
          Expanded(
            child: Keypad(
              enabled: !_busy && locked == null,
              onDigit: _press,
              onBack: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
              onClear: () => setState(() => _digits = ''),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// --- who rode --------------------------------------------------------------------------------------

/// The home a ride is for, and how the rider knows who it was.
class WhoRode {
  const WhoRode(this.home, this.confirm);
  final Home home;
  final RideConfirm confirm;
}

/// At pickup (a parcel: at drop-off). [home] is the ride's home; null for a flagged-down ride,
/// where the card, the house code or the rider's pick says which home it is.
Future<WhoRode?> askWhoRode(BuildContext context, {Home? home, bool fromGate = false, bool parcel = false}) =>
    _push<WhoRode>(context, WhoRodeScreen(home: home, fromGate: fromGate, parcel: parcel));

class WhoRodeScreen extends StatelessWidget {
  const WhoRodeScreen({super.key, this.home, this.fromGate = false, this.parcel = false});
  final Home? home;
  final bool fromGate;
  final bool parcel;

  Future<void> _card(BuildContext context) async {
    final c = GateScope.read(context);
    final uid = await tapCard(context);
    if (uid == null || !context.mounted) return;
    final card = c.cardFor(uid);
    if (card == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Card not known'),
          content: const Text('This card is not on the estate list. Use the house code.', style: TextStyle(fontSize: 19)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    final resident = c.snapshot?.resident(card.residentId);
    final cardHome = c.snapshot?.home(card.homeId);
    if (cardHome == null) return;
    final ok = await confirm(
      context,
      resident?.name ?? 'A resident',
      body: [cardHome.displayAddress, if (home != null && home!.id != cardHome.id) 'Not the home on this ride.'].join('\n'),
      yes: 'Yes, this is them',
      no: 'No',
    );
    if (ok && context.mounted) Navigator.pop(context, WhoRode(cardHome, RideConfirm.card(cardId: card.id, residentId: card.residentId)));
  }

  Future<void> _houseCode(BuildContext context) async {
    final h = home ?? await pickHome(context, title: 'Which home?');
    if (h == null || !context.mounted) return;
    if (h.houseCodeHash == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No house code'),
          content: const Text('This home has not asked for a house code yet. Use the card, or vouch for them.', style: TextStyle(fontSize: 19)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!await askHouseCode(context, h) || !context.mounted) return;
    final who = await pickResident(context, h);
    if (who == null || !context.mounted) return;
    Navigator.pop(context, WhoRode(h, RideConfirm.houseCode(residentId: who.isEmpty ? null : who)));
  }

  Future<void> _vouch(BuildContext context) async {
    final h = home ?? await pickHome(context, title: 'Which home?');
    if (h == null || !context.mounted) return;
    Navigator.pop(context, WhoRode(h, const RideConfirm.rider()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(parcel ? 'Parcel handed over' : (home == null ? 'New ride' : 'Picked up'))),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _Heading(parcel ? 'Who took the parcel?' : 'Who is riding?', sub: home?.displayAddress),
            ChoiceButton(label: 'Estate card', sub: 'Tap their card on the phone', icon: Icons.contactless, onPressed: () => _card(context)),
            ChoiceButton(label: 'House code', sub: 'They say their 4 digits', icon: Icons.pin_outlined, onPressed: () => _houseCode(context)),
            if (fromGate && !parcel && home != null)
              ChoiceButton(
                label: 'The guard sent them',
                sub: 'Booked at the gate',
                icon: Icons.shield_outlined,
                onPressed: () => Navigator.pop(context, WhoRode(home!, const RideConfirm.guard())),
              ),
            ChoiceButton(
              label: home == null ? 'Pick the home: I vouch' : 'No card or code: I vouch',
              icon: Icons.how_to_reg_outlined,
              onPressed: () => _vouch(context),
            ),
          ]),
        ),
      );
}

// --- booking at the gate (guard view) --------------------------------------------------------------

/// "Shuttle to the home": pick the home if not given, then a parcel or a guest.
Future<void> openShuttleToHome(BuildContext context, {Home? home, String? guestName, bool replace = false}) async {
  final h = home ?? await pickHome(context, title: 'Shuttle to which home?');
  if (h == null || !context.mounted) return;
  final route = MaterialPageRoute<void>(builder: (_) => BookAtGateScreen(home: h, guestName: guestName));
  replace ? await Navigator.of(context).pushReplacement(route) : await Navigator.of(context).push(route);
}

class BookAtGateScreen extends StatefulWidget {
  const BookAtGateScreen({super.key, required this.home, this.guestName});
  final Home home;
  final String? guestName;
  @override
  State<BookAtGateScreen> createState() => _BookAtGateScreenState();
}

class _BookAtGateScreenState extends State<BookAtGateScreen> {
  late String _kind = widget.guestName != null ? RideKind.guest : RideKind.delivery;
  late final _what = TextEditingController(text: widget.guestName);
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _what.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _what.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _book() async {
    final c = GateScope.read(context);
    setState(() => _busy = true);
    await c.bookAtGate(home: widget.home, kind: _kind, passenger: _what.text, note: _note.text);
    if (!mounted) return;
    final message = 'Shuttle booked: ${_kind == RideKind.delivery ? 'parcel' : _what.text.trim()} to ${widget.home.displayAddress}';
    c.showNotice(message);
    if (c.isCso) toast(context, message);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final parcel = _kind == RideKind.delivery;
    Widget kindButton(String kind, String label, IconData icon) {
      final on = _kind == kind;
      return Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(72),
            backgroundColor: on ? GateColors.navy : GateColors.wash,
            foregroundColor: on ? Colors.white : GateColors.navy,
            side: const BorderSide(color: GateColors.navy, width: 2),
          ),
          icon: Icon(icon, size: 28),
          label: Text(label),
          onPressed: () => setState(() => _kind = kind),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Shuttle to the home')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _Heading(widget.home.displayAddress, sub: 'From ${GateScope.of(context).gateName ?? 'the gate'}'),
          Row(children: [
            kindButton(RideKind.delivery, 'Parcel', Icons.inventory_2_outlined),
            const SizedBox(width: 12),
            kindButton(RideKind.guest, 'Guest', Icons.person_outline),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _what,
            textCapitalization: parcel ? TextCapitalization.sentences : TextCapitalization.words,
            maxLength: 120,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(labelText: parcel ? 'What is the parcel?' : 'Guest name', hintText: parcel ? 'Jumia parcel' : 'Name', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 200,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: 'Note for the rider (optional)', counterText: ''),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: 'Book the shuttle',
            icon: Icons.two_wheeler,
            color: GateColors.go,
            onPressed: _busy || _what.text.trim().isEmpty ? null : _book,
          ),
        ]),
      ),
    );
  }
}

// --- the CSO's Shuttle tab -------------------------------------------------------------------------

String rideStateLine(Ride r, String Function(DateTime) wait) => switch (r.state) {
      RideState.accepted => 'Taken by ${r.rider ?? 'a rider'}',
      RideState.pickedUp => 'On the way with ${r.rider ?? 'a rider'}',
      _ => 'No rider yet. ${wait(r.wantedAt ?? DateTime.now())}',
    };

class ShuttleTab extends StatelessWidget {
  const ShuttleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final now = t.now();
    String wait(DateTime d) => waitLabel(d, now, (x) => hhmm(t.of(x)));
    final waiting = c.cso?.ridesWaiting ?? const [];
    final open = c.rides.open;
    return RefreshIndicator(
      onRefresh: () async {
        await c.syncNow();
        await c.refreshCso();
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text(c.lastSyncAt == null ? 'Not synced yet' : 'Rides as of ${hhmm(t.of(c.lastSyncAt!))}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        BigButton(label: 'Book a ride', icon: Icons.two_wheeler, color: GateColors.navy, onPressed: () => openDispatch(context)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          icon: const Icon(Icons.contactless),
          label: const Text('Issue a card'),
          onPressed: () => _push<void>(context, const IssueCardScreen()),
        ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Waiting over 10 minutes (${waiting.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GateColors.stop)),
          const SizedBox(height: 6),
          for (final w in waiting)
            LineCard(
              color: GateColors.stopWash,
              border: GateColors.stop,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${rideKindLabel(w.kind)}: ${w.from ?? '?'} to ${w.to ?? '?'}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                if (w.wantedAt != null) Text(wait(w.wantedAt!), style: const TextStyle(fontSize: 16)),
              ]),
            ),
        ],
        const SizedBox(height: 16),
        Text('Open rides (${open.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: GateColors.navy)),
        const SizedBox(height: 6),
        if (open.isEmpty) const Text('No open rides.', style: TextStyle(fontSize: 18)),
        for (final r in open)
          LineCard(
            color: r.isRequested ? GateColors.warnWash : null,
            border: r.isRequested ? GateColors.warn : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${rideKindLabel(r.kind)}: ${r.pickup.label} to ${r.dropoff.label}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              if (r.passenger != null) Text(r.passenger!, style: const TextStyle(fontSize: 16)),
              Text(rideStateLine(r, wait), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}

// --- the CSO books a ride for a resident who rang ---------------------------------------------------

Future<void> openDispatch(BuildContext context) async {
  final home = await pickHome(context, title: 'Book a ride: which home?');
  if (home == null || !context.mounted) return;
  await _push<void>(context, DispatchScreen(home: home));
}

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key, required this.home});
  final Home home;
  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  String? _resident;
  RideStop? _from;
  RideStop? _to;
  DateTime? _at; // null: now
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.home.residents.length == 1) _resident = widget.home.residents.single.id;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ready => _resident != null && _from != null && _to != null && !_from!.sameAs(_to!);

  Future<void> _later() async {
    final c = GateScope.read(context);
    final now = c.time.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0), helpText: 'Ride wanted at');
    if (picked == null) return;
    var at = c.time.at(now.year, now.month, now.day, picked.hour, picked.minute);
    if (at.isBefore(now.subtract(const Duration(minutes: 15)))) at = at.add(const Duration(days: 1));
    setState(() => _at = at);
  }

  Future<void> _book() async {
    final c = GateScope.read(context);
    setState(() => _busy = true);
    await c.bookDispatch(home: widget.home, residentId: _resident!, pickup: _from!, dropoff: _to!, wantedAt: _at, note: _note.text);
    if (!mounted) return;
    toast(context, 'Ride booked: ${_from!.label} to ${_to!.label}');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final stops = rideStops(c.snapshot!, home: widget.home);
    Widget chip(String label, bool on, VoidCallback tap) => ChoiceChip(
          label: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(label, style: const TextStyle(fontSize: 18))),
          selected: on,
          onSelected: (_) => tap(),
        );
    Text sub(String s) => Text(s, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
    String stopLabel(RideStop s) => s.kind == 'home' ? 'Their home' : s.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Book a ride')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _Heading(widget.home.displayAddress),
          sub('Who rang?'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in widget.home.residents) chip(r.name, _resident == r.id, () => setState(() => _resident = r.id)),
          ]),
          if (widget.home.residents.isEmpty) const Text('No residents are listed for this home.', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          sub('From'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in stops) chip(stopLabel(s), _from?.sameAs(s) ?? false, () => setState(() => _from = s))]),
          const SizedBox(height: 16),
          sub('To'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in stops) chip(stopLabel(s), _to?.sameAs(s) ?? false, () => setState(() => _to = s))]),
          if (_from != null && _to != null && _from!.sameAs(_to!))
            const Text('From and To are the same place.', style: TextStyle(fontSize: 16, color: GateColors.stop, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          sub('When'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip('Now', _at == null, () => setState(() => _at = null)),
            chip(_at == null ? 'Later' : 'At ${hhmm(_at!)}', _at != null, _later),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 200,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: 'Note for the rider (optional)', counterText: ''),
          ),
          const SizedBox(height: 12),
          BigButton(label: 'Book the ride', icon: Icons.two_wheeler, color: GateColors.go, onPressed: _ready && !_busy ? _book : null),
        ]),
      ),
    );
  }
}

// --- the CSO issues a card ----------------------------------------------------------------------------

class IssueCardScreen extends StatefulWidget {
  const IssueCardScreen({super.key});
  @override
  State<IssueCardScreen> createState() => _IssueCardScreenState();
}

enum _Issue { tap, taken, pick, sending, done }

class _IssueCardScreenState extends State<IssueCardScreen> {
  _Issue _step = _Issue.tap;
  String? _uid; // in memory only, never shown
  EstateCard? _known;
  Resident? _resident;
  Home? _home;
  Verdict? _result;

  Future<void> _tap() async {
    final c = GateScope.read(context);
    final uid = await tapCard(context, title: 'Issue a card');
    if (uid == null || !mounted) return;
    final known = c.cardFor(uid);
    setState(() {
      _uid = uid;
      _known = known;
      _step = known == null ? _Issue.pick : _Issue.taken;
    });
  }

  Future<void> _pick() async {
    final home = await pickHome(context, title: 'Whose card is it?');
    if (home == null || !mounted) return;
    final id = await pickResident(context, home, allowSomeoneElse: false, title: 'Who gets the card?');
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      _home = home;
      _resident = home.residents.firstWhere((r) => r.id == id);
    });
  }

  Future<void> _issue() async {
    final c = GateScope.read(context);
    final r = _resident!;
    setState(() => _step = _Issue.sending);
    final id = await c.issueCard(uid: _uid!, resident: r);
    await c.syncNow();
    final item = await c.queuedItem(id);
    if (!mounted) return;
    setState(() {
      _step = _Issue.done;
      _result = item != null && item.isRejected
          ? Verdict(title: 'Card not issued', color: GateColors.stop, wash: GateColors.stopWash, icon: Icons.block, children: [
              Text(_sentence(item.reason ?? 'The server refused it.'), style: const TextStyle(fontSize: 18)),
            ])
          : item != null && item.isPending
              ? Verdict(title: 'Saved', color: GateColors.warn, wash: GateColors.warnWash, icon: Icons.cloud_off, children: [
                  Text('It goes to the server when there is a connection. ${r.name} can use the card after that.', style: const TextStyle(fontSize: 18)),
                ])
              : Verdict(title: 'Card issued', color: GateColors.go, wash: GateColors.goWash, icon: Icons.check_circle, children: [
                  Text('${r.name}, ${_home?.displayAddress ?? ''}', style: const TextStyle(fontSize: 18)),
                ]);
    });
  }

  static String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

  void _again() => setState(() {
        _step = _Issue.tap;
        _uid = null;
        _known = null;
        _resident = null;
        _home = null;
        _result = null;
      });

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final children = <Widget>[];
    switch (_step) {
      case _Issue.tap:
        children.addAll([
          const _Heading('Issue a card', sub: 'Tap the new card on the phone, then pick the resident.'),
          BigButton(label: 'Tap the card', icon: Icons.contactless, color: GateColors.navy, onPressed: _tap),
        ]);
      case _Issue.taken:
        final owner = c.snapshot?.resident(_known?.residentId);
        children.addAll([
          Verdict(title: 'This card is already issued', color: GateColors.stop, wash: GateColors.stopWash, icon: Icons.block, children: [
            Text('It is ${owner?.name ?? 'someone else'}\'s card. Revoke it in the dashboard first.', style: const TextStyle(fontSize: 18)),
          ]),
          const SizedBox(height: 16),
          BigButton(label: 'Try another card', icon: Icons.contactless, color: GateColors.navy, onPressed: _again),
        ]);
      case _Issue.pick:
        children.addAll([
          _Heading('Card ending ${uidLast4(_uid!)}', sub: _resident == null ? 'Who gets it?' : null),
          if (_resident != null) ...[
            LineCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_resident!.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(_home!.displayAddress, style: const TextStyle(fontSize: 17)),
              ]),
            ),
            BigButton(label: 'Issue the card', icon: Icons.check, color: GateColors.go, onPressed: _issue),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.person_search),
            label: Text(_resident == null ? 'Pick the resident' : 'Someone else'),
            onPressed: _pick,
          ),
        ]);
      case _Issue.sending:
        children.add(const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())));
      case _Issue.done:
        children.addAll([
          ?_result,
          const SizedBox(height: 16),
          BigButton(label: 'Done', color: GateColors.navy, onPressed: () => Navigator.pop(context)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _again, child: const Text('Issue another card')),
        ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Issue a card')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: children)),
    );
  }
}

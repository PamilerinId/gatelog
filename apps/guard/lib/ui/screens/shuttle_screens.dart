/// The shuttle's screens, built to the handoff's guard app rules (see `ui/kit.dart`): one job per
/// screen, Yes or No, no typing, results read aloud. The home is picked from the register by
/// street, then house number, so nobody types.
library;

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
import '../kit.dart';

Future<T?> _push<T>(BuildContext context, Widget screen) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen));

/// "14B" for a home, the name for a gate or a place.
String stopShort(StateSnapshot? snap, RideStop s) => s.kind == 'home' ? (snap?.home(s.ref ?? '')?.label.toUpperCase() ?? s.label) : s.label;

/// The street line under a home's number.
String? stopSub(StateSnapshot? snap, RideStop s) {
  if (s.kind != 'home') return null;
  return snap?.home(s.ref ?? '')?.street;
}

// --- cards --------------------------------------------------------------------------------------

/// A home as Guard-Call shows it: the number large in mono, the street and the residents.
class HouseCard extends StatelessWidget {
  const HouseCard({super.key, required this.home, this.name});
  final Home home;

  /// The person (a resident's name) instead of the list of residents.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final who = name ?? home.residents.map((r) => r.name).join(', ');
    return KitCard(
      child: Row(
        children: [
          Text(home.label.toUpperCase(), style: monoStyle(context, 40)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(home.street, style: mutedStyle(context, 16)),
                if (who.isNotEmpty)
                  Text(
                    who,
                    style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One end of a ride: FROM / TO in small mono, the place large.
class StopLine extends StatelessWidget {
  const StopLine({super.key, required this.label, required this.stop});
  final String label;
  final RideStop stop;

  @override
  Widget build(BuildContext context) {
    final snap = GateScope.of(context).snapshot;
    final sub = stopSub(snap, stop);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: monoStyle(context, 14, color: Palette.of(context).muted, weight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: stopShort(snap, stop),
                    style: stop.kind == 'home' ? monoStyle(context, 30) : const TextStyle(fontFamily: inter, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  if (sub != null) TextSpan(text: '  $sub', style: mutedStyle(context, 16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a ride is, where from and to, how long it has waited.
class RideSummary extends StatelessWidget {
  const RideSummary({super.key, required this.ride, this.counter});
  final Ride ride;

  /// "1 OF 3" in the queue.
  final String? counter;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final under = ride.state == RideState.pickedUp;
    final wait = under ? 'Under way' : waitLabel(ride.wantedAt, t.now(), (d) => hhmm(t.of(d)));
    final who = ride.passenger ?? (ride.residentId == null ? null : c.snapshot?.resident(ride.residentId)?.name);
    return KitCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(rideIcon(ride.kind), size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rideKindLabel(ride.kind),
                  style: const TextStyle(fontFamily: inter, fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              if (counter != null)
                Text(
                  counter!,
                  style: monoStyle(context, 13, color: p.muted, weight: FontWeight.w500),
                ),
            ],
          ),
          const SizedBox(height: 6),
          StopLine(label: 'FROM', stop: ride.pickup),
          StopLine(label: 'TO', stop: ride.dropoff),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                wait.toUpperCase(),
                style: monoStyle(context, 15, color: under ? p.text : p.warnText, weight: FontWeight.w600),
              ),
              if (who != null && who.isNotEmpty)
                Text(
                  who,
                  style: const TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          if (ride.note != null && ride.note!.isNotEmpty) Text(ride.note!, style: mutedStyle(context, 16)),
        ],
      ),
    );
  }
}

IconData rideIcon(String kind) => switch (kind) {
  RideKind.delivery => Icons.inventory_2_outlined,
  RideKind.guest => Icons.person_outline,
  _ => Icons.home_outlined,
};

/// Read aloud: "Resident. From 14B to Main gate. Waiting 12 min."
String rideWords(StateSnapshot? snap, Ride r, String wait) =>
    '${rideKindLabel(r.kind)}. From ${stopShort(snap, r.pickup)} to ${stopShort(snap, r.dropoff)}. $wait.';

// --- Yes or No --------------------------------------------------------------------------------------

/// One question, Yes or No. Returns null on Back.
Future<bool?> askYesNo(BuildContext context, {required String question, Widget? about, String? label, String? say, String yes = 'Yes', String no = 'No'}) =>
    _push<bool>(context, YesNoScreen(question: question, about: about, label: label, say: say, yes: yes, no: no));

class YesNoScreen extends StatefulWidget {
  const YesNoScreen({super.key, required this.question, this.about, this.label, this.say, this.yes = 'Yes', this.no = 'No'});
  final String question;
  final Widget? about;
  final String? label;
  final String? say;
  final String yes;
  final String no;
  @override
  State<YesNoScreen> createState() => _YesNoScreenState();
}

class _YesNoScreenState extends State<YesNoScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.say != null) speak(widget.say!);
  }

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: widget.label, sayAloud: [widget.say, widget.question].whereType<String>().join(' ')),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?widget.about, const SizedBox(height: 12), Headline(widget.question)]),
          ),
        ),
        const SizedBox(height: 12),
        YesNo(yes: widget.yes, no: widget.no, onYes: () => Navigator.pop(context, true), onNo: () => Navigator.pop(context, false)),
      ],
    ),
  );
}

/// The answer to a run of Yes or No questions: [value] is the one said Yes to, or null when
/// every answer was No.
class Picked<T> {
  const Picked(this.value);
  final T? value;
}

/// Asks about each of [items] in turn ("Going to Main gate?") until one gets a Yes. Null on Back.
Future<Picked<T>?> askEach<T>(
  BuildContext context, {
  required List<T> items,
  required String Function(T) question,
  Widget Function(T)? about,
  String? label,
}) async {
  for (final item in items) {
    if (!context.mounted) return null;
    final yes = await askYesNo(context, question: question(item), about: about?.call(item), label: label, say: question(item));
    if (yes == null) return null;
    if (yes) return Picked(item);
  }
  return Picked<T>(null);
}

/// "Is it Mrs Adeyemi?" for each resident. Picked(null): someone else from the home.
Future<Picked<Resident>?> askResident(BuildContext context, Home home, {String Function(Resident)? question, String? label}) => askEach<Resident>(
  context,
  items: home.residents,
  question: question ?? (r) => 'Is it ${r.name}?',
  about: (r) => HouseCard(home: home, name: r.name),
  label: label,
);

// --- the register: street, then house number ----------------------------------------------------------

/// Picks a home from the register without typing. Null on Back.
Future<Home?> pickHome(BuildContext context, {String title = 'Which house?'}) async {
  final c = GateScope.read(context);
  final homes = [...?c.snapshot?.homes]..sort(compareHomes);
  final streets = <String, List<Home>>{};
  for (final h in homes) {
    streets.putIfAbsent(h.street.isEmpty ? h.zone : h.street, () => []).add(h);
  }
  if (streets.isEmpty) return null;
  final one = streets.length == 1 ? streets.keys.single : null;
  while (true) {
    if (!context.mounted) return null;
    final street = one ?? await _push<String>(context, _StreetPicker(title: title, streets: streets));
    if (street == null || !context.mounted) return null;
    final home = await _push<Home>(context, _HousePicker(title: title, street: street, homes: streets[street]!));
    if (home != null) return home;
    if (one != null) return null;
  }
}

class _StreetPicker extends StatelessWidget {
  const _StreetPicker({required this.title, required this.streets});
  final String title;
  final Map<String, List<Home>> streets;

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: 'Street', sayAloud: '$title Tap the street.'),
        Headline(title),
        Expanded(
          child: ListView(
            children: [
              for (final e in streets.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BigTile(label: e.key, sub: e.value.first.zone, height: 88, onTap: () => Navigator.pop(context, e.key)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HousePicker extends StatelessWidget {
  const _HousePicker({required this.title, required this.street, required this.homes});
  final String title;
  final String street;
  final List<Home> homes;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cols = MediaQuery.sizeOf(context).width < 360 ? 2 : 3;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: street, sayAloud: '$title Tap the house number.'),
          Headline(title),
          Expanded(
            child: GridView.count(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: [
                for (final h in homes)
                  Semantics(
                    button: true,
                    label: '${h.label} ${h.street}',
                    excludeSemantics: true,
                    child: Material(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.pop(context, h),
                        child: Center(child: Text(h.label.toUpperCase(), style: monoStyle(context, 32))),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- estate card ------------------------------------------------------------------------------------

/// "Tap their card": listens for one card while it shows. The UID goes to [onUid] and is kept
/// nowhere. The emulator has no NFC: debug builds only add a typed UID (kDebugMode is a
/// compile-time constant, so a release build has no such field).
class CardStep extends StatefulWidget {
  const CardStep({super.key, required this.onUid, this.title = 'Tap their card'});
  final void Function(String uid) onUid;
  final String title;
  @override
  State<CardStep> createState() => _CardStepState();
}

class _CardStepState extends State<CardStep> {
  late final CardReader _reader = GateScope.read(context).cardReader;
  CardReaderState? _state;
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  Future<void> _listen() async {
    final st = await _reader.state();
    if (!mounted) return;
    setState(() => _state = st);
    if (st != CardReaderState.ready) return;
    final uid = await _reader.read();
    if (!mounted || uid == null) return;
    widget.onUid(uid);
  }

  @override
  void dispose() {
    unawaited(_reader.cancel());
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final st = _state;
    final note = switch (st) {
      CardReaderState.off => 'Card reader is off. Turn on NFC in settings.',
      CardReaderState.none => 'This phone cannot read cards.',
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.contactless_outlined, size: 96, color: st == CardReaderState.ready ? p.text : p.muted),
        Headline(widget.title, center: true),
        if (note != null)
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: inter, fontSize: 17, color: p.warnText, fontWeight: FontWeight.w600),
          ),
        if (st == CardReaderState.off)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pill(label: 'Try again', icon: Icons.refresh, onTap: _listen),
          ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          Text(
            'Test build only: type a card UID',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: mono, fontSize: 12, color: p.warnText),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _typed,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(fontFamily: mono, fontSize: 16, color: p.text),
                  decoration: InputDecoration(isDense: true, hintText: '04:A2:1B:7C:55:80', hintStyle: mutedStyle(context, 14)),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (isPlausibleUid(_typed.text)) widget.onUid(normaliseUid(_typed.text));
                },
                child: Text(
                  'Use',
                  style: TextStyle(fontFamily: inter, color: p.text),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// --- home PIN ---------------------------------------------------------------------------------------

/// The home PIN keypad (one 4-digit PIN per home, for the gate and the shuttle). Returns 'ok',
/// 'none' (no PIN: vouch instead), 'card' (back to the card), or null on Back.
Future<String?> askHouseCode(BuildContext context, Home home) => _push<String>(context, HouseCodeScreen(home: home));

class HouseCodeScreen extends StatefulWidget {
  const HouseCodeScreen({super.key, required this.home});
  final Home home;
  @override
  State<HouseCodeScreen> createState() => _HouseCodeScreenState();
}

class _HouseCodeScreenState extends State<HouseCodeScreen> {
  String _digits = '';
  bool _error = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    final c = GateScope.read(context);
    final stop = widget.home.houseCodeHash == null || c.houseCodeLockedUntil(widget.home.id) != null;
    speak(stop ? _stopWords : 'Ask for their home PIN.');
  }

  String get _stopWords =>
      widget.home.houseCodeHash == null ? 'This home has no PIN. Tap their card, or vouch for them.' : 'Ask them to call the gate. Or tap their card.';

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_digits.length != 4 || _busy) return;
    setState(() => _busy = true);
    final r = await GateScope.read(context).checkHouseCode(widget.home.id, _digits);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _digits = '';
      _error = r is! HouseCodeOk;
    });
    switch (r) {
      case HouseCodeOk():
        speak('PIN is correct.');
        Navigator.pop(context, 'ok');
      case HouseCodeWrong():
        speak('Wrong PIN, try again.');
      case HouseCodeLocked():
        speak('Wrong PIN. $_stopWords');
      case HouseCodeNone():
        speak(_stopWords);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final locked = c.houseCodeLockedUntil(widget.home.id);
    final noPin = widget.home.houseCodeHash == null;
    // A 320 by 568 phone: the keypad and No PIN must fit with no scrolling.
    final compact = MediaQuery.sizeOf(context).height < 700;
    if (noPin || locked != null) {
      // Three wrong tries (or no PIN set): no more guessing here.
      return KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTopBar(label: 'Home PIN', sayAloud: _stopWords),
            HouseCard(home: widget.home),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ResultMark(
                        icon: noPin ? Icons.pin_outlined : Icons.phone_in_talk_outlined,
                        warn: true,
                        text: noPin ? 'This home has no PIN' : 'Ask them to call the gate',
                      ),
                      if (locked != null) Text('Three wrong tries', style: mutedStyle(context, 17)),
                    ],
                  ),
                ),
              ),
            ),
            BigTile(label: 'Tap their card', icon: Icons.contactless_outlined, primary: true, height: 104, onTap: () => Navigator.pop(context, 'card')),
            const SizedBox(height: 10),
            Pill(label: 'No card', onTap: () => Navigator.pop(context, 'none')),
          ],
        ),
      );
    }
    return KitScaffold(
      child: LayoutBuilder(
        builder: (context, box) {
          // The keys take what is left, so the keypad and No PIN always fit without scrolling.
          final keyHeight = ((box.maxHeight - (compact ? 300 : 340)) / 4 - 10).clamp(44.0, 66.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KitTopBar(label: 'Home PIN', sayAloud: 'Ask for their home PIN. Four numbers.'),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HouseCard(home: widget.home),
                      if (!compact) const Headline('Home PIN', size: 28, center: true) else const SizedBox(height: 14),
                      Dots(filled: _digits.length, length: 4, error: _error),
                      SizedBox(
                        height: 30,
                        child: Center(
                          child: _error
                              ? Text(
                                  'Wrong PIN, try again',
                                  style: TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w700, color: p.noText),
                                )
                              : (_busy ? LinearProgressIndicator(color: p.text, backgroundColor: p.surface) : null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              KitKeypad(
                enabled: !_busy,
                keyHeight: keyHeight,
                onDigit: (d) {
                  if (_digits.length >= 4) return;
                  setState(() {
                    _digits += d;
                    _error = false;
                  });
                  if (_digits.length == 4) _check();
                },
                onClear: () => setState(() => _digits = ''),
                onGo: _check,
              ),
              const SizedBox(height: 10),
              Pill(label: 'No PIN', onTap: () => Navigator.pop(context, 'none')),
            ],
          );
        },
      ),
    );
  }
}

// --- who rode -----------------------------------------------------------------------------------------

/// The home a ride is for, and how the rider knows who it was.
class WhoRode {
  const WhoRode(this.home, this.confirm);
  final Home home;
  final RideConfirm confirm;
}

/// Tap their card; "No card" goes to the home PIN; "No PIN" asks whether the guard sent them
/// (a gate booking) or the rider knows them. [home] null: a flagged-down ride, where the card or
/// the house picked says which home.
class WhoPanel extends StatefulWidget {
  const WhoPanel({super.key, required this.onDone, this.home, this.fromGate = false, this.title = 'Tap their card'});
  final Home? home;
  final bool fromGate;
  final String title;
  final void Function(WhoRode) onDone;
  @override
  State<WhoPanel> createState() => _WhoPanelState();
}

class _WhoPanelState extends State<WhoPanel> {
  int _session = 0;
  bool _away = false; // another screen is on top: stop listening for cards
  String? _note;

  Future<T?> _over<T>(Future<T?> Function() step) async {
    setState(() => _away = true);
    try {
      return await step();
    } finally {
      if (mounted) {
        setState(() {
          _away = false;
          _session++;
        });
      }
    }
  }

  Future<void> _card(String uid) async {
    final c = GateScope.read(context);
    final card = c.cardFor(uid);
    if (card == null) {
      setState(() => _note = 'Card not known. Use the home PIN.');
      speak('Card not known. Use the home PIN.');
      return;
    }
    final home = c.snapshot?.home(card.homeId);
    final r = c.snapshot?.resident(card.residentId);
    if (home == null) return;
    final name = r?.name ?? 'a resident';
    final other = widget.home != null && widget.home!.id != home.id;
    final yes = await _over(
      () => askYesNo(
        context,
        label: 'Estate card',
        question: 'Is this them?',
        about: HouseCard(home: home, name: r?.name),
        say: 'Card is $name, ${home.label.toUpperCase()}.${other ? ' Not the house on this ride.' : ''}',
      ),
    );
    if (yes == true && mounted) widget.onDone(WhoRode(home, RideConfirm.card(cardId: card.id, residentId: card.residentId)));
  }

  Future<void> _noCard() async {
    await _over(() async {
      final home = widget.home ?? await pickHome(context);
      if (home == null || !mounted) return null;
      final code = await askHouseCode(context, home);
      if (code == null || code == 'card' || !mounted) return null;
      if (code == 'ok') {
        final who = await askResident(context, home);
        if (who == null || !mounted) return null;
        widget.onDone(WhoRode(home, RideConfirm.houseCode(residentId: who.value?.id)));
        return null;
      }
      if (widget.fromGate) {
        final sent = await askYesNo(
          context,
          label: 'No PIN',
          question: 'Did the guard send them?',
          about: HouseCard(home: home),
          say: 'Did the guard send them?',
        );
        if (sent == null || !mounted) return null;
        if (sent) {
          widget.onDone(WhoRode(home, const RideConfirm.guard()));
          return null;
        }
      }
      final known = await askYesNo(
        context,
        label: 'No PIN',
        question: 'Do you know them?',
        about: HouseCard(home: home),
        say: 'Do you know them?',
      );
      if (known == true && mounted) widget.onDone(WhoRode(home, const RideConfirm.rider()));
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_away) const SizedBox(height: 160) else CardStep(key: ValueKey(_session), title: widget.title, onUid: _card),
        if (_note != null)
          Text(
            _note!,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w700, color: p.noText),
          ),
        const SizedBox(height: 12),
        Pill(label: 'No card', icon: Icons.dialpad, onTap: _noCard),
      ],
    );
  }
}

/// Who rode (a parcel: who took it), on its own screen. Null on Back.
Future<WhoRode?> askWhoRode(BuildContext context, {Home? home, bool fromGate = false, String title = 'Tap their card', String? label}) =>
    _push<WhoRode>(context, _WhoScreen(home: home, fromGate: fromGate, title: title, label: label));

class _WhoScreen extends StatelessWidget {
  const _WhoScreen({this.home, this.fromGate = false, required this.title, this.label});
  final Home? home;
  final bool fromGate;
  final String title;
  final String? label;

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: label, sayAloud: '$title. Or tap No card.'),
        if (home != null) HouseCard(home: home!),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: WhoPanel(home: home, fromGate: fromGate, title: title, onDone: (w) => Navigator.pop(context, w)),
            ),
          ),
        ),
      ],
    ),
  );
}

// --- booking at the gate ------------------------------------------------------------------------------

/// "Shuttle to the home" (guard menu, and after a guest is let in on No code). No typing: the
/// house from the register, then Parcel or Guest. A guest let in on No code keeps their name.
/// True once booked.
Future<bool> openShuttleToHome(BuildContext context, {Home? home, String? guestName}) async {
  final c = GateScope.read(context);
  final h = home ?? await pickHome(context, title: 'Shuttle to which house?');
  if (h == null || !context.mounted) return false;
  var kind = RideKind.guest;
  if (guestName == null) {
    final k = await _push<String>(context, _ParcelOrGuest(home: h));
    if (k == null || !context.mounted) return false;
    kind = k;
  }
  final what = kind == RideKind.delivery ? 'parcel' : (guestName ?? 'guest');
  final yes = await askYesNo(
    context,
    label: 'Shuttle',
    question: 'Book the shuttle?',
    about: Column(
      children: [
        HouseCard(home: h),
        const SizedBox(height: 10),
        KitCard(
          child: Row(
            children: [
              Icon(rideIcon(kind), size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kind == RideKind.delivery ? 'Parcel' : (guestName ?? 'Guest'),
                  style: const TextStyle(fontFamily: inter, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    say: 'Shuttle to ${h.label.toUpperCase()} for a $what?',
  );
  if (yes != true || !context.mounted) return false;
  await c.bookAtGate(home: h, kind: kind, passenger: guestName);
  speak('Shuttle booked.');
  c.showNotice('Shuttle booked: $what to ${h.displayAddress}');
  return true;
}

class _ParcelOrGuest extends StatefulWidget {
  const _ParcelOrGuest({required this.home});
  final Home home;
  @override
  State<_ParcelOrGuest> createState() => _ParcelOrGuestState();
}

class _ParcelOrGuestState extends State<_ParcelOrGuest> {
  @override
  void initState() {
    super.initState();
    speak('Parcel or guest?');
  }

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitTopBar(label: 'Shuttle', sayAloud: 'Parcel or guest?'),
        HouseCard(home: widget.home),
        const Spacer(),
        const Headline('Parcel or guest?', center: true),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: BigTile(label: 'Parcel', icon: Icons.inventory_2_outlined, height: 150, onTap: () => Navigator.pop(context, RideKind.delivery)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BigTile(label: 'Guest', icon: Icons.person_outline, height: 150, onTap: () => Navigator.pop(context, RideKind.guest)),
            ),
          ],
        ),
      ],
    ),
  );
}

// --- the CSO's Shuttle tab ----------------------------------------------------------------------------

String rideStateLine(Ride r, String wait) => switch (r.state) {
  RideState.accepted => 'Taken by ${r.rider ?? 'a rider'}',
  RideState.pickedUp => 'On the way with ${r.rider ?? 'a rider'}',
  _ => 'No rider yet, $wait',
};

class ShuttleTab extends StatelessWidget {
  const ShuttleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final now = t.now();
    String wait(DateTime? d) => waitLabel(d, now, (x) => hhmm(t.of(x))).toLowerCase();
    final waiting = c.cso?.ridesWaiting ?? const [];
    final open = c.rides.open;
    Widget section(String s, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        s.toUpperCase(),
        style: monoStyle(context, 14, color: color ?? p.muted, weight: FontWeight.w600),
      ),
    );
    return KitSurface(
      child: RefreshIndicator(
        onRefresh: () async {
          await c.syncNow();
          await c.refreshCso();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: BigTile(label: 'Book a ride', icon: Icons.two_wheeler, primary: true, height: 112, onTap: () => openDispatch(context)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BigTile(
                    label: 'Issue a card',
                    icon: Icons.contactless_outlined,
                    height: 112,
                    onTap: () => _push<void>(context, const IssueCardScreen()),
                  ),
                ),
              ],
            ),
            if (waiting.isNotEmpty) ...[
              section('Waiting over 10 min · ${waiting.length}', color: p.warnText),
              for (final w in waiting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KitCard(
                    border: p.warn,
                    child: Row(
                      children: [
                        Icon(rideIcon(w.kind), size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${w.from ?? '?'} to ${w.to ?? '?'}',
                                style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w700),
                              ),
                              Text(wait(w.wantedAt).toUpperCase(), style: monoStyle(context, 14, color: p.warnText)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            section('Open rides · ${open.length}'),
            if (open.isEmpty) Text('No open rides', style: mutedStyle(context, 18)),
            for (final r in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KitCard(
                  child: Row(
                    children: [
                      Icon(rideIcon(r.kind), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${stopShort(c.snapshot, r.pickup)} to ${stopShort(c.snapshot, r.dropoff)}',
                              style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              rideStateLine(r, wait(r.wantedAt)),
                              style: TextStyle(fontFamily: inter, fontSize: 16, color: r.isRequested ? p.warnText : p.text, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- the CSO books a ride for a resident who rang -------------------------------------------------------

Future<void> openDispatch(BuildContext context) async {
  final c = GateScope.read(context);
  final home = await pickHome(context, title: 'Book a ride: which house?');
  if (home == null || !context.mounted) return;
  final who = await askResident(context, home, question: (r) => 'Did ${r.name} ring?', label: 'Book a ride');
  if (who == null || !context.mounted) return;
  final resident = who.value;
  if (resident == null) {
    speak('Book the ride for a resident of this house.');
    return;
  }
  final stops = rideStops(c.snapshot!, home: home);
  final from = await askEach<RideStop>(
    context,
    items: stops,
    label: 'Pick up',
    question: (s) => s.kind == 'home' ? 'Pick up at home?' : 'Pick up at ${s.label}?',
    about: (s) => s.kind == 'home' ? HouseCard(home: home, name: resident.name) : _PlaceCard(s.label),
  );
  if (from?.value == null || !context.mounted) return;
  final to = await askEach<RideStop>(
    context,
    items: [
      for (final s in stops)
        if (!s.sameAs(from!.value!)) s,
    ],
    label: 'Going to',
    question: (s) => s.kind == 'home' ? 'Going home?' : 'Going to ${s.label}?',
    about: (s) => s.kind == 'home' ? HouseCard(home: home, name: resident.name) : _PlaceCard(s.label),
  );
  if (to?.value == null || !context.mounted) return;
  final when = await askEach<int>(
    context,
    items: const [0, 30, 60, 120],
    label: 'When',
    question: (m) => switch (m) {
      0 => 'Now?',
      30 => 'In 30 minutes?',
      60 => 'In 1 hour?',
      _ => 'In 2 hours?',
    },
  );
  if (when?.value == null || !context.mounted) return;
  final at = when!.value == 0 ? null : c.now().add(Duration(minutes: when.value!));
  final ok = await askYesNo(
    context,
    label: 'Book a ride',
    question: 'Book this ride?',
    about: KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resident.name,
            style: const TextStyle(fontFamily: inter, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          StopLine(label: 'FROM', stop: from!.value!),
          StopLine(label: 'TO', stop: to!.value!),
          Text(at == null ? 'NOW' : 'AT ${hhmm(c.time.of(at))}', style: monoStyle(context, 16)),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await c.bookDispatch(home: home, residentId: resident.id, pickup: from.value!, dropoff: to.value!, wantedAt: at);
  speak('Ride booked.');
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => KitCard(
    child: Row(
      children: [
        const Icon(Icons.place_outlined, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontFamily: inter, fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// What a ride end looks like on a Yes or No screen.
Widget stopCard(Home? home, RideStop s) => s.kind == 'home' && home != null ? HouseCard(home: home) : _PlaceCard(s.label);

// --- the CSO issues a card -------------------------------------------------------------------------------

class IssueCardScreen extends StatefulWidget {
  const IssueCardScreen({super.key});
  @override
  State<IssueCardScreen> createState() => _IssueCardScreenState();
}

class _IssueCardScreenState extends State<IssueCardScreen> {
  int _session = 0;
  bool _busy = false;
  EstateCard? _taken;
  (IconData, String, bool)? _result; // icon, words, bad

  @override
  void initState() {
    super.initState();
    speak('Tap the new card.');
  }

  Future<void> _uid(String uid) async {
    final c = GateScope.read(context);
    final known = c.cardFor(uid);
    if (known != null) {
      final owner = c.snapshot?.resident(known.residentId)?.name ?? 'someone else';
      setState(() => _taken = known);
      speak('This card is already $owner\'s.');
      return;
    }
    setState(() => _busy = true);
    try {
      final home = await pickHome(context, title: 'Whose card is it?');
      if (home == null || !mounted) return;
      final r = await askResident(context, home, question: (r) => 'Give the card to ${r.name}?', label: 'Issue a card');
      final resident = r?.value;
      if (resident == null || !mounted) return;
      final id = await c.issueCard(uid: uid, resident: resident);
      await c.syncNow();
      final item = await c.queuedItem(id);
      if (!mounted) return;
      final (IconData, String, bool) result = item != null && item.isRejected
          ? (Icons.close, _sentence(item.reason ?? 'The server refused it'), true)
          : item != null && item.isPending
          ? (Icons.cloud_off, 'Saved. It is sent when there is network.', false)
          : (Icons.check, 'Card issued to ${resident.name}, ${home.label.toUpperCase()}', false);
      setState(() => _result = result);
      speak(result.$2);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _session++;
        });
      }
    }
  }

  static String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final taken = _taken;
    final result = _result;
    final Widget body;
    if (result != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ResultMark(icon: result.$1, text: result.$3 ? 'Card not issued' : (result.$1 == Icons.check ? 'Card issued' : 'Saved')),
          const SizedBox(height: 8),
          Text(
            result.$2,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: inter, fontSize: 19, color: result.$3 ? p.noText : p.text),
          ),
        ],
      );
    } else if (taken != null) {
      final owner = c.snapshot?.resident(taken.residentId)?.name ?? 'someone else';
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ResultMark(icon: Icons.close, bad: true, text: 'Card already issued'),
          const SizedBox(height: 8),
          Text(
            "It is $owner's card. Revoke it in the dashboard first.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: inter, fontSize: 19),
          ),
        ],
      );
    } else if (_busy) {
      body = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else {
      body = CardStep(key: ValueKey(_session), title: 'Tap the new card', onUid: _uid);
    }
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KitTopBar(label: 'Issue a card', sayAloud: 'Tap the new card on the back of the phone.'),
          Expanded(
            child: Center(child: SingleChildScrollView(child: body)),
          ),
          if (result != null || taken != null) ...[
            BigTile(label: 'Done', icon: Icons.check, primary: true, height: 96, onTap: () => Navigator.pop(context)),
            const SizedBox(height: 10),
            Pill(
              label: 'Another card',
              onTap: () => setState(() {
                _taken = null;
                _result = null;
                _session++;
              }),
            ),
          ],
        ],
      ),
    );
  }
}

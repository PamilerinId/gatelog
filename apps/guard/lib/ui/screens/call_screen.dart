/// Phone call (Guard-Call). Someone rang the gate about a visitor, or a visitor with no code is
/// at the gate. Find the home with no typing, call it back on a registered number (the proof),
/// say the visitor's name, "Did they say yes?". Or the caller gave the home PIN. Or the CSO
/// decides. One question per screen, every result read aloud.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/admission.dart';
import '../../app/call_flow.dart';
import '../../app/caller.dart';
import '../../core/estate_time.dart';
import '../../data/models.dart';
import '../../sync/capture.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../widgets.dart' show dial;
import '../words.dart';
import 'admit_screens.dart';
import 'shuttle_screens.dart';

/// The start of a phone call: the caller's home first when their number is registered ("Is it
/// Mrs Adeyemi, 14B?", a hint only), else street then house. Then any guest this home already
/// confirmed ("Is this them?"), then the callback. Pops itself when the guard backs out.
class PhoneCallStart extends StatefulWidget {
  const PhoneCallStart({super.key, this.home});
  final Home? home;
  @override
  State<PhoneCallStart> createState() => _PhoneCallStartState();
}

class _PhoneCallStartState extends State<PhoneCallStart> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final c = GateScope.read(context);
    final caller = await c.recentCaller();
    if (!mounted) return;
    var home = widget.home;
    if (home == null && caller != null) {
      final who = whoCalled(caller.number, c.snapshot?.homes ?? const []);
      if (who != null) {
        final (h, r) = who;
        final q = tr(M.isItResident, {
          'name': r.name,
          'house': h.label.toUpperCase(),
        });
        final yes = await askYesNo(
          context,
          label: tr(M.phoneCall),
          question: q,
          say: q,
          about: HouseCard(home: h, name: r.name),
        );
        if (yes == null || !mounted) return _leave();
        if (yes) home = h;
      }
    }
    if (!mounted) return;
    if ((c.snapshot?.homes ?? const []).isEmpty) {
      say(M.noHomes);
      return _leave();
    }
    home ??= await pickHome(context, title: tr(M.whichHouse));
    if (home == null || !mounted) return _leave();

    // A guest this home announced earlier ("Coming later"): in on that confirmation.
    for (final v in c.view.confirmedFor(home.id)) {
      if (!mounted) return;
      final clip = c.hasClip([v.id]);
      final yes = await askYesNo(
        context,
        label: tr(M.expectedHere, {'house': home.label.toUpperCase()}),
        question: tr(M.isThisThem),
        say:
            '${tr(M.expectedHere, {'house': home.label.toUpperCase()})}. ${tr(M.isThisThem)}',
        about: _ExpectedGuest(home: home, visit: v, clip: clip),
      );
      if (yes == null || !mounted) return _leave();
      if (yes) {
        final photos = await captureAtGate(
          context,
          home: home,
          method: 'callback_confirmed',
        );
        final id = await c.admitExpected(v, photos: photos);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DoneScreen(
              outcome: Outcome.letIn,
              home: home!,
              recordId: id,
              name: v.guestName == voiceClipName ? null : v.guestName,
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(home: home!, caller: caller),
      ),
    );
  }

  void _leave() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: tr(M.phoneCall)),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    ),
  );
}

class _ExpectedGuest extends StatelessWidget {
  const _ExpectedGuest({
    required this.home,
    required this.visit,
    required this.clip,
  });
  final Home home;
  final Visit visit;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final named = visit.guestName != voiceClipName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HouseHero(
          home: home,
          name: named ? visit.guestName : tr(M.voiceClip),
          voiceClip: !named,
          compact: true,
        ),
        if (clip) ...[
          const SizedBox(height: 10),
          Center(child: _PlayRecord(refs: [visit.id])),
        ],
      ],
    );
  }
}

/// Plays a record's clip while it is still on the phone.
class _PlayRecord extends StatelessWidget {
  const _PlayRecord({required this.refs});
  final List<String?> refs;

  @override
  Widget build(BuildContext context) => KitChip(
    label: tr(M.play),
    icon: Icons.play_arrow,
    onTap: () async {
      final clip = await GateScope.read(context).clipOf(refs);
      if (clip != null) await playClip(clip.bytes, clip.contentType);
    },
  );
}

/// The callback and everything after it, driven by [CallFlow].
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.home, this.visit, this.caller});

  /// A coded guest whose home wants a call first.
  const CallScreen.forCode({super.key, required this.home, required this.visit})
    : caller = null;

  final Home home;
  final Visit? visit;
  final IncomingCall? caller;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  late final CallFlow f;
  bool _busy = false;
  String _pin = '';
  bool _pinError = false;
  bool _awayAtDialler = false;

  @override
  void initState() {
    super.initState();
    f = CallFlow(
      GateScope.read(context),
      widget.home,
      visit: widget.visit,
      caller: widget.caller,
    );
    WidgetsBinding.instance.addObserver(this);
    _announce();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the dialler: when the house was called back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && f.step == CallStep.answer) {
      _awayAtDialler = true;
    }
    if (state == AppLifecycleState.resumed && _awayAtDialler) {
      _awayAtDialler = false;
      setState(() => f.calledBackAt = DateTime.now());
      _announce();
    }
  }

  String get _house => widget.home.label.toUpperCase();

  /// The question on screen, read aloud.
  String get _words => switch (f.step) {
    CallStep.callback => f.noAnswers > 0 ? tr(M.callAgain) : tr(M.callBackSay),
    CallStep.answer => tr(M.didTheySayYes),
    CallStep.letIn => '${tr(M.letThemIn)} $_house.',
    CallStep.hereNow => tr(M.areTheyHereNow),
    CallStep.stay => tr(M.howLong),
    CallStep.pin => tr(M.askHomePin),
    CallStep.pinLocked => '${tr(M.threeWrongTries)}. ${tr(M.callOrSupervisor)}',
    CallStep.pickCso => tr(M.whichCso),
    CallStep.csoReason => tr(M.whyLetIn),
    CallStep.csoOther => tr(M.sayTheReason),
    CallStep.csoLetIn =>
      f.decidingAlone
          ? '${tr(M.decidingAlone)} ${tr(M.letThemIn)}'
          : tr(M.letThemIn),
    CallStep.offerNumber => tr(M.addNumber, {
      'name': f.confirmedBy?.name ?? '',
    }),
    CallStep.done => '',
  };

  void _announce() {
    final w = _words;
    if (w.isNotEmpty) speak(w);
  }

  void _go(VoidCallback change) {
    setState(change);
    _announce();
    _finishIfDone();
  }

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _announce();
    _finishIfDone();
  }

  void _finishIfDone() {
    if (f.step != CallStep.done || !mounted) return;
    final outcome = switch (f.result) {
      CallResult.letIn => Outcome.letIn,
      CallResult.expected => Outcome.expected,
      _ => Outcome.turnedAway,
    };
    final name = widget.visit?.guestName;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DoneScreen(
          outcome: outcome,
          home: widget.home,
          recordId: f.recordId,
          name: name == voiceClipName ? null : name,
          homeGetsText:
              f.result == CallResult.letIn && f.proof == CallProof.cso,
        ),
      ),
    );
  }

  /// Opens the dialler. The answer step is ready for when the guard comes back (said aloud then).
  Future<void> _call(Resident r, PhoneNumber n) async {
    f.dialling(r, n);
    setState(() => f.calledBack(DateTime.now()));
    await dial(n.e164);
  }

  Future<void> _letIn() => _do(() async {
    final method = switch (f.proof) {
      CallProof.callback when widget.visit != null => 'code',
      CallProof.callback => 'callback_confirmed',
      CallProof.pin => 'pin_confirmed',
      _ => 'walk_in_admitted',
    };
    final photos = await captureAtGate(
      context,
      home: widget.home,
      method: method,
    );
    await f.letIn(photos);
  });

  Future<void> _turnAwayWithReason() async {
    final why = await askTurnAway(context, widget.home);
    if (why == null || !mounted) return;
    await _do(() => f.turnAway(why: why.api));
  }

  Future<void> _laterDay() async {
    final t = GateScope.read(context).time;
    final now = t.now();
    final days = [
      for (var i = 1; i <= 6; i++) t.at(now.year, now.month, now.day + i),
    ];
    final day = await pushScreen<DateTime>(context, _DayPicker(days: days));
    if (day == null || !mounted) return;
    await _do(() => f.expect(Stay.date, until: day));
  }

  void _back() {
    final prev = switch (f.step) {
      CallStep.stay => CallStep.hereNow,
      CallStep.pin => CallStep.callback,
      CallStep.csoOther => CallStep.csoReason,
      CallStep.csoLetIn => CallStep.csoReason,
      CallStep.csoReason when !f.decidingAlone && f.decider != null =>
        CallStep.pickCso,
      _ => null,
    };
    if (prev == null) {
      Navigator.of(context).pop();
      return;
    }
    _go(() => f.step = prev);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RoundButton(
                  icon: Icons.arrow_back,
                  label: tr(M.back),
                  onTap: _busy ? null : _back,
                ),
                const SizedBox(width: 12),
                Expanded(child: _Steps(step: f.step)),
                RoundButton(
                  icon: Icons.volume_up_outlined,
                  label: tr(M.readAloud),
                  onTap: _announce,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(context, p)),
          ],
        ),
      ),
    );
  }

  Widget _homeCard() {
    final who =
        f.confirmedBy?.name ??
        (widget.home.residents.isEmpty
            ? null
            : widget.home.residents.first.name);
    return HouseCard(home: widget.home, name: who);
  }

  Widget _body(BuildContext context, Palette p) {
    switch (f.step) {
      case CallStep.callback:
        final numbers = f.numbers;
        return _Page(
          top: [
            _homeCard(),
            if (f.noAnswers > 0) ...[
              const SizedBox(height: 10),
              KitChip(label: tr(M.callAgain), dot: p.warn, outline: true),
            ],
          ],
          bottom: [
            if (numbers.isEmpty)
              Text(
                tr(M.noNumbers),
                textAlign: TextAlign.center,
                style: mutedStyle(context, 17),
              ),
            for (final (i, (r, n)) in numbers.indexed) ...[
              BigTile(
                label: tr(M.callBack),
                sub: '${r.name}  ${n.masked}',
                icon: Icons.call_outlined,
                primary: i == 0,
                height: i == 0 ? 120 : 88,
                onTap: _busy ? null : () => _call(r, n),
              ),
              const SizedBox(height: 10),
            ],
            if (f.homeHasPin) ...[
              Pill(
                label: tr(M.theyGaveHomePin),
                icon: Icons.pin_outlined,
                onTap: () => _go(f.wantPin),
              ),
              const SizedBox(height: 10),
            ],
            Pill(
              label: tr(M.callSupervisor),
              icon: Icons.support_agent,
              color: p.warnText,
              onTap: () => _go(f.supervisor),
            ),
          ],
        );
      case CallStep.answer:
        final at = f.calledBackAt;
        return _Page(
          top: [
            _homeCard(),
            const SizedBox(height: 10),
            KitChip(
              label: tr(M.houseCalledBack),
              icon: Icons.check,
              outline: true,
              trailing: at == null
                  ? null
                  : hhmm(GateScope.of(context).time.of(at)),
            ),
            const SizedBox(height: 10),
            NameRecorder(
              clip: f.nameClip,
              onClip: (c) => setState(() => f.nameClip = c),
            ),
          ],
          question: tr(M.didTheySayYes),
          bottom: [
            YesNo(
              onYes: _busy
                  ? null
                  : () => _do(() => f.answer(CallOutcome.confirmed)),
              onNo: _busy
                  ? null
                  : () => _do(() => f.answer(CallOutcome.saidNo)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Pill(
                    label: tr(M.noAnswer),
                    onTap: _busy
                        ? null
                        : () => _do(() => f.answer(CallOutcome.noAnswer)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pill(
                    label: tr(M.callSupervisor),
                    color: p.warnText,
                    onTap: _busy ? null : () => _go(f.supervisor),
                  ),
                ),
              ],
            ),
          ],
        );
      case CallStep.letIn:
        final v = widget.visit!;
        final named = v.guestName != voiceClipName;
        return _Page(
          top: [
            HouseHero(
              home: widget.home,
              name: named ? v.guestName : tr(M.voiceClip),
              voiceClip: !named,
            ),
          ],
          question: tr(M.letThemIn),
          bottom: [
            YesNo(
              onYes: _busy ? null : _letIn,
              onNo: _busy ? null : _turnAwayWithReason,
            ),
          ],
        );
      case CallStep.hereNow:
        return _Page(
          top: [
            _homeCard(),
            if (f.proof == CallProof.pin) ...[
              const SizedBox(height: 10),
              KitChip(
                label: tr(M.pinCorrect),
                icon: Icons.check,
                outline: true,
              ),
            ],
            const SizedBox(height: 10),
            NameRecorder(
              clip: f.nameClip,
              onClip: (c) => setState(() => f.nameClip = c),
            ),
          ],
          question: tr(M.areTheyHereNow),
          bottom: [
            YesNo(onYes: _busy ? null : _letIn, onNo: () => _go(f.notHereNow)),
          ],
        );
      case CallStep.stay:
        BigTile tile(M label, IconData icon, VoidCallback onTap) => BigTile(
          label: tr(label),
          icon: icon,
          height: 112,
          onTap: _busy ? null : onTap,
        );
        return _Page(
          top: [_homeCard()],
          question: tr(M.howLong),
          bottom: [
            TileGrid(
              tiles: [
                tile(
                  M.aboutAnHour,
                  Icons.timelapse,
                  () => _do(() => f.expect(Stay.hour)),
                ),
                tile(
                  M.aFewHours,
                  Icons.schedule,
                  () => _do(() => f.expect(Stay.hours)),
                ),
                tile(
                  M.overnight,
                  Icons.bedtime_outlined,
                  () => _do(() => f.expect(Stay.overnight)),
                ),
                tile(M.aLaterDay, Icons.calendar_today_outlined, _laterDay),
              ],
            ),
          ],
        );
      case CallStep.pin:
        return LayoutBuilder(
          builder: (context, box) {
            final keyHeight = ((box.maxHeight - 330) / 4 - 10).clamp(
              44.0,
              66.0,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HouseCard(home: widget.home),
                        Headline(tr(M.homePin), size: 26, center: true),
                        Dots(filled: _pin.length, length: 4, error: _pinError),
                        SizedBox(
                          height: 30,
                          child: Center(
                            child: _pinError
                                ? Text(
                                    tr(M.wrongPinLeft, {'n': f.pinTriesLeft}),
                                    style: TextStyle(
                                      fontFamily: inter,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: p.noText,
                                    ),
                                  )
                                : (_busy
                                      ? LinearProgressIndicator(
                                          color: p.text,
                                          backgroundColor: p.surface,
                                        )
                                      : null),
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
                    if (_pin.length >= 4) return;
                    setState(() {
                      _pin += d;
                      _pinError = false;
                    });
                    if (_pin.length == 4) _tryPin();
                  },
                  onClear: () => setState(() => _pin = ''),
                  onGo: _tryPin,
                ),
                const SizedBox(height: 10),
                Pill(
                  label: tr(M.callSupervisor),
                  color: p.warnText,
                  onTap: () => _go(f.supervisor),
                ),
              ],
            );
          },
        );
      case CallStep.pinLocked:
        return _Page(
          top: [
            _homeCard(),
            const SizedBox(height: 16),
            ResultMark(
              icon: Icons.lock_outline,
              warn: true,
              text: tr(M.threeWrongTries),
            ),
            const SizedBox(height: 8),
            Text(
              tr(M.callOrSupervisor),
              textAlign: TextAlign.center,
              style: mutedStyle(context, 17),
            ),
          ],
          bottom: [
            BigTile(
              label: tr(M.callBack),
              icon: Icons.call_outlined,
              primary: true,
              height: 104,
              onTap: () => _go(f.backToCallback),
            ),
            const SizedBox(height: 10),
            Pill(
              label: tr(M.callSupervisor),
              color: p.warnText,
              onTap: () => _go(f.supervisor),
            ),
          ],
        );
      case CallStep.pickCso:
        final c = GateScope.of(context);
        final csos = c.csosOnShiftFirst;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Headline(tr(M.whichCso)),
            const SizedBox(height: 8),
            Expanded(
              child: FaceGrid(
                children: [
                  for (final g in csos)
                    FaceTile(
                      name: g.name,
                      tag: c.csoOnShift(g) ? tr(M.onShift) : null,
                      onTap: () => _go(() => f.pickCso(g)),
                    ),
                ],
              ),
            ),
          ],
        );
      case CallStep.csoReason:
        BigTile tile(CsoReason r, M label, IconData icon) => BigTile(
          label: tr(label),
          icon: icon,
          height: 112,
          onTap: () => _go(() => f.pickReason(r)),
        );
        return _Page(
          top: [_DeciderLine(flow: f)],
          question: tr(M.whyLetIn),
          bottom: [
            TileGrid(
              tiles: [
                tile(
                  CsoReason.known,
                  M.reasonKnown,
                  Icons.verified_user_outlined,
                ),
                tile(
                  CsoReason.described,
                  M.reasonDescribed,
                  Icons.home_outlined,
                ),
                tile(
                  CsoReason.delivery,
                  M.reasonDelivery,
                  Icons.local_shipping_outlined,
                ),
                tile(CsoReason.other, M.reasonOther, Icons.mic_none),
              ],
            ),
            Pill(
              label: tr(M.turnedAway),
              icon: Icons.close,
              color: p.noText,
              onTap: _busy ? null : () => _do(() => f.turnAway()),
            ),
          ],
        );
      case CallStep.csoOther:
        return _Page(
          top: [_DeciderLine(flow: f)],
          question: tr(M.sayTheReason),
          bottom: [
            NameRecorder(
              clip: f.reasonClip,
              label: tr(M.sayTheReason),
              onClip: (c) {
                if (c != null) _go(() => f.otherReasonSaid(c));
              },
            ),
          ],
        );
      case CallStep.csoLetIn:
        return _Page(
          top: [
            _homeCard(),
            const SizedBox(height: 10),
            _DeciderLine(flow: f),
            if (f.decidingAlone) ...[
              const SizedBox(height: 10),
              Text(
                tr(M.decidingAlone),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: inter,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.warnText,
                ),
              ),
            ],
            if (f.nameClip == null) ...[
              const SizedBox(height: 10),
              NameRecorder(
                clip: f.nameClip,
                onClip: (c) => setState(() => f.nameClip = c),
              ),
            ],
          ],
          question: tr(M.letThemIn),
          bottom: [
            YesNo(
              onYes: _busy ? null : _letIn,
              onNo: _busy ? null : () => _do(() => f.turnAway()),
            ),
          ],
        );
      case CallStep.offerNumber:
        return _Page(
          top: [
            HouseCard(home: widget.home, name: f.confirmedBy?.name),
            const SizedBox(height: 10),
            Text(
              tr(M.homeAsked),
              textAlign: TextAlign.center,
              style: mutedStyle(context, 17),
            ),
          ],
          question: tr(M.addNumber, {'name': f.confirmedBy?.name ?? ''}),
          bottom: [
            YesNo(
              onYes: _busy ? null : () => _do(() => f.offer(true)),
              onNo: _busy ? null : () => _do(() => f.offer(false)),
            ),
          ],
        );
      case CallStep.done:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Future<void> _tryPin() async {
    if (_pin.length != 4 || _busy) return;
    final pin = _pin;
    setState(() {
      _busy = true;
      _pin = '';
    });
    final ok = await f.tryPin(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pinError = !ok;
    });
    if (ok) {
      say(M.pinCorrect);
      _announce();
    } else if (f.step == CallStep.pinLocked) {
      _announce();
    } else {
      say(M.wrongPinLeft, {'n': f.pinTriesLeft});
    }
  }
}

/// Who decides: the CSO picked, or "you" when the CSO is the one on the gate.
class _DeciderLine extends StatelessWidget {
  const _DeciderLine({required this.flow});
  final CallFlow flow;

  @override
  Widget build(BuildContext context) {
    final d = flow.decider;
    if (d == null) return const SizedBox.shrink();
    return Row(
      children: [
        const Avatar(size: 44, onSurface: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.name,
                style: const TextStyle(
                  fontFamily: inter,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                tr(M.roleCso),
                style: monoStyle(
                  context,
                  12,
                  color: Palette.of(context).muted,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (flow.reason != null)
          Flexible(
            child: Text(
              switch (flow.reason!) {
                CsoReason.known => tr(M.reasonKnown),
                CsoReason.described => tr(M.reasonDescribed),
                CsoReason.delivery => tr(M.reasonDelivery),
                CsoReason.other => tr(M.reasonOther),
              },
              textAlign: TextAlign.end,
              style: mutedStyle(context, 15),
            ),
          ),
      ],
    );
  }
}

/// The step dots of Guard-Call: callback, then the answer.
class _Steps extends StatelessWidget {
  const _Steps({required this.step});
  final CallStep step;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final second = step != CallStep.callback;
    Widget dot(bool on) => Container(
      width: 28,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: on ? p.accent : p.line,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [dot(true), dot(second)],
    );
  }
}

/// A call step: what it is about at the top, the question, the answers at the bottom.
class _Page extends StatelessWidget {
  const _Page({required this.top, this.question, required this.bottom});
  final List<Widget> top;
  final String? question;
  final List<Widget> bottom;

  /// The answers sit at the bottom; on a short phone the whole page scrolls instead.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...top,
              if (question != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.volume_up_outlined, size: 24),
                    const SizedBox(width: 8),
                    Flexible(child: Headline(question!, size: 26, center: true)),
                  ],
                ),
              ],
              const Spacer(),
              const SizedBox(height: 8),
              ...bottom,
            ],
          ),
        ),
      ),
    ),
  );
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.days});
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: tr(M.aLaterDay), sayAloud: tr(M.whichDay)),
        Headline(tr(M.whichDay)),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: TileGrid(
              tiles: [
                for (final (i, d) in days.indexed)
                  BigTile(
                    label: i == 0 ? tr(M.tomorrow) : dayMonth(d),
                    height: 96,
                    onTap: () => Navigator.pop(context, d),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

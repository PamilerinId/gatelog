/// Visitor has code (Guard-Gate): a big keypad, six digits checked on the phone with no
/// network, then one clear result read aloud: the house number huge, the guest's name, and
/// "Let them in?" Yes or No.
library;

import 'package:flutter/material.dart';

import '../../app/admission.dart';
import '../../core/codes.dart';
import '../../core/estate_time.dart';
import '../../core/verify.dart';
import '../../data/models.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../words.dart';
import 'admit_screens.dart';
import 'call_screen.dart';

class CodeScreen extends StatefulWidget {
  /// [leaving]: opened from Visitor leaving ("Has a code"): only an exit makes sense.
  const CodeScreen({super.key, this.leaving = false});
  final bool leaving;
  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  String _digits = '';
  CodeCheck? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    say(M.typeTheCode);
  }

  void _press(String d) {
    if (_digits.length >= codeDigits) return;
    setState(() => _digits += d);
    if (_digits.length == codeDigits) _check();
  }

  void _check() {
    if (_digits.length != codeDigits) return;
    final c = GateScope.read(context);
    final r = c.verifyCode(_digits);
    final home = _homeOf(r);
    if (r is AdmitMatch && !widget.leaving && home != null && home.callbackRequired) {
      // The home wants a call before anyone comes in, code or not: straight to the callback.
      say(M.callFirst);
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => CallScreen.forCode(home: home, visit: r.visit)));
      return;
    }
    setState(() => _result = r);
    speak(_words(r, home));
  }

  Home? _homeOf(CodeCheck r) {
    final c = GateScope.read(context);
    final v = switch (r) {
      AdmitMatch(:final visit) || NotValidNow(:final visit) || ExitMatch(:final visit) || AlreadyLeft(:final visit) => visit,
      NoMatch() => null,
    };
    return v == null ? null : c.snapshot?.home(v.homeId);
  }

  String _words(CodeCheck r, Home? home) {
    final house = home?.label.toUpperCase() ?? '';
    String name(Visit v) => v.guestName == voiceClipName ? '' : v.guestName;
    return switch (r) {
      AdmitMatch(:final visit) when widget.leaving => '${tr(M.notInside)}. $house. ${name(visit)}',
      AdmitMatch(:final visit) => '${tr(M.codeIsCorrect)}. $house. ${name(visit)}. ${tr(M.letThemIn)}',
      NotValidNow(:final visit, :final early) => '${tr(M.notValidNow)}. $house. ${_window(visit, early)}.',
      ExitMatch(:final visit) => '${tr(M.alreadyInside)}. $house. ${name(visit)}. ${tr(M.leavingNow)}',
      AlreadyLeft() => '${tr(M.alreadyLeft)}. $house.',
      NoMatch() => '${tr(M.noMatch)}. ${tr(M.checkCodeWithVisitor)}.',
    };
  }

  String _window(Visit v, bool early) {
    final t = GateScope.read(context).time;
    return early ? tr(M.opensAt, {'when': when(t.ofUnix(v.windowStart), t.now())}) : tr(M.closedAt, {'when': when(t.ofUnix(v.windowEnd), t.now())});
  }

  void _again() => setState(() {
    _digits = '';
    _result = null;
  });

  Future<void> _letIn(Visit v, Home home) async {
    if (_busy) return;
    setState(() => _busy = true);
    final c = GateScope.read(context);
    final photos = await captureAtGate(context, home: home, method: 'code');
    final id = await c.admitWithCode(v, photos: photos);
    if (!mounted) return;
    await _show(Outcome.letIn, home, id, v.guestName);
  }

  Future<void> _turnAway(Visit v, Home home) async {
    final why = await askTurnAway(context, home);
    if (why == null || !mounted) return;
    final id = await GateScope.read(context).turnAway(homeId: home.id, guestName: v.guestName, visitId: v.id, reason: why.api);
    if (!mounted) return;
    await _show(Outcome.turnedAway, home, id, v.guestName);
  }

  Future<void> _leave(Visit v, Home home) async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await GateScope.read(context).exitByCode(v);
    if (!mounted) return;
    await _show(Outcome.left, home, id, v.guestName);
  }

  Future<void> _show(Outcome o, Home home, String id, String name) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => DoneScreen(outcome: o, home: home, recordId: id, name: name == voiceClipName ? null : name),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return KitScaffold(child: r == null ? _keypad(context) : _verdict(context, r));
  }

  Widget _keypad(BuildContext context) {
    final c = GateScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final keyHeight = ((box.maxHeight - 290) / 4 - 10).clamp(48.0, 76.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTopBar(label: widget.leaving ? tr(M.visitorLeaving) : (c.gateName ?? tr(M.visitorHasCode)), sayAloud: tr(M.typeTheCode)),
            Headline(tr(M.typeTheCode), size: 26),
            const SizedBox(height: 8),
            CodeDigits(digits: _digits),
            const Spacer(),
            KitKeypad(
              keyHeight: keyHeight,
              onDigit: _press,
              onClear: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
              onGo: _digits.length == codeDigits ? _check : null,
            ),
          ],
        );
      },
    );
  }

  Widget _verdict(BuildContext context, CodeCheck r) {
    final home = _homeOf(r);
    final Widget mark;
    Widget? question;
    final actions = <Widget>[];
    String? name;
    String? line;
    switch (r) {
      case AdmitMatch(:final visit) when widget.leaving:
        mark = ResultMark(icon: Icons.info_outline, warn: true, text: tr(M.notInside));
        name = visit.guestName;
        actions.add(BigTile(label: tr(M.ok), icon: Icons.check, primary: true, height: 96, onTap: () => Navigator.pop(context)));
      case AdmitMatch(:final visit):
        mark = ResultMark(icon: Icons.check, text: tr(M.codeIsCorrect));
        name = visit.guestName;
        question = Headline(tr(M.letThemIn), center: true);
        actions.add(YesNo(onYes: _busy ? null : () => _letIn(visit, home!), onNo: _busy ? null : () => _turnAway(visit, home!)));
      case NotValidNow(:final visit, :final early):
        mark = ResultMark(icon: Icons.schedule, warn: true, text: tr(M.notValidNow));
        name = visit.guestName;
        line = _window(visit, early);
        actions.addAll([
          BigTile(label: tr(M.tryAgain), icon: Icons.dialpad, primary: true, height: 96, onTap: _again),
          const SizedBox(height: 10),
          Pill(
            label: tr(M.phoneCall),
            icon: Icons.call_outlined,
            onTap: home == null
                ? null
                : () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => PhoneCallStart(home: home))),
          ),
        ]);
      case ExitMatch(:final visit):
        mark = ResultMark(icon: Icons.logout, text: tr(M.alreadyInside));
        name = visit.guestName;
        question = Headline(tr(M.leavingNow), center: true);
        actions.add(YesNo(onYes: _busy ? null : () => _leave(visit, home!), onNo: () => Navigator.pop(context)));
      case AlreadyLeft(:final visit):
        mark = ResultMark(icon: Icons.info_outline, warn: true, text: tr(M.alreadyLeft));
        name = visit.guestName;
        actions.add(BigTile(label: tr(M.ok), icon: Icons.check, primary: true, height: 96, onTap: () => Navigator.pop(context)));
      case NoMatch():
        mark = ResultMark(icon: Icons.close, bad: true, text: tr(M.noMatch));
        line = tr(M.checkCodeWithVisitor);
        actions.addAll([
          BigTile(label: tr(M.tryAgain), icon: Icons.dialpad, primary: true, height: 96, onTap: _again),
          if (!widget.leaving) ...[
            const SizedBox(height: 10),
            Pill(
              label: tr(M.phoneCall),
              icon: Icons.call_outlined,
              onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const PhoneCallStart())),
            ),
          ],
        ]);
    }
    final clip = name == voiceClipName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: GateScope.of(context).gateName, sayAloud: _words(r, home)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mark,
                  const SizedBox(height: 16),
                  if (home != null) HouseHero(home: home, name: clip ? tr(M.voiceClip) : name, voiceClip: clip),
                  if (line != null) ...[
                    const SizedBox(height: 10),
                    Text(line, textAlign: TextAlign.center, style: mutedStyle(context, 18)),
                  ],
                  ?question,
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...actions,
      ],
    );
  }
}

/// Six mono boxes with a gap after the third. Digits are shown (a guest's code is not secret
/// at the gate), never read aloud.
class CodeDigits extends StatelessWidget {
  const CodeDigits({super.key, required this.digits, this.length = 6});
  final String digits;
  final int length;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = ((box.maxWidth - 24) / length - 8).clamp(30.0, 50.0);
        return Semantics(
          label: tr(M.typeTheCode),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < length; i++) ...[
                if (i == 3) const SizedBox(width: 16),
                Container(
                  width: w,
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: i == digits.length ? p.text : Colors.transparent, width: 2),
                  ),
                  child: i < digits.length ? Text(digits[i], style: monoStyle(context, 32)) : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

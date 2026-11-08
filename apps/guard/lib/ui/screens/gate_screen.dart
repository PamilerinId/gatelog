import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/no_code.dart';
import '../../core/codes.dart';
import '../../core/estate_time.dart';
import '../../core/verify.dart';
import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';
import 'leaving_screen.dart';
import 'no_code_screen.dart';

/// The guard's screen: the keypad is the whole screen, with two dock buttons, No code and
/// Leaving. Six digits check at once with no network, and the verdict takes the keypad's place.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  String _digits = '';
  CodeCheck? _result;

  void _press(String d) {
    if (_digits.length >= codeDigits) return;
    GateScope.read(context).clearNotice();
    setState(() => _digits += d);
    if (_digits.length == codeDigits) {
      setState(() => _result = GateScope.read(context).verifyCode(_digits));
    }
  }

  void _back() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _result = null;
    });
  }

  void _reset() => setState(() {
        _digits = '';
        _result = null;
      });

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: CodeBoxes(digits: _digits)),
      if (r == null) ...[
        const _NoticeOrHint(),
        Expanded(child: Keypad(onDigit: _press, onBack: _back, onClear: _reset)),
        const _Dock(),
      ] else
        Expanded(
          child: _VerdictPanel(
            key: ValueKey(_digits),
            code: _digits,
            result: r,
            onDone: (message, undoId) {
              _reset();
              if (message != null) GateScope.read(context).showNotice(message, undoId: undoId);
            },
          ),
        ),
    ]);
  }
}

/// "Type the guest's code", or for a few seconds after a record, what was recorded and Undo.
class _NoticeOrHint extends StatefulWidget {
  const _NoticeOrHint();
  @override
  State<_NoticeOrHint> createState() => _NoticeOrHintState();
}

class _NoticeOrHintState extends State<_NoticeOrHint> {
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
    if (n == null || left <= Duration.zero) {
      return const SizedBox(
        height: 52,
        child: Center(child: Text("Type the guest's code", style: TextStyle(fontSize: 17, color: Colors.black87))),
      );
    }
    _timer?.cancel();
    _timer = Timer(left, () {
      if (mounted) setState(() {});
    });
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: GateColors.navy, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(n.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        if (n.undoId != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              final ok = await c.undo(n.undoId!);
              c.showNotice(ok ? 'Undone' : 'Too late to undo: it was already sent');
            },
            child: const Text('UNDO'),
          ),
      ]),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: GateColors.navy, minimumSize: const Size.fromHeight(72)),
              icon: const Icon(Icons.person_search, size: 28),
              label: const Text('No code'),
              onPressed: () => openNoCode(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(72), textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              icon: const Icon(Icons.logout, size: 28),
              label: const Text('Leaving'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LeavingScreen())),
            ),
          ),
        ]),
      );
}

/// Code OK / call first / already inside / no match. "Let them in" is the main action.
class _VerdictPanel extends StatefulWidget {
  const _VerdictPanel({super.key, required this.code, required this.result, required this.onDone});
  final String code;
  final CodeCheck result;

  /// Back to the keypad, with a message and the record to offer Undo for.
  final void Function(String? message, String? undoId) onDone;

  @override
  State<_VerdictPanel> createState() => _VerdictPanelState();
}

class _VerdictPanelState extends State<_VerdictPanel> {
  final _plate = TextEditingController();
  NoCodeFlow? _callFirst; // homes that want a callback before a coded guest comes in
  bool _busy = false;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _act(Future<String> Function() record, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await record();
    widget.onDone(message, id);
  }

  Future<void> _turnAway(GateController c, Visit v, {String? suggested}) async {
    final reason = await askTurnAwayReason(context, suggested: suggested);
    if (reason == null || !mounted) return;
    await _act(() => c.turnAway(homeId: v.homeId, guestName: v.guestName, visitId: v.id, reason: reason), 'Turned away: ${v.guestName}');
  }

  Future<void> _call(GateController c, NoCodeFlow flow, Visit v, Resident r, PhoneNumber n) async {
    flow.call(r, n);
    await dial(n.e164);
    if (!mounted) return;
    final outcome = await askCallOutcome(context, r, n);
    if (outcome == null || !mounted) {
      flow.calling = null;
      return;
    }
    flow.record(outcome);
    await c.recordCallback(homeId: v.homeId, numberId: n.id, outcome: outcome.api, visitId: v.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final now = t.now();
    String homeOf(Visit v) => c.snapshot?.home(v.homeId)?.displayAddress ?? 'Unknown home';
    Text big(String s) => Text(s, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800));
    Text line(String s) => Text(s, style: const TextStyle(fontSize: 19));
    final again = TextButton(onPressed: () => widget.onDone(null, null), child: const Text('Enter another code'));

    final children = <Widget>[];
    switch (widget.result) {
      case AdmitMatch(:final visit):
        final home = c.snapshot?.home(visit.homeId);
        final flow = home != null && home.callbackRequired ? (_callFirst ??= NoCodeFlow(home)) : null;
        final step = flow?.step;
        final cleared = flow == null || step == NoCodeStep.confirmed;
        if (cleared) {
          children.addAll([
            Verdict(title: 'Code OK', color: GateColors.go, wash: GateColors.goWash, icon: Icons.check_circle, children: [
              big(visit.guestName),
              line(homeOf(visit)),
              line('Valid until ${when(t.ofUnix(visit.windowEnd), now)}'),
              if (flow != null) line('Confirmed on the phone by ${flow.confirmedBy!.$1.name}.'),
            ]),
            const SizedBox(height: 12),
            PlateField(controller: _plate, home: home),
            const SizedBox(height: 8),
            BigButton(
              label: 'Let them in',
              icon: Icons.login,
              color: GateColors.go,
              onPressed: _busy ? null : () => _act(() => c.admitWithCode(visit, plate: _plate.text), 'Let in: ${visit.guestName}'),
            ),
            const SizedBox(height: 10),
            _SecondaryStop(label: 'Turn away', onPressed: _busy ? null : () => _turnAway(c, visit)),
          ]);
        } else if (step == NoCodeStep.stop) {
          children.addAll([
            Verdict(title: 'Do not let them in', color: GateColors.stop, wash: GateColors.stopWash, icon: Icons.block, children: [
              big(visit.guestName),
              line(homeOf(visit)),
              line(flow.stopReason),
            ]),
            const SizedBox(height: 16),
            BigButton(label: 'Turn away', icon: Icons.block, color: GateColors.stop, onPressed: _busy ? null : () => _turnAway(c, visit, suggested: flow.stopReason)),
          ]);
        } else {
          children.addAll([
            Verdict(title: 'Code OK: call first', color: GateColors.warn, wash: GateColors.warnWash, icon: Icons.phone_in_talk, children: [
              big(visit.guestName),
              line(homeOf(visit)),
              line('This home asks the gate to call before anyone comes in.'),
              if (step == NoCodeStep.tryAgain) line('No answer. Call again or try another number.'),
            ]),
            const SizedBox(height: 12),
            for (final r in home!.residents) ResidentCallCard(resident: r, onCall: (n) => _call(c, flow, visit, r, n)),
            const SizedBox(height: 4),
            _SecondaryStop(label: 'Turn away', onPressed: _busy ? null : () => _turnAway(c, visit)),
          ]);
        }
      case NotValidNow(:final visit, :final early):
        children.addAll([
          Verdict(title: 'Code not valid now', color: GateColors.warn, wash: GateColors.warnWash, icon: Icons.schedule, children: [
            big(visit.guestName),
            line(homeOf(visit)),
            line(early ? 'This code opens later.' : 'This code has expired.'),
            line('Valid ${when(t.ofUnix(visit.windowStart), now)} to ${when(t.ofUnix(visit.windowEnd), now)}'),
          ]),
          const SizedBox(height: 16),
          BigButton(
            label: 'Call the home',
            icon: Icons.call,
            color: GateColors.navy,
            onPressed: () {
              final home = c.snapshot?.home(visit.homeId);
              widget.onDone(null, null);
              if (home != null) openHome(context, home);
            },
          ),
          const SizedBox(height: 10),
          _SecondaryStop(label: 'Turn away', onPressed: _busy ? null : () => _turnAway(c, visit, suggested: 'Code outside its window')),
        ]);
      case ExitMatch(:final visit):
        final home = c.snapshot?.home(visit.homeId);
        children.addAll([
          Verdict(title: 'Already inside', color: GateColors.info, wash: GateColors.infoWash, icon: Icons.logout, children: [
            big(visit.guestName),
            line(homeOf(visit)),
            if (visit.enteredAt != null) line('Came in ${when(t.of(visit.enteredAt!), now)}'),
          ]),
          const SizedBox(height: 12),
          PlateField(controller: _plate, home: home),
          const SizedBox(height: 8),
          BigButton(
            label: 'They are leaving',
            icon: Icons.logout,
            color: GateColors.info,
            onPressed: _busy ? null : () => _act(() => c.exitByCode(visit, plate: _plate.text), 'Left: ${visit.guestName}'),
          ),
        ]);
      case AlreadyLeft(:final visit):
        children.addAll([
          Verdict(title: 'Already left', color: GateColors.warn, wash: GateColors.warnWash, icon: Icons.info_outline, children: [
            line('${visit.guestName}, ${homeOf(visit)}, is already marked as gone.'),
          ]),
          const SizedBox(height: 16),
          BigButton(label: 'OK', onPressed: () => widget.onDone(null, null)),
        ]);
      case NoMatch():
        children.addAll([
          Verdict(title: 'No match', color: GateColors.stop, wash: GateColors.stopWash, icon: Icons.cancel, children: [
            line('${displayCode(widget.code)} is not a code for any expected guest.'),
            line('Check the code with the guest.'),
          ]),
          const SizedBox(height: 16),
          BigButton(label: 'Try again', icon: Icons.dialpad, color: GateColors.navy, onPressed: () => widget.onDone(null, null)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_search),
            label: const Text('No code: find the home'),
            onPressed: () {
              widget.onDone(null, null);
              openNoCode(context);
            },
          ),
        ]);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, again]),
    );
  }
}

/// A red-outlined secondary button: Turn away is never the main action.
class _SecondaryStop extends StatelessWidget {
  const _SecondaryStop({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: GateColors.stop, side: const BorderSide(color: GateColors.stop, width: 2)),
        icon: const Icon(Icons.block),
        label: Text(label),
        onPressed: onPressed,
      );
}

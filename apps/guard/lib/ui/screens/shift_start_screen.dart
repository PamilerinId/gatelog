/// Start shift (Guard-ShiftStart), for everyone who opens a shift on this phone: guards, the
/// CSO and shuttle riders. Tap your face, then the PIN keypad (6 digits), then the selfie,
/// taken by itself with no preview. Riders then pick their motorcycle (the photo is taken on
/// that tap). The role decides the view after. A camera that fails never blocks a shift.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/shift.dart';
import '../../core/estate_time.dart';
import '../../core/pin.dart';
import '../../core/selfie_image.dart';
import '../../data/models.dart';
import '../../data/shuttle.dart';
import '../../sync/capture.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../words.dart';

class ShiftStartScreen extends StatefulWidget {
  const ShiftStartScreen({super.key});
  @override
  State<ShiftStartScreen> createState() => _ShiftStartScreenState();
}

enum _Step { face, pin, bike, opening }

class _ShiftStartScreenState extends State<ShiftStartScreen> {
  _Step _step = _Step.face;
  Guard? _who;
  String _digits = '';
  String? _first; // setting a PIN: the first entry
  String? _status;
  bool _error = false;
  bool _busy = false;
  Future<GateCamera?>? _cam;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    say(M.tapYourFace);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _closeCamera();
    super.dispose();
  }

  void _closeCamera() {
    final cam = _cam;
    _cam = null;
    cam?.then((c) => c?.dispose());
  }

  void _face(Guard g) {
    if (!g.consent) {
      setState(() => _status = tr(M.consentFirst));
      say(M.consentFirst);
      return;
    }
    final c = GateScope.read(context);
    final step = c.pinStepFor(g);
    setState(() {
      _who = g;
      _step = _Step.pin;
      _digits = '';
      _first = null;
      _error = false;
      _status = null;
    });
    // The front camera warms up while the PIN is typed; the photo is taken when it is right.
    _closeCamera();
    _cam = openCamera(front: true);
    say(step == PinStep.setPin ? M.choosePinSay : M.yourPin);
  }

  Future<void> _go() async {
    final c = GateScope.read(context);
    final g = _who!;
    if (_digits.length != pinLength || _busy) return;
    final pin = _digits;
    if (c.pinStepFor(g) == PinStep.setPin) {
      if (_first == null) {
        setState(() {
          _first = pin;
          _digits = '';
        });
        say(M.samePinAgain);
        return;
      }
      if (_first != pin) {
        setState(() {
          _first = null;
          _digits = '';
          _error = true;
          _status = tr(M.notSame);
        });
        say(M.notSame);
        return;
      }
      setState(() => _busy = true);
      await c.setGuardPin(g.id, pin);
      await _pinOk(g);
      return;
    }
    setState(() => _busy = true);
    final r = await c.checkGuardPin(g.id, pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _digits = '';
    });
    switch (r) {
      case PinOk():
        await _pinOk(g);
      case PinWrong():
        setState(() {
          _error = true;
          _status = tr(M.wrongPin);
        });
        say(M.wrongPin);
      case PinLocked():
        say(M.lockedSay);
        setState(() {});
    }
  }

  Future<void> _pinOk(Guard g) async {
    if (!mounted) return;
    final c = GateScope.read(context);
    if (g.isRider && c.shuttle != null) {
      setState(() {
        _busy = false;
        _step = _Step.bike;
        _status = null;
      });
      say(M.whichMotorcycle);
      return;
    }
    await _open(null);
  }

  /// The selfie, with no preview, then the shift. No camera, or a failed photo: no selfie.
  Future<void> _open(ShuttleBike? bike) async {
    final c = GateScope.read(context);
    setState(() => _step = _Step.opening);
    List<int>? jpeg;
    final cam = await _cam;
    _cam = null;
    if (cam != null) {
      final shot = await cam.take();
      await cam.dispose();
      if (shot != null) {
        jpeg = await shrinkSelfie(shot.raw);
        await shot.discard();
      }
    }
    await c.openShift(_who!.id, selfieJpeg: jpeg, shuttleId: bike?.id);
    if (bike == null) {
      say(M.shiftStarted);
    } else {
      say(M.shiftStartedOn, {'bike': bike.label});
    }
  }

  void _back() {
    if (_step == _Step.opening || _step == _Step.face) return;
    _closeCamera();
    setState(() {
      _step = _Step.face;
      _who = null;
      _digits = '';
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final label = c.gateName ?? c.estateName ?? 'Gatelog';
    if (c.snapshot == null) return _Loading(label: label);
    final Widget body;
    String aloud;
    switch (_step) {
      case _Step.face:
        aloud = tr(M.tapYourFace);
        body = _faces(context);
      case _Step.pin:
        final g = _who!;
        final step = c.pinStepFor(g);
        final heading = step == PinStep.setPin ? (_first == null ? tr(M.choosePin) : tr(M.samePinAgain)) : tr(M.yourPin);
        aloud = '${g.name}. $heading.';
        body = _pin(context, g, heading);
      case _Step.bike:
        aloud = tr(M.whichMotorcycle);
        body = _bikes(context);
      case _Step.opening:
        aloud = tr(M.startingShift);
        body = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Headline(tr(M.startingShift), center: true),
          ],
        );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_step == _Step.pin || _step == _Step.bike) ...[
                  RoundButton(icon: Icons.arrow_back, label: tr(M.back), onTap: _back),
                  const SizedBox(width: 12),
                ],
                Expanded(child: KitTopBar(label: label, sayAloud: aloud, back: false)),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _faces(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final people = c.snapshot!.guards.where((g) => !g.isRider || c.shuttle != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Headline(tr(M.tapYourFace)),
        if (_status != null)
          Text(
            _status!,
            style: TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w700, color: p.warnText),
          ),
        if (people.isEmpty) Text(tr(M.nobodySetUp), style: mutedStyle(context, 18)),
        const SizedBox(height: 8),
        Expanded(
          child: FaceGrid(
            children: [
              for (final g in people)
                FaceTile(
                  name: g.name,
                  tag: g.isCso ? tr(M.roleCso) : (g.isRider ? tr(M.roleRider) : null),
                  dim: !g.consent,
                  onTap: () => _face(g),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.photo_camera_outlined, color: p.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(M.photoWhenStart), style: mutedStyle(context, 14))),
          ],
        ),
        const SizedBox(height: 4),
        Text(tr(M.notOnList), style: mutedStyle(context, 14)),
      ],
    );
  }

  Widget _pin(BuildContext context, Guard g, String heading) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final locked = c.lockedUntil(g.id);
    final status = locked != null ? tr(M.lockedUntil, {'time': hhmm(c.time.of(locked))}) : _status;
    return LayoutBuilder(
      builder: (context, box) {
        final keyHeight = ((box.maxHeight - 250) / 4 - 10).clamp(48.0, 70.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Avatar(size: 48, onSurface: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(g.name, style: const TextStyle(fontFamily: inter, fontSize: 20, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Headline(heading),
            Dots(filled: _digits.length, length: pinLength, error: _error),
            SizedBox(
              height: 32,
              child: Center(
                child: status == null
                    ? (_busy ? LinearProgressIndicator(color: p.text, backgroundColor: p.surface) : null)
                    : Text(
                        status,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: inter, fontSize: 16, fontWeight: FontWeight.w700, color: locked != null ? p.warnText : p.noText),
                      ),
              ),
            ),
            const Spacer(),
            KitKeypad(
              enabled: !_busy && locked == null,
              keyHeight: keyHeight,
              onDigit: (d) {
                if (_digits.length >= pinLength) return;
                setState(() {
                  _digits += d;
                  _error = false;
                  _status = null;
                });
                if (_digits.length == pinLength) _go();
              },
              onClear: () => setState(() => _digits = ''),
              onGo: _go,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.photo_camera_outlined, color: p.muted, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tr(M.photoWhenStart), style: mutedStyle(context, 13))),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _bikes(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final bikes = c.shuttle?.shuttles ?? const <ShuttleBike>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Headline(tr(M.whichMotorcycle)),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            children: [
              for (final b in bikes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    button: true,
                    label: '${b.label} ${b.plate ?? ''}',
                    excludeSemantics: true,
                    child: Material(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => _open(b),
                        child: SizedBox(
                          height: 120,
                          child: Row(
                            children: [
                              const SizedBox(width: 22),
                              const Icon(Icons.two_wheeler, size: 56),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.label, style: monoStyle(context, 40)),
                                    if (b.plate != null && b.plate!.isNotEmpty)
                                      Text(b.plate!.toUpperCase(), style: monoStyle(context, 15, color: p.muted, weight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (bikes.isEmpty)
                BigTile(label: tr(M.startWithoutBike), sub: tr(M.noBikeSetUp), icon: Icons.login, primary: true, onTap: () => _open(null)),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.location_on_outlined, color: p.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(M.estateSeesShuttle), style: mutedStyle(context, 14))),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.photo_camera_outlined, color: p.muted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(M.photoWhenStart), style: mutedStyle(context, 14))),
          ],
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: label, back: false),
          const Spacer(),
          if (c.syncing) const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Headline(c.syncing ? tr(M.loadingEstate) : tr(M.couldNotLoad), center: true),
          if (c.lastError != null && !c.syncing)
            Text(c.lastError!, textAlign: TextAlign.center, style: TextStyle(fontFamily: inter, fontSize: 17, color: p.noText)),
          const Spacer(),
          if (!c.syncing) BigTile(label: tr(M.tryAgain), icon: Icons.sync, primary: true, height: 96, onTap: c.syncNow),
        ],
      ),
    );
  }
}

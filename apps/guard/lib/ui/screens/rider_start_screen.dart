import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/shift.dart';
import '../../core/estate_time.dart';
import '../../core/pin.dart';
import '../../core/selfie_image.dart';
import '../../data/models.dart';
import '../../data/shuttle.dart';
import '../app.dart';
import '../kit.dart';

/// Opens the front camera for the shift photo, or null. Replaced in tests (no camera there).
Future<CameraController?> Function() openFrontCamera = () async {
  try {
    final cams = await availableCameras().timeout(const Duration(seconds: 6));
    if (cams.isEmpty) return null;
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    final cam = CameraController(front, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await cam.initialize().timeout(const Duration(seconds: 6));
    return cam;
  } catch (e) {
    debugPrint('camera unavailable: ${e.runtimeType}');
    return null;
  }
};

/// Rider shift start, as Guard-ShiftStart: tap your face, the PIN keypad, then the motorcycle
/// as big tiles. The photo is taken when the rider taps the motorcycle; never shown, kept
/// encrypted until it uploads. A camera that fails never blocks the shift.
class RiderStartScreen extends StatefulWidget {
  const RiderStartScreen({super.key, required this.onCancel});

  /// Back from the faces: the guards' start screen again.
  final VoidCallback onCancel;
  @override
  State<RiderStartScreen> createState() => _RiderStartScreenState();
}

enum _Step { face, pin, bike, opening }

class _RiderStartScreenState extends State<RiderStartScreen> {
  _Step _step = _Step.face;
  Guard? _who;
  String _digits = '';
  String? _first; // setting a PIN: the first entry
  String? _status;
  bool _error = false;
  bool _busy = false;
  CameraController? _cam;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    speak('Tap your face.');
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  void _face(Guard g) {
    if (!g.consent) {
      setState(() => _status = 'Ask the estate admin to record your consent form first.');
      speak('Ask the estate admin to record your consent form first.');
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
    speak(step == PinStep.setPin ? 'Choose a PIN. Six numbers.' : 'Your PIN.');
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
        speak('Same PIN again.');
        return;
      }
      if (_first != pin) {
        setState(() {
          _first = null;
          _digits = '';
          _error = true;
          _status = 'Not the same. Start again.';
        });
        speak('Not the same. Start again.');
        return;
      }
      setState(() => _busy = true);
      await c.setGuardPin(g.id, pin);
      _toBike();
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
        _toBike();
      case PinWrong():
        setState(() {
          _error = true;
          _status = 'Wrong PIN, try again';
        });
        speak('Wrong PIN, try again.');
      case PinLocked():
        speak('Too many wrong tries. Wait five minutes.');
        setState(() {});
    }
  }

  void _toBike() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.bike;
      _status = null;
    });
    speak('Which motorcycle?');
    // The camera warms up while the rider picks; the photo is taken on the tap.
    openFrontCamera().then((cam) {
      if (!mounted || _step != _Step.bike) {
        cam?.dispose();
        return;
      }
      _cam = cam;
    });
  }

  Future<void> _start(ShuttleBike? bike) async {
    final c = GateScope.read(context);
    setState(() => _step = _Step.opening);
    List<int>? jpeg;
    final cam = _cam;
    if (cam != null) {
      try {
        final shot = await cam.takePicture().timeout(const Duration(seconds: 5));
        final raw = await shot.readAsBytes();
        try {
          await File(shot.path).delete();
        } catch (_) {}
        jpeg = await shrinkSelfie(raw);
      } catch (e) {
        debugPrint('selfie failed: ${e.runtimeType}');
      }
    }
    await c.openShift(_who!.id, selfieJpeg: jpeg, shuttleId: bike?.id);
    speak('Shift started${bike == null ? '' : ' on ${bike.label}'}.');
  }

  void _back() {
    if (_step == _Step.opening) return;
    if (_step == _Step.face) {
      widget.onCancel();
      return;
    }
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
    final p = Palette.of(context);
    final riders = [
      for (final g in c.snapshot?.guards ?? const <Guard>[])
        if (g.isRider) g,
    ];
    final label = c.gateName ?? 'Shuttle';
    final Widget body;
    String aloud;
    switch (_step) {
      case _Step.face:
        aloud = 'Tap your face.';
        final cols = MediaQuery.sizeOf(context).width < 360 ? 3 : 4;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Headline('Tap your face'),
            if (_status != null)
              Text(
                _status!,
                style: TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w700, color: p.warnText),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 132),
                children: [for (final g in riders) _FaceTile(guard: g, onTap: () => _face(g))],
              ),
            ),
            Row(
              children: [
                Icon(Icons.photo_camera_outlined, color: p.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Photo is taken when you start', style: mutedStyle(context, 14))),
              ],
            ),
          ],
        );
      case _Step.pin:
        final g = _who!;
        final step = c.pinStepFor(g);
        final locked = c.lockedUntil(g.id);
        final heading = step == PinStep.setPin ? (_first == null ? 'Choose a PIN' : 'Same PIN again') : 'Your PIN';
        aloud = '${g.name}. $heading.';
        final status = locked != null ? 'Too many tries. Wait until ${hhmm(c.time.of(locked))}' : _status;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Avatar(size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.name,
                    style: const TextStyle(fontFamily: inter, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Headline(heading),
            const SizedBox(height: 4),
            Dots(filled: _digits.length, length: pinLength, error: _error),
            SizedBox(
              height: 32,
              child: Center(
                child: status == null
                    ? (_busy ? LinearProgressIndicator(color: p.text, backgroundColor: p.surface) : null)
                    : Text(
                        status,
                        style: TextStyle(fontFamily: inter, fontSize: 17, fontWeight: FontWeight.w700, color: locked != null ? p.warnText : p.noText),
                      ),
              ),
            ),
            const Spacer(),
            KitKeypad(
              enabled: !_busy && locked == null,
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
          ],
        );
      case _Step.bike:
        final bikes = c.shuttle?.shuttles ?? const <ShuttleBike>[];
        aloud = 'Which motorcycle?';
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Headline('Which motorcycle?'),
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
                            onTap: () => _start(b),
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
                                          Text(
                                            b.plate!.toUpperCase(),
                                            style: monoStyle(context, 15, color: p.muted, weight: FontWeight.w500),
                                          ),
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
                    BigTile(label: 'Start without one', sub: 'No motorcycle is set up', icon: Icons.login, primary: true, onTap: () => _start(null)),
                ],
              ),
            ),
            Row(
              children: [
                Icon(Icons.location_on_outlined, color: p.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('The estate sees the shuttle until you end your shift', style: mutedStyle(context, 14))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.photo_camera_outlined, color: p.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Photo is taken when you start', style: mutedStyle(context, 14))),
              ],
            ),
          ],
        );
      case _Step.opening:
        aloud = 'Starting your shift.';
        body = const Center(child: CircularProgressIndicator());
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
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  RoundButton(icon: Icons.arrow_back, label: 'Back', onTap: _step == _Step.opening ? null : _back),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KitTopBar(label: label, sayAloud: aloud, back: false),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.size = 56});
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.bg, shape: BoxShape.circle),
      child: Icon(Icons.person_outline, size: size * 0.55, color: p.text),
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({required this.guard, required this.onTap});
  final Guard guard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: guard.name,
      excludeSemantics: true,
      child: Opacity(
        opacity: guard.consent ? 1 : 0.45,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Avatar(),
                  const SizedBox(height: 8),
                  Text(
                    guard.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: inter, fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

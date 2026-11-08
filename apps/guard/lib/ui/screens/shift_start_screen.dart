import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/shift.dart';
import '../../core/estate_time.dart';
import '../../core/pin.dart';
import '../../core/selfie_image.dart';
import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';

/// Start a shift: pick your name, your PIN, a selfie. A shuttle rider then picks the motorcycle.
class ShiftStartScreen extends StatefulWidget {
  const ShiftStartScreen({super.key});
  @override
  State<ShiftStartScreen> createState() => _ShiftStartScreenState();
}

enum _Step { name, pin, selfie, bike, opening }

class _ShiftStartScreenState extends State<ShiftStartScreen> {
  _Step _step = _Step.name;
  Guard? _who;
  List<int>? _jpeg; // a rider's selfie, held while they pick the motorcycle

  void _back() => setState(() {
    _step = _Step.name;
    _who = null;
    _jpeg = null;
  });

  Future<void> _selfieDone(List<int>? jpeg) async {
    if (_who!.isRider) {
      setState(() {
        _jpeg = jpeg;
        _step = _Step.bike;
      });
      return;
    }
    await _open(jpeg);
  }

  Future<void> _open(List<int>? jpeg, {String? shuttleId}) async {
    final c = GateScope.read(context);
    setState(() => _step = _Step.opening);
    await c.openShift(_who!.id, selfieJpeg: jpeg, shuttleId: shuttleId);
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final title = c.gateName ?? c.estateName ?? 'Gatelog Gate';
    if (c.snapshot == null) return _Loading(title: title);
    return PopScope(
      canPop: _step == _Step.name,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.opening) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: _step == _Step.name || _step == _Step.opening ? null : IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: _back),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: switch (_step) {
            _Step.name => _NamePicker(
              onPick: (g) => setState(() {
                _who = g;
                _step = _Step.pin;
              }),
            ),
            _Step.pin => _PinStep(guard: _who!, onDone: () => setState(() => _step = _Step.selfie)),
            _Step.selfie => _SelfieStep(guard: _who!, onDone: _selfieDone),
            _Step.bike => _BikeStep(guard: _who!, onPick: (id) => _open(_jpeg, shuttleId: id)),
            _Step.opening => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              if (c.syncing) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Text(c.syncing ? 'Loading the estate...' : 'Could not load the estate yet.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
              if (c.lastError != null && !c.syncing) ...[
                const SizedBox(height: 8),
                Text(
                  c.lastError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: GateColors.stop),
                ),
              ],
              const SizedBox(height: 24),
              if (!c.syncing) BigButton(label: 'Try again', onPressed: c.syncNow),
            ],
          ),
        ),
      ),
    );
  }
}

class _NamePicker extends StatelessWidget {
  const _NamePicker({required this.onPick});
  final void Function(Guard) onPick;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final people = c.snapshot!.guards;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Start your shift', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Tap your name.', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 16),
        if (people.isEmpty) const Text('Nobody is set up yet. Ask the estate admin to add the guards.', style: TextStyle(fontSize: 18)),
        for (final g in people) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(72), alignment: Alignment.centerLeft),
            onPressed: () {
              if (g.isRider && c.shuttle == null) {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(g.name),
                    content: const Text('The estate shuttle is not running on Gatelog. Ask the estate admin.', style: TextStyle(fontSize: 19)),
                    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
                return;
              }
              if (!g.consent) {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(g.name),
                    content: const Text('Ask the estate admin to record your consent form first.', style: TextStyle(fontSize: 19)),
                    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
                return;
              }
              onPick(g);
            },
            child: Row(
              children: [
                Icon(
                  g.isCso ? Icons.shield_outlined : (g.isRider ? Icons.two_wheeler : Icons.badge_outlined),
                  size: 30,
                  color: g.consent ? GateColors.navy : GateColors.line,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: TextStyle(fontSize: 22, color: g.consent ? GateColors.ink : Colors.black54)),
                      if (g.isCso || g.isRider || !g.consent)
                        Wrap(
                          spacing: 6,
                          children: [
                            if (g.isCso) const _Tag('CSO'),
                            if (g.isRider) const _Tag('Shuttle rider'),
                            if (!g.consent) const _Tag('No consent form', color: GateColors.warn),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        const Text('Not on the list? Ask the CSO.', style: TextStyle(fontSize: 17, color: Colors.black87)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = GateColors.navy});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color, width: 1.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

/// Enter the PIN, or set one (twice) the first time or after an admin reset.
class _PinStep extends StatefulWidget {
  const _PinStep({required this.guard, required this.onDone});
  final Guard guard;
  final VoidCallback onDone;

  @override
  State<_PinStep> createState() => _PinStepState();
}

class _PinStepState extends State<_PinStep> {
  String _digits = '';
  String? _first; // setting a PIN: the first entry, waiting for the second
  String? _message;
  bool _error = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresh the lockout countdown.
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
    if (_busy || _digits.length >= pinLength) return;
    setState(() {
      _digits += d;
      _error = false;
    });
    if (_digits.length == pinLength) await _complete(_digits);
  }

  Future<void> _complete(String pin) async {
    final c = GateScope.read(context);
    final step = c.pinStepFor(widget.guard);
    if (step == PinStep.setPin) {
      if (_first == null) {
        setState(() {
          _first = pin;
          _digits = '';
          _message = null;
        });
        return;
      }
      if (_first != pin) {
        setState(() {
          _first = null;
          _digits = '';
          _error = true;
          _message = 'The two PINs were different. Start again.';
        });
        return;
      }
      setState(() => _busy = true);
      await c.setGuardPin(widget.guard.id, pin);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onDone();
      return;
    }
    setState(() => _busy = true);
    final r = await c.checkGuardPin(widget.guard.id, pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _digits = '';
    });
    switch (r) {
      case PinOk():
        widget.onDone();
      case PinWrong(:final triesLeft):
        setState(() {
          _error = true;
          _message = 'Wrong PIN. $triesLeft ${triesLeft == 1 ? 'try' : 'tries'} left.';
        });
      case PinLocked():
        setState(() {
          _error = true;
          _message = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final step = c.pinStepFor(widget.guard);
    final locked = c.lockedUntil(widget.guard.id);
    final heading = switch (step) {
      PinStep.setPin => _first == null ? 'Choose a 6-digit PIN' : 'Enter the same PIN again',
      PinStep.locked => 'Too many wrong tries',
      _ => 'Enter your PIN',
    };
    final note = switch (step) {
      PinStep.setPin => 'Only you will know it. If you forget it, the estate admin can reset it.',
      PinStep.locked => 'Try again at ${hhmm(c.time.of(locked!))}.',
      _ => null,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.guard.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              Text(heading, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              if (note != null) Text(note, style: const TextStyle(fontSize: 17)),
              if (_message != null && step != PinStep.locked)
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 18, color: GateColors.stop, fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 12),
              CodeBoxes(digits: _digits, obscure: true, error: _error),
              SizedBox(height: 28, child: _busy ? const Center(child: LinearProgressIndicator()) : null),
            ],
          ),
        ),
        Expanded(
          child: Keypad(
            enabled: !_busy && step != PinStep.locked,
            onDigit: _press,
            onBack: () => setState(() => _digits = _digits.isEmpty ? '' : _digits.substring(0, _digits.length - 1)),
            onClear: () => setState(() => _digits = ''),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A rider: which motorcycle today. One tap starts the shift.
class _BikeStep extends StatelessWidget {
  const _BikeStep({required this.guard, required this.onPick});
  final Guard guard;
  final void Function(String? shuttleId) onPick;

  @override
  Widget build(BuildContext context) {
    final bikes = GateScope.of(context).shuttle?.shuttles ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(guard.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const Text('Which motorcycle are you on?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      for (final b in bikes) ...[
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(76), alignment: Alignment.centerLeft),
          onPressed: () => onPick(b.id),
          child: Row(children: [
            const Icon(Icons.two_wheeler, size: 32),
            const SizedBox(width: 14),
            Expanded(child: Text(b.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            if (b.plate != null && b.plate!.isNotEmpty) Text(b.plate!.toUpperCase(), style: const TextStyle(fontSize: 17, letterSpacing: 1)),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (bikes.isEmpty) ...[
        const Text('No motorcycles are set up yet. Ask the estate admin.', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        BigButton(label: 'Start without one', icon: Icons.login, color: GateColors.navy, onPressed: () => onPick(null)),
      ],
      const SizedBox(height: 8),
      LineCard(
        color: GateColors.infoWash,
        border: GateColors.info,
        child: const Text(
          'While your shift is open, this phone tells the estate where the shuttle is, every 15 seconds. It stops when you end your shift.',
          style: TextStyle(fontSize: 17),
        ),
      ),
    ]);
  }
}

/// One front-camera photo for the shift record. Never shown on the phone, kept encrypted,
/// uploaded and deleted. If the camera fails the shift starts anyway, marked "no selfie".
class _SelfieStep extends StatefulWidget {
  const _SelfieStep({required this.guard, required this.onDone});
  final Guard guard;
  final Future<void> Function(List<int>? jpeg) onDone;

  @override
  State<_SelfieStep> createState() => _SelfieStepState();
}

class _SelfieStepState extends State<_SelfieStep> {
  CameraController? _cam;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras().timeout(const Duration(seconds: 8));
      if (cams.isEmpty) throw StateError('no camera');
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final cam = CameraController(front, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await cam.initialize().timeout(const Duration(seconds: 8));
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
    } catch (e) {
      debugPrint('camera unavailable: ${e.runtimeType}');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final cam = _cam;
    if (cam == null || _busy) return;
    setState(() => _busy = true);
    List<int>? jpeg;
    try {
      final shot = await cam.takePicture();
      final raw = await shot.readAsBytes();
      // The camera writes to the app's cache; remove the full-size original at once.
      try {
        await File(shot.path).delete();
      } catch (_) {}
      jpeg = await shrinkSelfie(raw);
    } catch (e) {
      debugPrint('selfie failed: ${e.runtimeType}');
    }
    await widget.onDone(jpeg);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    const heading = [
      Text('Photo for the shift record', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
    ];
    if (_failed) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.guard.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ...heading,
        const SizedBox(height: 12),
        BigButton(label: 'Start shift', icon: Icons.login, color: GateColors.navy, onPressed: () => widget.onDone(null)),
        const SizedBox(height: 12),
        Verdict(
          title: 'The camera is not working',
          color: GateColors.warn,
          wash: GateColors.warnWash,
          icon: Icons.no_photography_outlined,
          children: const [Text('The shift starts without a photo and is marked "no selfie".', style: TextStyle(fontSize: 18))],
        ),
      ]);
    }
    // Scrolls on short screens; the preview gets what is left, never less than 180.
    return LayoutBuilder(
      builder: (context, box) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.guard.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ...heading,
        const Text('Look at the screen. The estate keeps this photo for 30 days to show who was on duty. It is never shown on this phone.',
            style: TextStyle(fontSize: 17)),
        const SizedBox(height: 12),
        SizedBox(
          height: (box.maxHeight - 360).clamp(180.0, 520.0),
          child: cam == null
              ? const Center(child: CircularProgressIndicator())
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Center(child: AspectRatio(aspectRatio: 1 / cam.value.aspectRatio, child: CameraPreview(cam))),
                ),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: _busy ? 'Saving...' : 'Take photo and start',
          icon: Icons.photo_camera,
          color: GateColors.navy,
          onPressed: cam == null || _busy ? null : _take,
        ),
        TextButton(onPressed: _busy ? null : () => widget.onDone(null), child: const Text('Camera not working? Start without a photo')),
      ]),
    );
  }
}

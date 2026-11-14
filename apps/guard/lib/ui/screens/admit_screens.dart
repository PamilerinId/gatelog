/// After "Let them in": the visitor's photo (when the estate wants one), "Car?", the plate by
/// camera. Then the result, read aloud. And the fixed reasons for turning someone away.
///
/// No retakes and no typing; Skip is always there. A photo is never shown once taken.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/admission.dart';
import '../../core/plate_text.dart';
import '../../core/selfie_image.dart';
import '../../data/models.dart';
import '../../sync/capture.dart';
import '../app.dart';
import '../kit.dart';
import '../parts.dart';
import '../words.dart';
import 'shuttle_screens.dart';

/// The visitor's photo per the estate's rule for [method], then the car and its plate.
/// Always returns: Back on any of these screens is a skip, and the entry is still recorded.
Future<GatePhotos> captureAtGate(BuildContext context, {required Home home, required String method}) async {
  final c = GateScope.read(context);
  var photos = GatePhotos.none;
  if (c.snapshot?.estate.photoFor(method) ?? false) {
    photos = await pushScreen<GatePhotos>(context, const VisitorPhotoScreen()) ?? const GatePhotos(skipped: PhotoSkipped.refused);
  }
  if (!context.mounted) return photos;
  final car = await askYesNo(context, label: home.label.toUpperCase(), question: tr(M.car), say: tr(M.car), about: HouseHero(home: home, compact: true));
  if (car != true || !context.mounted) return photos;
  final plate = await pushScreen<GatePhotos>(context, PlatePhotoScreen(home: home));
  if (plate == null) return photos;
  return photos.copyWith(plate: plate.plate, plateText: plate.plateText);
}

/// "Photo of the visitor": the back camera, one tap. Skip asks why (no camera, they refused).
/// A phone with no working camera goes on at once with `no_camera`.
class VisitorPhotoScreen extends StatefulWidget {
  const VisitorPhotoScreen({super.key});
  @override
  State<VisitorPhotoScreen> createState() => _VisitorPhotoScreenState();
}

class _VisitorPhotoScreenState extends State<VisitorPhotoScreen> {
  GateCamera? _cam;
  bool _opening = true;
  bool _why = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    say(M.photoOfVisitor);
    openCamera(front: false).then((cam) {
      if (!mounted) {
        cam?.dispose();
        return;
      }
      if (cam == null) {
        say(M.noCamera);
        Navigator.pop(context, const GatePhotos(skipped: PhotoSkipped.noCamera));
        return;
      }
      setState(() {
        _cam = cam;
        _opening = false;
      });
    });
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
    final shot = await cam.take();
    final jpeg = shot == null ? null : await shrinkGatePhoto(shot.raw);
    await shot?.discard();
    if (!mounted) return;
    Navigator.pop(context, jpeg == null ? const GatePhotos(skipped: PhotoSkipped.noCamera) : GatePhotos(visitor: jpeg));
  }

  void _skip() {
    setState(() => _why = true);
    say(M.whyNoPhoto);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_why) _skip();
      },
      child: KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTopBar(label: tr(M.photoOfVisitor), sayAloud: tr(_why ? M.whyNoPhoto : M.photoOfVisitor), back: false),
            if (_why) ...[
              Headline(tr(M.whyNoPhoto)),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: BigTile(
                      label: tr(M.noCamera),
                      icon: Icons.no_photography_outlined,
                      height: 150,
                      onTap: () => Navigator.pop(context, const GatePhotos(skipped: PhotoSkipped.noCamera)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BigTile(
                      label: tr(M.theyRefused),
                      icon: Icons.do_not_touch_outlined,
                      height: 150,
                      onTap: () => Navigator.pop(context, const GatePhotos(skipped: PhotoSkipped.refused)),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Headline(tr(M.photoOfVisitor)),
              const SizedBox(height: 8),
              Expanded(
                child: cam == null || _opening
                    ? const Center(child: CircularProgressIndicator())
                    : cam.preview(),
              ),
              const SizedBox(height: 12),
              BigTile(label: tr(M.takePhoto), icon: Icons.photo_camera_outlined, primary: true, height: 96, onTap: _busy || cam == null ? null : _take),
              const SizedBox(height: 10),
              Pill(label: tr(M.skip), onTap: _busy ? null : _skip),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Photo of the plate": the back camera, one tap; the text is read on the phone (ML Kit, no
/// network) and the guard confirms it: "Is this the plate?". The photo is kept either way
/// (`plate_photo_id`). Returns null on Skip.
class PlatePhotoScreen extends StatefulWidget {
  const PlatePhotoScreen({super.key, required this.home});
  final Home home;
  @override
  State<PlatePhotoScreen> createState() => _PlatePhotoScreenState();
}

class _PlatePhotoScreenState extends State<PlatePhotoScreen> {
  GateCamera? _cam;
  bool _opening = true;
  bool _reading = false;
  List<int>? _photo;
  String? _plate;
  bool _unread = false;

  @override
  void initState() {
    super.initState();
    say(M.photoOfPlate);
    openCamera(front: false).then((cam) {
      if (!mounted) {
        cam?.dispose();
        return;
      }
      if (cam == null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _cam = cam;
        _opening = false;
      });
    });
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final cam = _cam;
    if (cam == null || _reading) return;
    setState(() => _reading = true);
    say(M.readingPlate);
    final shot = await cam.take();
    if (shot == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final read = await readPlate(shot, widget.home);
    if (!mounted) return;
    setState(() {
      _reading = false;
      _photo = read.plate;
      _plate = read.plateText;
      _unread = read.plateText == null;
    });
    if (_plate != null) {
      speak('${tr(M.isThisThePlate)} ${spacePlate(_plate!)}');
    } else {
      say(M.couldNotReadPlate);
    }
  }

  void _confirm(bool yes) {
    final plate = _plate;
    if (yes && plate != null) {
      final v = widget.home.vehicleFor(plate);
      if (v != null) say(M.registeredCarSay, {'house': widget.home.label.toUpperCase()});
    }
    Navigator.pop(context, GatePhotos(plate: _photo, plateText: yes ? plate : null));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cam = _cam;
    final plate = _plate;
    final Widget body;
    if (plate != null) {
      final v = widget.home.vehicleFor(plate);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          KitCard(
            child: Column(
              children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(spacePlate(plate), style: monoStyle(context, 44))),
                if (v != null) ...[
                  const SizedBox(height: 8),
                  KitChip(
                    label: [tr(M.registeredCar, {'house': widget.home.label.toUpperCase()}), ?v.description].join(' · '),
                    icon: Icons.verified_outlined,
                    outline: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Headline(tr(M.isThisThePlate), center: true),
          const Spacer(),
          YesNo(onYes: () => _confirm(true), onNo: () => _confirm(false)),
        ],
      );
    } else if (_unread) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          ResultMark(icon: Icons.help_outline, warn: true, text: tr(M.couldNotReadPlate)),
          const Spacer(),
          BigTile(label: tr(M.ok), icon: Icons.check, primary: true, height: 96, onTap: () => _confirm(false)),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Headline(tr(_reading ? M.readingPlate : M.photoOfPlate)),
          const SizedBox(height: 8),
          Expanded(
            child: cam == null || _opening || _reading
                ? Center(child: CircularProgressIndicator(color: p.text))
                : cam.preview(),
          ),
          const SizedBox(height: 12),
          BigTile(label: tr(M.takePhoto), icon: Icons.photo_camera_outlined, primary: true, height: 96, onTap: _reading || cam == null ? null : _take),
          const SizedBox(height: 10),
          Pill(label: tr(M.skip), onTap: _reading ? null : () => Navigator.pop(context)),
        ],
      );
    }
    return PopScope(
      canPop: !_reading,
      child: KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTopBar(label: tr(M.photoOfPlate), sayAloud: tr(plate != null ? M.isThisThePlate : M.photoOfPlate)),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Reads the plate in [shot] and makes the photo to keep: the text (or null) and a JPEG under
/// 400 KB. The camera's file is deleted.
Future<GatePhotos> readPlate(Shot shot, Home home) async {
  try {
    final lines = await readText(shot);
    final text = plateFromText(lines, known: home.vehicles);
    final jpeg = await shrinkGatePhoto(shot.raw);
    return GatePhotos(plate: jpeg, plateText: text);
  } finally {
    await shot.discard();
  }
}

// --- turning away -----------------------------------------------------------------------------------

/// "Why not?" as fixed tiles. Null on Back.
Future<TurnAwayReason?> askTurnAway(BuildContext context, Home home) => pushScreen<TurnAwayReason>(context, TurnAwayScreen(home: home));

class TurnAwayScreen extends StatefulWidget {
  const TurnAwayScreen({super.key, required this.home});
  final Home home;
  @override
  State<TurnAwayScreen> createState() => _TurnAwayScreenState();
}

class _TurnAwayScreenState extends State<TurnAwayScreen> {
  @override
  void initState() {
    super.initState();
    say(M.whyNot);
  }

  @override
  Widget build(BuildContext context) {
    BigTile tile(TurnAwayReason r, M label, IconData icon) => BigTile(label: tr(label), icon: icon, height: 112, onTap: () => Navigator.pop(context, r));
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: widget.home.label.toUpperCase(), sayAloud: tr(M.whyNot)),
          Headline(tr(M.whyNot)),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: TileGrid(
                tiles: [
                  tile(TurnAwayReason.wrongPerson, M.reasonWrongPerson, Icons.person_off_outlined),
                  tile(TurnAwayReason.homeSaidNo, M.reasonHomeSaidNo, Icons.home_outlined),
                  tile(TurnAwayReason.behaviour, M.reasonBehaviour, Icons.report_outlined),
                  tile(TurnAwayReason.wouldNotWait, M.reasonWouldNotWait, Icons.timer_off_outlined),
                  tile(TurnAwayReason.other, M.reasonOther, Icons.more_horiz),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- the result ---------------------------------------------------------------------------------

enum Outcome { letIn, turnedAway, expected, left }

/// The result of a gate action, read aloud: the mark, the house, and Done (back home). Undo
/// while the record has not left the phone. After a let-in where the estate runs a shuttle,
/// "Shuttle to the home".
class DoneScreen extends StatefulWidget {
  const DoneScreen({super.key, required this.outcome, required this.home, this.recordId, this.name, this.homeGetsText = false, this.extra});
  final Outcome outcome;
  final Home home;
  final String? recordId;
  final String? name;

  /// A walk-in on the CSO's word: the server texts the home "Not you? Reply NO".
  final bool homeGetsText;

  /// One more short line (the registered car).
  final String? extra;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  bool _undone = false;

  String get _words {
    final house = widget.home.label.toUpperCase();
    final head = switch (widget.outcome) {
      Outcome.letIn => tr(M.letInSay, {'house': house}),
      Outcome.turnedAway => tr(M.turnedAwaySay),
      Outcome.expected => tr(M.expectedSay, {'house': house}),
      Outcome.left => tr(M.leftSay, {'house': house}),
    };
    return [head, if (widget.homeGetsText) '${tr(M.homeWillGetText)}.'].join(' ');
  }

  @override
  void initState() {
    super.initState();
    speak(_words);
    // The guard goes back home by themselves after a while: the next visitor is waiting.
    _home = Timer(const Duration(seconds: 20), _done);
  }

  Timer? _home;

  @override
  void dispose() {
    _home?.cancel();
    super.dispose();
  }

  void _done() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _undo() async {
    final id = widget.recordId;
    if (id == null) return;
    final ok = await GateScope.read(context).undo(id);
    if (!mounted) return;
    say(ok ? M.undone : M.tooLateToUndo);
    if (ok) {
      setState(() => _undone = true);
      _done();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final (icon, text, bad) = switch (widget.outcome) {
      Outcome.letIn => (Icons.check, tr(M.letIn), false),
      Outcome.turnedAway => (Icons.close, tr(M.turnedAway), true),
      Outcome.expected => (Icons.schedule, tr(M.expectedLater), false),
      Outcome.left => (Icons.logout, tr(M.left), false),
    };
    final pending = widget.recordId != null && !_undone && c.view.queued > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: KitScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitTopBar(label: c.gateName, sayAloud: _words, back: false),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ResultMark(icon: icon, text: text, bad: bad),
                      const SizedBox(height: 16),
                      HouseHero(home: widget.home, name: widget.name, compact: true),
                      if (widget.homeGetsText) ...[
                        const SizedBox(height: 12),
                        Center(child: KitChip(label: tr(M.homeWillGetText), icon: Icons.sms_outlined, outline: true)),
                      ],
                      if (widget.extra != null) ...[
                        const SizedBox(height: 8),
                        Text(widget.extra!, textAlign: TextAlign.center, style: mutedStyle(context, 16)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (widget.outcome == Outcome.letIn && c.shuttle != null) ...[
              Pill(
                label: tr(M.shuttleToHome),
                icon: Icons.two_wheeler,
                onTap: () => openShuttleToHome(context, home: widget.home, guestName: widget.name),
              ),
              const SizedBox(height: 10),
            ],
            if (pending) ...[
              Pill(label: tr(M.undo), icon: Icons.undo, onTap: _undo),
              const SizedBox(height: 10),
            ],
            BigTile(label: tr(M.done), icon: Icons.check, primary: true, height: 96, onTap: _done),
          ],
        ),
      ),
    );
  }
}

/// Shows the result in place of the current screen.
Future<void> showDone(
  BuildContext context, {
  required Outcome outcome,
  required Home home,
  String? recordId,
  String? name,
  bool homeGetsText = false,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DoneScreen(outcome: outcome, home: home, recordId: recordId, name: name, homeGetsText: homeGetsText),
    ),
  );
}

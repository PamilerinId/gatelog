/// Pieces of the handoff design used across the guard and CSO screens: faces, the network chip,
/// the home's big buttons, the house number hero, the name recorder. Built on `kit.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/estate_time.dart';
import '../data/models.dart';
import '../sync/capture.dart';
import 'app.dart';
import 'kit.dart';
import 'screens/sync_screen.dart';
import 'words.dart';

Future<T?> pushScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => screen));

/// A round face placeholder (no photo is ever shown on the phone).
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 56, this.onSurface = true});
  final double size;

  /// On a surface tile the circle takes the background colour; on the background, the surface's.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onSurface ? p.bg : p.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person_outline, size: size * 0.55, color: p.text),
    );
  }
}

/// Guard-ShiftStart's name tile: the face and the name, with a small mono tag (CSO, RIDER,
/// ON SHIFT). Dimmed when the person cannot start (no consent).
class FaceTile extends StatelessWidget {
  const FaceTile({
    super.key,
    required this.name,
    required this.onTap,
    this.tag,
    this.dim = false,
    this.selected = false,
  });
  final String name;
  final String? tag;
  final VoidCallback onTap;
  final bool dim;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: [name, ?tag].join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: dim ? 0.45 : 1,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected ? p.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Avatar(),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: inter,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  if (tag != null)
                    Text(
                      tag!,
                      maxLines: 1,
                      style: monoStyle(
                        context,
                        11,
                        color: p.muted,
                        weight: FontWeight.w500,
                      ),
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

/// A grid of face tiles, four across (three under 360dp).
class FaceGrid extends StatelessWidget {
  const FaceGrid({super.key, required this.children, this.scroll = true});
  final List<Widget> children;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width < 360 ? 3 : 4;
    return GridView(
      shrinkWrap: !scroll,
      physics: scroll ? null : const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 140,
      ),
      children: children,
    );
  }
}

/// A small pill: a dot or an icon, and a few words.
class KitChip extends StatelessWidget {
  const KitChip({
    super.key,
    required this.label,
    this.dot,
    this.icon,
    this.trailing,
    this.onTap,
    this.outline = false,
  });
  final String label;
  final Color? dot;
  final IconData? icon;
  final String? trailing;
  final VoidCallback? onTap;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: outline ? Colors.transparent : p.surface,
      shape: StadiumBorder(
        side: outline ? BorderSide(color: p.line, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (icon != null) ...[
                  Icon(icon, size: 20, color: p.text),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: inter,
                      fontSize: 14,
                      color: p.text,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    trailing!,
                    style: monoStyle(
                      context,
                      13,
                      color: p.muted,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Guard-Home's chip: "No network · still works" in amber when offline, "Check sync" in red
/// when the server refused something, otherwise when it last synced. Opens Sync.
class NetworkChip extends StatelessWidget {
  const NetworkChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final attention = c.view.needsAttention.isNotEmpty;
    final offline = !c.online || (c.lastError != null && !c.syncing);
    final last = c.lastSyncAt;
    final (label, dot) = attention
        ? (tr(M.checkSync), p.no)
        : offline
        ? (tr(M.noNetwork), p.warn)
        : (
            c.syncing
                ? tr(M.syncing)
                : (last == null
                      ? tr(M.notSynced)
                      : tr(M.synced, {'time': hhmm(c.time.of(last))})),
            p.muted,
          );
    return KitChip(
      label: label,
      dot: dot,
      onTap: () => pushScreen<void>(context, const SyncScreen()),
    );
  }
}

/// One of the home's three jobs: a 56 px icon and the job in 26 px bold, filling its share of
/// the screen. [primary] is Visitor has code (inverted colours).
class HomeJob extends StatelessWidget {
  const HomeJob({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.sub,
    this.primary = false,
  });
  final String label;
  final String? sub;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = primary ? p.onAccent : p.text;
    return Semantics(
      button: true,
      label: [label, ?sub].join(', '),
      excludeSemantics: true,
      child: Material(
        color: primary ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 96),
            child: LayoutBuilder(
              builder: (context, box) {
                // A 320dp phone: a little smaller, so the job always fits on one or two lines.
                final narrow = box.maxWidth < 320;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 22),
                  child: Row(
                    children: [
                      Icon(icon, size: narrow ? 44 : 52, color: fg),
                      SizedBox(width: narrow ? 14 : 18),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: box.maxWidth - (narrow ? 90 : 110),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: inter,
                                    fontSize: narrow ? 24 : 26,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                    color: fg,
                                  ),
                                ),
                                if (sub != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    sub!,
                                    style: monoStyle(
                                      context,
                                      14,
                                      color: primary ? fg : p.muted,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A red count on a button (things that need the CSO).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final p = Palette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -4,
          child: Container(
            constraints: const BoxConstraints(minWidth: 24),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: p.no,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: mono,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Guard-Gate's card: the house number huge in mono, the street, then the guest's name.
class HouseHero extends StatelessWidget {
  const HouseHero({
    super.key,
    required this.home,
    this.name,
    this.voiceClip = false,
    this.compact = false,
  });
  final Home home;
  final String? name;

  /// The name is a voice clip on the phone: show "Voice clip" with nothing to read.
  final bool voiceClip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return KitCard(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 14 : 20,
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              home.label.toUpperCase(),
              style: monoStyle(context, compact ? 48 : 64),
            ),
          ),
          Text(
            home.street,
            textAlign: TextAlign.center,
            style: mutedStyle(context, 16),
          ),
          if (name != null && name!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              name!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: inter,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: voiceClip ? p.muted : p.text,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiles in two columns (fixed reasons, stays, days): no lists to read, no typing.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.tiles, this.height = 104});
  final List<BigTile> tiles;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          // Both tiles of a row as tall as the taller one.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ),
    ],
  );
}

/// "Say the visitor's name": tap to record (30 seconds at most), tap again to stop. Then the
/// clip can be played back or said again. Never typed.
class NameRecorder extends StatefulWidget {
  const NameRecorder({
    super.key,
    required this.clip,
    required this.onClip,
    this.label,
  });
  final VoiceClip? clip;
  final ValueChanged<VoiceClip?> onClip;

  /// Instead of "Say the visitor's name" (the CSO's reason).
  final String? label;

  @override
  State<NameRecorder> createState() => _NameRecorderState();
}

class _NameRecorderState extends State<NameRecorder> {
  ClipRecorder? _rec;
  DateTime? _started;
  Timer? _tick;
  bool _refused = false;

  @override
  void dispose() {
    _tick?.cancel();
    final r = _rec;
    if (r != null) unawaited(r.stop().then((_) => r.dispose()));
    super.dispose();
  }

  Future<void> _start() async {
    final r = newRecorder();
    if (!await r.start()) {
      await r.dispose();
      if (!mounted) return;
      setState(() => _refused = true);
      say(M.micRefused);
      return;
    }
    if (!mounted) {
      await r.stop();
      await r.dispose();
      return;
    }
    setState(() {
      _rec = r;
      _refused = false;
      _started = DateTime.now();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (DateTime.now().difference(_started!) >= clipMaxLength) {
        _stop();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _stop() async {
    final r = _rec;
    if (r == null) return;
    _tick?.cancel();
    setState(() => _rec = null);
    final clip = await r.stop();
    await r.dispose();
    if (!mounted) return;
    widget.onClip(clip);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final clip = widget.clip;
    if (_rec != null) {
      final secs = DateTime.now().difference(_started!).inSeconds;
      return Semantics(
        button: true,
        label: tr(M.recordingTapToStop),
        excludeSemantics: true,
        child: Material(
          color: p.no,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _stop,
            child: SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.stop_circle_outlined,
                    size: 32,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      tr(M.recordingTapToStop),
                      style: const TextStyle(
                        fontFamily: inter,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '0:${two(secs)}',
                    style: const TextStyle(
                      fontFamily: mono,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (clip != null) {
      return Row(
        children: [
          Expanded(
            child: KitChip(
              label: tr(M.nameRecorded),
              icon: Icons.check,
              outline: true,
            ),
          ),
          const SizedBox(width: 10),
          RoundButton(
            icon: Icons.play_arrow,
            label: tr(M.play),
            onTap: () => playClip(clip.bytes, clip.contentType),
          ),
          const SizedBox(width: 10),
          RoundButton(
            icon: Icons.mic_none,
            label: tr(M.sayAgain),
            onTap: _start,
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      label: widget.label ?? tr(M.sayVisitorName),
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _start,
          child: SizedBox(
            height: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_none, size: 30, color: p.text),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _refused
                        ? tr(M.micRefused)
                        : (widget.label ?? tr(M.sayVisitorName)),
                    style: TextStyle(
                      fontFamily: inter,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _refused ? p.warnText : p.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

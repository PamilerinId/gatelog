import 'package:flutter/material.dart';

import '../../core/estate_time.dart';
import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';
import 'directory_screen.dart';
import 'gate_screen.dart';
import 'shuttle_screens.dart';
import 'sync_screen.dart';

/// The guard view. Nothing else: no counts, no rota, no night list.
class GuardHome extends StatelessWidget {
  const GuardHome({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    appBar: GateAppBar(),
    body: SafeArea(child: GateScreen()),
  );
}

/// Gate name, who is on duty, the sync chip and the shift menu.
class GateAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GateAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final bike = c.bike;
    final title = c.isRider ? (bike == null ? 'Shuttle' : 'Shuttle ${bike.label}') : (c.gateName ?? c.snapshot?.estate.name ?? 'Gate');
    final role = c.isCso ? 'CSO' : (c.isRider ? 'Rider' : 'On duty');
    return AppBar(
      titleSpacing: 16,
      toolbarHeight: kToolbarHeight + 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Text(
            '$role: ${c.guard?.name ?? '-'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
      actions: const [SyncChip(), ShiftMenu()],
    );
  }
}

class ShiftMenu extends StatelessWidget {
  const ShiftMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    // The gate books the shuttle; a rider does not book from the menu (New ride is on screen).
    final shuttle = c.shuttle != null && !c.isRider;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 30),
      tooltip: 'Menu',
      onSelected: (v) {
        final nav = Navigator.of(context);
        switch (v) {
          case 'shuttle':
            openShuttleToHome(context);
          case 'numbers':
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Emergency numbers')),
                  body: const SafeArea(child: DirectoryScreen()),
                ),
              ),
            );
          case 'sync':
            nav.push(MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
          case 'end':
            endShiftFlow(context);
        }
      },
      itemBuilder: (_) => [
        if (shuttle)
          const PopupMenuItem(
            value: 'shuttle',
            height: 60,
            child: ListTile(leading: Icon(Icons.two_wheeler), title: Text('Shuttle to the home')),
          ),
        const PopupMenuItem(
          value: 'numbers',
          height: 60,
          child: ListTile(leading: Icon(Icons.local_hospital_outlined), title: Text('Emergency numbers')),
        ),
        const PopupMenuItem(
          value: 'sync',
          height: 60,
          child: ListTile(leading: Icon(Icons.sync), title: Text('Sync')),
        ),
        const PopupMenuItem(
          value: 'end',
          height: 60,
          child: ListTile(leading: Icon(Icons.logout), title: Text('End my shift')),
        ),
      ],
    );
  }
}

/// "Who is taking over?" then back to the shift start screen for the next person.
Future<void> endShiftFlow(BuildContext context) async {
  final c = GateScope.read(context);
  final pick = await showModalBottomSheet<_Takeover>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GateScope(controller: c, child: const EndShiftSheet()),
  );
  if (pick == null) return;
  await c.endShift(handedTo: pick.guard?.id);
}

class _Takeover {
  const _Takeover(this.guard);
  final Guard? guard;
}

class EndShiftSheet extends StatelessWidget {
  const EndShiftSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final h = c.handoverNow();
    final people = c.takeoverCandidates;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text('End my shift', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Text('Who is taking over?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (!c.isRider) _HandoverLine(h.inside, 'inside now', 'inside now'),
            _HandoverLine(h.unsynced, 'record not sent yet', 'records not sent yet', warn: h.unsynced > 0),
            if (c.snapshot?.rollup != null && !c.isRider)
              _HandoverLine(h.nightListOpen, 'on the night list to check', 'on the night list to check', warn: h.nightListOpen > 0),
            if (c.isRider && c.myRides.any((r) => r.state == 'accepted'))
              const Text(
                'Rides you took and have not picked up go back to the queue.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GateColors.warn),
              ),
            const SizedBox(height: 12),
            for (final g in people) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64), alignment: Alignment.centerLeft),
                onPressed: () => Navigator.pop(context, _Takeover(g)),
                child: Row(
                  children: [
                    Icon(g.isCso ? Icons.shield_outlined : (g.isRider ? Icons.two_wheeler : Icons.badge_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(g.name, style: const TextStyle(fontSize: 20))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            BigButton(label: 'Nobody', icon: Icons.person_off_outlined, color: GateColors.navy, onPressed: () => Navigator.pop(context, const _Takeover(null))),
            const SizedBox(height: 8),
            const Text('The next person starts their own shift with their PIN and photo.', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _HandoverLine extends StatelessWidget {
  const _HandoverLine(this.n, this.one, this.many, {this.warn = false});
  final int n;
  final String one;
  final String many;
  final bool warn;

  @override
  Widget build(BuildContext context) => Text(
    '$n ${n == 1 ? one : many}',
    style: TextStyle(fontSize: 18, fontWeight: warn ? FontWeight.w700 : FontWeight.w400, color: warn ? GateColors.warn : GateColors.ink),
  );
}

/// Last sync time, queued count, and a red mark if something needs attention.
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final attention = c.view.needsAttention.length;
    final last = c.lastSyncAt;
    final label = c.syncing
        ? 'Syncing'
        : last == null
        ? 'Not synced'
        : hhmm(c.time.of(last));
    final color = attention > 0 ? GateColors.stop : (c.lastError != null ? GateColors.warn : GateColors.go);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncScreen())),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.lastError != null ? Icons.cloud_off : Icons.cloud_done, color: color, size: 22),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: GateColors.ink, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (c.view.queued > 0) ...[
              const SizedBox(width: 6),
              Text(
                '${c.view.queued}',
                style: const TextStyle(color: GateColors.warn, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
            if (attention > 0) ...[
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 11,
                backgroundColor: GateColors.stop,
                child: Text('$attention', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/estate_time.dart';
import '../app.dart';
import '../kit.dart';
import '../words.dart';

/// When the phone last synced, what waits to go, Sync now, and what the server refused.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final t = c.time;
    final last = c.lastSyncAt;
    final offline = !c.online || c.lastError != null;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(label: tr(M.sync), sayAloud: tr(offline ? M.noNetwork : M.sync)),
          Expanded(
            child: ListView(
              children: [
                KitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        last == null ? tr(M.neverSynced) : tr(M.lastSync, {'when': when(t.of(last), t.now())}),
                        style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w600),
                      ),
                      Text(tr(M.waitingToSend, {'n': c.view.queued}), style: monoStyle(context, 17, weight: FontWeight.w500)),
                      if (offline) Text(tr(M.noNetwork), style: TextStyle(fontFamily: inter, fontSize: 16, color: p.warnText, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BigTile(label: c.syncing ? tr(M.syncing) : tr(M.syncNow), icon: Icons.sync, primary: true, height: 96, onTap: c.syncing ? null : c.syncNow),
                const SizedBox(height: 20),
                Text('${tr(M.needsAttention)} (${c.view.needsAttention.length})', style: const TextStyle(fontFamily: inter, fontSize: 22, fontWeight: FontWeight.w700)),
                Text(tr(M.serverRefused), style: mutedStyle(context, 15)),
                const SizedBox(height: 8),
                if (c.view.needsAttention.isEmpty) Text(tr(M.nothing), style: mutedStyle(context, 17)),
                for (final i in c.view.needsAttention)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: KitCard(
                      border: p.no,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(c.describe(i), style: const TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(when(t.of(i.createdAt), t.now()), style: monoStyle(context, 14, color: p.muted, weight: FontWeight.w500)),
                          Text(tr(M.reason, {'why': i.reason ?? '?'}), style: TextStyle(fontFamily: inter, fontSize: 16, color: p.noText)),
                          const SizedBox(height: 8),
                          Pill(label: tr(M.dismiss), onTap: () => c.dismissRejected(i.id)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  '${(c.snapshot?.estate.name ?? c.estateName ?? '-').toUpperCase()} · ${(c.gateName ?? '-').toUpperCase()}',
                  style: monoStyle(context, 12, color: p.muted, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

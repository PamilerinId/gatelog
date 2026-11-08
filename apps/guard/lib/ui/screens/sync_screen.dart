import 'package:flutter/material.dart';

import '../../core/estate_time.dart';
import '../app.dart';
import '../theme.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final t = c.time;
    final last = c.lastSyncAt;
    Text line(String s, {Color? color}) => Text(s, style: TextStyle(fontSize: 19, color: color));
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            line(last == null ? 'Never synced' : 'Last sync: ${when(t.of(last), t.now())}'),
            line('Waiting to send: ${c.view.queued}'),
            if (c.lastError != null) line('Last try: ${c.lastError}', color: GateColors.stop),
            line(c.push.available ? 'Push: on' : 'Push: off (checks every 2 minutes)'),
            const SizedBox(height: 16),
            BigButton(label: c.syncing ? 'Syncing...' : 'Sync now', icon: Icons.sync, onPressed: c.syncing ? null : c.syncNow),
            const SizedBox(height: 24),
            Text('Needs attention (${c.view.needsAttention.length})', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('The server refused these. They will not be sent again. Tell the estate admin.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            if (c.view.needsAttention.isEmpty) line('Nothing.'),
            for (final i in c.view.needsAttention)
              Card(
                elevation: 0,
                color: GateColors.stopWash,
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(c.describe(i), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('Recorded ${when(t.of(i.createdAt), t.now())}', style: const TextStyle(fontSize: 16)),
                    Text('Reason: ${i.reason ?? 'unknown'}', style: const TextStyle(fontSize: 16, color: GateColors.stop)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => c.dismissRejected(i.id), child: const Text('Dismiss')),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 24),
            Text('Paired to ${c.snapshot?.estate.name ?? c.estateName ?? '-'}, ${c.gateName ?? '-'}', style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

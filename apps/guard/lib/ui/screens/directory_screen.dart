import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../app.dart';
import '../theme.dart';

const _categoryLabel = {'estate': 'Estate', 'crime': 'Crime', 'fire': 'Fire', 'medical': 'Medical', 'utilities': 'Utilities'};

/// Emergency numbers, from the cache, so they work with no data. Tap to call.
class DirectoryScreen extends StatelessWidget {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final groups = <String, List<DirectoryEntry>>{};
    for (final d in c.snapshot?.directory ?? const <DirectoryEntry>[]) {
      groups.putIfAbsent(d.category, () => []).add(d); // already ordered by the server
    }
    if (groups.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('No numbers yet.', style: TextStyle(fontSize: 20)));
    }
    return ListView(children: [
      for (final e in groups.entries) ...[
        SectionHeader(_categoryLabel[e.key] ?? e.key),
        for (final d in e.value) _Row(entry: d, reported: d.reportedNotWorking || c.view.reportedNumbers.contains(d.id)),
      ],
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.reported});
  final DirectoryEntry entry;
  final bool reported;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.read(context);
    return InkWell(
      onTap: () => launchUrl(Uri(scheme: 'tel', path: entry.number.replaceAll(' ', ''))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: GateColors.line))),
        child: Row(children: [
          const Icon(Icons.call, color: GateColors.go, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(entry.number, style: const TextStyle(fontSize: 19, letterSpacing: 0.5)),
              if (reported)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: GateColors.stopWash, borderRadius: BorderRadius.circular(4)),
                  child: const Text('Reported not working', style: TextStyle(color: GateColors.stop, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
            ]),
          ),
          if (!reported)
            TextButton(
              onPressed: () async {
                final yes = await confirm(context, "This number didn't work?", body: '${entry.name}\nThe estate admin will be told.', yes: 'Report it');
                if (yes) {
                  await c.reportNumber(entry.id);
                  if (context.mounted) toast(context, 'Reported. Thank you.');
                }
              },
              child: const Text("Didn't work", style: TextStyle(color: GateColors.stop)),
            ),
        ]),
      ),
    );
  }
}

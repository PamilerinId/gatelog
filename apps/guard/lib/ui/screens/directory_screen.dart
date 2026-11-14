import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../app.dart';
import '../kit.dart';
import '../widgets.dart' show dial;
import '../words.dart';
import 'shuttle_screens.dart' show askYesNo;

const _categoryLabel = {'estate': 'ESTATE', 'crime': 'POLICE', 'fire': 'FIRE', 'medical': 'MEDICAL', 'utilities': 'UTILITIES'};

/// Emergency numbers on their own screen (the guard's home, below the three jobs).
class EmergencyNumbersScreen extends StatelessWidget {
  const EmergencyNumbersScreen({super.key});

  @override
  Widget build(BuildContext context) => KitScaffold(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitTopBar(label: tr(M.emergencyNumbers), sayAloud: tr(M.emergencyNumbers)),
        const Expanded(child: DirectoryList()),
      ],
    ),
  );
}

/// The estate's emergency numbers from the cache, so they work with no data. Grouped; tap to
/// call. "Didn't work" queues a report for the estate admin.
class DirectoryList extends StatelessWidget {
  const DirectoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    final p = Palette.of(context);
    final groups = <String, List<DirectoryEntry>>{};
    for (final d in c.snapshot?.directory ?? const <DirectoryEntry>[]) {
      groups.putIfAbsent(d.category, () => []).add(d); // already ordered by the server
    }
    if (groups.isEmpty) return Center(child: Text(tr(M.noNumbersYet), style: mutedStyle(context, 18)));
    return ListView(
      children: [
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              _categoryLabel[e.key] ?? e.key.toUpperCase(),
              style: monoStyle(context, 13, color: p.muted, weight: FontWeight.w500).copyWith(letterSpacing: 1.6),
            ),
          ),
          for (final d in e.value) _Row(entry: d, reported: d.reportedNotWorking || c.view.reportedNumbers.contains(d.id)),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.reported});
  final DirectoryEntry entry;
  final bool reported;

  @override
  Widget build(BuildContext context) {
    final c = GateScope.read(context);
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => dial(entry.number),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.call_outlined, size: 30, color: p.text),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.name, style: const TextStyle(fontFamily: inter, fontSize: 19, fontWeight: FontWeight.w700)),
                        Text(entry.number, style: monoStyle(context, 18, weight: FontWeight.w500)),
                        if (reported) Text(tr(M.reported), style: TextStyle(fontFamily: inter, fontSize: 14, fontWeight: FontWeight.w700, color: p.noText)),
                      ],
                    ),
                  ),
                  if (!reported)
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(56, 56), foregroundColor: p.noText),
                      onPressed: () async {
                        final yes = await askYesNo(context, label: entry.name, question: tr(M.reportNumberQ), say: tr(M.reportNumberQ));
                        if (yes != true) return;
                        await c.reportNumber(entry.id);
                        say(M.reportedThanks);
                      },
                      child: Text(tr(M.didNotWork)),
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

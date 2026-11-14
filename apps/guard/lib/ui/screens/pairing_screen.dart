/// Pairing: once per phone, by the estate admin, so typing the pairing code is allowed here. In the
/// handoff's look (charcoal with the twill at night, light by day; Inter for words, JetBrains Mono
/// for the code).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../sync/api.dart';
import '../app.dart';
import '../kit.dart';
import '../words.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = GateController.normalizePairingCode(_code.text);
    if (code == null) {
      setState(() => _error = tr(M.pairingCodeShape));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await GateScope.read(context).pair(code);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } on NetworkException {
      setState(() => _error = tr(M.pairingNeedsData));
    } catch (_) {
      setState(() => _error = tr(M.pairingFailed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // A 320 by 568 phone: the code, a three-line error and Pair phone fit with no scrolling.
    final compact = MediaQuery.sizeOf(context).height < 700;
    return KitScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitTopBar(back: false, label: tr(M.appName), sayAloud: '${tr(M.pairThisPhone)}. ${tr(M.pairingCodeFromAdmin)}'),
          Expanded(
            child: ListView(
              children: [
                if (!compact) ...[Icon(Icons.phonelink_lock_outlined, size: 64, color: p.text), const SizedBox(height: 4)],
                Headline(tr(M.pairThisPhone), size: 32),
                Text(tr(M.pairingCodeFromAdmin), style: mutedStyle(context, 18)),
                SizedBox(height: compact ? 16 : 24),
                KitCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  border: _error != null ? p.no : null,
                  child: TextField(
                    controller: _code,
                    autofocus: true,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')), LengthLimitingTextInputFormatter(11)],
                    cursorColor: p.text,
                    style: monoStyle(context, 32).copyWith(letterSpacing: 4),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: tr(M.pairingCodeHint),
                      hintStyle: monoStyle(context, 32, color: p.muted.withValues(alpha: 0.5), weight: FontWeight.w500).copyWith(letterSpacing: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: p.noText, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(fontFamily: inter, fontSize: 18, fontWeight: FontWeight.w700, color: p.noText),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          BigTile(label: tr(_busy ? M.pairingNow : M.pairPhone), icon: Icons.link, primary: true, height: 96, onTap: _busy ? null : _submit),
        ],
      ),
    );
  }
}

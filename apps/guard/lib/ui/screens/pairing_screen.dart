import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../sync/api.dart';
import '../app.dart';
import '../theme.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final code = GateController.normalizePairingCode(_code.text);
    if (code == null) {
      setState(() => _error = 'The code has 8 letters and numbers, like ABCD-2345.');
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
      setState(() => _error = 'No connection. Pairing needs data. Check the SIM and try again.');
    } catch (_) {
      setState(() => _error = 'Pairing failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Gatelog Gate')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Pair this phone', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Enter the pairing code from the estate admin.', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                  LengthLimitingTextInputFormatter(11),
                ],
                style: const TextStyle(fontSize: 32, letterSpacing: 4, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(hintText: 'ABCD-2345'),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Verdict(title: _error!, color: GateColors.stop, wash: GateColors.stopWash, icon: Icons.error_outline),
              ],
              const SizedBox(height: 24),
              BigButton(label: _busy ? 'Pairing...' : 'Pair phone', onPressed: _busy ? null : _submit),
            ],
          ),
        ),
      );
}

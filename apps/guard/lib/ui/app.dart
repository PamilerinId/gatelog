import 'dart:async';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'screens/cso_screens.dart';
import 'screens/guard_home.dart';
import 'screens/pairing_screen.dart';
import 'screens/rider_home.dart';
import 'screens/shift_start_screen.dart';
import 'theme.dart';

class GateScope extends InheritedNotifier<GateController> {
  const GateScope({super.key, required GateController controller, required super.child}) : super(notifier: controller);

  /// Rebuilds the caller when the controller changes.
  static GateController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GateScope>()!.notifier!;

  /// For callbacks: no rebuild dependency.
  static GateController read(BuildContext context) => context.getInheritedWidgetOfExactType<GateScope>()!.notifier!;
}

class GuardApp extends StatefulWidget {
  const GuardApp({super.key, required this.controller});
  final GateController controller;

  @override
  State<GuardApp> createState() => _GuardAppState();
}

class _GuardAppState extends State<GuardApp> with WidgetsBindingObserver {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A shift ends by itself after 14 hours, even with no network.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => widget.controller.checkShiftExpiry());
  }

  @override
  void dispose() {
    _minute?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Poll every 2 minutes in the foreground only; pull straight away on return.
    if (state == AppLifecycleState.resumed) {
      widget.controller.setForeground(true);
      widget.controller.checkShiftExpiry();
    }
    if (state == AppLifecycleState.paused) widget.controller.setForeground(false);
  }

  @override
  Widget build(BuildContext context) => GateScope(
        controller: widget.controller,
        child: MaterialApp(
          title: 'Gatelog Gate',
          debugShowCheckedModeBanner: false,
          theme: gateTheme(),
          home: const _Root(),
        ),
      );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final c = GateScope.of(context);
    return switch (c.phase) {
      Phase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      Phase.unpaired => const PairingScreen(),
      Phase.startShift => const ShiftStartScreen(),
      // A new shift starts on a fresh screen stack (the key), as the person it belongs to.
      Phase.ready => KeyedSubtree(
          key: ValueKey(c.shift?.id),
          child: c.isCso ? const CsoShell() : (c.isRider ? const RiderHome() : const GuardHome()),
        ),
    };
  }
}

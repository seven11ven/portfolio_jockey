import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/app/app_controller.dart';
import 'package:portfolio_jockey/app/settings_store.dart';
import 'package:portfolio_jockey/app/theme.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/ui/home/home_screen.dart';
import 'package:portfolio_jockey/ui/setup/first_run_screen.dart';
import 'package:portfolio_jockey/ui/setup/unlock_screen.dart';

void main() {
  final controller = AppController(settingsStore: SettingsStore.standard());
  unawaited(controller.start());
  runApp(PortfolioJockeyApp(controller: controller));
}

class PortfolioJockeyApp extends StatefulWidget {
  const PortfolioJockeyApp({required this.controller, super.key});

  final AppController controller;

  @override
  State<PortfolioJockeyApp> createState() => _PortfolioJockeyAppState();
}

class _PortfolioJockeyAppState extends State<PortfolioJockeyApp> {
  final _navigator = GlobalKey<NavigatorState>();
  AppStage? _lastStage;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_stageChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_stageChanged);
    super.dispose();
  }

  // Locking closes every open screen and dialog, so nothing decrypted stays visible.
  void _stageChanged() {
    final stage = widget.controller.stage;
    if (stage != _lastStage && stage != AppStage.unlocked) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    _lastStage = stage;
  }

  @override
  Widget build(BuildContext context) => AppScope(
    controller: widget.controller,
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => MaterialApp(
        title: 'Portfolio Jockey',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigator,
        themeMode: widget.controller.themeMode,
        theme: buildTheme(Brightness.light, accent: widget.controller.accent),
        darkTheme: buildTheme(Brightness.dark, accent: widget.controller.accent),
        home: const _Root(),
      ),
    ),
  );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => switch (AppScope.of(context).stage) {
    AppStage.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
    AppStage.setup => const FirstRunScreen(),
    AppStage.locked => const UnlockScreen(),
    AppStage.unlocked => const HomeScreen(),
  };
}

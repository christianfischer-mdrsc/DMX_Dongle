import 'package:flutter/widgets.dart';

import '../state/app_state.dart';

/// Stellt AppState im Widget-Baum bereit. Neu zeichnen über
/// [AppListener], damit nur betroffene Teile rebuilden.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.app, required super.child});
  final AppState app;

  static AppState of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.app;

  @override
  bool updateShouldNotify(AppScope old) => old.app != app;
}

/// Rebuildet bei Änderungen an Show-Daten und/oder Kanalwerten.
class AppListener extends StatelessWidget {
  const AppListener({super.key, required this.builder, this.engine = true});
  final Widget Function(BuildContext, AppState) builder;
  final bool engine;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: engine ? Listenable.merge([app, app.engine]) : app,
      builder: (c, _) => builder(c, app),
    );
  }
}

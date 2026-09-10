import 'package:flutter/widgets.dart';

/// Key global del Navigator de la app, para poder navegar desde fuera del
/// árbol de widgets (p. ej. al tocar una notificación de mensaje de grupo).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

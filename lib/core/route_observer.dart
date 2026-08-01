import 'package:flutter/material.dart';

/// Observador global de navegación. Permite que una página sepa cuándo deja
/// de ser la ruta visible (tapada por otra) y cuándo vuelve a serlo —
/// necesario para MapPage, que no debe tocar canales nativos del mapa
/// mientras está tapada por otras pantallas (ver RouteAware en map_page.dart).
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

// ignore_for_file: unused_field

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        HapticFeedback,
        SystemChrome,
        SystemUiOverlayStyle,
        SystemUiMode,
        SystemUiOverlay,
        MethodChannel,
        PlatformException;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide ImageSource;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/presence_service.dart';
import '../services/events_service.dart';
import '../services/alerts_service.dart';
import '../services/co2_service.dart';
import '../services/favorites_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/fall_detection_service.dart';
import '../services/proximity_alert_service.dart';
import '../services/notification_service.dart';
import '../services/ride_stats_service.dart';
import '../services/ride_stats_sync_service.dart';
import '../services/ride_heat_service.dart';
import '../services/plus_prefs_service.dart';
import '../services/subscription_service.dart';
import '../services/poi_photos_service.dart';
import '../services/achievements_service.dart';
import '../widgets/achievement_unlock_toast.dart';
import '../core/route_observer.dart';
import '../core/confirm_word_dialog.dart';
import '../widgets/event_photo_gallery.dart';
import 'paywall_page.dart';
import '../pages/auth_page.dart';
import '../pages/events_page.dart';
import '../pages/create_event_page.dart';
import '../pages/event_chat_page.dart';
import '../pages/profile_page.dart';
import '../pages/ranking_page.dart';
import '../pages/rider_ranking_page.dart';
import '../pages/route_planner_page.dart';
import '../pages/stats_page.dart';
import '../pages/moments_page.dart';
import '../pages/messages_page.dart';
import '../pages/settings_page.dart';
import '../core/glass.dart';
import '../core/constants.dart';
import '../widgets/weather_widget.dart';
import '../widgets/rain_overlay.dart';
import '../widgets/plus_medal.dart';
import '../services/weather_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with RouteAware {
  MapboxMap? mapboxMap;
  StreamSubscription<geo.Position>? _positionStreamSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _cyclistsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _alertsSubscription;

  final PresenceService _presenceService = PresenceService();
  final EventsService _eventsService = EventsService();
  final AlertsService _alertsService = AlertsService();

  bool _isFollowingUser = false;
  bool _cicloviasAdded = false;

  // Overlay de lluvia: refleja el clima detectado por WeatherService.
  bool _isRaining = false;
  bool _isHeavyRain = false;
  // false mientras el estilo del mapa está cargando/transicionando (justo
  // después de loadStyleURI y hasta que onStyleLoadedListener confirma que
  // el nuevo StyleManager ya está listo). Sin esto, una actualización de
  // eventos/alertas que llega en medio de un cambio de estilo (día/noche)
  // intenta usar addStyleImage sobre un estilo que ya no existe, y explota
  // con "Unable to establish connection on channel: StyleManager...".
  bool _styleIsLoaded = false;
  // Se incrementa cada vez que se crea una instancia nueva de MapboxMap
  // (onMapCreated). Si una operación async en curso ve que la "generación"
  // cambió antes de terminar, sabe que su referencia a mapboxMap/estilo ya
  // quedó obsoleta (view/canal nativo distinto) y debe abortar en vez de
  // llamar a un canal que ya no existe.
  int _mapGeneration = 0;

  // Mientras MapPage está tapada por otra pantalla (EventsPage, CrearEvento,
  // el selector de ubicación, etc.), la vista nativa del mapa no responde de
  // forma confiable a canales de plataforma (ver _ensureEventsIcon) — así
  // que evitamos tocar el estilo del mapa hasta volver a estar visibles.
  bool _routeIsCurrent = true;
  bool _showLayersTip = false;
  Offset? _helpBubblePos;
  bool _helpBubbleBounce = false;
  bool _showHelpTipText = false;
  int _helpTipIndex = 0;
  Timer? _helpTipHideTimer;

  static const List<String> _helpTips = [
    '💡 Puedes activar o desactivar los pines (BiciMetro, estacionamientos, talleres) desde el menú ☰ → MAPA.',
    '🚴 "Modo activo" te hace visible para otros ciclistas cerca y suma tus km.',
    '📸 En cada pin de BiciMetro o taller puedes subir una foto de referencia para ayudar a otros.',
    '⭐ Con Pedalea Plus desbloqueas estadísticas avanzadas y más personalización.',
    '🆘 La detección de caídas puede llamar a emergencias automáticamente si tienes un golpe fuerte.',
    '🗺️ Mantén presionado el mapa para reportar un problema en esa ubicación.',
    '🧭 Puedes arrastrar esta burbuja a donde quieras — se queda ahí.',
  ];

  void _onHelpBubbleTap() {
    _helpTipHideTimer?.cancel();
    setState(() {
      _helpBubbleBounce = true;
      _showHelpTipText = true;
      _helpTipIndex = (_helpTipIndex + 1) % _helpTips.length;
    });
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _helpBubbleBounce = false);
    });
    _helpTipHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHelpTipText = false);
    });
  }

  double _layersTipOpacity = 0.0;
  int _layersTipSecondsLeft = 20;
  Timer? _layersTipTimer;

  void _startLayersTipCountdown() {
    _layersTipTimer?.cancel();
    setState(() {
      _showLayersTip = true;
      _layersTipOpacity = 1.0;
      _layersTipSecondsLeft = 20;
    });
    _layersTipTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_layersTipSecondsLeft <= 1) {
        timer.cancel();
        // Se desvanece suavemente antes de desmontarse del todo.
        setState(() => _layersTipOpacity = 0.0);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _showLayersTip = false);
        });
      } else {
        setState(() => _layersTipSecondsLeft--);
      }
    });
  }

  String?
  _cicloviasGeoJson; // caché para no re-llamar a Overpass tras cambio de estilo
  bool _cyclistsIconAdded = false;
  List<Map<String, dynamic>> _lastCyclists = [];
  bool _eventsIconAdded = false;
  bool _alertsIconAdded = false;
  bool _alertsLayerAdded = false;

  // ── Mi mapa de calor (Plus) ──────────────────────────────────────────────
  bool _showHeatmap = false;
  static const _heatSrcId = 'my-heat-src';
  static const _heatLyrId = 'my-heat-lyr';

  // ── Estacionamientos de bici (OSM) ────────────────────────────────────────
  bool _showBikeParkings = true;
  bool _bikeParkingsLoading = false;
  bool _bikeParkingsIconAdded = false;
  List<Map<String, dynamic>> _bikeParkings = [];

  // ── BiciMetro ─────────────────────────────────────────────────────────────
  bool _showBicimetro = true;
  bool _bicimetroIconAdded = false;

  // ── Servicios para bici (inflado / talleres / gasolineras con aire) ───────
  bool _showBikeServices = true;
  bool _autoLayersTriggered = false; // las capas por defecto se cargan 1 vez

  // ── CicloRecreoVía (cierres de calles dominicales para ciclistas) ─────────
  bool _showCicloRecreo = true;
  bool _cicloRecreoIconAdded = false;
  List<Map<String, dynamic>> _cicloRecreoPoints = [];
  static const _crvSrcId = 'ciclorecreovia-src';
  static const _crvLyrId = 'ciclorecreovia-lyr';
  bool _bikeServicesLoading = false;
  bool _bikeServicesIconsAdded = false;
  List<Map<String, dynamic>> _bikeServices = [];

  // ── Dificultad de ruta ───────────────────────────────────────────────────
  String? _routeDifficulty;
  double? _routeElevGain;
  bool _elevationLoading = false;

  // Estado previo de capas opcionales (para restaurar al cerrar la ruta)
  bool _prevShowBikeParkings = false;
  bool _prevShowBicimetro = false;
  bool _prevShowBikeServices = false;

  bool _modoActivo = true;
  bool _autoDarkMode = true;

  bool get _isDayMode =>
      (_autoDarkMode && _currentStyle == kMapStyleDay) ||
      _currentStyle == kMapStyleMinimal;

  /// Estilo de mapa a usar: si el ciclista es Plus y eligió un estilo premium,
  /// ese; si no, el modo día/noche automático (o siempre noche).
  String _resolveMapStyle() {
    final premium = PlusPrefsService.mapStyle.value;
    if (premium.isNotEmpty && SubscriptionService.instance.isPlus.value) {
      return premium;
    }
    return _autoDarkMode ? autoDarkMapStyle() : kMapStyleNight;
  }

  /// Recarga el estilo cuando cambia la preferencia (sincroniza entre equipos).
  void _onMapStylePrefChanged() {
    if (!mounted) return;
    final s = _resolveMapStyle();
    if (s != _currentStyle && mapboxMap != null) {
      setState(() => _currentStyle = s);
      _styleIsLoaded = false;
      mapboxMap!.loadStyleURI(s);
    }
  }

  void _applyMapStyle(String premiumUri) {
    // '' = volver al automático día/noche. Guarda en el perfil (BD).
    PlusPrefsService.setMapStyle(premiumUri);
    setState(() => _currentStyle = _resolveMapStyle());
    _styleIsLoaded = false;
    mapboxMap?.loadStyleURI(_currentStyle);
  }

  // ── Mi mapa de calor personal (capa Plus sobre el mapa) ─────────────
  Future<void> _toggleHeatmap() async {
    if (!SubscriptionService.instance.isPlus.value) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason: 'El mapa de calor personal es una función de Pedalea Plus.',
          ),
        ),
      );
      return;
    }
    final turningOn = !_showHeatmap;
    setState(() => _showHeatmap = turningOn);
    if (turningOn) {
      await RideHeatService.init();
      if (RideHeatService.cellCount == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aún no hay recorridos. Pedalea con el "Modo activo" encendido y '
              'tus zonas irán apareciendo aquí.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
    await _updateHeatmapLayer();
  }

  Future<void> _updateHeatmapLayer() async {
    if (mapboxMap == null || !_styleIsLoaded) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_heatLyrId)) {
        await style.removeStyleLayer(_heatLyrId);
      }
      if (await style.styleSourceExists(_heatSrcId)) {
        await style.removeStyleSource(_heatSrcId);
      }
      if (!_showHeatmap) return;

      await RideHeatService.init();
      final cells = RideHeatService.cells();
      if (cells.isEmpty) return;

      final features = cells
          .map((c) => {
                'type': 'Feature',
                'properties': {'w': c.weight},
                'geometry': {
                  'type': 'Point',
                  'coordinates': [c.lng, c.lat],
                },
              })
          .toList();
      final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});

      await style.addSource(GeoJsonSource(id: _heatSrcId, data: fc));
      await style.addLayer(HeatmapLayer(
        id: _heatLyrId,
        sourceId: _heatSrcId,
        heatmapOpacity: 0.75,
        heatmapWeightExpression: <Object>[
          'interpolate', ['linear'], ['get', 'w'], 0, 0.0, 8, 1.0,
        ],
        heatmapIntensityExpression: <Object>[
          'interpolate', ['linear'], ['zoom'], 0, 1.0, 18, 3.0,
        ],
        heatmapRadiusExpression: <Object>[
          'interpolate', ['linear'], ['zoom'],
          8, 6.0, 12, 16.0, 15, 28.0, 18, 46.0,
        ],
        heatmapColorExpression: <Object>[
          'interpolate', ['linear'], ['heatmap-density'],
          0.0, 'rgba(0,0,0,0)',
          0.2, 'rgba(65,145,255,0.55)',
          0.4, 'rgba(70,220,120,0.8)',
          0.6, 'rgba(253,219,64,0.9)',
          0.8, 'rgba(240,130,40,0.95)',
          1.0, 'rgb(230,40,40)',
        ],
      ));
    } catch (e) {
      debugPrint('❌ Error mapa de calor: $e');
    }
  }

  /// Selector de estilo de mapa en el menú ☰ → "Mapa". El automático es gratis;
  /// satélite/exterior/minimalista son de Pedalea Plus.
  Widget _mapStylePicker() {
    final isPlus = SubscriptionService.instance.isPlus.value;
    final current = PlusPrefsService.mapStyle.value;
    const accent = Color(0xFF7CF0BC);
    Widget chip(String label, String uri, {required bool locked}) {
      final selected = current == uri && (uri.isEmpty || isPlus);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (locked) {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PaywallPage(
                  reason:
                      'Los estilos de mapa exclusivos son parte de Pedalea Plus.',
                ),
              ),
            );
            return;
          }
          _applyMapStyle(uri);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.18)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? accent : Colors.white.withOpacity(0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, color: accent, size: 14),
                const SizedBox(width: 4),
              ] else if (locked) ...[
                Icon(Icons.lock_outline_rounded,
                    color: Colors.white.withOpacity(0.5), size: 12),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? accent : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ESTILO DE MAPA',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Automático', '', locked: false),
              for (final s in PlusPrefsService.premiumMapStyles)
                chip(s.$1, s.$2, locked: !isPlus),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers de estilo día/noche para overlays ─────────────────────────────
  Color get _overlayBg => _isDayMode
      ? Colors.white.withOpacity(0.92)
      : Colors.white.withOpacity(0.12);
  Color get _overlayText => _isDayMode ? const Color(0xFF1A1A2E) : Colors.white;
  Color get _overlaySubtext =>
      _isDayMode ? const Color(0xFF555577) : Colors.white60;

  BoxDecoration _dayNightBox({double radius = 20}) => BoxDecoration(
    color: _overlayBg,
    borderRadius: BorderRadius.circular(radius),
    border: _isDayMode
        ? null
        : Border.all(color: Colors.white.withOpacity(0.18)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(_isDayMode ? 0.12 : 0.30),
        blurRadius: _isDayMode ? 8 : 20,
        offset: const Offset(0, 3),
      ),
    ],
  );

  // Tracking de km
  geo.Position? _lastPosition;
  DateTime? _lastFixAt; // hora del último fix, para estimar velocidad
  double _sessionKm = 0;
  double _unsavedKm = 0;
  double _sessionMaxSpeedKmh = 0; // velocidad máxima detectada en la sesión
  bool _communeAutofillTried = false; // 1 intento de autocompletar comuna/sesión

  // ── Trazado de la sesión actual (para compartir el viaje al terminar) ────
  final List<geo.Position> _routePoints = [];
  DateTime? _sessionStartAt;

  // Nombre de usuario real (cargado desde profiles) para la presencia en vivo
  String _myUsername = 'Ciclista';

  // Conteo de km en segundo plano (servicio en primer plano con GPS).
  // Encendido por defecto: contar los km del usuario es prioritario aunque
  // cueste algo de batería. El usuario lo puede apagar en el menú ☰.
  bool _bgTrackingEnabled = true;

  // ── Compartir ubicación en vivo (OPT-IN, ver initState) ───────────────────
  // Solo se muestra en el mapa a quienes tienen follow mutuo contigo (lo
  // impone también la RLS de `user_locations`, no solo esta bandera).
  bool _shareLiveLocation = false;

  // ── Seguridad: detección de caídas + alertas de proximidad ────────────────
  final FallDetectionService _fallService = FallDetectionService();
  final ProximityAlertService _proximityService = ProximityAlertService();
  bool _fallDetectionEnabled = true;
  bool _proximityAlertsEnabled = true;
  bool _fallDialogOpen = false;

  // ── Detección de choque por frenada imposible (velocidad GPS) ─────────────
  // Complementa al acelerómetro: si el celular va en un portacelular fijo,
  // nunca "cae" ni recibe el impacto característico, pero un choque real sí
  // se ve como una caída de velocidad físicamente imposible para un frenado
  // normal de bicicleta (ej. de 30 km/h a casi 0 en 1.5 s).
  double _maxRecentSpeedKmh = 0;
  DateTime? _maxRecentSpeedAt;
  DateTime? _lastSuddenStopTrigger;
  static const _suddenStopHighKmh = 20.0;
  static const _suddenStopLowKmh = 4.0;
  static const _suddenStopWindow = Duration(seconds: 2);
  static const _suddenStopCooldown = Duration(seconds: 20);

  // ── Modo pasajero: detectar por velocidad si vas en auto/micro/metro ──────
  // Una bici urbana rara vez sostiene >32 km/h; si pasa, preguntamos si es
  // pasajero para NO contar esos km como pedaleo (calidad de las estadísticas).
  bool _isPassenger = false;
  String _passengerVehicle = 'auto'; // 'auto' | 'micro' | 'metro'
  bool _passengerPromptOpen = false;
  DateTime? _highSpeedSince;
  DateTime? _lowSpeedSince;
  DateTime? _passengerSnoozeUntil;

  // Timer para modo oscuro automático
  Timer? _styleCheckTimer;
  String _currentStyle = kMapStyleNight;

  // Timer que vuelve a ocultar la barra de navegación tras revelarla
  Timer? _immersiveTimer;

  // ── Planificador de rutas overlay ─────────────────────────────────────────
  bool _routePlannerOpen = false;
  bool _routeAddMode = false;
  bool _routeCalculating = false;
  final List<_RouteWp> _routeWps = [];
  double? _routeDistKm;
  double? _routeDurMin;
  List<FavoriteRoute> _savedRoutes = [];
  bool _loadingFavorites = false;

  // Progreso de navegación (borrar ruta recorrida)
  bool _navigating = false;
  List<List<double>> _routeCoords = [];
  int _routeProgressIdx = 0;

  // ── HUD de navegación (ETA, velocidad promedio, progreso, etc.) ─────────
  DateTime? _navStartTime;
  // Índice en _routeWps de la próxima parada a mostrar en el HUD. El punto
  // de partida es siempre el GPS en vivo (no forma parte de _routeWps), así
  // que la primera parada real está en el índice 0.
  int _navNextWpIndex = 0;
  static const _rpRouteSrc = 'rp-route-src';
  static const _rpRouteLyr = 'rp-route-lyr';
  static const _rpWpSrc = 'rp-wp-src';
  static const _rpWpLyr = 'rp-wp-lyr';

  // ── Estacionamientos / BiciMetro layer IDs ───────────────────────────────
  static const _parkingSrcId = 'bike-parking-src';
  static const _parkingLyrId = 'bike-parking-lyr';
  static const _parkingIconId = 'bike-parking-icon';
  static const _bicimetroSrcId = 'bicimetro-src';
  static const _bicimetroLyrId = 'bicimetro-lyr';
  static const _bicimetroIconId = 'bicimetro-icon';
  static const _servicesSrcId = 'bike-services-src';
  static const _servicesLyrId = 'bike-services-lyr';

  // ── Estaciones Metro de Santiago con BiciMetro ────────────────────────────
  static const _kBicimetroStations = <Map<String, Object>>[
    {'name': 'Baquedano', 'line': 'L1 / L2', 'lat': -33.4372, 'lng': -70.6326},
    {
      'name': 'Universidad de Chile',
      'line': 'L1',
      'lat': -33.4423,
      'lng': -70.6503,
    },
    {'name': 'Los Héroes', 'line': 'L1 / L2', 'lat': -33.4514, 'lng': -70.6623},
    {'name': 'Tobalaba', 'line': 'L1 / L4', 'lat': -33.4208, 'lng': -70.5979},
    {'name': 'Salvador', 'line': 'L1', 'lat': -33.4381, 'lng': -70.6142},
    {'name': 'Manuel Montt', 'line': 'L1', 'lat': -33.4274, 'lng': -70.6219},
    {
      'name': 'La Cisterna',
      'line': 'L2 / L4A',
      'lat': -33.5316,
      'lng': -70.6591,
    },
    {
      'name': 'Parque O\'Higgins',
      'line': 'L2 / L6',
      'lat': -33.4591,
      'lng': -70.6552,
    },
    {
      'name': 'Puente Cal y Canto',
      'line': 'L2 / L3',
      'lat': -33.4391,
      'lng': -70.6571,
    },
    {'name': 'Santa Ana', 'line': 'L1 / L5', 'lat': -33.4388, 'lng': -70.6749},
    {'name': 'Ñuble', 'line': 'L5 / L9', 'lat': -33.4618, 'lng': -70.6258},
    {'name': 'Ñuñoa', 'line': 'L6', 'lat': -33.4564, 'lng': -70.6012},
    {'name': 'Vicente Valdés', 'line': 'L4', 'lat': -33.5044, 'lng': -70.5803},
    {'name': 'Quilín', 'line': 'L4', 'lat': -33.4751, 'lng': -70.5672},
    {'name': 'Bicentenario', 'line': 'L6', 'lat': -33.3990, 'lng': -70.6340},
  ];

  // Feedback visual para long press
  OverlayEntry? _longPressOverlay;
  Offset? _longPressTapPosition;

  // Variables para el modo de selección de ubicación (para eventos)
  final bool _isSelectingLocation = false;
  Point? _selectedLocation;
  Map<String, dynamic>? _pendingAlertData;
  bool _isConfirming = false;

  final ValueNotifier<double> _speedNotifier = ValueNotifier(0.0);

  final String _cyclistsSourceId = "cyclists-source";
  final String _cyclistsLayerId = "cyclists-layer";
  final String _cyclistsIconImageId = "bike-icon-others";

  final String _eventsSourceId = "events-source";
  final String _eventsLayerId = "events-layer";
  final String _eventsIconImageId = "event-icon";

  final String _alertsSourceId = "alerts-source";
  final String _alertsLayerId = "alerts-layer";
  final String _alertsIconImageId = "alert-icon";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;

  List<Map<String, dynamic>> _currentEvents = [];
  List<Map<String, dynamic>> _currentAlerts = [];

  // ── Conectividad ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // Capa para el pin de selección
  final String _selectionSourceId = "selection-source";
  final String _selectionLayerId = "selection-layer";
  bool _selectionLayerAdded = false;

  // Para long press manual
  Timer? _longPressTimer;
  Point? _longPressPoint;
  final bool _isLongPressDetected = false;

  VoidCallback? get _confirmLocationAndCreateAlert => null;

  GestureLongPressCallback? get _onLongPressFromGesture => null;

  @override
  void initState() {
    super.initState();
    // Oculta SOLO la barra de navegación inferior pero mantiene la barra de
    // estado superior (hora, batería, ícono de ubicación compartida).
    // Un temporizador la vuelve a ocultar tras revelarla (no se queda fija).
    _applyImmersiveBottom();
    _immersiveTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _applyImmersiveBottom(),
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF08080F),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _currentStyle = _resolveMapStyle();
    PlusPrefsService.mapStyle.addListener(_onMapStylePrefChanged);
    _checkLocationPermission();
    _loadMyUsername();
    _loadFallDetectionPref();
    _loadRainState();

    // Restaurar preferencia de conteo en segundo plano (encendido por defecto).
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      // Compartir ubicación en vivo es OPT-IN (apagado por defecto): que otros
      // te vean pedaleando en tiempo real es sensible (riesgo de que alguien
      // te espere en el camino), así que el usuario debe activarlo a mano.
      setState(() => _shareLiveLocation = p.getBool('share_live_location') ?? false);
      final bgOn = p.getBool('bg_tracking') ?? true;
      setState(() => _bgTrackingEnabled = bgOn);
      if (bgOn) {
        // Pide "Permitir todo el tiempo" para que cuente con la pantalla
        // apagada; si el usuario lo niega, igual cuenta mientras la app está
        // abierta. No bloquea el arranque.
        Permission.locationAlways.request().whenComplete(() {
          if (mounted) _restartGps();
        });
      }
      // Aviso recurrente (1 vez por semana): contarles que pueden
      // prender/apagar los pines de BiciMetro, estacionamientos, etc.
      final lastShownMs = p.getInt('layers_tip_last_shown_ms');
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final dueAgain =
          lastShownMs == null ||
          DateTime.fromMillisecondsSinceEpoch(lastShownMs).isBefore(weekAgo);
      if (dueAgain) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _startLayersTipCountdown();
        });
        p.setInt(
          'layers_tip_last_shown_ms',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    });

    // Cargar el dataset incluido de servicios (Copec, talleres, aire) — no
    // depende de internet ni del GPS, así siempre se muestran por defecto.
    _loadBundledServices().then((d) {
      if (!mounted) return;
      _bikeServices = d;
      if (_showBikeServices) _updateBikeServicesLayer();
    });

    // CicloRecreoVía (cierres dominicales) — dataset incluido.
    _loadCicloRecreo().then((d) {
      if (!mounted) return;
      _cicloRecreoPoints = d;
      if (_showCicloRecreo) _updateCicloRecreoLayer();
    });

    // Cargar caché inmediatamente (datos mientras carga el mapa)
    _loadCachedData();

    // Chequear modo oscuro cada 5 minutos
    _styleCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      final newStyle = _resolveMapStyle();
      if (newStyle != _currentStyle && mapboxMap != null) {
        setState(() => _currentStyle = newStyle);
        _styleIsLoaded = false;
        mapboxMap!.loadStyleURI(newStyle);
      }
    });

    // Monitorear conectividad
    _isOffline = !ConnectivityService.isOnline;
    _connectivitySub = ConnectivityService.stream.listen((online) {
      if (!mounted) return;
      setState(() => _isOffline = !online);
      if (online) {
        // Reconectar streams cuando vuelve la red
        debugPrint('🌐 Red restaurada → reconectando streams');
        _listenToAlerts();
        _listenToEvents();
        _listenToActiveCyclists();
      }
    });
  }

  void _loadCachedData() {
    final cachedAlerts = CacheService.loadAlerts(ignoreExpiry: true);
    final cachedEvents = CacheService.loadEvents(ignoreExpiry: true);
    if (cachedAlerts != null || cachedEvents != null) {
      setState(() {
        if (cachedAlerts != null) _currentAlerts = cachedAlerts;
        if (cachedEvents != null) _currentEvents = cachedEvents;
      });
    }
    final cachedCiclovias = CacheService.loadCiclovias();
    if (cachedCiclovias != null) {
      _cicloviasGeoJson = cachedCiclovias;
    } else {
      // Sin caché → usar las ciclovías incluidas en la app (no dependen de red).
      rootBundle
          .loadString('assets/data/ciclovias_chile.json')
          .then((geo) {
            if (!mounted || _cicloviasGeoJson != null) return;
            _cicloviasGeoJson = geo;
            _cicloviasAdded = false;
            _addCicloviasLayer();
          })
          .catchError((Object e) {
            debugPrint('Error ciclovías incluidas: $e');
          });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  /// Otra pantalla se abrió encima de MapPage (EventsPage, CrearEvento,
  /// selector de ubicación...) — dejamos de tocar el canal nativo del mapa
  /// hasta que volvamos a estar visibles.
  @override
  void didPushNext() {
    _routeIsCurrent = false;
  }

  /// Volvimos a ser la pantalla visible (se cerró la que estaba encima) —
  /// reintentamos aplicar cualquier cambio de eventos/alertas que haya
  /// quedado pendiente mientras estábamos tapados.
  @override
  void didPopNext() {
    _routeIsCurrent = true;
    _refreshEventsNow();
    if (_currentAlerts.isNotEmpty) {
      _updateAlertsLayer(_currentAlerts);
    }
  }

  /// Trae los eventos frescos de la BD (no solo lo que quedó en caché) y
  /// actualiza el pin al instante — se usa al crear/unirse/salir de un
  /// evento y al volver a ver el mapa, para no depender de que llegue el
  /// push de Realtime a tiempo ni de reabrir la app.
  Future<void> _refreshEventsNow() async {
    final events = await _eventsService.getUpcomingEvents();
    if (!mounted) return;
    setState(() => _currentEvents = events);
    await _updateEventsLayer(_visibleEventPinsForMap(events));
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    // Invalida cualquier operación async de mapa en curso (ver
    // _ensureEventsIcon) antes de que el widget termine de destruirse.
    _mapGeneration++;
    _styleIsLoaded = false;
    // Guarda los km que quedaron por debajo del umbral de persistencia.
    if (_unsavedKm > 0.02) {
      _saveKmToProfile(_unsavedKm);
      RideStatsService.addKm(_unsavedKm);
      RideStatsSyncService.instance.pushDelta(
        km: _unsavedKm,
        maxSpeedKmh: _sessionMaxSpeedKmh,
      );
      _unsavedKm = 0;
    }
    RideHeatService.flushNow();
    PlusPrefsService.mapStyle.removeListener(_onMapStylePrefChanged);
    _positionStreamSubscription?.cancel();
    _layersTipTimer?.cancel();
    _helpTipHideTimer?.cancel();
    _diagCompassSub?.cancel();
    _cyclistsSubscription?.cancel();
    _cyclistsDelayTimer?.cancel();
    _eventsSubscription?.cancel();
    _alertsSubscription?.cancel();
    _connectivitySub?.cancel();
    _speedNotifier.dispose();
    _longPressTimer?.cancel();
    _styleCheckTimer?.cancel();
    _immersiveTimer?.cancel();
    _fallService.stop();
    _presenceService.clearMyLocation(); // marcar offline al salir
    // Restaurar las barras del sistema al salir del mapa.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Detección de caídas → auto-SOS ─────────────────────────────────────────

  /// Se invoca cuando el acelerómetro detecta una posible caída. Muestra una
  /// cuenta regresiva; si el usuario no la cancela, llama a Carabineros (133).
  /// Al terminar una sesión de pedaleo (apagar "Modo activo"), si hubo un
  /// recorrido mínimo, ofrece compartir una tarjeta con la ruta y las
  /// estadísticas del viaje (estilo Strava).
  void _maybeOfferRouteShare() {
    if (_sessionKm < 0.3 || _routePoints.length < 2) return;
    final startAt = _sessionStartAt ?? DateTime.now();
    final duration = DateTime.now().difference(startAt);

    if (!SubscriptionService.instance.isPlus.value) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _ShareUpsellSheet(
          distanceKm: _sessionKm,
          onUpgrade: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PaywallPage(
                  reason:
                      'Comparte tus viajes y estadísticas en historias con Pedalea Plus.',
                ),
              ),
            );
          },
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RouteShareSheet(
        distanceKm: _sessionKm,
        duration: duration,
        route: List<geo.Position>.from(_routePoints),
      ),
    );
  }

  void _onFallDetected() {
    if (!mounted || _fallDialogOpen) return;
    _fallDialogOpen = true;
    HapticFeedback.heavyImpact(); // vibración para llamar la atención
    NotificationService.instance.showEmergencyAlert(
      title: '⚠️ Posible caída detectada',
      body: 'Confirma que estás bien o se llamará a emergencias.',
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FallCountdownDialog(
        onCall: (number) async {
          final uri = Uri(scheme: 'tel', path: number);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
          _notifyEmergencyContactOfFall();
        },
        onDisableTapped: () {
          Navigator.of(context).pop();
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
    ).whenComplete(() => _fallDialogOpen = false);
  }

  /// Envía un SMS de aviso al contacto de emergencia guardado en `profiles`,
  /// además de la llamada a Carabineros/SAMU/Bomberos.
  Future<void> _notifyEmergencyContactOfFall() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('emergency_contact_phone')
          .eq('id', uid)
          .maybeSingle();
      final phone = data?['emergency_contact_phone'] as String?;
      if (phone == null || phone.isEmpty) return;
      final pos = _lastPosition;
      final locationText = pos != null
          ? ' Ubicación: https://maps.google.com/?q=${pos.latitude},${pos.longitude}'
          : ' No se pudo obtener la ubicación exacta.';
      final uri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {
          'body':
              'Pedalea detectó una posible caída mientras pedaleaba. Se llamó a emergencias automáticamente.$locationText',
        },
      );
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {
      // Sin conexión no se puede leer el contacto; no bloquea el flujo de emergencia.
    }
  }

  /// Carga la preferencia de detección de caídas guardada en `profiles`.
  /// Por defecto viene activada; si el usuario la desactivó antes, respeta
  /// esa elección en vez de arrancar el servicio a ciegas.
  Future<void> _loadFallDetectionPref() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (_fallDetectionEnabled) _fallService.start(_onFallDetected);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('fall_detection_enabled')
          .eq('id', uid)
          .maybeSingle();
      final enabled = data?['fall_detection_enabled'] as bool? ?? true;
      if (!mounted) return;
      setState(() => _fallDetectionEnabled = enabled);
    } catch (_) {
      // Sin conexión: se queda con el valor por defecto (activado).
    } finally {
      if (_fallDetectionEnabled) _fallService.start(_onFallDetected);
    }
  }

  /// Consulta el clima actual y activa el overlay de lluvia si corresponde.
  /// Se reintenta cada 10 minutos para reflejar cambios de clima en vivo.
  Future<void> _loadRainState() async {
    try {
      geo.Position? pos = await geo.Geolocator.getLastKnownPosition();
      pos ??= await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));
      final data = await WeatherService().fetch(pos.latitude, pos.longitude);
      if (!mounted || data == null) return;
      final heavy =
          data.precipitation > 5 ||
          (data.weatherCode >= 63 && data.weatherCode <= 67);
      setState(() {
        _isRaining = data.isRaining;
        _isHeavyRain = heavy;
      });
    } catch (e) {
      debugPrint('No se pudo cargar el estado de lluvia: $e');
    } finally {
      if (mounted) {
        Timer(const Duration(minutes: 10), _loadRainState);
      }
    }
  }

  /// Activa/desactiva la detección de caídas y guarda la elección en `profiles`
  /// para que se recuerde entre sesiones.
  Future<void> _setFallDetectionEnabled(bool val) async {
    setState(() => _fallDetectionEnabled = val);
    if (val) {
      _fallService.start(_onFallDetected);
    } else {
      _fallService.stop();
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fall_detection_enabled': val})
          .eq('id', uid);
    } catch (_) {
      // Sin conexión: queda aplicado localmente; se reintentará al recargar.
    }
  }

  /// Detecta una frenada físicamente imposible (ej. de 20+ km/h a casi 0 en
  /// menos de 2 s), señal de choque aunque el celular no reciba el impacto
  /// directo (va en un portacelular fijo al manubrio, por ejemplo).
  void _checkSuddenDeceleration(double speedKmh, DateTime now) {
    // Recordar la velocidad más alta reciente dentro de la ventana.
    if (_maxRecentSpeedAt == null ||
        now.difference(_maxRecentSpeedAt!) > _suddenStopWindow ||
        speedKmh >= _maxRecentSpeedKmh) {
      _maxRecentSpeedKmh = speedKmh;
      _maxRecentSpeedAt = now;
    }

    final withinWindow =
        _maxRecentSpeedAt != null &&
        now.difference(_maxRecentSpeedAt!) <= _suddenStopWindow;

    if (withinWindow &&
        _maxRecentSpeedKmh >= _suddenStopHighKmh &&
        speedKmh <= _suddenStopLowKmh) {
      if (_lastSuddenStopTrigger != null &&
          now.difference(_lastSuddenStopTrigger!) < _suddenStopCooldown) {
        return; // en enfriamiento, evita disparos repetidos
      }
      _lastSuddenStopTrigger = now;
      _maxRecentSpeedAt =
          null; // reinicia para no re-disparar con el mismo evento
      _onFallDetected();
    }
  }

  // ── Alertas push de proximidad ──────────────────────────────────────────────

  /// Revisa si el ciclista entró en el radio de algún incidente activo y, de
  /// ser así, dispara una notificación local (una sola vez por alerta).
  void _checkProximityAlerts(geo.Position position) {
    if (_currentAlerts.isEmpty) return;
    final nearby = _proximityService.alertsToNotify(
      position.latitude,
      position.longitude,
      _currentAlerts,
    );
    for (final alert in nearby) {
      final type = alert['type'] as String? ?? 'other';
      NotificationService.instance.showProximityAlert(
        id: (alert['id']?.toString() ?? '').hashCode & 0x7fffffff,
        title: '⚠️ Incidente cerca: ${_alertTypeLabel(type)}',
        body: alert['title'] as String? ?? 'Hay un reporte en tu trayecto',
      );
    }
  }

  String _alertTypeLabel(String type) {
    switch (type) {
      case 'danger':
        return 'Peligro';
      case 'theft':
        return 'Robo';
      case 'construction':
        return 'Obras';
      case 'accident':
        return 'Accidente';
      default:
        return 'Aviso';
    }
  }

  /// Oculta la barra de navegación inferior dejando visible solo la superior.
  void _applyImmersiveBottom() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isDenied) {
      await Permission.location.request();
    }
  }

  /// Carga el nombre de usuario real desde la tabla `profiles` para mostrarlo
  /// en la presencia en vivo (antes estaba hardcodeado como "Grace").
  Future<void> _loadMyUsername() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Fallback inmediato con los metadatos del registro
      final metaName = user.userMetadata?['username'] as String?;
      if (metaName != null && metaName.trim().isNotEmpty) {
        _myUsername = metaName.trim();
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('username, full_name')
          .eq('id', user.id)
          .maybeSingle();

      final name = (profile?['username'] as String?)?.trim();
      final fullName = (profile?['full_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        _myUsername = name;
      } else if (fullName != null && fullName.isNotEmpty) {
        _myUsername = fullName;
      }
    } catch (e) {
      debugPrint('No se pudo cargar el username: $e');
    }
  }

  void _stopFollowingByGesture() {
    if (_isFollowingUser && mounted) {
      setState(() => _isFollowingUser = false);
    }
  }

  /// Ajusta la precisión del GPS según el estado.
  /// Navegando o siguiendo al usuario: máxima precisión + filtro 5m (cámara
  /// fluida). Idle: precisión alta + filtro 15m (ahorra ~50% batería).
  geo.LocationSettings _gpsSettings() {
    final bool precise = _navigating || _isFollowingUser;
    final accuracy = precise
        ? geo.LocationAccuracy.bestForNavigation
        : geo.LocationAccuracy.high;
    final filter = precise ? 5 : 15;

    // Con tracking en segundo plano: servicio en primer plano (notificación
    // fija) para seguir contando km aunque la app no esté visible.
    if (_bgTrackingEnabled) {
      return geo.AndroidSettings(
        accuracy: accuracy,
        distanceFilter: filter,
        foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
          notificationTitle: 'Pedalea',
          notificationText: 'Contando tus kilómetros 🚴',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return geo.LocationSettings(accuracy: accuracy, distanceFilter: filter);
  }

  void _startFollowing() {
    if (_positionStreamSubscription != null) return;
    _positionStreamSubscription =
        geo.Geolocator.getPositionStream(
          locationSettings: _gpsSettings(),
        ).listen((position) async {
          if (!mounted) return;

          final curSpeedKmh = position.speed < 0 ? 0.0 : position.speed * 3.6;
          _speedNotifier.value = curSpeedKmh;

          // Detección de modo pasajero (auto/micro/metro) según la velocidad.
          _maybeHandlePassengerMode(curSpeedKmh);

          // Detección de choque por frenada imposible (solo pedaleando de verdad,
          // no en modo pasajero, donde frenar fuerte en auto/micro es normal).
          if (_fallDetectionEnabled && _modoActivo && !_isPassenger) {
            _checkSuddenDeceleration(curSpeedKmh, DateTime.now());
          }

          // Tracking de km — cuenta los desplazamientos reales del usuario.
          // NO exige el campo `speed` del GPS (en muchos Android llega en 0 y
          // hacía que no se contara nada): si no es fiable, la velocidad se
          // estima con distancia/tiempo entre fixes. En modo pasajero NO se
          // cuenta (esos km no son pedaleo).
          if (_modoActivo && !_isPassenger && _lastPosition != null) {
            final distM = geo.Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              position.latitude,
              position.longitude,
            );
            final fixAt = position.timestamp;
            final elapsedSec = _lastFixAt == null
                ? 0.0
                : fixAt.difference(_lastFixAt!).inMilliseconds / 1000.0;
            // Velocidad: usa la del GPS solo si es creíble; si no, la estima.
            final gpsSpeed = position.speed; // m/s
            final estSpeed = elapsedSec > 0 ? distM / elapsedSec : 0.0;
            final speedMs = (gpsSpeed > 0.3 && gpsSpeed < 30) ? gpsSpeed : estSpeed;
            final speedKmh = speedMs * 3.6;

            final accuracyOk = position.accuracy <= 50;
            final timeOk = elapsedSec >= 1 && elapsedSec <= 120;
            // 1,8 km/h descarta el jitter del GPS estando parado; 80 km/h
            // descarta saltos imposibles (rebote entre edificios, túneles).
            final speedOk = speedKmh >= 1.8 && speedKmh <= 80;

            if (distM >= 5 && distM < 500 && accuracyOk && timeOk && speedOk) {
              _sessionKm += distM / 1000;
              _unsavedKm += distM / 1000;
              if (speedKmh > _sessionMaxSpeedKmh && speedKmh <= 80) {
                _sessionMaxSpeedKmh = speedKmh;
              }
              _routePoints.add(position);
              // Mapa de calor personal (Plus): registra la zona, no el trazado.
              RideHeatService.addPoint(position.latitude, position.longitude);
              // Se persiste seguido (0,2 km) para no perder km si el SO mata
              // la app; el RPC de Supabase es incremental, no pesa.
              if (_unsavedKm >= 0.2) {
                _saveKmToProfile(_unsavedKm); // total histórico (Supabase)
                RideStatsService.addKm(_unsavedKm); // registro diario local
                RideStatsService.recordMaxSpeed(_sessionMaxSpeedKmh);
                RideStatsSyncService.instance.pushDelta(
                  km: _unsavedKm,
                  maxSpeedKmh: _sessionMaxSpeedKmh,
                ); // estadísticas por día + ranking (Supabase)
                _unsavedKm = 0;
                if (_showHeatmap) _updateHeatmapLayer(); // ~cada 200 m
              }
            }
          }
          _lastPosition = position;
          _lastFixAt = position.timestamp;

          // Refresca el HUD de navegación (ETA, progreso, distancia a la
          // próxima parada) en cada fix de GPS mientras se está navegando.
          if (_navigating && mounted) setState(() {});

          // Primer fix de GPS → cargar las capas por defecto alrededor del usuario.
          _maybeAutoLoadLayers();

          if (_navigating && _routeCoords.isNotEmpty) {
            _advanceRouteProgress(position.latitude, position.longitude);
          }

          // Alertas push de proximidad: avisar al acercarse a un incidente activo.
          if (_proximityAlertsEnabled) {
            _checkProximityAlerts(position);
          }

          if (_modoActivo && _shareLiveLocation) {
            await _presenceService.upsertMyLocation(
              position: position,
              username: _myUsername,
            );
          }

          if (mapboxMap != null && _isFollowingUser) {
            _moveCameraInstant(position);
          }
        },
        onError: (Object e) {
          // El stream muere si se revoca el permiso o se apaga el GPS. Sin
          // este handler la excepción quedaba sin capturar y el conteo de km
          // no volvía a arrancar en toda la sesión.
          debugPrint('Stream de GPS con error: $e');
          _positionStreamSubscription?.cancel();
          _positionStreamSubscription = null;
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) _startFollowing();
          });
        },
        cancelOnError: true);
  }

  /// Reinicia el stream de GPS con la configuración correcta para el estado actual.
  void _restartGps() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _startFollowing();
  }

  // ── Modo pasajero ─────────────────────────────────────────────────────────

  /// Evalúa la velocidad para entrar/salir del modo pasajero.
  void _maybeHandlePassengerMode(double speedKmh) {
    const highKmh = 32.0; // sobre esto, difícil que sea pedaleo
    const lowKmh = 6.0; // bajo esto, probablemente ya bajaste del vehículo
    final now = DateTime.now();

    if (_isPassenger) {
      _highSpeedSince = null;
      // Salir automáticamente si la velocidad baja de forma sostenida.
      if (speedKmh < lowKmh) {
        _lowSpeedSince ??= now;
        if (now.difference(_lowSpeedSince!) > const Duration(seconds: 15)) {
          _exitPassengerMode(auto: true);
        }
      } else {
        _lowSpeedSince = null;
      }
      return;
    }

    // No es pasajero: ¿lleva varios segundos a velocidad de vehículo?
    if (speedKmh >= highKmh) {
      _highSpeedSince ??= now;
      final sustained =
          now.difference(_highSpeedSince!) > const Duration(seconds: 6);
      final snoozed =
          _passengerSnoozeUntil != null && now.isBefore(_passengerSnoozeUntil!);
      if (sustained && !_passengerPromptOpen && !snoozed && mounted) {
        _showPassengerPrompt();
      }
    } else {
      _highSpeedSince = null;
    }
  }

  Future<void> _showPassengerPrompt() async {
    _passengerPromptOpen = true;
    HapticFeedback.mediumImpact();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => _PassengerPrompt(speedKmh: _speedNotifier.value.round()),
    );
    _passengerPromptOpen = false;
    if (!mounted) return;

    if (result == null || result == 'bici') {
      // Sigo pedaleando: no volver a preguntar por un rato.
      _passengerSnoozeUntil = DateTime.now().add(const Duration(minutes: 5));
      _highSpeedSince = null;
    } else {
      _enterPassengerMode(result); // 'auto' | 'micro' | 'metro'
    }
  }

  void _enterPassengerMode(String vehicle) {
    // Guardar km pendientes antes de dejar de contar.
    if (_unsavedKm > 0) {
      _saveKmToProfile(_unsavedKm);
      RideStatsService.addKm(_unsavedKm);
      RideStatsSyncService.instance.pushDelta(
        km: _unsavedKm,
        maxSpeedKmh: _sessionMaxSpeedKmh,
      );
      _unsavedKm = 0;
    }
    _fallService.stop(); // sin falsos positivos por frenadas del vehículo
    setState(() {
      _isPassenger = true;
      _passengerVehicle = vehicle;
      _lowSpeedSince = null;
      _highSpeedSince = null;
    });
  }

  void _exitPassengerMode({bool auto = false}) {
    if (_fallDetectionEnabled) _fallService.start(_onFallDetected);
    setState(() {
      _isPassenger = false;
      _lowSpeedSince = null;
      _highSpeedSince = null;
      // Tras salir, deja un pequeño margen antes de volver a preguntar.
      _passengerSnoozeUntil = DateTime.now().add(const Duration(seconds: 30));
    });
    if (auto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🚴 De vuelta en modo ciclista'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  ({String emoji, String label}) _vehicleInfo(String v) {
    switch (v) {
      case 'micro':
        return (emoji: '🚌', label: 'Micro');
      case 'metro':
        return (emoji: '🚇', label: 'Metro');
      default:
        return (emoji: '🚗', label: 'Auto');
    }
  }

  /// Cuánto se retrasa a propósito la posición de los demás ciclistas en el
  /// mapa: sigue sirviendo para ubicarse y juntarse a pedalear, pero nadie
  /// sabe tu punto EXACTO en este instante (defensa extra contra que alguien
  /// te espere en el camino, sumada al filtro de follow mutuo).
  static const _cyclistsDisplayDelay = Duration(seconds: 30);
  Timer? _cyclistsDelayTimer;

  void _listenToActiveCyclists() {
    _cyclistsSubscription?.cancel();
    _cyclistsSubscription = _presenceService.streamActiveCyclists().listen((
      cyclists,
    ) async {
      // Cada actualización se aplica recién ~30 s después de recibirla
      // (nunca antes que la anterior, así no se adelanta la posición real).
      _cyclistsDelayTimer?.cancel();
      _cyclistsDelayTimer = Timer(_cyclistsDisplayDelay, () {
        if (!mounted) return;
        _lastCyclists = cyclists;
        _updateCyclistsLayer(cyclists);
      });
    });
  }

  void _listenToEvents() {
    _eventsSubscription?.cancel();
    _eventsSubscription = _eventsService.streamUpcomingEvents().listen(
      (events) {
        debugPrint('📦 Eventos recibidos: ${events.length}');
        setState(() => _currentEvents = events);
        _updateEventsLayer(_visibleEventPinsForMap(events));
        CacheService.saveEvents(events); // Guardar en caché
      },
      onError: (error) {
        debugPrint('❌ Error stream eventos: $error');
        // Intentar usar caché si hay error de red
        final cached = CacheService.loadEvents(ignoreExpiry: true);
        if (cached != null && mounted) {
          setState(() => _currentEvents = cached);
          _updateEventsLayer(_visibleEventPinsForMap(cached));
        }
      },
    );
  }

  /// El pin de un evento en el mapa solo debe verlo quien creó el evento o
  /// ya está unido a él — no todos los usuarios ven todos los pines. Los
  /// demás pueden seguir descubriendo el evento desde "Próximos eventos".
  List<Map<String, dynamic>> _visibleEventPinsForMap(
    List<Map<String, dynamic>> events,
  ) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return const [];
    return events.where((event) {
      if (event['user_id'] == uid) return true;
      final participantsIds = List<String>.from(
        event['participants_ids'] ?? [],
      );
      return participantsIds.contains(uid);
    }).toList();
  }

  void _listenToAlerts() {
    _alertsSubscription?.cancel();
    _alertsSubscription = _alertsService.streamAlerts().listen(
      (alerts) {
        debugPrint('🚨 Alertas recibidas: ${alerts.length}');
        setState(() => _currentAlerts = alerts);
        _updateAlertsLayer(alerts);
        CacheService.saveAlerts(alerts); // Guardar en caché
      },
      onError: (error) {
        debugPrint('❌ Error stream alertas: $error');
        // Intentar usar caché si hay error de red
        final cached = CacheService.loadAlerts(ignoreExpiry: true);
        if (cached != null && mounted) {
          setState(() => _currentAlerts = cached);
          _updateAlertsLayer(cached);
        }
      },
    );
  }

  void _moveCameraInstant(geo.Position position) {
    if (mapboxMap == null) return;

    // El mapa se mantiene siempre orientado al norte (bearing forzado a 0
    // explícitamente para descartar que la rotación del mapa esté alterando
    // la percepción de la flecha). El puck NATIVO de Mapbox sigue rotando
    // la flecha solo con PuckBearing.HEADING — en paralelo, calculamos nuestra
    // propia versión corregida por declinación magnética, solo con fines de
    // diagnóstico (ver _kDiagPanel / _updateDiagnosticHeading).
    mapboxMap!.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 17.5,
        bearing: 0.0,
        pitch: 0.0,
      ),
    );

    _lastGeoPosition = position;
    _maybeRefreshDeclination(position);
    _updateTestConePosition(position);

    mapboxMap!.getCameraState().then((camState) {
      if (mounted) setState(() => _cameraBearingDeg = camState.bearing);
    });
  }

  Future<void> _setupUserPuck() async {
    if (mapboxMap == null) return;
    try {
      final Uint8List bikeBytes = (await rootBundle.load(
        "assets/icons/gps_puck_top.png",
      )).buffer.asUint8List();
      final Uint8List arrowBytes = (await rootBundle.load(
        "assets/icons/gps_puck_bearing.png",
      )).buffer.asUint8List();

      await mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          // El puck nativo de Mapbox rota según la brújula del teléfono
          // (PuckBearing.HEADING) — nunca según el rumbo GPS/movimiento.
          // topImage (la bici) queda SIEMPRE fija/vertical: Mapbox solo rota
          // bearingImage (el cono), por eso van en imágenes separadas.
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
          showAccuracyRing: false,
          pulsingEnabled: false,
          locationPuck: LocationPuck(
            locationPuck2D: DefaultLocationPuck2D(
              topImage: bikeBytes,
              bearingImage: arrowBytes,
              shadowImage: Uint8List.fromList([]),
              scaleExpression:
                  '["interpolate",["linear"],["zoom"],0,0.40,22,0.40]',
              opacity: 1.0,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error configurando puck personalizado: $e");
    }

    _startDiagnosticCompass();
  }

  // ── Diagnóstico de desfase por declinación magnética ───────────────────
  //
  // Mapbox usa el norte MAGNÉTICO crudo para PuckBearing.HEADING (confirmado
  // leyendo su código fuente nativo), sin corregir por declinación como sí
  // hace Google Maps. Esto es SOLO un panel de comparación — el puck nativo
  // (arriba) sigue siendo la única flecha visible en el mapa; no se dibuja
  // ningún marcador manual encima.
  static const bool _kEnableHeadingDiagnostics = false;
  static const bool _kShowHeadingDiagPanel = false;
  static const double _kHeadingSmoothingAlpha = 0.15;

  late final MethodChannel _geomagneticChannel = const MethodChannel(
    'com.pedalea.app/geomagnetic',
  );

  StreamSubscription<CompassEvent>? _diagCompassSub;
  geo.Position? _lastGeoPosition;
  double? _rawMagneticHeadingDeg;
  double? _correctedHeadingDeg;
  double? _compassAccuracy;
  double _declinationDeg = 0;
  double _cameraBearingDeg = 0;
  DateTime? _lastDeclinationFetch;
  geo.Position? _lastDeclinationPosition;

  // ── Modo B: cono manual (cian) rotado por nosotros con el heading
  // corregido, para comparar en vivo contra el cono nativo de Mapbox
  // (lime, Modo A). Se dibuja al lado del puck nativo, con un pequeño
  // desplazamiento de longitud, para que ambos se vean simultáneamente.
  PointAnnotationManager? _testConeManager;
  PointAnnotation? _testConeAnnotation;
  Uint8List? _testConeBytes;
  double? _lastRenderedTestHeading;
  static const double _kMinAngularMoveDeg = 1.0;
  static const double _kTestConeLonOffset = 0.00006; // ~5 m al este

  void _startDiagnosticCompass() {
    if (!_kEnableHeadingDiagnostics) return;
    _diagCompassSub?.cancel();
    _diagCompassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      _compassAccuracy = event.accuracy;
      _applyDiagnosticHeading(heading);
    });
    _setupTestCone();
  }

  Future<void> _setupTestCone() async {
    if (mapboxMap == null) return;
    try {
      _testConeBytes ??= (await rootBundle.load(
        "assets/icons/gps_puck_bearing_test.png",
      )).buffer.asUint8List();
      _testConeManager ??= await mapboxMap!.annotations
          .createPointAnnotationManager();

      final start = _lastGeoPosition;
      if (_testConeAnnotation == null && start != null) {
        _testConeAnnotation = await _testConeManager!.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(
                start.longitude + _kTestConeLonOffset,
                start.latitude,
              ),
            ),
            image: _testConeBytes,
            iconSize: 0.40,
            iconRotate: _correctedHeadingDeg ?? 0,
            iconAnchor: IconAnchor.CENTER,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error configurando cono de prueba (Modo B): $e');
    }
  }

  void _updateTestConePosition(geo.Position position) {
    final annotation = _testConeAnnotation;
    final manager = _testConeManager;
    if (annotation == null || manager == null) return;
    annotation.geometry = Point(
      coordinates: Position(
        position.longitude + _kTestConeLonOffset,
        position.latitude,
      ),
    );
    manager.update(annotation);
  }

  void _updateTestConeRotation(double correctedHeadingDeg) {
    final annotation = _testConeAnnotation;
    final manager = _testConeManager;
    if (annotation == null || manager == null) return;

    // Filtro mínimo de movimiento angular: evita repintar por ruido.
    final prev = _lastRenderedTestHeading;
    if (prev != null) {
      double diff = (correctedHeadingDeg - prev) % 360;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      if (diff.abs() < _kMinAngularMoveDeg) return;
    }
    _lastRenderedTestHeading = correctedHeadingDeg;

    annotation.iconRotate = correctedHeadingDeg;
    manager.update(annotation);
  }

  /// Suavizado circular (media móvil exponencial) que respeta el
  /// wrap-around 359°→0°. NO es un promedio lineal normal de grados —
  /// eso rompería justo al cruzar el norte.
  double _smoothCircular(double? prev, double next, double alpha) {
    if (prev == null) return next;
    double diff = (next - prev) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    double result = (prev + alpha * diff) % 360;
    if (result < 0) result += 360;
    return result;
  }

  double _normalizeHeading(double value) => ((value % 360) + 360) % 360;

  void _applyDiagnosticHeading(double magneticHeadingDeg) {
    final prevRaw = _rawMagneticHeadingDeg;
    final smoothedRaw = _smoothCircular(
      prevRaw,
      magneticHeadingDeg,
      _kHeadingSmoothingAlpha,
    );
    final corrected = _normalizeHeading(smoothedRaw + _declinationDeg);

    // Evita reconstruir la UI por cada micro-ruido del sensor: solo si el
    // cambio visible es >= 0.5°.
    final changedEnough =
        prevRaw == null ||
        (smoothedRaw - prevRaw).abs() >= 0.5 ||
        _correctedHeadingDeg == null ||
        (corrected - _correctedHeadingDeg!).abs() >= 0.5;

    _rawMagneticHeadingDeg = smoothedRaw;
    _correctedHeadingDeg = corrected;

    _updateTestConeRotation(corrected);

    if (changedEnough && mounted) setState(() {});
  }

  /// La declinación solo depende de ubicación/fecha, no del sensor, así que
  /// se recalcula apenas cuando cambia la posición >~500 m (o no hay dato
  /// previo) — nunca en cada frame.
  Future<void> _maybeRefreshDeclination(geo.Position position) async {
    final prev = _lastDeclinationPosition;
    final now = DateTime.now();
    final tooSoon =
        _lastDeclinationFetch != null &&
        now.difference(_lastDeclinationFetch!) < const Duration(seconds: 20);
    final movedEnough =
        prev == null ||
        geo.Geolocator.distanceBetween(
              prev.latitude,
              prev.longitude,
              position.latitude,
              position.longitude,
            ) >
            500;

    if (!movedEnough && tooSoon) return;

    try {
      final result = await _geomagneticChannel.invokeMethod<double>(
        'declination',
        {
          'lat': position.latitude,
          'lon': position.longitude,
          'alt': position.altitude,
        },
      );
      if (result != null) {
        _declinationDeg = result;
        _lastDeclinationFetch = now;
        _lastDeclinationPosition = position;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error calculando declinación magnética: $e');
    }
  }

  Widget _buildHeadingDiagnosticPanel() {
    if (!_kShowHeadingDiagPanel) return const SizedBox.shrink();
    final raw = _rawMagneticHeadingDeg;
    final corrected = _correctedHeadingDeg;
    final diff = (raw != null && corrected != null)
        ? _normalizeHeading(corrected - raw)
        : null;

    String fmt(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';

    return Positioned(
      top: 100,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'DIAGNÓSTICO DE HEADING',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Heading magnético (crudo): ${fmt(raw)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Text(
              'Declinación calculada: ${fmt(_declinationDeg)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Text(
              'Heading corregido (geográfico): ${fmt(corrected)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Text(
              'Bearing de cámara: ${fmt(_cameraBearingDeg)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Text(
              'Diferencia nativo vs corregido: ${fmt(diff)}',
              style: const TextStyle(
                color: Colors.lime,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Precisión del sensor (accuracy): ${fmt(_compassAccuracy)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cono LIME = Mapbox nativo (Modo A)  ·  Cono CIAN = manual corregido (Modo B)',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ensureCyclistsIcon() async {
    if (mapboxMap == null || !_styleIsLoaded || _cyclistsIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_cyclistsIconImageId)) {
        _cyclistsIconAdded = true;
        return;
      }
      final ByteData data = await rootBundle.load("assets/icono_ciclista.png");
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      await style.addStyleImage(
        _cyclistsIconImageId,
        1.0,
        MbxImage(
          width: frame.image.width,
          height: frame.image.height,
          data: byteData.buffer.asUint8List(),
        ),
        false,
        [],
        [],
        null,
      );
      _cyclistsIconAdded = true;
    } catch (e) {
      debugPrint("Error agregando icono de ciclistas: $e");
    }
  }

  /// Devuelve true si el ícono quedó listo para usarse (ya existía o se
  /// agregó ahora). Captura la instancia de mapboxMap y la "generación"
  /// actual al empezar, y revisa después de CADA await que sigan siendo las
  /// mismas — si el mapa se recreó mientras esta llamada estaba en curso
  /// (cambio de estilo, hot restart, remount del widget), aborta en vez de
  /// llamar a un canal nativo que ya no existe.
  Future<bool> _ensureEventsIcon() async {
    final map = mapboxMap;
    final generation = _mapGeneration;
    if (!mounted ||
        map == null ||
        !_styleIsLoaded ||
        !_routeIsCurrent ||
        _eventsIconAdded) {
      return false;
    }

    bool stillValid() =>
        mounted &&
        mapboxMap == map &&
        _mapGeneration == generation &&
        _styleIsLoaded &&
        _routeIsCurrent;

    try {
      final style = map.style;
      final alreadyExists = await style.hasStyleImage(_eventsIconImageId);
      if (!stillValid()) return false;

      if (alreadyExists) {
        _eventsIconAdded = true;
        return true;
      }

      // Mismo enfoque que los íconos de alertas: dibujar con Canvas en vez
      // de decodificar un PNG de assets — un paso menos, y así se comporta
      // igual que un tipo de pin que nunca tuvo el error del canal.
      final bytes = await _renderAlertIcon(Colors.orange, Icons.event);
      if (!stillValid()) return false;

      await style.addStyleImage(
        _eventsIconImageId,
        1.0, // scale 1:1 → 80dp nativos, igual que las alertas
        MbxImage(width: 80, height: 80, data: bytes),
        false,
        [],
        [],
        null,
      );
      _eventsIconAdded = true;
      debugPrint('✅ Ícono de eventos registrado');
      return true;
    } on PlatformException catch (e) {
      debugPrint(
        'Error nativo agregando ícono de eventos: ${e.code} | ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint("Error agregando icono de eventos: $e");
      return false;
    }
  }

  /// Dibuja un círculo de color con el ícono Material encima y lo devuelve como PNG.
  Future<Uint8List> _renderAlertIcon(Color color, IconData iconData) async {
    const double size = 80;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Sombra exterior
    final shadowPaint = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2 + 3),
      size / 2 - 2,
      shadowPaint,
    );

    // Relleno del círculo
    final fillPaint = ui.Paint()..color = color;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2 - 2,
      fillPaint,
    );

    // Borde blanco
    final borderPaint = ui.Paint()
      ..color = Colors.white
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(
      const ui.Offset(size / 2, size / 2),
      size / 2 - 2,
      borderPaint,
    );

    // Ícono Material centrado
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 38,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      ui.Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Dibuja un pin tipo "globito" (cabeza circular con ícono + punta abajo).
  /// La punta apunta exactamente a la ubicación (usar iconAnchor BOTTOM).
  Future<Uint8List> _renderPinIcon(Color color, IconData iconData) async {
    const double w = 84;
    const double h = 108;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final center = const ui.Offset(w / 2, w / 2 + 2); // centro de la cabeza
    final headR = w / 2 - 6;
    final tip = const ui.Offset(w / 2, h - 3); // punta inferior

    // Sombra
    final shadow = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 3), headR, shadow);

    // Cuerpo del pin: triángulo de color hacia la punta + aro de color
    final body = ui.Path()
      ..moveTo(center.dx - headR * 0.6, center.dy + headR * 0.72)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(center.dx + headR * 0.6, center.dy + headR * 0.72)
      ..close();
    final colorPaint = ui.Paint()..color = color;
    canvas.drawPath(body, colorPaint);
    canvas.drawCircle(center, headR, colorPaint); // aro de color exterior

    // Cabeza blanca (badge) donde va el ícono/logo, para que resalte
    final whitePaint = ui.Paint()..color = Colors.white;
    canvas.drawCircle(center, headR - 5, whitePaint);

    // Ícono en el color de la categoría, centrado en la cabeza blanca
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 38,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      ui.Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _ensureAlertsIcon() async {
    if (mapboxMap == null || !_styleIsLoaded) return;
    try {
      final style = mapboxMap!.style;

      final alertTypes = <String, (Color, IconData)>{
        'danger': (Colors.red, Icons.warning_rounded),
        'theft': (Colors.purple, Icons.no_accounts),
        'construction': (Colors.orange, Icons.construction),
        'accident': (Colors.deepOrange, Icons.car_crash),
        'other': (Colors.blue, Icons.info),
      };

      for (final entry in alertTypes.entries) {
        final imageId = 'alert-icon-${entry.key}';
        if (await style.hasStyleImage(imageId)) continue;

        final bytes = await _renderAlertIcon(entry.value.$1, entry.value.$2);
        await style.addStyleImage(
          imageId,
          1.0, // scale 1:1 → 80dp nativos
          MbxImage(width: 80, height: 80, data: bytes),
          false,
          [],
          [],
          null,
        );
        debugPrint('✅ Ícono de alerta "$imageId" registrado');
      }

      _alertsIconAdded = true;
    } catch (e) {
      debugPrint("Error agregando íconos de alertas: $e");
    }
  }

  Future<void> _removeSelectionLayer() async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      if (await style.styleLayerExists(_selectionLayerId)) {
        await style.removeStyleLayer(_selectionLayerId);
      }
      if (await style.styleSourceExists(_selectionSourceId)) {
        await style.removeStyleSource(_selectionSourceId);
      }
      _selectionLayerAdded = false;
    } catch (e) {
      debugPrint('❌ Error removiendo capa de selección: $e');
    }
  }

  // ✅ Mostrar formulario de alerta en el punto de long press
  void _showAlertFormAtLocation(Point point) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SimpleAlertFormDialog(point: point),
    );

    if (result != null && mounted) {
      await _createAlertAtLocation(point, result);
    }
  }

  // ✅ Crear alerta directamente en la ubicación
  Future<void> _createAlertAtLocation(
    Point point,
    Map<String, dynamic> alertData,
  ) async {
    if (_isConfirming) return;
    _isConfirming = true;

    try {
      // Subir foto a Supabase Storage si existe
      String? photoUrl;
      final photoFile = alertData['photoFile'] as File?;
      if (photoFile != null) {
        try {
          final userId =
              Supabase.instance.client.auth.currentUser?.id ?? 'anon';
          final fileName =
              '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
          await Supabase.instance.client.storage
              .from('alert-photos')
              .upload(fileName, photoFile);
          photoUrl = Supabase.instance.client.storage
              .from('alert-photos')
              .getPublicUrl(fileName);
          debugPrint('📸 Foto subida: $photoUrl');
        } catch (e) {
          debugPrint('⚠️ Error subiendo foto (continúa sin foto): $e');
        }
      }

      final newAlert = await _alertsService.createAlert(
        type: alertData['type'],
        title: alertData['title'],
        description: alertData['description'],
        latitude: point.coordinates.lat.toDouble(),
        longitude: point.coordinates.lng.toDouble(),
        locationName: alertData['locationName'],
        photoUrl: photoUrl,
      );

      if (newAlert != null) {
        setState(() {
          _currentAlerts.add(newAlert);
        });
        await _updateAlertsLayer(_currentAlerts);

        // Mostrar pin verde temporalmente
        await _showTemporaryPin(point);

        debugPrint('✅ Alerta guardada en BD y mostrada en mapa');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Alerta creada con éxito'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        _checkAchievementsAndNotify();
      }
    } catch (e) {
      debugPrint('❌ Error creando alerta: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      _isConfirming = false;
    }
  }

  // ✅ Mostrar pin temporal para feedback visual
  Future<void> _showTemporaryPin(Point point) async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;

      final features = [
        {
          "type": "Feature",
          "properties": {"type": "temp_pin"},
          "geometry": {
            "type": "Point",
            "coordinates": [point.coordinates.lng, point.coordinates.lat],
          },
        },
      ];

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      final tempSourceId = "temp-pin-source";
      final tempLayerId = "temp-pin-layer";

      if (await style.styleSourceExists(tempSourceId)) {
        await style.removeStyleSource(tempSourceId);
      }
      if (await style.styleLayerExists(tempLayerId)) {
        await style.removeStyleLayer(tempLayerId);
      }

      await style.addSource(
        GeoJsonSource(id: tempSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: tempLayerId,
          sourceId: tempSourceId,
          iconImage: "marker-15",
          iconSize: 2.5,
          iconColor: Colors.greenAccent.value,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      // Eliminar el pin después de 2 segundos
      Future.delayed(const Duration(seconds: 2), () async {
        if (await style.styleLayerExists(tempLayerId)) {
          await style.removeStyleLayer(tempLayerId);
        }
        if (await style.styleSourceExists(tempSourceId)) {
          await style.removeStyleSource(tempSourceId);
        }
      });
    } catch (e) {
      debugPrint('❌ Error mostrando pin temporal: $e');
    }
  }

  Future<void> _updateSelectionLayer() async {
    if (mapboxMap == null || _selectedLocation == null) return;

    try {
      final style = mapboxMap!.style;

      final features = [
        {
          "type": "Feature",
          "properties": {"type": "selection"},
          "geometry": {
            "type": "Point",
            "coordinates": [
              _selectedLocation!.coordinates.lng,
              _selectedLocation!.coordinates.lat,
            ],
          },
        },
      ];

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      if (await style.styleSourceExists(_selectionSourceId)) {
        await style.removeStyleSource(_selectionSourceId);
      }
      if (await style.styleLayerExists(_selectionLayerId)) {
        await style.removeStyleLayer(_selectionLayerId);
      }

      await style.addSource(
        GeoJsonSource(id: _selectionSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _selectionLayerId,
          sourceId: _selectionSourceId,
          iconImage: "marker-15",
          iconSize: 2.5,
          iconColor: Colors.greenAccent.value,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      _selectionLayerAdded = true;
      debugPrint('✅ Pin de selección actualizado');
    } catch (e) {
      debugPrint('❌ Error actualizando capa de selección: $e');
    }
  }

  Future<void> _updateEventsLayer(List<Map<String, dynamic>> events) async {
    // Solo el REGISTRO del ícono (_ensureEventsIcon) necesita esperar a que
    // el estilo/ruta estén listos — ese es el único paso que puede pegarle a
    // un canal nativo todavía no disponible. Mostrar/ocultar el pin (agregar
    // o quitar el source/layer según los eventos actuales) debe poder correr
    // siempre que haya un mapa, si no, un "Salir del evento" o un evento
    // recién creado se queda sin reflejar hasta reiniciar la app.
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      // Best-effort: si el ícono todavía no está listo, se sigue igual —
      // _ensureEventsIcon queda reintentando solo en la próxima llamada.
      await _ensureEventsIcon();
      if (!mounted || mapboxMap == null) return;

      final features = <Map<String, dynamic>>[];
      for (var event in events) {
        final lat = (event["latitude"] as num?)?.toDouble();
        final lng = (event["longitude"] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        features.add({
          "type": "Feature",
          "properties": {"id": event["id"], "title": event["title"]},
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat],
          },
        });
      }

      if (features.isEmpty) {
        if (await style.styleLayerExists(_eventsLayerId)) {
          await style.removeStyleLayer(_eventsLayerId);
        }
        if (await style.styleSourceExists(_eventsSourceId)) {
          await style.removeStyleSource(_eventsSourceId);
        }
        return;
      }

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      if (await style.styleLayerExists(_eventsLayerId)) {
        await style.removeStyleLayer(_eventsLayerId);
      }
      if (await style.styleSourceExists(_eventsSourceId)) {
        await style.removeStyleSource(_eventsSourceId);
      }

      await style.addSource(
        GeoJsonSource(id: _eventsSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _eventsLayerId,
          sourceId: _eventsSourceId,
          iconImage: _eventsIconImageId,
          iconSize:
              0.55, // más grande que las alertas (28dp) para destacar que es un evento
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error actualizando eventos: $e');
    }
  }

  Future<void> _updateAlertsLayer(List<Map<String, dynamic>> alerts) async {
    if (mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;
      await _ensureAlertsIcon();

      final features = <Map<String, dynamic>>[];
      for (var alert in alerts) {
        final lat = (alert["latitude"] as num?)?.toDouble();
        final lng = (alert["longitude"] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final alertType = alert["type"] as String? ?? 'other';
        final validTypes = {'danger', 'theft', 'construction', 'accident'};
        final iconId = validTypes.contains(alertType)
            ? 'alert-icon-$alertType'
            : 'alert-icon-other';

        features.add({
          "type": "Feature",
          "properties": {
            "id": alert["id"],
            "type": alertType,
            "icon_id": iconId,
            "title": alert["title"],
            "description": alert["description"],
            "user_name": alert["user_name"],
            "votes_up": alert["votes_up"],
            "votes_down": alert["votes_down"],
          },
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat],
          },
        });
      }

      if (features.isEmpty) {
        if (await style.styleLayerExists(_alertsLayerId)) {
          await style.removeStyleLayer(_alertsLayerId);
        }
        if (await style.styleSourceExists(_alertsSourceId)) {
          await style.removeStyleSource(_alertsSourceId);
        }
        _alertsLayerAdded = false;
        return;
      }

      final featureCollection = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });

      // IMPORTANTE: primero capa, después source (orden obligatorio en Mapbox)
      if (await style.styleLayerExists(_alertsLayerId)) {
        await style.removeStyleLayer(_alertsLayerId);
      }
      if (await style.styleSourceExists(_alertsSourceId)) {
        await style.removeStyleSource(_alertsSourceId);
      }

      await style.addSource(
        GeoJsonSource(id: _alertsSourceId, data: featureCollection),
      );

      await style.addLayer(
        SymbolLayer(
          id: _alertsLayerId,
          sourceId: _alertsSourceId,
          iconImage: 'alert-icon-other', // se sobreescribe abajo
          iconSize: 0.35, // 80dp × 0.35 = 28dp
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      // Ícono correcto según tipo del feature
      await style.setStyleLayerProperty(
        _alertsLayerId,
        'icon-image',
        jsonEncode(['get', 'icon_id']),
      );

      _alertsLayerAdded = true;
    } catch (e) {
      debugPrint('❌ Error actualizando alertas: $e');
    }
  }

  void _showLongPressIndicator(Offset position) {
    _removeLongPressIndicator();
    _longPressOverlay = OverlayEntry(
      builder: (_) => _LongPressRipple(position: position),
    );
    Overlay.of(context).insert(_longPressOverlay!);
  }

  void _removeLongPressIndicator() {
    _longPressOverlay?.remove();
    _longPressOverlay = null;
  }

  // Tap corto: muestra info de la alerta/evento tocado
  Future<void> _onMapTap(Point point) async {
    // Modo planificador: añadir parada
    if (_routePlannerOpen && _routeAddMode) {
      _addRouteWp(point);
      return;
    }
    if (mapboxMap == null) return;
    try {
      final screenPos = await mapboxMap!.pixelForCoordinate(point);
      debugPrint('🖱️ Tap en pantalla: (${screenPos.x}, ${screenPos.y})');

      final features = await mapboxMap!.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: screenPos.x - 50, y: screenPos.y - 50),
            max: ScreenCoordinate(x: screenPos.x + 50, y: screenPos.y + 50),
          ),
        ),
        RenderedQueryOptions(
          layerIds: [
            _alertsLayerId,
            _eventsLayerId,
            _parkingLyrId,
            _bicimetroLyrId,
            _servicesLyrId,
            _crvLyrId,
            _cyclistsLayerId,
          ],
          filter: null,
        ),
      );

      debugPrint('🔍 Features encontrados: ${features.length}');

      // Elegir el pin MÁS CERCANO al toque (no el primero), para abrir
      // exactamente el que el usuario apuntó aunque toque un poco al lado.
      final tapLng = point.coordinates.lng.toDouble();
      final tapLat = point.coordinates.lat.toDouble();
      Map<String, dynamic>? best;
      List<String> bestLayers = [];
      double bestDist = double.infinity;

      for (var featureInfo in features) {
        final inLayers = featureInfo?.layers ?? [];
        final feature = featureInfo?.queriedFeature.feature;
        if (feature == null) continue;
        final rawProps = feature["properties"];
        if (rawProps == null) continue;
        final props = Map<String, dynamic>.from(rawProps as Map);

        double dist = 0;
        final geom = feature["geometry"];
        if (geom is Map && geom["coordinates"] is List) {
          final c = geom["coordinates"] as List;
          if (c.length >= 2) {
            final dLng = (c[0] as num).toDouble() - tapLng;
            final dLat = (c[1] as num).toDouble() - tapLat;
            dist = dLng * dLng + dLat * dLat;
          }
        }
        if (dist < bestDist) {
          bestDist = dist;
          best = props;
          bestLayers = List<String>.from(inLayers.whereType<String>());
        }
      }

      if (best == null) return;

      if (bestLayers.contains(_parkingLyrId)) {
        _showBikeParkingModal(best);
        return;
      }
      if (bestLayers.contains(_cyclistsLayerId)) {
        _showCyclistModal(best);
        return;
      }
      if (bestLayers.contains(_servicesLyrId)) {
        _showBikeServiceModal(best);
        return;
      }
      if (bestLayers.contains(_crvLyrId)) {
        _showCicloRecreoModal(best);
        return;
      }
      if (bestLayers.contains(_bicimetroLyrId)) {
        _showBicimetroModal(best);
        return;
      }

      final idStr = best["id"]?.toString() ?? '';
      if (idStr.isNotEmpty) {
        final alert = _currentAlerts.firstWhere(
          (a) => a["id"].toString() == idStr,
          orElse: () => {},
        );
        if (alert.isNotEmpty) {
          _showAlertModal(alert);
          return;
        }
        final event = _currentEvents.firstWhere(
          (e) => e["id"].toString() == idStr,
          orElse: () => {},
        );
        if (event.isNotEmpty) {
          _showEventModal(event);
          return;
        }
      }
    } catch (e) {
      debugPrint('❌ Error procesando tap: $e');
    }
  }

  // ✅ MANEJAR LONG PRESS para crear alerta
  void _onLongPress(Point point) {
    debugPrint(
      '📍 Long press detectado en: ${point.coordinates.lat}, ${point.coordinates.lng}',
    );
    _showAlertFormAtLocation(point);
  }

  void _showFullPhoto(BuildContext ctx, String url) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlertModal(Map<String, dynamic> alert) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final isCreator = alert['user_id'] == userId;
    final hasVotedUp = (alert['voters_up'] as List?)?.contains(userId) ?? false;
    final hasVotedDown =
        (alert['voters_down'] as List?)?.contains(userId) ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getAlertColor(alert['type']).withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getAlertColor(alert['type']),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getAlertIcon(alert['type']),
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert['title'],
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          alert['location_name'] ?? 'Ubicación sin nombre',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Foto de la alerta
            if (alert['photo_url'] != null &&
                (alert['photo_url'] as String).isNotEmpty)
              GestureDetector(
                onTap: () => _showFullPhoto(context, alert['photo_url']),
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: Image.network(
                    alert['photo_url'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            height: 180,
                            color: Colors.white.withOpacity(0.05),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.greenAccent,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (alert['description'] != null &&
                      alert['description'].isNotEmpty) ...[
                    const Text(
                      'Descripción',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert['description'],
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Icon(
                        Icons.person,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Reportado por: ${alert['user_name']}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(DateTime.parse(alert['created_at'])),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildVoteButton(
                        icon: Icons.thumb_up,
                        count: alert['votes_up'] ?? 0,
                        isActive: hasVotedUp,
                        color: Colors.green,
                        onTap: () => _handleVote(alert['id'], 'up', hasVotedUp),
                      ),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _buildVoteButton(
                        icon: Icons.thumb_down,
                        count: alert['votes_down'] ?? 0,
                        isActive: hasVotedDown,
                        color: Colors.red,
                        onTap: () =>
                            _handleVote(alert['id'], 'down', hasVotedDown),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (isCreator)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              final confirm = await _showDeleteAlertDialog();
                              if (confirm != true) return;
                              final id = alert['id'].toString();
                              final ok = await _alertsService.deleteAlert(
                                alert['id'],
                              );
                              if (!ok) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '⚠️ No se pudo eliminar: falta permiso en la base de datos (RLS)',
                                    ),
                                    backgroundColor: Colors.redAccent,
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                                return;
                              }
                              // Quitar el pin de inmediato (sin esperar al tiempo real)
                              if (mounted) {
                                setState(
                                  () => _currentAlerts.removeWhere(
                                    (a) => a['id'].toString() == id,
                                  ),
                                );
                              }
                              await _updateAlertsLayer(_currentAlerts);
                              CacheService.saveAlerts(_currentAlerts);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('🗑️ Alerta eliminada'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Eliminar alerta',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required int count,
    required bool isActive,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? color : Colors.grey, size: 28),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: isActive ? color : Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleVote(
    String alertId,
    String voteType,
    bool hasVoted,
  ) async {
    Navigator.pop(context);

    if (hasVoted) {
      if (voteType == 'up') {
        await _alertsService.removeVoteUp(alertId);
      } else {
        await _alertsService.removeVoteDown(alertId);
      }
    } else {
      if (voteType == 'up') {
        await _alertsService.voteUp(alertId);
      } else {
        await _alertsService.voteDown(alertId);
      }
    }
  }

  Future<bool?> _showDeleteAlertDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Eliminar alerta',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '¿Estás seguro de que quieres eliminar esta alerta?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Sí, eliminar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAlertColor(String type) {
    switch (type) {
      case 'danger':
        return Colors.red;
      case 'theft':
        return Colors.purple;
      case 'construction':
        return Colors.orange;
      case 'accident':
        return Colors.deepOrange;
      default:
        return Colors.blue;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type) {
      case 'danger':
        return Icons.warning;
      case 'theft':
        return Icons.no_accounts;
      case 'construction':
        return Icons.construction;
      case 'accident':
        return Icons.car_crash;
      default:
        return Icons.info;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return 'Hace ${difference.inDays} día${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Ahora mismo';
    }
  }

  /// Pide la contraseña de un evento privado. Devuelve null si cancela.
  Future<String?> _askEventPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0E0E18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Evento privado',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pide la contraseña a quien lo creó para unirte.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Contraseña',
                  hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white38,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Unirme'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEventModal(Map<String, dynamic> event) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final participantsIds = List<String>.from(event['participants_ids'] ?? []);
    final isCreator = event['user_id'] == uid;
    final isJoined = participantsIds.contains(uid);
    final maxParticipants = event['max_participants'] as int?;
    final participantsCount =
        event['participants_count'] as int? ?? participantsIds.length;
    final isFull =
        maxParticipants != null && participantsCount >= maxParticipants;
    final eventDate = DateTime.tryParse(
      event['event_date']?.toString() ?? '',
    )?.toLocal();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> handleJoin() async {
            String? password;
            if (event['is_private'] == true) {
              if (!SubscriptionService.instance.isPlus.value) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PaywallPage(
                      reason:
                          'Unirte a eventos privados es una función de Pedalea Plus.',
                    ),
                  ),
                );
                return;
              }
              password = await _askEventPassword();
              if (password == null) return;
            }
            final result = await _eventsService.joinEvent(
              event['id'].toString(),
              password: password,
            );
            if (result == 'ok') {
              setModalState(() => participantsIds.add(uid!));
              await _refreshEventsNow(); // muestra/oculta el pin al instante
            } else if (result == 'wrong_password' && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Contraseña incorrecta')),
              );
            }
          }

          Future<void> handleLeave() async {
            final confirmed = await confirmWithWord(
              context,
              title: 'Salir del evento',
              message: 'Vas a salir de este evento y perderás tu cupo.',
              requiredWord: 'SALIR',
              confirmLabel: 'Salir',
              confirmColor: Colors.orange,
            );
            if (!confirmed) return;

            final ok = await _eventsService.leaveEvent(event['id'].toString());
            if (ok) {
              setModalState(() => participantsIds.remove(uid));
              await _refreshEventsNow();
            }
          }

          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E18),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.13)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.event,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                event['title']?.toString() ?? 'Evento',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (event['is_private'] == true) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.lock,
                                size: 15,
                                color: Colors.amber,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if ((event['description']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      event['description'].toString(),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (eventDate != null)
                    _infoRow(
                      Icons.calendar_today,
                      'Cuándo',
                      '${eventDate.day}/${eventDate.month}/${eventDate.year} ${eventDate.hour.toString().padLeft(2, '0')}:${eventDate.minute.toString().padLeft(2, '0')}',
                    ),
                  if ((event['location_name']?.toString() ?? '').isNotEmpty)
                    _infoRow(
                      Icons.place,
                      'Lugar',
                      event['location_name'].toString(),
                    ),
                  _infoRow(
                    Icons.people,
                    'Participantes',
                    maxParticipants != null
                        ? '$participantsCount / $maxParticipants'
                        : '$participantsCount',
                  ),
                  const SizedBox(height: 16),
                  EventPhotoGallery(
                    eventId: event['id'].toString(),
                    accentColor: Colors.orange,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (!isCreator)
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              onPressed: isJoined
                                  ? handleLeave
                                  : (isFull ? null : handleJoin),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isJoined
                                    ? Colors.white10
                                    : Colors.greenAccent,
                                foregroundColor: isJoined
                                    ? Colors.white
                                    : Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                isJoined
                                    ? 'Salir del evento'
                                    : (isFull ? 'Sin cupo' : 'Unirme'),
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!isCreator) const SizedBox(width: 10),
                      if (isJoined || isCreator)
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EventChatPage(
                                      eventId: event['id'].toString(),
                                      eventTitle:
                                          event['title']?.toString() ??
                                          'Evento',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                              ),
                              label: const Text('Chatear'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.greenAccent,
                                side: const BorderSide(
                                  color: Colors.greenAccent,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpeedometer() {
    return ValueListenableBuilder<double>(
      valueListenable: _speedNotifier,
      builder: (context, speed, _) {
        String? mensaje;
        Color mensajeColor = Colors.orangeAccent;
        if (_isPassenger) {
          final v = _vehicleInfo(_passengerVehicle);
          mensaje = "${v.emoji} Vas en ${v.label} · no cuenta como pedaleo";
          mensajeColor = Colors.lightBlueAccent;
        } else if (speed > 35) {
          mensaje = "⚠️ ¡MUY RÁPIDO! Considera reducir la velocidad";
          mensajeColor = Colors.redAccent;
        } else if (speed > 30) {
          mensaje = "💧 Hidrátate, vas muy rápido";
          mensajeColor = Colors.orangeAccent;
        } else if (speed > 25) {
          mensaje = "⚡ Buen ritmo, ¡sigue así!";
          mensajeColor = Colors.greenAccent;
        } else if (speed > 0 && speed <= 25) {
          mensaje = "🚴 Pedalea, ¡buen paseo!";
          mensajeColor = Colors.lightBlueAccent;
        }
        final accentColor = _isDayMode
            ? const Color(0xFF00A86B)
            : Colors.greenAccent;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mensaje != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: _dayNightBox(radius: 20),
                child: Text(
                  mensaje,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _isDayMode
                        ? mensajeColor.withOpacity(0.85)
                        : mensajeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              width: 85,
              height: 85,
              decoration: _dayNightBox(radius: 50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    speed.toStringAsFixed(0),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: _overlayText,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    "km/h",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    final statusColor = _isPassenger
        ? Colors.lightBlueAccent
        : Colors.greenAccent;
    final vInfo = _vehicleInfo(_passengerVehicle);
    final statusIcon = _isPassenger
        ? (_passengerVehicle == 'micro'
              ? Icons.directions_bus_rounded
              : _passengerVehicle == 'metro'
              ? Icons.subway_rounded
              : Icons.directions_car_rounded)
        : Icons.directions_bike;
    final statusText = _isPassenger
        ? 'PASAJERO · ${vInfo.label.toUpperCase()}'
        : 'CICLISTA ACTIVO';
    return Container(
      decoration: _dayNightBox(radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            statusIcon,
            color: _isPassenger
                ? Colors.lightBlue
                : (_isDayMode ? const Color(0xFF00A86B) : Colors.greenAccent),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _overlayText,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (_isPassenger)
            GestureDetector(
              onTap: () => _exitPassengerMode(),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.4),
                  ),
                ),
                child: const Text(
                  '🚴 Pedalear',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            WeatherPill(isDayMode: _isDayMode),
        ],
      ),
    );
  }

  void _resetNorth() {
    if (mapboxMap != null) {
      mapboxMap!.setCamera(CameraOptions(bearing: 0.0));
    }
  }

  // ── Planificador de rutas ─────────────────────────────────────────────────

  void _addRouteWp(Point point) {
    setState(() {
      _routeWps.add(
        _RouteWp(
          lat: point.coordinates.lat.toDouble(),
          lng: point.coordinates.lng.toDouble(),
          label: 'Parada ${_routeWps.length + 1}',
        ),
      );
      _routeAddMode = false;
      _routeDistKm = null;
      _routeDurMin = null;
    });
    _redrawRoutePins();
  }

  Future<void> _redrawRoutePins() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpWpLyr)) {
        await style.removeStyleLayer(_rpWpLyr);
      }
      if (await style.styleSourceExists(_rpWpSrc)) {
        await style.removeStyleSource(_rpWpSrc);
      }
      if (_routeWps.isEmpty) return;
      final lastIdx = _routeWps.length - 1;
      final features = _routeWps
          .asMap()
          .entries
          .map(
            (e) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [e.value.lng, e.value.lat],
              },
              'properties': {
                'idx': e.key + 1,
                'isFirst': e.key == 0,
                'isLast': e.key == lastIdx,
              },
            },
          )
          .toList();
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
      });
      await style.addSource(GeoJsonSource(id: _rpWpSrc, data: fc));
      await style.addLayer(
        CircleLayer(
          id: _rpWpLyr,
          sourceId: _rpWpSrc,
          circleRadius: 14.0,
          circleColor: Colors.greenAccent.value,
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
      // Origen verde, destino rojo (más grande), intermedios naranjo.
      await style.setStyleLayerProperty(
        _rpWpLyr,
        'circle-color',
        jsonEncode([
          'case',
          ['get', 'isFirst'],
          '#00E676',
          ['get', 'isLast'],
          '#FF1744',
          '#FF9100',
        ]),
      );
      await style.setStyleLayerProperty(
        _rpWpLyr,
        'circle-radius',
        jsonEncode([
          'case',
          ['get', 'isLast'],
          18.0,
          13.0,
        ]),
      );
    } catch (e) {
      debugPrint('Error redrawRoutePins: $e');
    }
  }

  Future<void> _drawRouteLine(List<dynamic> coords) async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
      final positions = coords
          .map((c) => [c[0].toDouble(), c[1].toDouble()])
          .toList();
      // Guardar coords completas para borrar lo recorrido
      _routeCoords = positions.map((p) => List<double>.from(p)).toList();
      _routeProgressIdx = 0;
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'LineString', 'coordinates': positions},
            'properties': {},
          },
        ],
      });
      await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
      await style.addLayer(
        LineLayer(
          id: _rpRouteLyr,
          sourceId: _rpRouteSrc,
          lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineOpacity: 0.88,
        ),
      );
      // Pins encima de la línea
      await _redrawRoutePins();
      // Centrar cámara
      if (_routeWps.length >= 2) {
        final midLat =
            _routeWps.map((w) => w.lat).reduce((a, b) => a + b) /
            _routeWps.length;
        final midLng =
            _routeWps.map((w) => w.lng).reduce((a, b) => a + b) /
            _routeWps.length;
        mapboxMap!.setCamera(
          CameraOptions(
            center: Point(coordinates: Position(midLng, midLat)),
            zoom: 12.5,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error drawRouteLine: $e');
    }
  }

  Future<void> _clearRouteLayers() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpWpLyr)) {
        await style.removeStyleLayer(_rpWpLyr);
      }
      if (await style.styleSourceExists(_rpWpSrc)) {
        await style.removeStyleSource(_rpWpSrc);
      }
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
    } catch (_) {}
  }

  static const _kFreeRoutePlansPerDay = 2;

  /// true si el usuario gratis ya usó sus 2 planificaciones de ruta del día
  /// (Plus no tiene límite). Se resetea automáticamente al cambiar de día.
  Future<bool> _reachedFreeRoutePlanLimit() async {
    if (SubscriptionService.instance.isPlus.value) return false;
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateTime.now().toIso8601String().substring(
      0,
      10,
    ); // YYYY-MM-DD
    final storedDay = prefs.getString('route_plan_day');
    final count = storedDay == todayKey
        ? (prefs.getInt('route_plan_count') ?? 0)
        : 0;
    return count >= _kFreeRoutePlansPerDay;
  }

  Future<void> _recordRoutePlanUsage() async {
    if (SubscriptionService.instance.isPlus.value) return;
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    final storedDay = prefs.getString('route_plan_day');
    final count = storedDay == todayKey
        ? (prefs.getInt('route_plan_count') ?? 0)
        : 0;
    await prefs.setString('route_plan_day', todayKey);
    await prefs.setInt('route_plan_count', count + 1);
  }

  /// [countUsage] debe ser false cuando es una re-planificación interna
  /// (p.ej. al saltar una parada durante la navegación) — el límite diario
  /// es sobre "planificar una ruta nueva", no sobre sus ajustes internos.
  Future<void> _calcRoute({bool countUsage = true}) async {
    if (_routeWps.isEmpty) return;

    if (countUsage && await _reachedFreeRoutePlanLimit()) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason:
                'El plan gratis permite planificar hasta 2 rutas por día. Hazte Plus para planificar ilimitadas.',
          ),
        ),
      );
      return;
    }

    setState(() => _routeCalculating = true);
    try {
      // La ruta siempre parte de tu ubicación real en vivo, no de la primera
      // parada que tocaste en el mapa — por eso se antepone acá, en vez de
      // depender de que el usuario agregue su propia posición como parada.
      final current =
          _lastPosition ?? await geo.Geolocator.getCurrentPosition();

      // Se respeta el orden exacto en que tocaste las paradas (Parada 1,
      // 2, 3...) — no se reordenan por cercanía.
      final allPoints = [
        '${current.longitude},${current.latitude}',
        ..._routeWps.map((w) => '${w.lng},${w.lat}'),
      ];
      final coords = allPoints.join(';');
      // Limita a ~25m cuánto puede "pegar" cada punto a una calle distinta
      // de la que realmente tocaste — si el radio es muy amplio, Mapbox
      // puede ajustar el punto a una calle paralela o al lado equivocado de
      // una avenida dividida, y ahí nace el rodeo/vuelta rara.
      final radiuses = List.filled(allPoints.length, '25').join(';');

      final url =
          'https://api.mapbox.com/directions/v5/mapbox/cycling/$coords'
          '?geometries=geojson&overview=full&steps=false'
          '&continue_straight=true&alternatives=true&radiuses=$radiuses'
          '&access_token=$kMapboxToken';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) throw Exception('Sin rutas');

      // Diagnóstico: qué tan lejos quedó cada punto de la calle a la que
      // Mapbox lo "pegó". Si esto es alto, el rodeo raro nace de ahí.
      final waypoints = body['waypoints'] as List?;
      if (waypoints != null) {
        for (var i = 0; i < waypoints.length; i++) {
          final snapDist = (waypoints[i]['distance'] as num?)?.toDouble() ?? 0;
          if (snapDist > 20) {
            debugPrint(
              '⚠️ Punto $i quedó a ${snapDist.toStringAsFixed(0)}m de la calle ajustada',
            );
          }
        }
      }

      // Con alternatives=true, Mapbox puede devolver más de una opción
      // razonable — nos quedamos con la de mejor puntaje (tiempo + un poco
      // de peso a la distancia) en vez de aceptar ciegamente la primera.
      final route =
          routes.reduce((a, b) {
                double score(Map r) =>
                    (r['duration'] as num).toDouble() +
                    (r['distance'] as num).toDouble() * 0.02;
                return score(a as Map) <= score(b as Map) ? a : b;
              })
              as Map<String, dynamic>;

      setState(() {
        _routeDistKm = (route['distance'] as num).toDouble() / 1000;
        _routeDurMin = (route['duration'] as num).toDouble() / 60;
        _routeCalculating = false;
        _routeDifficulty = null;
        _routeElevGain = null;
      });
      await _drawRouteLine((route['geometry'] as Map)['coordinates'] as List);
      _fetchRouteElevation(); // Fire-and-forget; actualiza dificultad cuando llega
      if (countUsage) await _recordRoutePlanUsage();
    } catch (e) {
      setState(() => _routeCalculating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _closeRoutePlanner() {
    final restoreParking = _prevShowBikeParkings;
    final restoreBicimetro = _prevShowBicimetro;
    final restoreServices = _prevShowBikeServices;
    setState(() {
      _routePlannerOpen = false;
      _routeAddMode = false;
      _routeWps.clear();
      _routeDistKm = null;
      _routeDurMin = null;
      _routeCalculating = false;
      _navigating = false;
      _routeCoords = [];
      _routeProgressIdx = 0;
      _routeDifficulty = null;
      _routeElevGain = null;
      _elevationLoading = false;
      // Restaurar capas que se ocultaron al iniciar la ruta
      _showBikeParkings = restoreParking;
      _showBicimetro = restoreBicimetro;
      _showBikeServices = restoreServices;
      _prevShowBikeParkings = false;
      _prevShowBicimetro = false;
      _prevShowBikeServices = false;
    });
    _clearRouteLayers();
    _restartGps();
    // Re-mostrar las capas si estaban activas
    if (restoreParking) _updateBikeParkingsLayer();
    if (restoreBicimetro) _updateBicimetroLayer();
    if (restoreServices) _updateBikeServicesLayer();
  }

  // ── Panel UI del planificador ─────────────────────────────────────────────

  Widget _buildRoutePlannerPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF5080810),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + título
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.route,
                  color: Colors.lightBlueAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Planificador de ruta',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _closeRoutePlanner,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // ── Rutas guardadas ───────────────────────────────────────────
          if (_loadingFavorites)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.amberAccent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_savedRoutes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amberAccent, size: 13),
                  const SizedBox(width: 6),
                  const Text(
                    'RUTAS GUARDADAS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loadFavorites,
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white24,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _savedRoutes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final fav = _savedRoutes[i];
                  return GestureDetector(
                    onTap: () => _loadFavoriteRoute(fav),
                    onLongPress: () => _confirmDeleteFavorite(fav),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: glassDecoration(
                        radius: 12,
                        tint: Colors.amberAccent,
                        opacity: 0.08,
                        borderOpacity: 0.2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(fav.icon, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            fav.name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (fav.distanceKm != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              '${fav.distanceKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.amberAccent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Lista de paradas
          if (_routeWps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Toca "+" y luego el mapa para añadir paradas',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: _routeWps.length,
                itemBuilder: (_, i) => _rpWpTile(i),
              ),
            ),

          // Resultados
          if (_routeDistKm != null) _rpResults(),

          // Botón Iniciar (visible cuando hay ≥1 parada — el punto de
          // partida es siempre tu ubicación en vivo, calculado o no)
          if (_routeWps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_routeCalculating || _routeDistKm == null)
                      ? null
                      : _startNavigationMode,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Iniciar navegación'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0057FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white24,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

          // Botones
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              6,
              12,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: Row(
              children: [
                // Añadir parada
                GestureDetector(
                  onTap: () => setState(() => _routeAddMode = !_routeAddMode),
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: glassDecoration(
                      radius: 12,
                      tint: _routeAddMode ? Colors.greenAccent : Colors.white,
                      opacity: _routeAddMode ? 0.18 : 0.08,
                      borderOpacity: _routeAddMode ? 0.4 : 0.15,
                    ),
                    child: Icon(
                      _routeAddMode
                          ? Icons.touch_app
                          : Icons.add_location_alt_outlined,
                      color: _routeAddMode
                          ? Colors.greenAccent
                          : Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Calcular
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _routeWps.isNotEmpty && !_routeCalculating
                          ? _calcRoute
                          : null,
                      icon: _routeCalculating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.route, size: 16),
                      label: Text(
                        _routeCalculating ? 'Calculando...' : 'Calcular',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white24,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_routeWps.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // Guardar favorito
                  GestureDetector(
                    onTap: () => _showSaveRouteFavorite(),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: glassDecoration(
                        radius: 12,
                        tint: Colors.amberAccent,
                        opacity: 0.10,
                        borderOpacity: 0.22,
                      ),
                      child: const Icon(
                        Icons.star_outline,
                        color: Colors.amberAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Limpiar
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _routeWps.clear();
                      _routeDistKm = null;
                      _routeDurMin = null;
                    });
                    _clearRouteLayers();
                  },
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: glassDecoration(
                      radius: 12,
                      tint: Colors.redAccent,
                      opacity: 0.08,
                      borderOpacity: 0.18,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rpWpTile(int i) {
    final wp = _routeWps[i];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: glassDecoration(
        radius: 10,
        opacity: 0.06,
        borderOpacity: 0.10,
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wp.label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white70,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _routeWps.removeAt(i);
                _routeDistKm = null;
                _routeDurMin = null;
              });
              _clearRouteLayers();
              if (_routeWps.isNotEmpty) _redrawRoutePins();
            },
            child: const Icon(Icons.close, color: Colors.white24, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _rpResults() {
    final co2 = Co2Service.savedKg(_routeDistKm!);
    final durStr = _routeDurMin != null
        ? (_routeDurMin! >= 60
              ? '${(_routeDurMin! / 60).toStringAsFixed(1)}h'
              : '${_routeDurMin!.toStringAsFixed(0)} min')
        : '—';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: glassDecoration(
        radius: 14,
        tint: Colors.greenAccent,
        opacity: 0.06,
        borderOpacity: 0.12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _rpStat(
            Icons.straighten,
            '${_routeDistKm!.toStringAsFixed(1)} km',
            'Distancia',
            Colors.greenAccent,
          ),
          _rpStat(
            Icons.timer_outlined,
            durStr,
            'Tiempo',
            Colors.lightBlueAccent,
          ),
          _rpStat(
            Icons.eco_outlined,
            Co2Service.format(co2),
            'CO₂ ahorr.',
            Colors.lightGreenAccent,
          ),
          _rpStat(
            Icons.terrain,
            _elevationLoading
                ? '...'
                : (_routeDifficulty != null
                      ? (_routeElevGain != null
                            ? '${_routeElevGain!.toStringAsFixed(0)}m'
                            : _routeDifficulty!)
                      : '—'),
            _routeDifficulty ?? 'Dificultad',
            _routeDifficulty == 'Fácil'
                ? Colors.greenAccent
                : _routeDifficulty == 'Moderada'
                ? Colors.orangeAccent
                : _routeDifficulty == 'Difícil'
                ? Colors.redAccent
                : Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _rpStat(IconData icon, String val, String label, Color color) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      );

  void _showSaveRouteFavorite() async {
    final favSvc = FavoritesService();
    String selName = 'Mi ruta';
    String selIcon = '📍';
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Container(
            margin: const EdgeInsets.all(16),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 20,
              left: 16,
              right: 16,
            ),
            decoration: glassDecoration(
              radius: 24,
              opacity: 0.18,
              borderOpacity: 0.25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Guardar ruta favorita',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kFavoritePresets.map((p) {
                    final active = selName == p['name'] && selIcon == p['icon'];
                    return GestureDetector(
                      onTap: () => setModal(() {
                        selName = p['name']!;
                        selIcon = p['icon']!;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: glassDecoration(
                          radius: 20,
                          tint: active ? Colors.greenAccent : Colors.white,
                          opacity: active ? 0.15 : 0.05,
                          borderOpacity: active ? 0.35 : 0.1,
                        ),
                        child: Text(
                          '${p['icon']} ${p['name']}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: active ? Colors.greenAccent : Colors.white54,
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await favSvc.save(
                        FavoriteRoute(
                          name: selName,
                          icon: selIcon,
                          waypoints: _routeWps
                              .map(
                                (w) => {
                                  'lat': w.lat,
                                  'lng': w.lng,
                                  'name': w.label,
                                },
                              )
                              .toList(),
                          distanceKm: _routeDistKm,
                        ),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Ruta "$selName" guardada',
                              style: const TextStyle(fontFamily: 'Poppins'),
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Avanza el índice de progreso al coord más cercano adelante del usuario
  DateTime _lastTrim = DateTime(0);

  void _advanceRouteProgress(double lat, double lng) {
    if (_routeCoords.isEmpty) return;
    // Throttle: max una actualización cada 2 segundos
    final now = DateTime.now();
    if (now.difference(_lastTrim).inSeconds < 2) return;

    final searchEnd = (_routeProgressIdx + 100).clamp(0, _routeCoords.length);
    double minDist = double.infinity;
    int bestIdx = _routeProgressIdx;
    for (int i = _routeProgressIdx; i < searchEnd; i++) {
      final d = geo.Geolocator.distanceBetween(
        lat,
        lng,
        _routeCoords[i][1],
        _routeCoords[i][0],
      );
      if (d < minDist) {
        minDist = d;
        bestIdx = i;
      } else if (d > minDist + 80) {
        break;
      }
    }
    // Solo recortar si nos acercamos menos de 30m y avanzamos al menos 1 coord
    if (bestIdx > _routeProgressIdx && minDist < 30) {
      _routeProgressIdx = bestIdx;
      _lastTrim = now;
      _trimRouteLine();
      _offRouteStreak = 0;
      return;
    }

    // Detección de "te saliste de la ruta" (como Google Maps): si quedas
    // lejos de cualquier punto de la línea varias lecturas de GPS seguidas
    // (no solo un salto puntual del sensor), se recalcula la ruta desde
    // donde estás ahora hacia las paradas que faltan.
    const offRouteThresholdM = 60.0;
    const requiredStreak = 3;
    const minSecondsBetweenReroutes = 15;

    if (minDist > offRouteThresholdM) {
      _offRouteStreak++;
    } else {
      _offRouteStreak = 0;
    }

    final canRerouteNow =
        _lastRerouteAt == null ||
        now.difference(_lastRerouteAt!).inSeconds >= minSecondsBetweenReroutes;

    if (_offRouteStreak >= requiredStreak && canRerouteNow && !_rerouting) {
      _offRouteStreak = 0;
      _lastRerouteAt = now;
      _rerouteFromCurrentPosition();
    }
  }

  int _offRouteStreak = 0;
  DateTime? _lastRerouteAt;
  bool _rerouting = false;

  /// Recalcula la ruta desde tu posición actual hacia las paradas que
  /// faltan, cuando te saliste del trazado original — no cuenta contra el
  /// límite diario de planificaciones (no es una ruta nueva, es la misma
  /// corrigiéndose).
  Future<void> _rerouteFromCurrentPosition() async {
    if (_rerouting || !_navigating || _routeWps.isEmpty) return;
    _rerouting = true;
    if (mounted) setState(() {});
    try {
      await _calcRoute(countUsage: false);
    } finally {
      _rerouting = false;
      if (mounted) setState(() {});
    }
  }

  // Redibuja la línea de ruta con solo los coords restantes (remove+re-add)
  Future<void> _trimRouteLine() async {
    if (mapboxMap == null || _routeCoords.isEmpty) return;
    final remaining = _routeCoords.sublist(_routeProgressIdx);
    if (remaining.length < 2) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_rpRouteLyr)) {
        await style.removeStyleLayer(_rpRouteLyr);
      }
      if (await style.styleSourceExists(_rpRouteSrc)) {
        await style.removeStyleSource(_rpRouteSrc);
      }
      final fc = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {'type': 'LineString', 'coordinates': remaining},
            'properties': {},
          },
        ],
      });
      await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
      await style.addLayer(
        LineLayer(
          id: _rpRouteLyr,
          sourceId: _rpRouteSrc,
          lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineOpacity: 0.88,
        ),
      );
      // Pins siempre encima
      await _redrawRoutePins();
    } catch (e) {
      debugPrint('Error trimming route: $e');
    }
  }

  void _startNavigationMode() {
    if (_routeWps.isEmpty) return;
    setState(() {
      _navigating = true;
      _routeProgressIdx = 0;
      _isFollowingUser = true;
      _routePlannerOpen = false;
      _routeAddMode = false;
      _navStartTime = DateTime.now();
      // _routeWps ya no incluye el punto de partida (ese es tu GPS en vivo,
      // ver _calcRoute) — así que la primera parada real es el índice 0.
      _navNextWpIndex = 0;
      _offRouteStreak = 0;
      _lastRerouteAt = null;
    });
    _restartGps(); // Cambiar a GPS de máxima precisión
    if (_routeCoords.isNotEmpty) _trimRouteLine();
  }

  /// Distancia restante (km) sumando los tramos desde el progreso actual
  /// hasta el final de la ruta.
  double _remainingRouteDistanceKm() {
    if (_routeCoords.length < 2) return 0;
    final remaining = _routeCoords.sublist(_routeProgressIdx);
    if (remaining.length < 2) return 0;
    double meters = 0;
    for (var i = 0; i < remaining.length - 1; i++) {
      meters += geo.Geolocator.distanceBetween(
        remaining[i][1],
        remaining[i][0],
        remaining[i + 1][1],
        remaining[i + 1][0],
      );
    }
    return meters / 1000;
  }

  double get _navDoneDistanceKm {
    final total = _routeDistKm ?? 0;
    final done = total - _remainingRouteDistanceKm();
    return done.clamp(0, total);
  }

  /// Velocidad promedio desde que arrancó la navegación (km/h). Null si aún
  /// no ha pasado suficiente tiempo/distancia para que el dato sea útil.
  double? _navAvgSpeedKmh() {
    final start = _navStartTime;
    if (start == null) return null;
    final elapsedH = DateTime.now().difference(start).inSeconds / 3600.0;
    if (elapsedH < 0.01 || _navDoneDistanceKm < 0.05) return null;
    return _navDoneDistanceKm / elapsedH;
  }

  /// Hora estimada de llegada, formateada "HH:MM". Usa la velocidad
  /// promedio si ya es confiable; si no, un valor típico de bici urbana
  /// (15 km/h) para no mostrar un ETA absurdo al arrancar.
  String _navEtaLabel() {
    final remainingKm = _remainingRouteDistanceKm();
    final avgSpeed = _navAvgSpeedKmh() ?? 15.0;
    if (avgSpeed <= 0) return '—';
    final remainingHours = remainingKm / avgSpeed;
    final eta = DateTime.now().add(
      Duration(milliseconds: (remainingHours * 3600000).round()),
    );
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  /// Distancia en línea recta hasta la próxima parada pendiente (no sigue la
  /// calle exacta, pero es un buen estimado y muy simple de calcular).
  double? _navDistanceToNextStopKm() {
    if (_navNextWpIndex >= _routeWps.length) return null;
    final pos = _lastPosition;
    if (pos == null) return null;
    final wp = _routeWps[_navNextWpIndex];
    return geo.Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          wp.lat,
          wp.lng,
        ) /
        1000;
  }

  String get _navNextStopLabel => _navNextWpIndex < _routeWps.length
      ? _routeWps[_navNextWpIndex].label
      : 'Destino final';

  /// Salta la próxima parada de verdad: la saca de la ruta, recalcula el
  /// trayecto desde tu posición actual (saltándosela) y redibuja pines y
  /// línea — no es solo un cambio cosmético del HUD.
  Future<void> _skipCurrentStop() async {
    if (_navNextWpIndex >= _routeWps.length) return;
    setState(() => _routeWps.removeAt(_navNextWpIndex));

    if (_routeWps.isEmpty) {
      // No quedan paradas — llegaste al final de lo que faltaba.
      await _stopNavigation();
      return;
    }
    await _calcRoute(countUsage: false);
  }

  /// Detiene la navegación y muestra un resumen (distancia, tiempo, promedio,
  /// CO₂ ahorrado) antes de limpiar todo el estado de la ruta.
  Future<void> _stopNavigation() async {
    final doneKm = _navDoneDistanceKm;
    final elapsed = _navStartTime != null
        ? DateTime.now().difference(_navStartTime!)
        : Duration.zero;
    final avgSpeed = elapsed.inSeconds > 0
        ? doneKm / (elapsed.inSeconds / 3600.0)
        : 0.0;
    final co2 = Co2Service.savedKg(doneKm);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF0E0E18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¡Buen recorrido! 🚴',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow(
                  Icons.route,
                  'Distancia',
                  '${doneKm.toStringAsFixed(1)} km',
                ),
                _infoRow(
                  Icons.timer_outlined,
                  'Tiempo',
                  _formatDuration(elapsed),
                ),
                _infoRow(
                  Icons.speed,
                  'Velocidad promedio',
                  '${avgSpeed.toStringAsFixed(1)} km/h',
                ),
                _infoRow(
                  Icons.eco_outlined,
                  'CO₂ ahorrado',
                  Co2Service.format(co2),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    _closeRoutePlanner();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }

  Widget _buildNavigationHud() {
    final total = _routeDistKm ?? 0;
    final done = _navDoneDistanceKm;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final avgSpeed = _navAvgSpeedKmh();
    final nextStopKm = _navDistanceToNextStopKm();

    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18).withOpacity(0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_rerouting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Te saliste de la ruta — recalculando…',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${done.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} km  ·  ${(progress * 100).round()}%',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white70,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _hudStat(Icons.access_time, 'ETA', _navEtaLabel()),
                _hudStat(
                  Icons.speed,
                  'Prom.',
                  avgSpeed != null
                      ? '${avgSpeed.toStringAsFixed(1)} km/h'
                      : '—',
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _speedNotifier,
                  builder: (context, speed, _) => _hudStat(
                    Icons.pedal_bike,
                    'Ahora',
                    '${speed.round()} km/h',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextStopKm != null
                        ? '$_navNextStopLabel a ${nextStopKm.toStringAsFixed(1)} km'
                        : _navNextStopLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey[300],
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_routeWps.isNotEmpty)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _skipCurrentStop,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Saltar parada',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                      ),
                    ),
                  ),
                if (_routeWps.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _stopNavigation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Detener',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 15, color: Colors.greenAccent),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey[500],
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFavorite(FavoriteRoute fav) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Eliminar ${fav.icon} ${fav.name}',
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        content: const Text(
          '¿Borrar esta ruta favorita?',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white54,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && fav.id != null) {
      await FavoritesService().delete(fav.id!);
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    if (_loadingFavorites) return;
    setState(() => _loadingFavorites = true);
    final routes = await FavoritesService().getAll();
    if (mounted) {
      setState(() {
        _savedRoutes = routes;
        _loadingFavorites = false;
      });
    }
  }

  void _loadFavoriteRoute(FavoriteRoute fav) {
    final wps = fav.waypoints
        .map(
          (w) => _RouteWp(
            lat: (w['lat'] as num).toDouble(),
            lng: (w['lng'] as num).toDouble(),
            label: w['name'] as String? ?? '${fav.icon} ${fav.name}',
          ),
        )
        .toList();
    setState(() {
      _routeWps.clear();
      _routeWps.addAll(wps);
      _routeDistKm = null;
      _routeDurMin = null;
    });
    _clearRouteLayers();
    if (wps.isNotEmpty) {
      _redrawRoutePins();
      if (wps.length >= 2) _calcRoute();
    }
  }

  /// Activa/desactiva mostrar tu posición en vivo a tus seguidores mutuos.
  /// Al apagarlo, además de dejar de subir ubicaciones, borra la fila para
  /// que quien te esté viendo deje de verte de inmediato.
  Future<void> _toggleShareLocation(bool val) async {
    setState(() => _shareLiveLocation = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('share_live_location', val);
    if (!val) _presenceService.clearMyLocation();
  }

  /// Activa/desactiva el conteo de km en segundo plano. Requiere permiso de
  /// ubicación "Permitir todo el tiempo".
  Future<void> _toggleBgTracking(bool val) async {
    if (val) {
      final status = await Permission.locationAlways.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Activa la ubicación "Permitir todo el tiempo" en Ajustes para contar km en segundo plano',
              ),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return; // no se activa si no hay permiso
      }
    }
    setState(() => _bgTrackingEnabled = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_tracking', val);
    _restartGps(); // re-crea el stream con/sin servicio en primer plano
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            val
                ? '✅ Contando km en segundo plano'
                : 'Conteo en segundo plano desactivado',
          ),
          backgroundColor: val ? Colors.green : Colors.grey[800],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveKmToProfile(double km) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'increment_total_km',
        params: {'uid': uid, 'km_delta': km},
      );
    } catch (_) {
      // Si el RPC no existe, actualizamos con fetch+update
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('total_km')
            .eq('id', uid)
            .maybeSingle();
        final current = (profile?['total_km'] as num?)?.toDouble() ?? 0.0;
        await Supabase.instance.client
            .from('profiles')
            .update({'total_km': current + km})
            .eq('id', uid);
      } catch (e) {
        debugPrint('Error guardando km: $e');
      }
    }
    _maybeAutofillCommune(uid); // sin await: no bloquea el conteo
    _checkAchievementsAndNotify();
  }

  /// Si el perfil no tiene comuna, la deduce por geocodificación inversa de la
  /// posición actual y la guarda. Así el "Ranking por comuna" funciona sin que
  /// el usuario tenga que escribirla a mano. Un solo intento por sesión.
  Future<void> _maybeAutofillCommune(String uid) async {
    if (_communeAutofillTried) return;
    final pos = _lastPosition;
    if (pos == null) return;
    _communeAutofillTried = true;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('commune')
          .eq('id', uid)
          .maybeSingle();
      final current = (profile?['commune'] as String?)?.trim() ?? '';
      if (current.isNotEmpty) return; // el usuario ya la tiene puesta

      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${pos.latitude}&lon=${pos.longitude}'
        '&format=json&accept-language=es&zoom=12',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'pedalea/1.0'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final addr =
          (jsonDecode(res.body) as Map<String, dynamic>)['address']
              as Map<String, dynamic>?;
      final commune =
          (addr?['city'] as String? ??
                  addr?['town'] as String? ??
                  addr?['municipality'] as String? ??
                  addr?['county'] as String? ??
                  addr?['suburb'] as String? ??
                  '')
              .trim();
      if (commune.isEmpty) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'commune': commune})
          .eq('id', uid);
      debugPrint('🏙️ Comuna autocompletada: $commune');
    } catch (e) {
      debugPrint('No se pudo autocompletar la comuna: $e');
    }
  }

  final _achievementsService = AchievementsService();

  /// Chequea los logros justo después de guardar km (o cualquier otro
  /// avance) para que la notificación de "logro completado" salga al
  /// toque, en vez de tener que esperar a abrir el perfil.
  Future<void> _checkAchievementsAndNotify() async {
    try {
      final newIds = await _achievementsService.checkAndUnlock();
      if (newIds.isEmpty || !mounted) return;
      final all = await _achievementsService.getAllWithStatus();
      final details = newIds
          .map(
            (id) => all.firstWhere(
              (a) => a['id'] == id,
              orElse: () => <String, dynamic>{},
            ),
          )
          .where((a) => a.isNotEmpty)
          .map(
            (a) => {
              'icon': a['icon'] as String? ?? '🏅',
              'title': a['title'] as String? ?? 'Nuevo logro',
            },
          )
          .toList();
      if (mounted && details.isNotEmpty) {
        showAchievementUnlockedToasts(context, details);
      }
    } catch (e) {
      debugPrint('Error chequeando logros tras guardar km: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF12121C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '¿Cerrar sesión?',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        ),
        content: const Text(
          'Tendrás que iniciar sesión de nuevo para volver a usar Pedalea.',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
    }
  }

  Widget _drawerIconTile(
    IconData icon, {
    Color color = const Color(0xFF7CF0BC),
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _drawerFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Pedalea v1.0',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.28),
              fontSize: 11,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                color: Colors.white.withOpacity(0.28),
                size: 13,
              ),
              const SizedBox(width: 3),
              Text(
                'Región Metropolitana',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.28),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF12121C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFF12121C)),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerProfileHeader(),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.only(left: 16, right: 20),
                    iconColor: const Color(0xFF7CF0BC),
                    collapsedIconColor: Colors.white38,
                    leading: _drawerIconTile(Icons.monitor_heart_rounded),
                    title: const Text(
                      "Actividad",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      ListTile(
                        leading: _drawerIconTile(Icons.bar_chart_rounded),
                        title: const Text(
                          "Mis estadísticas",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Km de hoy, semana y racha",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StatsPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.route,
                          color: Colors.lightBlueAccent,
                        ),
                        title: const Text(
                          "Planificar ruta",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Multiparada con CO₂ estimado",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _routePlannerOpen = true);
                          _loadFavorites();
                        },
                      ),
                      SwitchListTile(
                        value: _modoActivo,
                        activeThumbColor: Colors.greenAccent,
                        title: const Text(
                          "Modo activo",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Cuenta tus km mientras pedaleas",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (value) {
                          if (value) {
                            // Empieza una sesión nueva: limpia el trazado anterior.
                            setState(() {
                              _modoActivo = value;
                              _sessionKm = 0;
                              _routePoints.clear();
                              _sessionStartAt = DateTime.now();
                            });
                          } else {
                            setState(() => _modoActivo = value);
                            _presenceService.clearMyLocation();
                            _maybeOfferRouteShare();
                          }
                        },
                      ),
                      SwitchListTile(
                        value: _shareLiveLocation,
                        activeThumbColor: Colors.greenAccent,
                        secondary: Icon(
                          _shareLiveLocation
                              ? Icons.share_location_rounded
                              : Icons.location_off_outlined,
                          color: Colors.greenAccent,
                        ),
                        title: const Text(
                          "Compartir mi ubicación en vivo",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Apagado por defecto. Si lo activas, solo te ven "
                          "en el mapa quienes te siguen mutuamente (nunca "
                          "toda la app) y con ~30 s de retraso.",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: _toggleShareLocation,
                      ),
                      SwitchListTile(
                        value: _bgTrackingEnabled,
                        activeThumbColor: Colors.greenAccent,
                        secondary: const Icon(
                          Icons.gps_fixed,
                          color: Colors.greenAccent,
                        ),
                        title: const Text(
                          "Contar km en segundo plano",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Suma tus km aunque no tengas la app abierta (usa más batería)",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: _toggleBgTracking,
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.only(left: 16, right: 20),
                    iconColor: const Color(0xFF7CF0BC),
                    collapsedIconColor: Colors.white38,
                    leading: _drawerIconTile(Icons.groups_rounded),
                    title: const Text(
                      "Comunidad",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.auto_awesome_rounded,
                          color: const Color(0xFF69FF47),
                        ),
                        title: const Text(
                          "Momentos",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Comparte tus mejores fotos pedaleando",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white38, size: 20),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MomentsPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.forum_rounded,
                          color: const Color(0xFF4FC3F7),
                        ),
                        title: const Text(
                          "Mensajes",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Chat con ciclistas que sigues mutuamente",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white38, size: 20),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MessagesPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.leaderboard,
                          color: Colors.amberAccent,
                        ),
                        title: const Text(
                          "Ranking local",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Top comunas y ciclistas",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RankingPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.emoji_events_rounded,
                          color: Colors.amberAccent,
                        ),
                        title: const Text(
                          "Ranking de ciclistas",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Km del día, semana y velocidad máx.",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RiderRankingPage(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(Icons.event),
                        title: const Text(
                          "Próximos eventos",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Encuentra ciclistas cerca",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EventsPage(),
                            ),
                          ).then((_) => _checkAchievementsAndNotify());
                        },
                      ),
                      ListTile(
                        leading: _drawerIconTile(Icons.add_location),
                        title: const Text(
                          "Crear evento",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Organiza una salida",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateEventPage(),
                            ),
                          ).then((_) => _checkAchievementsAndNotify());
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.only(left: 16, right: 20),
                    iconColor: const Color(0xFF7CF0BC),
                    collapsedIconColor: Colors.white38,
                    leading: _drawerIconTile(Icons.notifications_rounded),
                    title: const Text(
                      "Alertas",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      ListTile(
                        leading: _drawerIconTile(
                          Icons.add_alert,
                          color: Colors.redAccent,
                        ),
                        title: const Text(
                          "Reportar problema",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: const Text(
                          "Mantén presionado el mapa donde ocurre el problema",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '💡 Mantén presionado el mapa en el lugar del problema para crear una alerta',
                              ),
                              backgroundColor: Colors.blue,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.only(left: 16, right: 20),
                    iconColor: const Color(0xFF7CF0BC),
                    collapsedIconColor: Colors.white38,
                    leading: _drawerIconTile(Icons.map_rounded),
                    title: const Text(
                      "Mapa",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      SwitchListTile(
                        value: _autoDarkMode,
                        activeThumbColor: Colors.blueAccent,
                        title: const Text(
                          "Modo oscuro automático",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          _autoDarkMode
                              ? "Noche 7pm–7am, día 7am–7pm"
                              : "Siempre modo noche",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _autoDarkMode = val;
                            _currentStyle = _resolveMapStyle();
                          });
                          _styleIsLoaded = false;
                          mapboxMap?.loadStyleURI(_currentStyle);
                        },
                      ),
                      _mapStylePicker(),
                      SwitchListTile(
                        value: _showHeatmap,
                        activeThumbColor: const Color(0xFFFF6D00),
                        secondary: Icon(
                          SubscriptionService.instance.isPlus.value
                              ? Icons.local_fire_department_rounded
                              : Icons.lock_outline_rounded,
                          color: const Color(0xFFFF6D00),
                        ),
                        title: const Text(
                          "Mi mapa de calor",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          SubscriptionService.instance.isPlus.value
                              ? "Dónde has pedaleado más (Plus)"
                              : "Función de Pedalea Plus",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (_) => _toggleHeatmap(),
                      ),
                      SwitchListTile(
                        value: _showBikeParkings,
                        activeThumbColor: const Color(0xFF00BCD4),
                        secondary: _bikeParkingsLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF00BCD4),
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.local_parking,
                                color: Color(0xFF00BCD4),
                              ),
                        title: const Text(
                          "Estacionamientos de bici",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Biciparkings de OpenStreetMap",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (_) => _toggleBikeParkings(),
                      ),
                      SwitchListTile(
                        value: _showBicimetro,
                        activeThumbColor: const Color(0xFF7C3AED),
                        secondary: const Icon(
                          Icons.train,
                          color: Color(0xFF7C3AED),
                        ),
                        title: const Text(
                          "BiciMetro",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Estaciones Metro que permiten bici",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (_) => _toggleBicimetro(),
                      ),
                      SwitchListTile(
                        value: _showBikeServices,
                        activeThumbColor: const Color(0xFF22C55E),
                        secondary: _bikeServicesLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF22C55E),
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.pedal_bike,
                                color: Color(0xFF22C55E),
                              ),
                        title: const Text(
                          "Inflado, talleres y agua",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Aire, talleres, gasolineras y puntos de agua",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (_) => _toggleBikeServices(),
                      ),
                      SwitchListTile(
                        value: _showCicloRecreo,
                        activeThumbColor: const Color(0xFF7CB342),
                        secondary: const Icon(
                          Icons.event_available,
                          color: Color(0xFF7CB342),
                        ),
                        title: const Text(
                          "CicloRecreoVía",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Calles cerradas para ciclistas los domingos",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (_) => _toggleCicloRecreo(),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  ExpansionTile(
                    tilePadding: const EdgeInsets.only(left: 16, right: 20),
                    iconColor: const Color(0xFF7CF0BC),
                    collapsedIconColor: Colors.white38,
                    leading: _drawerIconTile(Icons.shield_rounded),
                    title: const Text(
                      "Seguridad",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      SwitchListTile(
                        value: _fallDetectionEnabled,
                        activeThumbColor: Colors.redAccent,
                        secondary: const Icon(
                          Icons.health_and_safety,
                          color: Colors.redAccent,
                        ),
                        title: const Text(
                          "Detección de caídas",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Llama a emergencias si detecta una caída brusca",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: _setFallDetectionEnabled,
                      ),
                      SwitchListTile(
                        value: _proximityAlertsEnabled,
                        activeThumbColor: Colors.orangeAccent,
                        secondary: const Icon(
                          Icons.notifications_active,
                          color: Colors.orangeAccent,
                        ),
                        title: const Text(
                          "Alertas de proximidad",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          "Notifica al acercarte a un incidente reportado",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() => _proximityAlertsEnabled = val);
                          _proximityService.reset();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const _DrawerPlusBanner(),
            const Divider(color: Colors.white24, height: 1),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "CUENTA",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ListTile(
              leading: _drawerIconTile(
                Icons.logout_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                "Cerrar sesión",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                tooltip: 'Configuración',
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
              onTap: _confirmLogout,
            ),
            _drawerFooter(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    MapboxOptions.setAccessToken(kMapboxToken);
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      onDrawerChanged: (opened) {
        setState(() => _drawerOpen = opened);
        // Al cerrar el menú, refresca el mapa de calor con lo pedaleado.
        if (!opened && _showHeatmap) _updateHeatmapLayer();
      },
      body: Stack(
        children: [
          // GestureDetector solo para capturar posición del dedo (overlay visual)
          GestureDetector(
            onTapDown: (details) {
              _longPressTapPosition = details.globalPosition;
            },
            child: MapWidget(
              key: const ValueKey("mapWidget"),
              styleUri: _currentStyle,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(-70.6483, -33.4569)),
                zoom: 15.0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: (_) => _onStyleLoaded(),
              onScrollListener: (_) => _stopFollowingByGesture(),
              onZoomListener: (_) => _stopFollowingByGesture(),
              // Tap corto → mostrar info de alerta/evento
              onTapListener: (info) => _onMapTap(info.point),
              // Long press nativo del SDK → crear alerta con indicador visual
              onLongTapListener: (info) {
                _showLongPressIndicator(_longPressTapPosition ?? Offset.zero);
                Future.delayed(const Duration(milliseconds: 150), () {
                  _removeLongPressIndicator();
                  _onLongPress(info.point);
                });
              },
            ),
          ),
          // ── Overlay de gotas de lluvia (según clima detectado) ────────────
          if (_isRaining)
            Positioned.fill(child: RainOverlay(heavy: _isHeavyRain)),
          // ── Banner sin conexión ───────────────────────────────────────────
          if (_isOffline)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.orange.shade800.withOpacity(0.95),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Sin conexión · Mostrando datos en caché',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          _buildHeadingDiagnosticPanel(),

          if (_showLayersTip)
            Positioned(
              top: 195,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _layersTipOpacity,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E0E18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          color: Color(0xFFC9FF5C),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '¿Sabías que puedes ocultar los pines?',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Puedes activar o desactivar BiciMetro, estacionamientos, talleres y CicloRecreoVía desde el menú ☰ → MAPA.',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            '$_layersTipSecondsLeft',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(top: 120, left: 20, right: 20, child: _buildTopBar()),
          Positioned(left: 20, bottom: 64, child: _buildSpeedometer()),

          if (_isSelectingLocation && _selectedLocation != null)
            Positioned(
              bottom: 120,
              right: 20,
              child: FloatingActionButton(
                backgroundColor: Colors.greenAccent,
                onPressed: _confirmLocationAndCreateAlert,
                child: const Icon(Icons.check, color: Colors.black),
              ),
            ),

          Positioned(
            top: 50,
            left: 16,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF12121C),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => RotationTransition(
                    turns: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    _drawerOpen ? Icons.close_rounded : Icons.menu_rounded,
                    key: ValueKey(_drawerOpen),
                    color: const Color(0xFF7CF0BC),
                    size: 22,
                  ),
                ),
                onPressed: () {
                  if (_drawerOpen) {
                    _scaffoldKey.currentState?.closeDrawer();
                  } else {
                    _scaffoldKey.currentState?.openDrawer();
                  }
                },
                tooltip: 'Menú',
              ),
            ),
          ),
          // ── Botón de búsqueda de destino ────────────────────────
          Positioned(
            top: 50,
            left: 74,
            child: Container(
              decoration: _dayNightBox(radius: 30),
              child: IconButton(
                icon: Icon(
                  Icons.search,
                  color: _isDayMode
                      ? const Color(0xFF00A86B)
                      : Colors.greenAccent,
                  size: 22,
                ),
                onPressed: _openPlaceSearch,
                tooltip: 'Buscar destino',
              ),
            ),
          ),
          // ── Botón de pánico ─────────────────────────────────────
          Positioned(bottom: 64, right: 20, child: _PanicButton()),

          // ── HUD de navegación (ETA, velocidad, progreso, parada) ─────────
          if (_navigating) _buildNavigationHud(),

          // ── Hint "toca el mapa" cuando _routeAddMode ─────────────────────
          if (_routePlannerOpen && _routeAddMode)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.greenAccent.withOpacity(0.5),
                    ),
                  ),
                  child: const Text(
                    '📍 Toca el mapa para añadir una parada',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.greenAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

          // ── Botón cancelar ruta (visible cuando hay una ruta activa) ─────
          if (_routePlannerOpen && _routeDistKm != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _closeRoutePlanner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Cancelar ruta',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Panel planificador de ruta ────────────────────────────────────
          if (_routePlannerOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildRoutePlannerPanel(),
            ),

          Positioned(
            top: 50,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: _dayNightBox(radius: 30),
                  child: IconButton(
                    icon: Icon(
                      Icons.explore,
                      color: _isDayMode
                          ? const Color(0xFF00A86B)
                          : Colors.greenAccent,
                      size: 22,
                    ),
                    onPressed: _resetNorth,
                    tooltip: 'Orientar al norte',
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: _dayNightBox(radius: 30),
                  child: IconButton(
                    icon: Icon(
                      Icons.navigation,
                      color: _isFollowingUser
                          ? (_isDayMode
                                ? const Color(0xFF00A86B)
                                : Colors.greenAccent)
                          : (_isDayMode
                                ? const Color(0xFF333355)
                                : Colors.white),
                      size: 22,
                    ),
                    onPressed: _toggleFollowing,
                    tooltip: 'Seguir ubicación',
                  ),
                ),
                _ProfileButton(isDayMode: _isDayMode),
              ],
            ),
          ),

          // ── Burbuja flotante de ayuda: se puede arrastrar por todo el
          // mapa; al tocarla hace un pequeño efecto y muestra un tip corto
          // al lado, sin abrir ningún modal.
          Builder(
            builder: (context) {
              final size = MediaQuery.of(context).size;
              final pos =
                  _helpBubblePos ?? Offset(size.width - 64, size.height - 220);
              const bubbleSize = 48.0;
              const tipMaxWidth = 220.0;
              const gap = 8.0;
              // Si no hay espacio a la derecha del burbuja para el tip, lo
              // mostramos a la izquierda en su lugar (y viceversa) para que
              // nunca se salga de la pantalla.
              final spaceRight = size.width - (pos.dx + bubbleSize) - gap;
              final showTipOnRight = spaceRight >= tipMaxWidth;
              return Stack(
                children: [
                  Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          final newX = (pos.dx + details.delta.dx).clamp(
                            4.0,
                            size.width - 52.0,
                          );
                          final newY = (pos.dy + details.delta.dy).clamp(
                            60.0,
                            size.height - 100.0,
                          );
                          _helpBubblePos = Offset(newX, newY);
                        });
                      },
                      onTap: _onHelpBubbleTap,
                      child: AnimatedScale(
                        scale: _helpBubbleBounce ? 1.18 : 1.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.elasticOut,
                        child: Container(
                          width: bubbleSize,
                          height: bubbleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF12213F),
                            border: Border.all(
                              color: const Color(0xFFC9FF5C),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.tips_and_updates_rounded,
                            color: Color(0xFFC9FF5C),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: pos.dy,
                    left: showTipOnRight ? pos.dx + bubbleSize + gap : null,
                    right: showTipOnRight ? null : size.width - pos.dx + gap,
                    child: IgnorePointer(
                      ignoring: !_showHelpTipText,
                      child: AnimatedOpacity(
                        opacity: _showHelpTipText ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: tipMaxWidth,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E0E18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            _helpTips[_helpTipIndex],
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
    _mapGeneration++;
    _styleIsLoaded = false;
    _eventsIconAdded = false;
    _configureMapOrnaments(mapboxMap);
    _startFollowing();
    _centerOnUserAtStartup();
    _listenToActiveCyclists();
    _listenToEvents();
    _listenToAlerts();
    // Las capas se agregan en _onStyleLoaded, que se dispara tras onMapCreated
  }

  /// Al abrir la app, obtiene la ubicación actual de inmediato y centra el mapa
  /// ahí (el stream de GPS solo emite al moverse, por eso hay que pedir una
  /// lectura puntual). También dispara la carga de las capas por defecto.
  Future<void> _centerOnUserAtStartup() async {
    try {
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        return;
      }

      // Salto rápido con la última posición conocida…
      geo.Position? pos = await geo.Geolocator.getLastKnownPosition();
      if (pos != null) {
        _lastPosition = pos;
        _moveCameraInstant(pos);
        _maybeAutoLoadLayers();
      }

      // …y centrado preciso con una lectura fresca.
      pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      _lastPosition = pos;
      if (mounted) setState(() => _isFollowingUser = true);
      _moveCameraInstant(pos);
      _maybeAutoLoadLayers();
    } catch (e) {
      debugPrint('No se pudo centrar al inicio: $e');
    }
  }

  /// Ajusta los adornos nativos de Mapbox para que no se encimen con la UI de
  /// la app ni con las barras del sistema:
  ///  • Barra de escala: se oculta (saturaba la parte superior).
  ///  • Brújula nativa: se oculta (la app ya tiene su propio botón de brújula).
  ///  • Logo y atribución: se mantienen visibles (requisito de Mapbox) pero se
  ///    suben para no chocar con la barra de navegación de Android.
  Future<void> _configureMapOrnaments(MapboxMap map) async {
    try {
      await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      await map.compass.updateSettings(CompassSettings(enabled: false));
      // Logo y ⓘ pegados a las esquinas inferiores, apenas por encima de la
      // barra de navegación (no flotando en medio de la pantalla).
      await map.logo.updateSettings(
        LogoSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 10,
          marginBottom: 26,
        ),
      );
      await map.attribution.updateSettings(
        AttributionSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 10,
          marginBottom: 26,
        ),
      );
    } catch (e) {
      debugPrint('Error configurando adornos del mapa: $e');
    }
  }

  /// Se dispara cada vez que el mapa carga un estilo (inicio + cada cambio día/noche).
  /// Re-agrega TODAS las capas custom porque Mapbox las borra al cambiar estilo.
  void _onStyleLoaded() {
    _styleIsLoaded = true;
    // Resetear flags para que se re-agreguen
    _cicloviasAdded = false;
    _cyclistsIconAdded = false;
    _eventsIconAdded = false;
    _alertsIconAdded = false;
    _alertsLayerAdded = false;
    _bikeParkingsIconAdded = false;
    _bicimetroIconAdded = false;
    _bikeServicesIconsAdded = false;
    _cicloRecreoIconAdded = false;

    Future.microtask(() async {
      if (mapboxMap == null || !mounted) return;
      await _setupUserPuck();
      await _addCicloviasLayer();
      // Mapa de calor bajo los pines (para no taparlos).
      if (_showHeatmap) await _updateHeatmapLayer();
      // Re-agregar alertas/eventos con los datos que ya tenemos en memoria
      if (_currentAlerts.isNotEmpty) await _updateAlertsLayer(_currentAlerts);
      if (_currentEvents.isNotEmpty) {
        await _updateEventsLayer(_visibleEventPinsForMap(_currentEvents));
      }
      // Re-agregar capas opcionales si estaban activas
      if (_showBikeParkings && _bikeParkings.isNotEmpty) {
        await _updateBikeParkingsLayer();
      }
      if (_lastCyclists.isNotEmpty) await _updateCyclistsLayer(_lastCyclists);
      if (_showBicimetro) await _updateBicimetroLayer();
      if (_showBikeServices && _bikeServices.isNotEmpty) {
        await _updateBikeServicesLayer();
      }
      if (_showCicloRecreo && _cicloRecreoPoints.isNotEmpty) {
        await _updateCicloRecreoLayer();
      }

      // El primer cargado de las capas por defecto se dispara tras el primer
      // fix de GPS (ver _maybeAutoLoadLayers), para usar un área pequeña
      // alrededor del usuario y evitar consultas lentas a todo Santiago.
      _maybeAutoLoadLayers();
      // Re-dibujar ruta si estaba calculada
      if (_routeCoords.isNotEmpty && _routeDistKm != null) {
        final remaining = _routeCoords.sublist(_routeProgressIdx);
        if (remaining.length >= 2) {
          final style = mapboxMap!.style;
          try {
            if (await style.styleLayerExists(_rpRouteLyr)) {
              await style.removeStyleLayer(_rpRouteLyr);
            }
            if (await style.styleSourceExists(_rpRouteSrc)) {
              await style.removeStyleSource(_rpRouteSrc);
            }
            final fc = jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                {
                  'type': 'Feature',
                  'geometry': {'type': 'LineString', 'coordinates': remaining},
                  'properties': {},
                },
              ],
            });
            await style.addSource(GeoJsonSource(id: _rpRouteSrc, data: fc));
            await style.addLayer(
              LineLayer(
                id: _rpRouteLyr,
                sourceId: _rpRouteSrc,
                lineColor: const Color(0xFF2962FF).value, // azul fuerte (ruta)
                lineWidth: 5.0,
                lineJoin: LineJoin.ROUND,
                lineCap: LineCap.ROUND,
                lineOpacity: 0.88,
              ),
            );
            await _redrawRoutePins();
          } catch (_) {}
        }
      }
    });
  }

  /// Capas de ciclovías con ancho y opacidad dependientes del zoom:
  /// finas y tenues al ver toda la ciudad (no saturan el mapa), nítidas al
  /// acercarte para pedalear. Se eliminó el "glow" que creaba la neblina neón.
  List<LineLayer> _cicloviaLayers() {
    // En modo claro el celeste suave se pierde contra el fondo blanco/gris
    // del mapa — usamos un azul mucho más saturado y opaco. En modo oscuro
    // cambiamos a lima (el acento de marca de Pedalea), que resalta mucho
    // más contra el navy oscuro que el celeste que había antes.
    final mainColor = _isDayMode
        ? const Color(0xFF0B5FFF)
        : const Color(0xFFC9FF5C);
    final centerColor = _isDayMode
        ? const Color(0xFF6FA8FF)
        : const Color(0xFFE6FFB0);
    final mainOpacity = _isDayMode
        ? [
            'interpolate',
            ['linear'],
            ['zoom'],
            11,
            0.55,
            13,
            0.75,
            15,
            0.9,
          ]
        : [
            'interpolate',
            ['linear'],
            ['zoom'],
            11,
            0.35,
            13,
            0.6,
            15,
            0.85,
          ];

    return [
      // Halo blanco debajo, solo en modo claro, para que la línea azul no se
      // confunda con calles o límites del propio mapa base.
      if (_isDayMode)
        LineLayer(
          id: "ciclovias-halo-layer",
          sourceId: "ciclovias-source",
          lineColor: Colors.white.value,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidthExpression: [
            'interpolate',
            ['linear'],
            ['zoom'],
            11,
            1.4,
            13,
            2.6,
            15,
            5.0,
            17,
            7.5,
          ],
          lineOpacityExpression: [
            'interpolate',
            ['linear'],
            ['zoom'],
            11,
            0.35,
            13,
            0.55,
            15,
            0.75,
          ],
        ),
      // Línea principal
      LineLayer(
        id: "ciclovias-main-layer",
        sourceId: "ciclovias-source",
        lineColor: mainColor.value,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidthExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          11,
          0.6,
          13,
          1.4,
          15,
          3.0,
          17,
          5.0,
        ],
        lineOpacityExpression: mainOpacity,
      ),
      // Centro claro — solo aparece al acercarse, da sensación de carril
      LineLayer(
        id: "ciclovias-center-layer",
        sourceId: "ciclovias-source",
        lineColor: centerColor.value,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidthExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          14,
          0.0,
          16,
          1.0,
          18,
          1.8,
        ],
        lineOpacityExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          14,
          0.0,
          16,
          0.6,
        ],
      ),
    ];
  }

  Future<void> _addCicloviasLayer() async {
    if (_cicloviasAdded || mapboxMap == null) return;
    try {
      final style = mapboxMap!.style;

      // Si ya tenemos el GeoJSON procesado en caché, lo usamos directamente
      if (_cicloviasGeoJson != null) {
        final sourceExists = await style.styleSourceExists("ciclovias-source");
        if (sourceExists) await style.removeStyleSource("ciclovias-source");
        for (var lyr in [
          "ciclovias-glow-layer",
          "ciclovias-halo-layer",
          "ciclovias-main-layer",
          "ciclovias-center-layer",
        ]) {
          if (await style.styleLayerExists(lyr)) {
            await style.removeStyleLayer(lyr);
          }
        }
        await style.addSource(
          GeoJsonSource(id: "ciclovias-source", data: _cicloviasGeoJson!),
        );
        for (final l in _cicloviaLayers()) {
          await style.addLayer(l);
        }
        _cicloviasAdded = true;
        if (_currentAlerts.isNotEmpty) await _updateAlertsLayer(_currentAlerts);
        if (_currentEvents.isNotEmpty) {
          await _updateEventsLayer(_visibleEventPinsForMap(_currentEvents));
        }
        return;
      }

      // Ciclovías incluidas en la app (sin depender de internet).
      final data = await rootBundle.loadString(
        'assets/data/ciclovias_chile.json',
      );
      debugPrint("📊 Datos de ciclovías recibidos: ${data.length} caracteres");
      if (data.isEmpty) {
        debugPrint("⚠️ No se recibieron datos de ciclovías");
        return;
      }
      final jsonData = jsonDecode(data);
      debugPrint("📦 JSON parseado correctamente");
      List features = [];
      if (jsonData.containsKey('elements')) {
        debugPrint("✅ Estructura 'elements' encontrada");
        for (var element in jsonData['elements']) {
          if (element['geometry'] != null) {
            if (element['type'] == 'way' || element['type'] == 'relation') {
              List coordinates = [];
              if (element['geometry'] is List) {
                coordinates = (element['geometry'] as List)
                    .map((p) => [p['lon'], p['lat']])
                    .toList();
              } else if (element['geometry'] is Map &&
                  element['geometry']['coordinates'] != null) {
                coordinates = element['geometry']['coordinates'];
              }
              if (coordinates.isNotEmpty) {
                features.add({
                  "type": "Feature",
                  "properties": {
                    "tipo": "ciclovia",
                    "name": element['tags']?['name'] ?? "Ciclovía",
                  },
                  "geometry": {
                    "type": "LineString",
                    "coordinates": coordinates,
                  },
                });
              }
            }
          }
        }
      } else if (jsonData.containsKey('features')) {
        debugPrint("✅ Estructura GeoJSON encontrada");
        features = jsonData['features'];
      }
      debugPrint("📍 Total de features generados: ${features.length}");
      if (features.isEmpty) {
        debugPrint("⚠️ No se generaron features para las ciclovías");
        return;
      }
      final geoJson = jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });
      final sourceExists = await style.styleSourceExists("ciclovias-source");
      if (sourceExists) {
        await style.removeStyleSource("ciclovias-source");
        debugPrint("🗑️ Fuente anterior eliminada");
      }
      await style.addSource(
        GeoJsonSource(id: "ciclovias-source", data: geoJson),
      );
      debugPrint("✅ Nueva fuente GeoJSON agregada");
      const layers = [
        "ciclovias-glow-layer",
        "ciclovias-halo-layer",
        "ciclovias-main-layer",
        "ciclovias-center-layer",
      ];
      for (var layer in layers) {
        if (await style.styleLayerExists(layer)) {
          await style.removeStyleLayer(layer);
          debugPrint("🗑️ Capa $layer eliminada");
        }
      }
      for (final l in _cicloviaLayers()) {
        await style.addLayer(l);
      }
      debugPrint("✅ Capas de ciclovías agregadas");
      _cicloviasGeoJson = geoJson;
      CacheService.saveCiclovias(geoJson); // Persistir en disco
      _cicloviasAdded = true;
      debugPrint("🎉 ¡Ciclovías cargadas exitosamente!");

      // Las ciclovías quedan encima de todo → re-agregar alertas y eventos
      // para que siempre estén por encima de las líneas.
      if (_currentAlerts.isNotEmpty) {
        await _updateAlertsLayer(_currentAlerts);
      }
      if (_currentEvents.isNotEmpty) {
        await _updateEventsLayer(_visibleEventPinsForMap(_currentEvents));
      }
    } catch (e) {
      debugPrint("❌ Error crítico en ciclovías: $e");
      debugPrint("Stack trace: ${StackTrace.current}");
    }
  }

  Future<void> _toggleFollowing() async {
    final enabling = !_isFollowingUser;
    setState(() => _isFollowingUser = enabling);
    _restartGps(); // aplica el filtro de 5 m al seguir / 15 m al soltar
    if (!enabling) return;

    // Al activar el seguimiento, centrar de inmediato en la ubicación actual
    // (sin esperar a que el usuario se mueva 15 m para que el GPS emita).
    try {
      // Asegurar permiso de ubicación.
      var perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activa el permiso de ubicación para centrarte'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // Usar la última posición conocida para un salto instantáneo…
      geo.Position? pos =
          _lastPosition ?? await geo.Geolocator.getLastKnownPosition();
      if (pos != null) _moveCameraInstant(pos);

      // …y luego refinar con una lectura fresca.
      pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 6));
      _lastPosition = pos;
      if (_isFollowingUser) _moveCameraInstant(pos);
    } catch (e) {
      debugPrint('No se pudo centrar en la ubicación: $e');
    }
  }

  /// Dibuja en el mapa a los demás ciclistas "en línea" (actividad en los
  /// últimos 5 min), con el mismo ícono de bici que usa el propio usuario,
  /// orientado según su rumbo (heading).
  ///
  /// Solo llegan ciclistas con los que hay follow mutuo: [PresenceService]
  /// solo escribe si el usuario activó "Compartir mi ubicación en vivo"
  /// (opt-in, apagado por defecto) y la RLS de `user_locations` en Supabase
  /// solo deja leer tu propia fila o la de alguien con follow mutuo — ni
  /// aunque se manipule el cliente se puede ver la ubicación de un
  /// desconocido.
  Future<void> _updateCyclistsLayer(
    List<Map<String, dynamic>> cyclists,
  ) async {
    if (mapboxMap == null || !_styleIsLoaded) return;
    final style = mapboxMap!.style;
    try {
      if (await style.styleLayerExists(_cyclistsLayerId)) {
        await style.removeStyleLayer(_cyclistsLayerId);
      }
      if (await style.styleSourceExists(_cyclistsSourceId)) {
        await style.removeStyleSource(_cyclistsSourceId);
      }
      if (cyclists.isEmpty) return;
      await _ensureCyclistsIcon();

      final features = cyclists
          .map((c) {
            final lat = (c['lat'] as num?)?.toDouble();
            final lng = (c['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            return {
              'type': 'Feature',
              'properties': {
                'user_id': c['user_id'],
                'username': (c['username'] as String?)?.trim().isNotEmpty ==
                        true
                    ? c['username']
                    : 'Ciclista',
                'speed_kmh': (c['speed_kmh'] as num?)?.toDouble() ?? 0,
                'heading': (c['heading'] as num?)?.toDouble() ?? 0,
              },
              'geometry': {
                'type': 'Point',
                'coordinates': [lng, lat],
              },
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      if (features.isEmpty) return;

      final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
      await style.addSource(GeoJsonSource(id: _cyclistsSourceId, data: fc));
      await style.addLayer(
        SymbolLayer(
          id: _cyclistsLayerId,
          sourceId: _cyclistsSourceId,
          iconImage: _cyclistsIconImageId,
          iconSize: 0.4,
          iconRotationAlignment: IconRotationAlignment.MAP,
          iconRotateExpression: const <Object>['get', 'heading'],
          // Ciclistas en movimiento: mejor mostrarlos siempre a que se
          // oculten entre ellos por colisión de íconos.
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error actualizando ciclistas activos: $e');
    }
  }

  void _showCyclistModal(Map<String, dynamic> props) {
    final name = props['username']?.toString() ?? 'Ciclista';
    final speed = (props['speed_kmh'] as num?)?.toDouble() ?? 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF7CF0BC),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_bike_rounded,
                  color: Colors.black, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(
                    speed > 1
                        ? '${speed.toStringAsFixed(0)} km/h · pedaleando ahora'
                        : 'Pedaleando ahora',
                    style: const TextStyle(
                        fontFamily: 'Poppins', color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ESTACIONAMIENTOS DE BICI
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureParkingIcon() async {
    if (mapboxMap == null || !_styleIsLoaded || _bikeParkingsIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_parkingIconId)) {
        _bikeParkingsIconAdded = true;
        return;
      }
      final bytes = await _renderAlertIcon(
        const Color(0xFF00BCD4),
        Icons.local_parking,
      );
      await style.addStyleImage(
        _parkingIconId,
        1.0,
        MbxImage(width: 80, height: 80, data: bytes),
        false,
        [],
        [],
        null,
      );
      _bikeParkingsIconAdded = true;
    } catch (e) {
      debugPrint('Error icono parking: $e');
    }
  }

  Future<void> _loadBikeParkings() async {
    if (_bikeParkingsLoading) return;
    setState(() => _bikeParkingsLoading = true);
    try {
      List? elements;
      // 1) Datos empacados en la app (instantáneo, offline y para todos por
      //    igual). Overpass en vivo fallaba en redes móviles, por lo que los
      //    estacionamientos no aparecían en algunos teléfonos.
      try {
        final raw = await rootBundle.loadString(
          'assets/data/bike_parkings_chile.json',
        );
        final decoded = jsonDecode(raw);
        elements = (decoded is Map ? decoded['elements'] : decoded) as List?;
        debugPrint('🅿️ Parkings empacados: ${elements?.length ?? 0}');
      } catch (e) {
        debugPrint('⚠️ No se pudo leer el asset de parkings: $e');
      }
      // 2) Respaldo: si no hay asset, intentar Overpass en vivo.
      if (elements == null || elements.isEmpty) {
        final p = _lastPosition;
        final bbox = p != null
            ? '(${p.latitude - 0.12},${p.longitude - 0.12},'
                  '${p.latitude + 0.12},${p.longitude + 0.12})'
            : '(-33.70,-70.95,-33.30,-70.45)';
        final query =
            '[out:json][timeout:25];'
            '(node["amenity"="bicycle_parking"]$bbox;'
            'way["amenity"="bicycle_parking"]$bbox;);'
            'out center;';
        elements = await _fetchOverpass(query);
      }
      if (elements != null) {
        _bikeParkings = elements
            .map<Map<String, dynamic>>((e) {
              double lat = 0, lng = 0;
              if (e['type'] == 'node') {
                lat = (e['lat'] as num).toDouble();
                lng = (e['lon'] as num).toDouble();
              } else {
                lat = (e['center']?['lat'] as num?)?.toDouble() ?? 0;
                lng = (e['center']?['lon'] as num?)?.toDouble() ?? 0;
              }
              final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
              final isCovered =
                  tags['covered'] == 'yes' ||
                  tags['bicycle_parking'] == 'shed' ||
                  tags['bicycle_parking'] == 'lockers';
              return {
                'id': e['id'].toString(),
                'lat': lat,
                'lng': lng,
                'name':
                    tags['name'] ?? tags['description'] ?? 'Estacionamiento',
                'capacity': tags['capacity'],
                'covered': isCovered ? 'Cubierto' : 'Descubierto',
                'type': tags['bicycle_parking'] ?? 'stands',
              };
            })
            .where((p) => (p['lat'] as double) != 0.0)
            .toList();
        debugPrint('🅿️ Parkings cargados: ${_bikeParkings.length}');
      }
    } catch (e) {
      debugPrint('Error cargando parkings: $e');
    } finally {
      if (mounted) setState(() => _bikeParkingsLoading = false);
    }
  }

  Future<void> _updateBikeParkingsLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_parkingLyrId)) {
      await style.removeStyleLayer(_parkingLyrId);
    }
    if (await style.styleSourceExists(_parkingSrcId)) {
      await style.removeStyleSource(_parkingSrcId);
    }
    if (!_showBikeParkings || _bikeParkings.isEmpty) return;
    await _ensureParkingIcon();
    final features = _bikeParkings
        .map(
          (p) => {
            'type': 'Feature',
            'properties': {
              'id': p['id'],
              'name': p['name'],
              'capacity': p['capacity'],
              'covered': p['covered'],
              'type': p['type'],
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [p['lng'], p['lat']],
            },
          },
        )
        .toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _parkingSrcId, data: fc));
    await style.addLayer(
      SymbolLayer(
        id: _parkingLyrId,
        sourceId: _parkingSrcId,
        iconImage: _parkingIconId,
        iconSize: 0.35,
        // Detección de colisiones: Mapbox oculta los pines que se encimarían y
        // muestra un conjunto representativo y legible en cualquier zoom (ni
        // amontonado ni vacío). Al acercarse aparecen más.
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
    );
  }

  void _toggleBikeParkings() async {
    final newVal = !_showBikeParkings;
    setState(() => _showBikeParkings = newVal);
    if (newVal && _bikeParkings.isEmpty) {
      await _loadBikeParkings();
    }
    await _updateBikeParkingsLayer();
  }

  void _showBikeParkingModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final parking = _bikeParkings.firstWhere(
      (p) => p['id'] == id,
      orElse: () => props,
    );
    final destLat = (parking['lat'] as num?)?.toDouble() ?? 0;
    final destLng = (parking['lng'] as num?)?.toDouble() ?? 0;
    final destName = parking['name']?.toString() ?? 'Estacionamiento';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00BCD4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_parking,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destName,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        parking['covered']?.toString() ?? 'Descubierto',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (parking['capacity'] != null)
              _infoRow(
                Icons.bike_scooter,
                'Capacidad',
                '${parking['capacity']} bicis',
              ),
            _infoRow(
              Icons.inventory_2_outlined,
              'Tipo',
              parking['type']?.toString() ?? 'stands',
            ),
            const SizedBox(height: 16),
            _PoiPhotoGallery(
              poiType: 'bike_parking',
              poiId: id,
              accentColor: const Color(0xFF00BCD4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0
                    ? () => _navigateTo(destLat, destLng, destName)
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BCD4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BICIMETRO
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _ensureBicimetroIcon() async {
    if (mapboxMap == null || !_styleIsLoaded || _bicimetroIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage(_bicimetroIconId)) {
        _bicimetroIconAdded = true;
        return;
      }
      final bytes = await _renderAlertIcon(
        const Color(0xFF7C3AED),
        Icons.train,
      );
      await style.addStyleImage(
        _bicimetroIconId,
        1.0,
        MbxImage(width: 80, height: 80, data: bytes),
        false,
        [],
        [],
        null,
      );
      _bicimetroIconAdded = true;
    } catch (e) {
      debugPrint('Error icono bicimetro: $e');
    }
  }

  Future<void> _updateBicimetroLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_bicimetroLyrId)) {
      await style.removeStyleLayer(_bicimetroLyrId);
    }
    if (await style.styleSourceExists(_bicimetroSrcId)) {
      await style.removeStyleSource(_bicimetroSrcId);
    }
    if (!_showBicimetro) return;
    await _ensureBicimetroIcon();
    final features = _kBicimetroStations
        .map(
          (s) => {
            'type': 'Feature',
            'properties': {
              'name': s['name'].toString(),
              'line': s['line'].toString(),
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [s['lng'], s['lat']],
            },
          },
        )
        .toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _bicimetroSrcId, data: fc));
    await style.addLayer(
      SymbolLayer(
        id: _bicimetroLyrId,
        sourceId: _bicimetroSrcId,
        iconImage: _bicimetroIconId,
        iconSize: 0.35,
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
    );
  }

  void _toggleBicimetro() async {
    setState(() => _showBicimetro = !_showBicimetro);
    await _updateBicimetroLayer();
  }

  void _showBicimetroModal(Map<String, dynamic> props) {
    final name = props['name']?.toString() ?? 'Estación';
    final line = props['line']?.toString() ?? '';
    final station = _kBicimetroStations.firstWhere(
      (s) => s['name'].toString() == name,
      orElse: () => const {'lat': 0.0, 'lng': 0.0, 'name': '', 'line': ''},
    );
    final destLat = (station['lat'] as num).toDouble();
    final destLng = (station['lng'] as num).toDouble();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF7C3AED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.train, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Metro $line',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Horarios BiciMetro',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.check_circle,
                    'Fin de semana',
                    'Todo el día ✔',
                  ),
                  _infoRow(
                    Icons.check_circle,
                    'Lunes – viernes',
                    '9:00 – 18:00  ·  20:00 en adelante ✔',
                  ),
                  _infoRow(Icons.block, 'Punta mañana', '7:00 – 9:00 ✖'),
                  _infoRow(Icons.block, 'Punta tarde', '18:00 – 20:00 ✖'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PoiPhotoGallery(
              poiType: 'bicimetro',
              poiId: name,
              accentColor: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0
                    ? () => _navigateTo(destLat, destLng, name)
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir a esta estación'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SERVICIOS PARA BICI — inflado / talleres / gasolineras con aire (OSM)
  // ══════════════════════════════════════════════════════════════════════════

  /// Devuelve (color, ícono Material) según la categoría del servicio.
  static (Color, IconData) _serviceStyle(String category) {
    switch (category) {
      case 'repair': // punto público de inflado/reparación
        return (const Color(0xFF22C55E), Icons.build); // llave de reparación
      case 'shop': // taller / tienda de bicis
        return (const Color(0xFF3B82F6), Icons.storefront); // tienda
      case 'fuel': // gasolinera con aire (Copec, etc.)
        return (const Color(0xFFE2231A), Icons.local_gas_station); // rojo Copec
      case 'water': // punto de agua / hidratación
        return (const Color(0xFF2196F3), Icons.water_drop); // azul agua
      default:
        return (const Color(0xFF22C55E), Icons.air);
    }
  }

  static String _serviceLabel(String category) {
    switch (category) {
      case 'repair':
        return 'Punto de inflado / reparación';
      case 'shop':
        return 'Taller / tienda de bicis';
      case 'fuel':
        return 'Gasolinera con aire';
      case 'water':
        return 'Punto de agua (hidratación)';
      default:
        return 'Servicio para bici';
    }
  }

  Future<void> _ensureServicesIcons() async {
    if (mapboxMap == null || _bikeServicesIconsAdded) return;
    try {
      final style = mapboxMap!.style;
      for (final cat in ['repair', 'shop', 'fuel', 'water']) {
        final iconId = 'svc-icon-$cat';
        if (await style.hasStyleImage(iconId)) continue;
        final (color, icon) = _serviceStyle(cat);
        final bytes = await _renderPinIcon(color, icon);
        await style.addStyleImage(
          iconId,
          1.0,
          MbxImage(width: 84, height: 108, data: bytes),
          false,
          [],
          [],
          null,
        );
      }

      // Pin especial con el logo de Copec dentro de la cabeza.
      if (!await style.hasStyleImage('svc-icon-fuel-copec')) {
        final data = await rootBundle.load('assets/brands/copec.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        final bytes = await _renderLogoPin(
          frame.image,
          const Color(0xFFE2231A),
        );
        await style.addStyleImage(
          'svc-icon-fuel-copec',
          1.0,
          MbxImage(width: 88, height: 112, data: bytes),
          false,
          [],
          [],
          null,
        );
      }

      _bikeServicesIconsAdded = true;
    } catch (e) {
      debugPrint('Error iconos servicios: $e');
    }
  }

  /// Pin tipo globito con un logo (imagen) dentro de la cabeza blanca.
  Future<Uint8List> _renderLogoPin(ui.Image logo, Color tailColor) async {
    const double w = 88;
    const double h = 112;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final center = const ui.Offset(w / 2, w / 2 + 2);
    final headR = w / 2 - 4;
    final tip = const ui.Offset(w / 2, h - 3);

    final shadow = ui.Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 3), headR, shadow);

    // Cola + aro del color de la marca
    final colorPaint = ui.Paint()..color = tailColor;
    final body = ui.Path()
      ..moveTo(center.dx - headR * 0.6, center.dy + headR * 0.72)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(center.dx + headR * 0.6, center.dy + headR * 0.72)
      ..close();
    canvas.drawPath(body, colorPaint);
    canvas.drawCircle(center, headR, colorPaint);

    // Cabeza blanca
    canvas.drawCircle(center, headR - 4, ui.Paint()..color = Colors.white);

    // Logo recortado dentro de la cabeza (contain por el lado mayor)
    canvas.save();
    canvas.clipPath(
      ui.Path()..addOval(ui.Rect.fromCircle(center: center, radius: headR - 6)),
    );
    final d = (headR - 8) * 2;
    final lw = logo.width.toDouble();
    final lh = logo.height.toDouble();
    final scale = d / (lw > lh ? lw : lh);
    final dst = ui.Rect.fromCenter(
      center: center,
      width: lw * scale,
      height: lh * scale,
    );
    canvas.drawImageRect(logo, ui.Rect.fromLTWH(0, 0, lw, lh), dst, ui.Paint());
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  /// Consulta Overpass probando varios servidores espejo en orden hasta que
  /// uno responda. Devuelve la lista de `elements` o null si todos fallan.
  Future<List?> _fetchOverpass(String query) async {
    const mirrors = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
      'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    ];
    for (final url in mirrors) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              body: 'data=${Uri.encodeQueryComponent(query)}',
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return data['elements'] as List;
        }
        debugPrint('Overpass $url → HTTP ${res.statusCode}');
      } catch (e) {
        debugPrint('Overpass $url falló: $e');
      }
    }
    return null;
  }

  /// Carga el dataset de servicios (talleres, aire, Copec y otras gasolineras)
  /// de todo Chile. Usa el archivo incluido en la app — cubre el país
  /// completo y siempre está disponible, sin depender de internet ni de
  /// una consulta pesada a Overpass en cada sesión.
  Future<void> _loadBikeServices() async {
    if (_bikeServicesLoading) return;
    setState(() => _bikeServicesLoading = true);
    try {
      if (_bikeServices.isEmpty) {
        _bikeServices = await _loadBundledServices();
        debugPrint('🔧 Servicios (incluidos, Chile): ${_bikeServices.length}');
      }
    } catch (e) {
      debugPrint('Error cargando servicios bici: $e');
    } finally {
      if (mounted) setState(() => _bikeServicesLoading = false);
    }
  }

  /// Lee el dataset de servicios (todo Chile) incluido en los assets de la app.
  Future<List<Map<String, dynamic>>> _loadBundledServices() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/bike_services_chile.json',
      );
      final list = (jsonDecode(raw) as List);
      return list.map<Map<String, dynamic>>((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'].toString(),
          'lat': (m['lat'] as num).toDouble(),
          'lng': (m['lng'] as num).toDouble(),
          'name': m['name'],
          'brand': m['brand'],
          'category': m['category'],
          'icon_id': m['icon_id'],
          'has_pump': m['has_pump'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error leyendo dataset incluido: $e');
      return [];
    }
  }

  Future<void> _updateBikeServicesLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_servicesLyrId)) {
      await style.removeStyleLayer(_servicesLyrId);
    }
    if (await style.styleSourceExists(_servicesSrcId)) {
      await style.removeStyleSource(_servicesSrcId);
    }
    if (!_showBikeServices || _bikeServices.isEmpty) return;
    await _ensureServicesIcons();
    final features = _bikeServices
        .map(
          (p) => {
            'type': 'Feature',
            'properties': {
              'id': p['id'],
              'name': p['name'],
              'category': p['category'],
              'icon_id': p['icon_id'],
              'has_pump': p['has_pump'],
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [p['lng'], p['lat']],
            },
          },
        )
        .toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _servicesSrcId, data: fc));
    await style.addLayer(
      SymbolLayer(
        id: _servicesLyrId,
        sourceId: _servicesSrcId,
        iconImage: 'svc-icon-repair', // se sobreescribe por feature abajo
        iconSize: 0.42,
        iconAnchor: IconAnchor.BOTTOM, // la punta del pin marca el lugar
        // Colisión: declutter automático sin desaparecer del todo al alejarse.
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
    );
    // Ícono según la categoría de cada punto.
    await style.setStyleLayerProperty(
      _servicesLyrId,
      'icon-image',
      jsonEncode(['get', 'icon_id']),
    );
  }

  /// Carga (una sola vez) las capas activas por defecto, esperando a tener un
  /// fix de GPS para consultar solo el área alrededor del usuario.
  void _maybeAutoLoadLayers() {
    if (_autoLayersTriggered || mapboxMap == null || _lastPosition == null) {
      return;
    }
    _autoLayersTriggered = true;
    if (_showBikeParkings && _bikeParkings.isEmpty && !_bikeParkingsLoading) {
      _loadBikeParkings().then((_) => _updateBikeParkingsLayer());
    }
    if (_showBikeServices && _bikeServices.isEmpty && !_bikeServicesLoading) {
      _loadBikeServices().then((_) => _updateBikeServicesLayer());
    }
  }

  void _toggleBikeServices() async {
    final newVal = !_showBikeServices;
    setState(() => _showBikeServices = newVal);
    if (newVal && _bikeServices.isEmpty) {
      await _loadBikeServices();
      if (mounted) {
        final n = _bikeServices.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n > 0
                  ? '✅ $n puntos cargados (talleres, aire y gasolineras)'
                  : '⚠️ No se encontraron puntos',
            ),
            backgroundColor: n > 0 ? Colors.green : Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    await _updateBikeServicesLayer();
  }

  void _showBikeServiceModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final svc = _bikeServices.firstWhere(
      (p) => p['id'] == id,
      orElse: () => props,
    );
    final destLat = (svc['lat'] as num?)?.toDouble() ?? 0;
    final destLng = (svc['lng'] as num?)?.toDouble() ?? 0;
    final category = svc['category']?.toString() ?? 'repair';
    final name = svc['name']?.toString() ?? _serviceLabel(category);
    final hasPump = svc['has_pump'] == true;
    final (color, icon) = _serviceStyle(category);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _serviceLabel(category),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(
              hasPump ? Icons.check_circle : Icons.help_outline,
              'Bomba de aire',
              hasPump
                  ? 'Disponible'
                  : (category == 'fuel'
                        ? 'Consultar en el local'
                        : 'No confirmado'),
            ),
            if (category == 'fuel' &&
                svc['brand'] != null &&
                svc['brand'].toString().isNotEmpty)
              _infoRow(
                Icons.local_gas_station,
                'Marca',
                svc['brand'].toString(),
              ),
            const SizedBox(height: 16),
            _PoiPhotoGallery(
              poiType: 'bike_service',
              poiId: id,
              accentColor: color,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: destLat != 0
                    ? () => _navigateTo(destLat, destLng, name)
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CICLORECREOVÍA — cierres de calles dominicales para ciclistas
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> _loadCicloRecreo() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/ciclorecreovia.json',
      );
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error cargando CicloRecreoVía: $e');
      return [];
    }
  }

  Future<void> _ensureCicloRecreoIcon() async {
    if (mapboxMap == null || !_styleIsLoaded || _cicloRecreoIconAdded) return;
    try {
      final style = mapboxMap!.style;
      if (await style.hasStyleImage('crv-icon')) {
        _cicloRecreoIconAdded = true;
        return;
      }
      // Pin lima con ícono de evento/bici (cierre recreativo).
      final bytes = await _renderPinIcon(
        const Color(0xFF7CB342),
        Icons.event_available,
      );
      await style.addStyleImage(
        'crv-icon',
        1.0,
        MbxImage(width: 84, height: 108, data: bytes),
        false,
        [],
        [],
        null,
      );
      _cicloRecreoIconAdded = true;
    } catch (e) {
      debugPrint('Error icono CicloRecreoVía: $e');
    }
  }

  Future<void> _updateCicloRecreoLayer() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;
    if (await style.styleLayerExists(_crvLyrId)) {
      await style.removeStyleLayer(_crvLyrId);
    }
    if (await style.styleSourceExists(_crvSrcId)) {
      await style.removeStyleSource(_crvSrcId);
    }
    if (!_showCicloRecreo || _cicloRecreoPoints.isEmpty) return;
    await _ensureCicloRecreoIcon();
    final features = _cicloRecreoPoints
        .map(
          (p) => {
            'type': 'Feature',
            'properties': {'id': p['id'], 'comuna': p['comuna']},
            'geometry': {
              'type': 'Point',
              'coordinates': [
                (p['lng'] as num).toDouble(),
                (p['lat'] as num).toDouble(),
              ],
            },
          },
        )
        .toList();
    final fc = jsonEncode({'type': 'FeatureCollection', 'features': features});
    await style.addSource(GeoJsonSource(id: _crvSrcId, data: fc));
    await style.addLayer(
      SymbolLayer(
        id: _crvLyrId,
        sourceId: _crvSrcId,
        iconImage: 'crv-icon',
        iconSize: 0.42,
        iconAnchor: IconAnchor.BOTTOM,
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
    );
  }

  void _toggleCicloRecreo() async {
    setState(() => _showCicloRecreo = !_showCicloRecreo);
    await _updateCicloRecreoLayer();
  }

  void _showCicloRecreoModal(Map<String, dynamic> props) {
    final id = props['id']?.toString() ?? '';
    final p = _cicloRecreoPoints.firstWhere(
      (e) => e['id'] == id,
      orElse: () => props,
    );
    final lat = (p['lat'] as num?)?.toDouble() ?? 0;
    final lng = (p['lng'] as num?)?.toDouble() ?? 0;
    final comuna = p['comuna']?.toString() ?? 'CicloRecreoVía';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF7CB342),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.event_available,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CicloRecreoVía',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        comuna,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(Icons.route, 'Ruta', p['ruta']?.toString() ?? '-'),
            _infoRow(
              Icons.calendar_today,
              'Días',
              p['dias']?.toString() ?? 'Domingos',
            ),
            _infoRow(
              Icons.schedule,
              'Horario',
              p['horario']?.toString() ?? '09:00 a 14:00',
            ),
            const SizedBox(height: 8),
            Text(
              p['descripcion']?.toString() ?? '',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: lat != 0
                    ? () => _navigateTo(lat, lng, 'CicloRecreoVía $comuna')
                    : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Ir aquí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7CB342),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BÚSQUEDA DE DESTINO — Mapbox Geocoding (sin backend propio)
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<_GeoResult>> _geocodePlaces(String query) async {
    if (query.trim().length < 3) return [];
    // Sesgar resultados hacia la ubicación del usuario (o centro de Santiago).
    final prox = _lastPosition != null
        ? '${_lastPosition!.longitude},${_lastPosition!.latitude}'
        : '-70.6483,-33.4569';
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query.trim())}.json'
        '?access_token=$kMapboxToken'
        '&country=cl&language=es&limit=6&proximity=$prox';
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (body['features'] as List?) ?? [];
      return feats.map((f) {
        final m = f as Map<String, dynamic>;
        final center = m['center'] as List; // [lng, lat]
        return _GeoResult(
          name: (m['text'] ?? '') as String,
          fullName: (m['place_name'] ?? '') as String,
          lng: (center[0] as num).toDouble(),
          lat: (center[1] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _openPlaceSearch() {
    final controller = TextEditingController();
    Timer? debounce;
    List<_GeoResult> results = [];
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            void runSearch(String q) {
              debounce?.cancel();
              if (q.trim().length < 3) {
                setSheet(() {
                  results = [];
                  loading = false;
                });
                return;
              }
              setSheet(() => loading = true);
              debounce = Timer(const Duration(milliseconds: 400), () async {
                final r = await _geocodePlaces(q);
                setSheet(() {
                  results = r;
                  loading = false;
                });
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xF5080810),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: runSearch,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: '¿A dónde quieres ir?',
                        hintStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        suffixIcon: loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.greenAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (results.isEmpty &&
                        !loading &&
                        controller.text.trim().length >= 3)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Sin resultados. Prueba con otro nombre.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else if (results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'Escribe una calle, plaza o lugar de Santiago',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.4,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (_, i) {
                            final r = results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.place,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              title: Text(
                                r.name,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                r.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              onTap: () {
                                debounce?.cancel();
                                _navigateTo(r.lat, r.lng, r.name);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _navigateTo(double destLat, double destLng, String name) async {
    if (!mounted) return;
    Navigator.pop(context); // Cierra el modal

    // Ocultar todas las capas de markers opcionales, guardando estado previo
    setState(() {
      _prevShowBikeParkings = _showBikeParkings;
      _prevShowBicimetro = _showBicimetro;
      _prevShowBikeServices = _showBikeServices;
      _showBikeParkings = false;
      _showBicimetro = false;
      _showBikeServices = false;
      _routePlannerOpen = true;
      _routeWps.clear();
      _routeDistKm = null;
      _routeDurMin = null;
      _routeDifficulty = null;
      _routeElevGain = null;
    });
    await _updateBikeParkingsLayer();
    await _updateBicimetroLayer();
    await _updateBikeServicesLayer();

    // El punto de partida ya lo agrega _calcRoute() automáticamente con tu
    // GPS en vivo — acá solo hace falta la parada de destino.
    _routeWps.add(_RouteWp(lat: destLat, lng: destLng, label: name));

    await _loadFavorites();
    await _redrawRoutePins();

    if (_routeWps.isNotEmpty) await _calcRoute();
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, color: Colors.greenAccent, size: 13),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white70,
              fontSize: 12,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  DIFICULTAD DE RUTA — Open-Elevation API
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchRouteElevation() async {
    if (_routeCoords.isEmpty) return;
    if (mounted) setState(() => _elevationLoading = true);
    try {
      // Muestrear hasta 30 puntos equidistantes
      final total = _routeCoords.length;
      final step = (total / 30).ceil().clamp(1, total);
      final sample = <Map<String, double>>[];
      for (int i = 0; i < total; i += step) {
        // _routeCoords almacena [lng, lat]
        sample.add({
          'latitude': _routeCoords[i][1],
          'longitude': _routeCoords[i][0],
        });
      }
      // Asegurar que incluimos el último punto
      if (sample.last['latitude'] != _routeCoords.last[1]) {
        sample.add({
          'latitude': _routeCoords.last[1],
          'longitude': _routeCoords.last[0],
        });
      }

      final body = jsonEncode({'locations': sample});
      final res = await http
          .post(
            Uri.parse('https://api.open-elevation.com/api/v1/lookup'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List;
        double gain = 0.0;
        for (int i = 1; i < results.length; i++) {
          final diff =
              (results[i]['elevation'] as num) -
              (results[i - 1]['elevation'] as num);
          if (diff > 0) gain += diff.toDouble();
        }
        final difficulty = gain < 100
            ? 'Fácil'
            : gain < 300
            ? 'Moderada'
            : 'Difícil';
        if (mounted) {
          setState(() {
            _routeElevGain = gain;
            _routeDifficulty = difficulty;
            _elevationLoading = false;
          });
        }
        debugPrint('🏔️ Desnivel: ${gain.toStringAsFixed(0)}m → $difficulty');
      } else {
        if (mounted) setState(() => _elevationLoading = false);
      }
    } catch (e) {
      debugPrint('Error elevación: $e');
      if (mounted) setState(() => _elevationLoading = false);
    }
  }
}

// ✅ GALERÍA DE FOTOS DE POI (subidas por la comunidad, no vienen de ninguna
// API externa — se llenan con el uso, como Waze/Google Maps).
class _PoiPhotoGallery extends StatefulWidget {
  final String poiType;
  final String poiId;
  final Color accentColor;

  const _PoiPhotoGallery({
    required this.poiType,
    required this.poiId,
    required this.accentColor,
  });

  @override
  State<_PoiPhotoGallery> createState() => _PoiPhotoGalleryState();
}

class _PoiPhotoGalleryState extends State<_PoiPhotoGallery> {
  final _service = PoiPhotosService();
  List<PoiPhoto> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.poiId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final photos = await _service.getPhotos(
      poiType: widget.poiType,
      poiId: widget.poiId,
    );
    if (mounted) {
      setState(() {
        _photos = photos;
        _loading = false;
      });
    }
  }

  Future<void> _addPhoto() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para subir una foto')),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    final result = await _service.uploadPhoto(
      poiType: widget.poiType,
      poiId: widget.poiId,
      photoFile: File(picked.path),
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result != null) {
      setState(() => _photos.insert(0, result));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo subir la foto, intenta de nuevo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Fotos del lugar',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _uploading ? null : _addPhoto,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _uploading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.accentColor,
                          ),
                        )
                      : Icon(
                          Icons.add_a_photo_outlined,
                          size: 15,
                          color: widget.accentColor,
                        ),
                  const SizedBox(width: 4),
                  Text(
                    'Agregar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: widget.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          Text(
            'Sé el primero en subir una foto de referencia',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey[600],
              fontSize: 12,
            ),
          )
        else
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _photos[i].photoUrl,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 76,
                    height: 76,
                    color: Colors.white10,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ✅ FORMULARIO SIMPLE PARA ALERTA
class _SimpleAlertFormDialog extends StatefulWidget {
  final Point point;

  const _SimpleAlertFormDialog({required this.point});

  @override
  State<_SimpleAlertFormDialog> createState() => _SimpleAlertFormDialogState();
}

class _SimpleAlertFormDialogState extends State<_SimpleAlertFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  String _selectedType = 'danger';
  File? _photoFile;
  final bool _uploadingPhoto = false;

  final Map<String, AlertTypeInfo> _alertTypes = {
    'danger': AlertTypeInfo(Icons.warning, Colors.red, 'Peligro'),
    'theft': AlertTypeInfo(Icons.no_accounts, Colors.purple, 'Robo'),
    'construction': AlertTypeInfo(Icons.construction, Colors.orange, 'Obras'),
    'accident': AlertTypeInfo(Icons.car_crash, Colors.deepOrange, 'Accidente'),
    'other': AlertTypeInfo(Icons.info, Colors.blue, 'Otro'),
  };

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        setState(() => _photoFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error seleccionando imagen: $e');
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.greenAccent,
              ),
              title: const Text(
                'Tomar foto',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Colors.greenAccent,
              ),
              title: const Text(
                'Elegir de galería',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_photoFile != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Eliminar foto',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.redAccent,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _photoFile = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _alertTypes[_selectedType]?.color ?? Colors.red;

    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E18),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.07)),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _alertTypes[_selectedType]?.icon ?? Icons.warning,
                    color: accentColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Nueva Alerta',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            // Contenido scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips de tipo
                      const Text(
                        'TIPO',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _alertTypes.entries.map((entry) {
                          final isSelected = _selectedType == entry.key;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedType = entry.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? entry.value.color.withOpacity(0.18)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? entry.value.color.withOpacity(0.7)
                                      : Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    entry.value.icon,
                                    color: isSelected
                                        ? entry.value.color
                                        : Colors.white38,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    entry.value.label,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: isSelected
                                          ? entry.value.color
                                          : Colors.white38,
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Título
                      const Text(
                        'DETALLES',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Título',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: accentColor.withOpacity(0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _descriptionController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Descripción',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: accentColor.withOpacity(0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _locationController,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Nombre del lugar (opcional)',
                          labelStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sección foto
                      const Text(
                        'FOTO DEL SECTOR',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _showPhotoOptions,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: _photoFile != null ? 140 : 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _photoFile != null
                                  ? Colors.greenAccent.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.1),
                              width: _photoFile != null ? 1.5 : 1,
                            ),
                          ),
                          child: _photoFile != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.file(
                                        _photoFile!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _photoFile = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_outlined,
                                      color: Colors.white24,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Agregar foto (opcional)',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),

            // Botones fijos abajo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _uploadingPhoto
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.pop(context, {
                                  'type': _selectedType,
                                  'title': _titleController.text,
                                  'description': _descriptionController.text,
                                  'locationName':
                                      _locationController.text.isNotEmpty
                                      ? _locationController.text
                                      : 'Ubicación seleccionada',
                                  'photoFile': _photoFile,
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Crear Alerta'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}

class AlertTypeInfo {
  final IconData icon;
  final Color color;
  final String label;

  AlertTypeInfo(this.icon, this.color, this.label);
}

/// Banner promocional de Pedalea Plus dentro del drawer, justo arriba de
/// "CUENTA". Si el usuario ya es Plus, en vez del anuncio muestra un
/// mensaje de agradecimiento.
class _DrawerPlusBanner extends StatefulWidget {
  const _DrawerPlusBanner();

  @override
  State<_DrawerPlusBanner> createState() => _DrawerPlusBannerState();
}

class _DrawerPlusBannerState extends State<_DrawerPlusBanner> {
  final _supabase = Supabase.instance.client;
  bool? _isPlus;

  @override
  void initState() {
    super.initState();
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null &&
        uid == _ProfileButtonState.cachedForUid &&
        _ProfileButtonState.cachedProfile != null) {
      _isPlus = _ProfileButtonState.cachedProfile!['is_plus'] as bool? ?? false;
    } else {
      final cached = CacheService.loadProfile();
      _isPlus = cached?['is_plus'] as bool? ?? false;
      _load();
    }
  }

  Future<void> _load() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await _supabase
          .from('profiles')
          .select('is_plus')
          .eq('id', uid)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _isPlus = data['is_plus'] as bool? ?? false);
      }
    } catch (_) {
      // Sin conexión: se queda con lo último que había en caché.
    }
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFF2C94C);
    final isPlus = _isPlus ?? false;

    if (isPlus) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: goldColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: goldColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              // Medalla con la variante que eligió el ciclista.
              const PlusMedal(size: 24, ringColor: Color(0xFF0E0E16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gracias por ser Pedalea Plus 💛',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PaywallPage(
                reason: 'Desbloquea funciones exclusivas con Pedalea Plus.',
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                goldColor.withOpacity(0.20),
                goldColor.withOpacity(0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: goldColor.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: goldColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hazte Pedalea Plus',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Más funciones, sin límites',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: goldColor,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encabezado del drawer: nombre real del usuario (no el correo) + avatar
/// grande, con un fondo llamativo en degradado verde.
class _DrawerProfileHeader extends StatefulWidget {
  @override
  State<_DrawerProfileHeader> createState() => _DrawerProfileHeaderState();
}

class _DrawerProfileHeaderState extends State<_DrawerProfileHeader> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null &&
        uid == _ProfileButtonState.cachedForUid &&
        _ProfileButtonState.cachedProfile != null) {
      _profile = _ProfileButtonState.cachedProfile;
    } else {
      // Mientras llega la respuesta de red (o si falla por estar sin
      // conexión), mostrar lo último guardado en disco en vez del
      // placeholder "Ciclista Pedalea".
      _profile = CacheService.loadProfile();
      _load();
    }
  }

  Future<void> _load() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await _supabase
          .from('profiles')
          .select('username, full_name, avatar_url, is_plus')
          .eq('id', uid)
          .maybeSingle();
      if (data != null) await CacheService.saveProfile(data);
      if (mounted) setState(() => _profile = data);
    } catch (_) {
      // Sin conexión: se queda con lo que había en _profile (caché en disco
      // o el estático en memoria), no lo pisa con null.
    }
  }

  String get _displayName {
    final fullName = (_profile?['full_name'] as String? ?? '').trim();
    final username = (_profile?['username'] as String? ?? '').trim();
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return 'Ciclista Pedalea';
  }

  String get _initials {
    final name = _displayName;
    if (name.isEmpty || name == 'Ciclista Pedalea') return 'P';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _profile?['avatar_url'] as String?;
    final username = (_profile?['username'] as String? ?? '').trim();
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    const goldColor = Color(0xFFF2C94C);
    final ringColor = isPlus ? goldColor : const Color(0xFF7CF0BC);

    Future<void> openProfile() async {
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
      _ProfileButtonState.invalidateCache();
      _load();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [Color(0xFF2F8F63), Color(0xFF1E5C41), Color(0xFF153F2E)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          InkWell(
            onTap: openProfile,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ringColor, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: avatarUrl != null && avatarUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                placeholder: (_, _) => _headerFallback(),
                                errorWidget: (_, _, _) => _headerFallback(),
                              )
                            : _headerFallback(),
                      ),
                    ),
                    if (isPlus)
                      const Positioned(
                        bottom: -2,
                        right: -2,
                        child: PlusMedal(
                            size: 24, ringColor: Color(0xFF153F2E)),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _displayName,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPlus) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: goldColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: goldColor.withOpacity(0.4),
                                ),
                              ),
                              child: const Text(
                                'PLUS',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: goldColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Ver perfil",
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 13,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerFallback() {
    return Container(
      color: Colors.greenAccent.withOpacity(0.12),
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.greenAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Botón circular de perfil para la barra superior del mapa.
class _ProfileButton extends StatefulWidget {
  final bool isDayMode;
  const _ProfileButton({this.isDayMode = false});

  @override
  State<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<_ProfileButton> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;

  // Caché en memoria compartida entre todas las instancias (drawer + botón
  // flotante sobre el mapa): evita volver a golpear Supabase cada vez que el
  // widget se remonta, que pasa seguido porque el mapa se redibuja mucho.
  static Map<String, dynamic>? _cachedProfile;
  static String? _cachedForUid;

  static Map<String, dynamic>? get cachedProfile => _cachedProfile;
  static String? get cachedForUid => _cachedForUid;

  @override
  void initState() {
    super.initState();
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null && uid == _cachedForUid && _cachedProfile != null) {
      _profile = _cachedProfile; // usa el caché de inmediato, sin parpadeo
    } else {
      _loadProfile();
    }
  }

  /// Fuerza recargar desde la BD (ej. al volver de editar el perfil).
  static void invalidateCache() {
    _cachedProfile = null;
    _cachedForUid = null;
  }

  Future<void> _loadProfile() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await _supabase
          .from('profiles')
          .select('username, full_name, avatar_url, is_plus')
          .eq('id', uid)
          .maybeSingle();
      _cachedProfile = data;
      _cachedForUid = uid;
      if (mounted) setState(() => _profile = data);
    } catch (_) {
      // Sin conexión o sin fila aún: se queda con las iniciales de fallback.
    }
  }

  String _initials(String? fullName, String? username, String? email) {
    final name =
        (fullName?.trim().isNotEmpty == true
                ? fullName!
                : username?.trim().isNotEmpty == true
                ? username!
                : email ?? '')
            .trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final avatarUrl = _profile?['avatar_url'] as String?;
    final fullName = _profile?['full_name'] as String?;
    final username = _profile?['username'] as String?;
    final email = user?.email;
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    final ringColor = isPlus ? Colors.amber : Colors.greenAccent;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
        // Al volver del perfil, refresca por si cambió la foto o el nombre.
        _ProfileButtonState.invalidateCache();
        _loadProfile();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ringColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      placeholder: (_, _) =>
                          _fallback(_initials(fullName, username, email)),
                      errorWidget: (_, _, _) =>
                          _fallback(_initials(fullName, username, email)),
                    )
                  : _fallback(_initials(fullName, username, email)),
            ),
          ),
          if (isPlus)
            const Positioned(
              bottom: -3,
              right: -3,
              child: PlusMedal(size: 16, ringColor: Color(0xFF0A1A0A)),
            ),
        ],
      ),
    );
  }

  Widget _fallback(String initials) {
    return Container(
      color: widget.isDayMode ? Colors.white : Colors.black.withOpacity(0.8),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: widget.isDayMode
                ? const Color(0xFF00A86B)
                : Colors.greenAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─── Waypoint del planificador de rutas ──────────────────────────────────────

class _RouteWp {
  final double lat;
  final double lng;
  final String label;
  const _RouteWp({required this.lat, required this.lng, required this.label});
}

/// Popup estilo "Pokémon GO" que pregunta si el usuario es pasajero
/// (auto/micro/metro) cuando la velocidad es demasiado alta para ir en bici.
class _PassengerPrompt extends StatelessWidget {
  final int speedKmh;
  const _PassengerPrompt({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 320),
        curve: Curves.elasticOut,
        tween: Tween(begin: 0.7, end: 1.0),
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12213A), Color(0xFF0A0A14)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.lightBlueAccent.withOpacity(0.25),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge de velocidad pulsante
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$speedKmh km/h',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.redAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '¡Vas muy rápido! 🏎️',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Eso es mucho para ir pedaleando.\n¿Vas como pasajero?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _vehicleOption(context, '🚗', 'Auto', 'auto'),
                  const SizedBox(width: 10),
                  _vehicleOption(context, '🚌', 'Micro', 'micro'),
                  const SizedBox(width: 10),
                  _vehicleOption(context, '🚇', 'Metro', 'metro'),
                ],
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, 'bici'),
                icon: const Text('🚴', style: TextStyle(fontSize: 16)),
                label: const Text(
                  'No, sigo pedaleando',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleOption(
    BuildContext context,
    String emoji,
    String label,
    String value,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.pop(context, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.lightBlueAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultado de búsqueda de lugar (geocoding de Mapbox).
class _GeoResult {
  final String name;
  final String fullName;
  final double lat;
  final double lng;
  const _GeoResult({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lng,
  });
}

/// Indicador visual que se expande al hacer long press en el mapa.
class _LongPressRipple extends StatefulWidget {
  final Offset position;
  const _LongPressRipple({required this.position});

  @override
  State<_LongPressRipple> createState() => _LongPressRippleState();
}

class _LongPressRippleState extends State<_LongPressRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.8,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - 40,
      top: widget.position.dy - 40,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context2, child2) => Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent, width: 3),
                  color: Colors.redAccent.withOpacity(0.25),
                ),
                child: const Center(
                  child: Icon(Icons.add_alert, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Botón de pánico ──────────────────────────────────────────────────────────

class _PanicButton extends StatefulWidget {
  @override
  State<_PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<_PanicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  String? _emergencyContactName;
  String? _emergencyContactPhone;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadEmergencyContact();
  }

  Future<void> _loadEmergencyContact() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('emergency_contact_name, emergency_contact_phone')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _emergencyContactName = data?['emergency_contact_name'] as String?;
        _emergencyContactPhone = data?['emergency_contact_phone'] as String?;
      });
    } catch (_) {
      // Sin conexión: el tile de contacto personal simplemente no aparece.
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir la app de teléfono en este dispositivo',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _messageEmergencyContact() async {
    final phone = _emergencyContactPhone;
    if (phone == null || phone.isEmpty) return;

    String locationText = ' No se pudo obtener la ubicación exacta.';
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      locationText =
          ' Ubicación: https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    } catch (_) {
      // Sin GPS disponible a tiempo: se envía igual sin coordenadas.
    }

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body': 'Necesito ayuda, tuve un problema pedaleando.$locationText',
      },
    );
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir la app de mensajes en este dispositivo',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showEmergencyMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EmergencySheet(
        onCall: _call,
        emergencyContactName: _emergencyContactName,
        emergencyContactPhone: _emergencyContactPhone,
        onMessageContact: _messageEmergencyContact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
      child: GestureDetector(
        onTap: () => _showEmergencyMenu(context),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.shade700,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.55),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.sos_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class _EmergencySheet extends StatelessWidget {
  final Future<void> Function(String) onCall;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final VoidCallback onMessageContact;

  const _EmergencySheet({
    required this.onCall,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.onMessageContact,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Sube el sheet si hay teclado o notch inferior
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F1A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.sos_rounded,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergencias Chile',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Selecciona el servicio de emergencia',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _EmergencyTile(
                icon: Icons.local_police_rounded,
                color: const Color(0xFF4A90D9),
                label: 'Carabineros',
                number: '133',
                description: 'Policía de Chile',
                onTap: () {
                  Navigator.pop(context);
                  onCall('133');
                },
              ),
              _EmergencyTile(
                icon: Icons.local_hospital_rounded,
                color: const Color(0xFFE53935),
                label: 'SAMU',
                number: '131',
                description: 'Urgencias médicas',
                onTap: () {
                  Navigator.pop(context);
                  onCall('131');
                },
              ),
              _EmergencyTile(
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF6D00),
                label: 'Bomberos',
                number: '132',
                description: 'Cuerpo de Bomberos',
                onTap: () {
                  Navigator.pop(context);
                  onCall('132');
                },
              ),
              if (emergencyContactPhone != null &&
                  emergencyContactPhone!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _EmergencyTile(
                  icon: Icons.sms_outlined,
                  color: Colors.greenAccent,
                  label: emergencyContactName?.isNotEmpty == true
                      ? emergencyContactName!
                      : 'Mi contacto',
                  number: emergencyContactPhone!,
                  description: 'Avisar por SMS que necesitas ayuda',
                  onTap: () {
                    Navigator.pop(context);
                    onMessageContact();
                  },
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white38),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String number;
  final String description;
  final VoidCallback onTap;

  const _EmergencyTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.number,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_rounded, color: color, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        number,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Diálogo de cuenta regresiva tras detectar una caída ────────────────────

class _FallCountdownDialog extends StatefulWidget {
  final Future<void> Function(String number) onCall;
  final VoidCallback onDisableTapped;
  const _FallCountdownDialog({
    required this.onCall,
    required this.onDisableTapped,
  });

  @override
  State<_FallCountdownDialog> createState() => _FallCountdownDialogState();
}

class _FallCountdownDialogState extends State<_FallCountdownDialog> {
  static const int _start = 15;
  int _remaining = _start;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _callEmergency();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _callEmergency() async {
    if (mounted) Navigator.of(context).pop();
    await widget.onCall('133'); // Carabineros
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: _remaining / _start,
                    strokeWidth: 6,
                    backgroundColor: Colors.red.withOpacity(0.15),
                    valueColor: const AlwaysStoppedAnimation(Colors.red),
                  ),
                ),
                Text(
                  '$_remaining',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '¿Tuviste una caída?',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Llamaremos a Carabineros (133) automáticamente si no respondes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Estoy bien'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _timer?.cancel();
                  _callEmergency();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Llamar ahora'),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                widget.onDisableTapped();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white38,
                padding: EdgeInsets.zero,
                minimumSize: ui.Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '¿Muchas alarmas falsas? Puedes desactivar esta opción',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Se muestra en vez de la tarjeta de compartir cuando el usuario NO tiene
/// Pedalea Plus: invita a suscribirse para desbloquear la función.
class _ShareUpsellSheet extends StatelessWidget {
  final double distanceKm;
  final VoidCallback onUpgrade;
  const _ShareUpsellSheet({required this.distanceKm, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber.withOpacity(0.25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withOpacity(0.12),
                border: Border.all(color: Colors.amber.withOpacity(0.35)),
              ),
              child: const Icon(
                Icons.ios_share_rounded,
                color: Colors.amber,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¡Pedaleaste ${distanceKm.toStringAsFixed(1)} km! 🚴',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Compartir tu ruta y estadísticas en historias es una función de Pedalea Plus.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpgrade,
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Ver Pedalea Plus'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text(
                'Ahora no',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Compartir viaje (ruta + estadísticas, estilo Strava) ─────────────────────

class _RouteShareSheet extends StatefulWidget {
  final double distanceKm;
  final Duration duration;
  final List<geo.Position> route;

  const _RouteShareSheet({
    required this.distanceKm,
    required this.duration,
    required this.route,
  });

  @override
  State<_RouteShareSheet> createState() => _RouteShareSheetState();
}

class _RouteShareSheetState extends State<_RouteShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  double get _avgSpeedKmh {
    final hours = widget.duration.inSeconds / 3600;
    if (hours <= 0) return 0;
    return widget.distanceKm / hours;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar la imagen');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/pedalea_viaje_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final co2 = Co2Service.savedKg(widget.distanceKm);
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '🚴 Acabo de pedalear ${widget.distanceKm.toStringAsFixed(1)} km en '
            '${_formatDuration(widget.duration)} con Pedalea 🌱 '
            '(${Co2Service.format(co2)} de CO₂ ahorrado)',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo compartir: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final co2 = Co2Service.savedKg(widget.distanceKm);
    final now = DateTime.now();
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final dateStr = '${now.day} ${meses[now.month - 1]} ${now.year}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '¡Buen viaje! 🚴',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Comparte tu recorrido con otros ciclistas',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0C2420), Color(0xFF12213F)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🚴', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        const Text(
                          'Pedalea',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        color: Colors.black.withOpacity(0.25),
                        child: CustomPaint(
                          painter: _RoutePainter(widget.route),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _statBlock(widget.distanceKm.toStringAsFixed(1), 'km'),
                        _statBlock(_formatDuration(widget.duration), 'tiempo'),
                        _statBlock(
                          _avgSpeedKmh.toStringAsFixed(1),
                          'km/h prom.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌱', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            '${Co2Service.format(co2)} de CO₂ ahorrado',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _sharing ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white38,
                    ),
                    child: const Text(
                      'Ahora no',
                      style: TextStyle(fontFamily: 'Poppins'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Compartir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBlock(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja un boceto simple de la ruta recorrida, normalizando las
/// coordenadas GPS al tamaño del lienzo disponible.
class _RoutePainter extends CustomPainter {
  final List<geo.Position> route;
  const _RoutePainter(this.route);

  @override
  void paint(Canvas canvas, ui.Size size) {
    if (route.length < 2) return;

    final lats = route.map((p) => p.latitude).toList();
    final lngs = route.map((p) => p.longitude).toList();
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final latRange = (maxLat - minLat).abs() < 1e-9 ? 1e-9 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 1e-9 ? 1e-9 : (maxLng - minLng);

    const padding = 20.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    Offset toOffset(geo.Position p) {
      final x = padding + ((p.longitude - minLng) / lngRange) * w;
      // Invertido: mayor latitud = más arriba en pantalla.
      final y = padding + (1 - (p.latitude - minLat) / latRange) * h;
      return Offset(x, y);
    }

    final path = Path();
    final first = toOffset(route.first);
    path.moveTo(first.dx, first.dy);
    for (final p in route.skip(1)) {
      final o = toOffset(p);
      path.lineTo(o.dx, o.dy);
    }

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    // Punto de inicio (blanco) y de fin (verde brillante).
    canvas.drawCircle(first, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      toOffset(route.last),
      6,
      Paint()..color = Colors.greenAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.route.length != route.length;
}

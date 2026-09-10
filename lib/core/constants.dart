// Reemplaza con tu token de Mapbox (https://account.mapbox.com)
const kMapboxToken = 'pk.eyJ1IjoiaWduYWNpb2FuZHJlcyIsImEiOiJjbWNsaDVwZzkwYW1xMmtweHg3Y2RoZXRpIn0.jNlD-Ra2hmiAZZNADrzQxg';

// Estilos SIN capa de tráfico (los "navigation-*" pintaban las calles de
// autos en verde/naranjo/rojo y se confundían con las ciclovías).
const kMapStyleNight = 'mapbox://styles/mapbox/dark-v11';
const kMapStyleDay   = 'mapbox://styles/mapbox/streets-v12';

// Estilos exclusivos de Pedalea Plus (elegibles a mano; no cambian con la
// hora). Se evitan los estilos "navigation-*" por la capa de tráfico.
const kMapStyleSatellite = 'mapbox://styles/mapbox/satellite-streets-v12';
const kMapStyleOutdoors  = 'mapbox://styles/mapbox/outdoors-v12';
const kMapStyleMinimal   = 'mapbox://styles/mapbox/light-v11';

/// Devuelve el estilo de mapa según la hora local.
String autoDarkMapStyle() {
  final hour = DateTime.now().hour;
  return (hour >= 7 && hour < 19) ? kMapStyleDay : kMapStyleNight;
}

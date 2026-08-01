package com.pedalea.app

import android.hardware.GeomagneticField
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val geomagneticChannel = "com.pedalea.app/geomagnetic"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Calcula la declinación magnética real (diferencia entre norte
        // magnético y norte geográfico) para una ubicación/fecha dadas, vía
        // la API nativa de Android. Mapbox no hace esta corrección
        // internamente en su motor de PuckBearing.HEADING, así que la
        // calculamos aparte para comparar contra el heading crudo del
        // sensor.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, geomagneticChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "declination") {
                    val lat = (call.argument<Double>("lat") ?: 0.0).toFloat()
                    val lon = (call.argument<Double>("lon") ?: 0.0).toFloat()
                    val alt = (call.argument<Double>("alt") ?: 0.0).toFloat()
                    val field = GeomagneticField(lat, lon, alt, System.currentTimeMillis())
                    result.success(field.declination.toDouble())
                } else {
                    result.notImplemented()
                }
            }
    }
}

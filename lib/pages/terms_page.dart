import 'package:flutter/material.dart';

const _kNavyBg = Color(0xFF0E1116);
const _kGreenAccent = Color(0xFF2E9C5A);

/// Pantalla con el detalle completo de Términos y Condiciones de Pedalea.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavyBg,
      appBar: AppBar(
        backgroundColor: _kNavyBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Términos y Condiciones',
          style: TextStyle(
            fontFamily: 'Sora',
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Última actualización: 30 de julio de 2026',
                style: TextStyle(
                  fontFamily: 'Sora',
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              ..._sections.map((s) => _TermsSection(title: s.$1, body: s.$2)),
            ],
          ),
        ),
      ),
    );
  }

  static final List<(String, String)> _sections = [
    (
      '1. Aceptación de los términos',
      'Al crear una cuenta o utilizar Pedalea ("la app", "el servicio"), aceptas quedar '
          'obligado por estos Términos y Condiciones y por nuestra Política de Privacidad. '
          'Si no estás de acuerdo con alguna parte de estos términos, no debes usar la app. '
          'El uso continuado del servicio después de una actualización de estos términos '
          'constituye tu aceptación de los cambios.',
    ),
    (
      '2. Descripción del servicio',
      'Pedalea es una aplicación para ciclistas urbanos de la Región Metropolitana de '
          'Chile que ofrece: un mapa con ciclovías, estacionamientos de bicicletas, '
          'estaciones BiciMetro, talleres y puntos de aire; planificación y navegación de '
          'rutas; alertas comunitarias de peligros en tiempo real; detección automática de '
          'caídas con contacto de emergencia; creación y participación en eventos grupales '
          'con chat integrado; estadísticas de uso y logros; y una suscripción opcional de '
          'pago ("Pedalea Plus") con funciones adicionales. El servicio puede cambiar, '
          'ampliarse o discontinuarse parcial o totalmente en cualquier momento, con o sin '
          'aviso previo, sin que esto genere derecho a compensación.',
    ),
    (
      '3. Elegibilidad y cuentas',
      'Debes tener al menos 13 años para usar Pedalea. Para acceder a la mayoría de las '
          'funciones necesitas crear una cuenta mediante correo electrónico y contraseña, o '
          'mediante inicio de sesión con Google. Eres responsable de mantener la '
          'confidencialidad de tus credenciales y de toda actividad que ocurra bajo tu '
          'cuenta. Debes notificarnos de inmediato ante cualquier uso no autorizado. '
          'Puedes solicitar la eliminación de tu cuenta en cualquier momento escribiendo a '
          'ignacioandres1201@gmail.com.',
    ),
    (
      '4. Conducta del usuario',
      'Al usar Pedalea te comprometes a: (a) proporcionar información veraz al registrarte '
          'y al reportar alertas, estacionamientos, talleres o incidentes; (b) no usar la '
          'app con fines ilegales, fraudulentos o para acosar, difamar o dañar a otros '
          'usuarios; (c) no publicar contenido ofensivo, violento, sexual, discriminatorio '
          'o que infrinja derechos de terceros en fotos, descripciones de eventos o chats; '
          '(d) no intentar vulnerar, realizar ingeniería inversa o interferir con la '
          'seguridad o el funcionamiento normal de la app o sus servidores; (e) no crear '
          'cuentas falsas ni suplantar la identidad de otra persona. Nos reservamos el '
          'derecho de suspender o eliminar cuentas que infrinjan estas reglas, sin previo '
          'aviso y a nuestra sola discreción.',
    ),
    (
      '5. Contenido generado por el usuario',
      'Tú conservas la propiedad del contenido que publiques (fotos, alertas, descripciones '
          'de eventos, mensajes de chat), pero al subirlo a Pedalea nos otorgas una licencia '
          'no exclusiva, mundial y libre de regalías para almacenarlo, mostrarlo a otros '
          'usuarios y procesarlo en la medida necesaria para operar el servicio (por '
          'ejemplo, mostrar tu foto de perfil o la ubicación de una alerta que reportaste). '
          'Eres el único responsable del contenido que publicas y garantizas que cuentas con '
          'los derechos necesarios para compartirlo. Podemos remover contenido que '
          'consideremos que infringe estos términos o la ley, sin necesidad de previo aviso.',
    ),
    (
      '6. Ubicación y datos de sensores',
      'Pedalea utiliza tu ubicación GPS para mostrar el mapa, calcular rutas, detectar '
          'caídas y activar alertas de proximidad. Si activas "Contar km en segundo plano", '
          'la app seguirá registrando tu ubicación mientras esa opción esté encendida, '
          'incluso con la app minimizada. Usamos el acelerómetro y otros sensores del '
          'dispositivo únicamente para la detección de caídas. Puedes desactivar los '
          'permisos de ubicación desde la configuración de tu dispositivo, entendiendo que '
          'esto puede limitar o inhabilitar funciones esenciales de la app.',
    ),
    (
      '7. Detección de caídas y funciones de seguridad — advertencia importante',
      'La detección automática de caídas, el botón de pánico y la notificación a tu '
          'contacto de confianza son herramientas de asistencia y NO reemplazan a los '
          'servicios de emergencia oficiales (Carabineros, SAMU, Bomberos). Estas funciones '
          'dependen de la conectividad de tu dispositivo, la precisión de sus sensores, el '
          'estado de la batería y otros factores fuera de nuestro control, por lo que no '
          'podemos garantizar que una caída sea detectada correctamente ni que una alerta '
          'llegue a destino en todos los casos. En una emergencia real, siempre debes '
          'contactar directamente a los servicios de emergencia. Pedalea, sus '
          'desarrolladores y colaboradores no serán responsables por daños derivados de '
          'fallas, retrasos o ausencia de detección de estas funciones.',
    ),
    (
      '8. Suscripción Pedalea Plus',
      'Pedalea Plus es una suscripción paga opcional que desbloquea rutas y eventos '
          'ilimitados, eventos privados con contraseña, estadísticas avanzadas y otras '
          'funciones adicionales. La compra se procesa a través de Google Play Billing; no '
          'almacenamos los datos de tu tarjeta o método de pago. La suscripción se renueva '
          'automáticamente al final de cada periodo salvo que la canceles antes de la fecha '
          'de renovación desde la configuración de tu cuenta de Google Play. Los precios '
          'pueden cambiar con aviso previo razonable; los cambios no afectan periodos ya '
          'pagados. Salvo que la ley aplicable exija lo contrario, los pagos realizados no '
          'son reembolsables.',
    ),
    (
      '9. Precisión de la información y mapas',
      'La información mostrada en Pedalea (ciclovías, estacionamientos, talleres, alertas, '
          'estimaciones de tiempo y distancia) proviene de fuentes propias, de la comunidad '
          'de usuarios y de proveedores externos como Mapbox, y puede contener errores, '
          'estar desactualizada o ser incompleta. Debes usar tu propio criterio y respetar '
          'siempre las normas de tránsito vigentes al planificar y seguir una ruta. No nos '
          'hacemos responsables por accidentes, multas, pérdidas o daños derivados de '
          'confiar exclusivamente en la información entregada por la app.',
    ),
    (
      '10. Propiedad intelectual',
      'La app, su diseño, logotipo, marca "Pedalea", código fuente y contenido original '
          '(excluyendo el contenido generado por usuarios) son propiedad de sus '
          'desarrolladores y están protegidos por las leyes de propiedad intelectual '
          'aplicables. No puedes copiar, modificar, distribuir o crear obras derivadas de '
          'la app sin autorización previa por escrito.',
    ),
    (
      '11. Terminación',
      'Podemos suspender o cancelar tu acceso a Pedalea, con o sin causa y con o sin previo '
          'aviso, especialmente en caso de incumplimiento de estos términos. Puedes dejar '
          'de usar la app y solicitar la eliminación de tu cuenta en cualquier momento. Las '
          'disposiciones que por su naturaleza deban sobrevivir a la terminación (por '
          'ejemplo, limitaciones de responsabilidad y propiedad intelectual) seguirán '
          'vigentes.',
    ),
    (
      '12. Limitación de responsabilidad',
      'Pedalea se entrega "tal cual" y "según disponibilidad", sin garantías de ningún '
          'tipo, expresas o implícitas. En la máxima medida permitida por la ley, ni '
          'Pedalea ni sus desarrolladores serán responsables por daños indirectos, '
          'incidentales, especiales o consecuentes derivados del uso o la imposibilidad de '
          'uso del servicio, incluyendo pero no limitado a lesiones personales, accidentes '
          'de tránsito, pérdida de datos o interrupciones del servicio.',
    ),
    (
      '13. Cambios a estos términos',
      'Podemos actualizar estos Términos y Condiciones ocasionalmente para reflejar '
          'cambios en el servicio o en la normativa aplicable. Te notificaremos los cambios '
          'importantes dentro de la app o por correo electrónico. La fecha de "Última '
          'actualización" al inicio de este documento indica cuándo se modificó por última '
          'vez.',
    ),
    (
      '14. Ley aplicable',
      'Estos términos se rigen por las leyes de la República de Chile. Cualquier disputa '
          'relacionada con el uso de Pedalea se someterá a los tribunales competentes de '
          'Chile.',
    ),
    (
      '15. Contacto',
      'Si tienes preguntas sobre estos Términos y Condiciones, escríbenos a: '
          'ignacioandres1201@gmail.com',
    ),
  ];
}

class _TermsSection extends StatelessWidget {
  final String title;
  final String body;
  const _TermsSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Sora',
              color: _kGreenAccent,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'Sora',
              color: Colors.white.withOpacity(0.75),
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Nivel de una insignia: define sus colores.
enum BadgeTier { bronze, silver, gold, platinum, plus }

/// Cómo se ve cada logro: un ícono de línea o un número grande (km, días),
/// y su nivel. Reemplaza a los emojis que vienen en el catálogo.
class _Look {
  final IconData icon;
  final String? label; // si existe, se muestra el número en vez del ícono
  final BadgeTier tier;
  const _Look(this.icon, this.tier, [this.label]);
}

const _bike = Icons.directions_bike_rounded;
const _fire = Icons.local_fire_department_rounded;
const _bolt = Icons.bolt_rounded;

const Map<String, _Look> _looks = {
  // Kilómetros
  'km_10': _Look(_bike, BadgeTier.bronze, '10'),
  'km_25': _Look(_bike, BadgeTier.bronze, '25'),
  'km_50': _Look(_bike, BadgeTier.silver, '50'),
  'km_100': _Look(_bike, BadgeTier.silver, '100'),
  'km_250': _Look(_bike, BadgeTier.silver, '250'),
  'km_500': _Look(_bike, BadgeTier.gold, '500'),
  'km_1000': _Look(_bike, BadgeTier.gold, '1K'),
  'km_2500': _Look(_bike, BadgeTier.platinum, '2,5K'),
  'km_5000': _Look(_bike, BadgeTier.platinum, '5K'),
  'km_10000': _Look(_bike, BadgeTier.platinum, '10K'),
  // Mejor día
  'bestday_20': _Look(_bolt, BadgeTier.silver, '20'),
  'bestday_50': _Look(_bolt, BadgeTier.gold, '50'),
  'bestday_100': _Look(_bolt, BadgeTier.platinum, '100'),
  // Racha
  'streak_3': _Look(_fire, BadgeTier.bronze, '3'),
  'streak_7': _Look(_fire, BadgeTier.bronze, '7'),
  'streak_14': _Look(_fire, BadgeTier.silver, '14'),
  'streak_30': _Look(_fire, BadgeTier.silver, '30'),
  'streak_60': _Look(_fire, BadgeTier.gold, '60'),
  'streak_100': _Look(_fire, BadgeTier.gold, '100'),
  'streak_180': _Look(_fire, BadgeTier.platinum, '180'),
  'streak_365': _Look(_fire, BadgeTier.platinum, '365'),
  // CO₂
  'co2_1': _Look(Icons.eco_rounded, BadgeTier.bronze),
  'co2_5': _Look(Icons.air_rounded, BadgeTier.bronze),
  'co2_10': _Look(Icons.park_rounded, BadgeTier.silver),
  'co2_50': _Look(Icons.forest_rounded, BadgeTier.gold),
  'co2_100': _Look(Icons.public_rounded, BadgeTier.platinum),
  // Alertas
  'first_alert': _Look(Icons.warning_amber_rounded, BadgeTier.bronze),
  'early_bird': _Look(Icons.wb_twilight_rounded, BadgeTier.bronze),
  'night_owl': _Look(Icons.nightlight_round, BadgeTier.bronze),
  'guardian_5': _Look(Icons.shield_rounded, BadgeTier.silver),
  'centinel_10': _Look(Icons.visibility_rounded, BadgeTier.silver),
  'reporter_25': _Look(Icons.campaign_rounded, BadgeTier.gold),
  'reporter_50': _Look(Icons.cell_tower_rounded, BadgeTier.gold),
  'reporter_100': _Look(Icons.groups_rounded, BadgeTier.platinum),
  // Eventos
  'first_event_join': _Look(Icons.handshake_rounded, BadgeTier.bronze),
  'event_chat_1': _Look(Icons.chat_bubble_rounded, BadgeTier.bronze),
  'first_event_create': _Look(Icons.celebration_rounded, BadgeTier.bronze),
  'event_private_1': _Look(Icons.lock_rounded, BadgeTier.bronze),
  'event_host_3': _Look(Icons.event_available_rounded, BadgeTier.silver),
  'event_social_5': _Look(Icons.people_alt_rounded, BadgeTier.silver),
  'event_host_5': _Look(Icons.stars_rounded, BadgeTier.silver),
  'event_chat_10': _Look(Icons.forum_rounded, BadgeTier.silver),
  'event_social_10': _Look(Icons.diversity_3_rounded, BadgeTier.gold),
  'event_host_10': _Look(Icons.military_tech_rounded, BadgeTier.gold),
  'event_social_20': _Look(Icons.emoji_people_rounded, BadgeTier.platinum),
  // Fotos
  'poi_photo_1': _Look(Icons.photo_camera_rounded, BadgeTier.bronze),
  'event_photo_1': _Look(Icons.landscape_rounded, BadgeTier.bronze),
  'poi_photo_5': _Look(Icons.add_a_photo_rounded, BadgeTier.silver),
  'event_photo_5': _Look(Icons.photo_library_rounded, BadgeTier.silver),
  'poi_photo_20': _Look(Icons.collections_rounded, BadgeTier.gold),
  // Karma
  'karma_explorador': _Look(Icons.explore_rounded, BadgeTier.bronze),
  'karma_guardian': _Look(Icons.security_rounded, BadgeTier.silver),
  'karma_heroe': _Look(_bolt, BadgeTier.gold),
  'karma_leyenda': _Look(Icons.workspace_premium_rounded, BadgeTier.platinum),
  // Rutas
  'fav_route_1': _Look(Icons.star_rounded, BadgeTier.bronze),
  'fav_route_5': _Look(Icons.map_rounded, BadgeTier.silver),
  'fav_route_10': _Look(Icons.pin_drop_rounded, BadgeTier.gold),
  // Otros
  'profile_complete': _Look(Icons.person_rounded, BadgeTier.bronze),
  'plus_member': _Look(Icons.favorite_rounded, BadgeTier.plus),
};

/// Colores del degradado de cada nivel (claro → oscuro).
const Map<BadgeTier, List<Color>> _tierColors = {
  BadgeTier.bronze: [Color(0xFFF2B98A), Color(0xFFA9612F)],
  BadgeTier.silver: [Color(0xFFF1F4F9), Color(0xFF8A96AA)],
  BadgeTier.gold: [Color(0xFFFFE590), Color(0xFFD99A00)],
  BadgeTier.platinum: [Color(0xFFC9F6FF), Color(0xFF6F7BFF)],
  BadgeTier.plus: [Color(0xFFA8FFD8), Color(0xFF22A876)],
};

String tierName(BadgeTier t) => switch (t) {
      BadgeTier.bronze => 'Bronce',
      BadgeTier.silver => 'Plata',
      BadgeTier.gold => 'Oro',
      BadgeTier.platinum => 'Platino',
      BadgeTier.plus => 'Plus',
    };

BadgeTier achievementTier(String? id) => _looks[id]?.tier ?? BadgeTier.bronze;

/// Insignia de un logro: medalla circular con degradado según su nivel y un
/// ícono de línea (o el número del logro). Bloqueada se ve gris y apagada.
class AchievementBadge extends StatelessWidget {
  final String? id;
  final bool unlocked;
  final double size;

  const AchievementBadge({
    super.key,
    required this.id,
    this.unlocked = true,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final look = _looks[id] ?? const _Look(Icons.emoji_events_rounded, BadgeTier.bronze);
    final colors = unlocked
        ? _tierColors[look.tier]!
        : const [Color(0xFF2A2D38), Color(0xFF1B1D25)];
    final fg = unlocked ? const Color(0xFF15161D) : Colors.white.withOpacity(0.28);

    Widget content;
    if (look.label != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(look.icon, color: fg.withOpacity(unlocked ? 0.75 : 1), size: size * 0.2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              look.label!,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: fg,
                fontSize: size * 0.3,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      );
    } else {
      content = Icon(look.icon, color: fg, size: size * 0.44);
    }

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: colors.last.withOpacity(0.35),
                    blurRadius: size * 0.22,
                    offset: Offset(0, size * 0.06),
                  ),
                ]
              : null,
        ),
        child: Padding(
          // Aro interior: da el aspecto de medalla.
          padding: EdgeInsets.all(size * 0.07),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: unlocked ? Colors.white.withOpacity(0.55) : Colors.white.withOpacity(0.06),
                width: size * 0.025,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

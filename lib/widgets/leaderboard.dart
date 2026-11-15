import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Piezas visuales compartidas por los rankings (ciclistas y local):
/// cabecera, pestañas en cápsula, podio, tarjeta de "tu posición" y filas.

const kGold = Color(0xFFFFD54F);
const kSilver = Color(0xFFCFD8DC);
const kBronze = Color(0xFFE0A06A);

Color podiumColor(int rank) => switch (rank) {
      1 => kGold,
      2 => kSilver,
      3 => kBronze,
      _ => Colors.white54,
    };

BoxDecoration _pillBox({double radius = 24}) => BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.14)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 16,
          offset: const Offset(0, 3),
        ),
      ],
    );

/// Barra superior: volver · píldora con título · acción opcional.
class LeaderboardHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback? onRefresh;
  const LeaderboardHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    this.onRefresh,
  });

  Widget _circle({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    double size = 21,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: 48,
            height: 48,
            decoration: _pillBox(),
            child: Icon(icon, color: color, size: size),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _circle(
            icon: Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
            tooltip: 'Volver',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: _pillBox(),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(width: 10),
            _circle(
              icon: Icons.refresh_rounded,
              color: accent,
              tooltip: 'Actualizar',
              onTap: onRefresh!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Pestañas en una sola cápsula con indicador relleno.
class LeaderboardTabs extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final Color accent;
  const LeaderboardTabs({
    super.key,
    required this.controller,
    required this.labels,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(0.35), blurRadius: 10),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.white60,
          splashBorderRadius: BorderRadius.circular(18),
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: [for (final l in labels) Tab(text: l)],
        ),
      ),
    );
  }
}

/// Avatar circular con foto o inicial.
class RankAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final IconData? icon;
  const RankAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 38,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final clean = name.replaceFirst('@', '');
    final initial = clean.isNotEmpty ? clean.characters.first.toUpperCase() : '?';
    Widget fallback() => Container(
          color: Colors.white.withOpacity(0.08),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.white70, size: size * 0.45)
              : Text(
                  initial,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.38,
                  ),
                ),
        );
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => fallback(),
                errorWidget: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

class PodiumEntry {
  final String name;
  final String value;
  final String unit;
  final Widget avatar;
  final bool isMe;
  final VoidCallback? onTap; // abre el perfil del ciclista
  const PodiumEntry({
    required this.name,
    required this.value,
    required this.unit,
    required this.avatar,
    this.isMe = false,
    this.onTap,
  });
}

/// Podio de los 3 primeros (2º · 1º · 3º) con pedestales.
class Podium extends StatelessWidget {
  final List<PodiumEntry> top; // exactamente 3, en orden 1º, 2º, 3º
  const Podium({super.key, required this.top});

  Widget _place(PodiumEntry e, int rank, double pedestal) {
    final c = podiumColor(rank);
    final avatarSize = rank == 1 ? 74.0 : 60.0;
    return Expanded(
      child: GestureDetector(
       behavior: HitTestBehavior.opaque,
       onTap: e.onTap,
       child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (rank == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Icon(Icons.workspace_premium_rounded,
                  color: kGold, size: 26),
            ),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [c, Color.lerp(c, Colors.black, 0.35)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.withOpacity(rank == 1 ? 0.5 : 0.3),
                      blurRadius: rank == 1 ? 20 : 12,
                    ),
                  ],
                ),
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: ClipOval(child: e.avatar),
                ),
              ),
              Positioned(
                bottom: -9,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A0A14), width: 2),
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              e.isMe ? '${e.name} (tú)' : e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: e.isMe ? kGold : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Pedestal
          Container(
            height: pedestal,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withOpacity(0.28), c.withOpacity(0.04)],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                top: BorderSide(color: c.withOpacity(0.7), width: 2),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: c,
                      fontSize: rank == 1 ? 20 : 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  e.unit,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10.5,
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
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _place(top[1], 2, 70),
        _place(top[0], 1, 96),
        _place(top[2], 3, 54),
      ],
    );
  }
}

/// Fila de la tabla: puesto, avatar, nombre, valor y barra vs. el líder.
class LeaderRow extends StatelessWidget {
  final int rank;
  final Widget avatar;
  final String name;
  final String? subtitle;
  final String value;
  final String unit;
  final double progress; // 0..1 respecto del 1º
  final bool isMe;
  final Color accent;
  final Color? valueColor;
  final VoidCallback? onTap; // abre el perfil del ciclista
  const LeaderRow({
    super.key,
    required this.rank,
    required this.avatar,
    required this.name,
    required this.value,
    required this.unit,
    required this.progress,
    required this.accent,
    this.subtitle,
    this.isMe = false,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rc = podiumColor(rank);
    final top3 = rank <= 3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _body(rc, top3),
    );
  }

  Widget _body(Color rc, bool top3) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: isMe
            ? accent.withOpacity(0.1)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMe
              ? accent.withOpacity(0.5)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: top3 ? rc.withOpacity(0.16) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: top3 ? rc : Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 38, height: 38, child: ClipOval(child: avatar)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'TÚ',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.white.withOpacity(0.07),
                          valueColor: AlwaysStoppedAnimation(
                            (valueColor ?? accent).withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: valueColor ?? accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tarjeta destacada con la posición del usuario y cuánto le falta.
class MyRankCard extends StatelessWidget {
  final int? rank; // null = aún no aparece
  final int total;
  final String value;
  final String unit;
  final String? chaseText; // "Te faltan 2.3 km para pasar a @x"
  final String emptyText;
  final Color accent;
  const MyRankCard({
    super.key,
    required this.rank,
    required this.total,
    required this.value,
    required this.unit,
    required this.accent,
    required this.emptyText,
    this.chaseText,
  });

  @override
  Widget build(BuildContext context) {
    final hasRank = rank != null;
    final rc = hasRank && rank! <= 3 ? podiumColor(rank!) : accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rc.withOpacity(0.2), rc.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: rc.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: rc.withOpacity(0.5)),
            ),
            child: hasRank
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'PUESTO',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '#$rank',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: rc,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ],
                  )
                : Icon(Icons.flag_rounded, color: rc, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasRank ? 'Tu posición' : 'Aún no apareces',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasRank
                      ? '$value $unit · de $total ${total == 1 ? 'participante' : 'participantes'}'
                      : emptyText,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                if (chaseText != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.trending_up_rounded, color: rc, size: 15),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          chaseText!,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: rc,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de sección con barrita de acento.
class LeaderSectionLabel extends StatelessWidget {
  final String text;
  final Color accent;
  final String? trailing;
  const LeaderSectionLabel(this.text,
      {super.key, required this.accent, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

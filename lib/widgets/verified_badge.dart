import 'package:flutter/material.dart';

/// Cuenta oficial de Pedalea (el equipo de la app). Se identifica por su id y
/// no por el nombre, para que nadie pueda copiar el verificado cambiándose el
/// nombre de usuario a «Pedalea».
const kOfficialPedaleaUserId = 'f6dbea0d-96a9-47fa-8ded-2361a8d1f0f9';

bool isOfficialAccount(Object? userId) => userId == kOfficialPedaleaUserId;

/// Insignia de verificado (azul) que se muestra junto al nombre de la cuenta
/// oficial en comentarios, publicaciones y su perfil.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cuenta oficial de Pedalea',
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: const Color(0xFF1D9BF0),
      ),
    );
  }
}

/// Nombre + verificado (si corresponde) en una fila que no se desborda.
class NameWithBadge extends StatelessWidget {
  final String name;
  final Object? userId;
  final TextStyle style;
  final double badgeSize;
  const NameWithBadge({
    super.key,
    required this.name,
    required this.userId,
    required this.style,
    this.badgeSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOfficialAccount(userId)) {
      return Text(name, style: style, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name, style: style, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 4),
        VerifiedBadge(size: badgeSize),
      ],
    );
  }
}

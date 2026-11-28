/// Vigencia de las alertas del mapa. Debe coincidir con vote_alert() y
/// expire_old_alerts() en el servidor (migración
/// 20261127231000_notification_prefs_alert_lifecycle.sql).
class AlertLife {
  AlertLife._();

  /// Horas que dura una alerta sin que nadie confirme que sigue ahí.
  static int lifeHours(String? type) => switch (type) {
    'accident' => 24,
    'theft' => 48,
    'danger' => 168, // 7 días
    'construction' => 504, // 21 días
    _ => 72,
  };

  /// Desde cuándo se sabe que sigue: última confirmación o, si no hay, creación.
  static DateTime? freshSince(Map alert) {
    final raw = (alert['confirmed_at'] ?? alert['created_at'])?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  /// Vencida: 3 o más dijeron «Ya no está» (y son más que los «Sigue ahí»), o
  /// nadie confirmó que sigue dentro de su vigencia.
  static bool isExpired(Map alert, {DateTime? now}) {
    final up = (alert['votes_up'] as num?)?.toInt() ?? 0;
    final down = (alert['votes_down'] as num?)?.toInt() ?? 0;
    if (down >= 3 && down > up) return true;
    final since = freshSince(alert);
    if (since == null) return false;
    return (now ?? DateTime.now()).difference(since).inHours >=
        lifeHours(alert['type'] as String?);
  }
}

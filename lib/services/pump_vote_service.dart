import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de la votación comunitaria de bomba de aire en una bencinera.
class PumpStatus {
  PumpStatus({
    required this.status,
    required this.decidedAt,
    required this.lockedUntil,
    required this.yes,
    required this.no,
    required this.myVote,
    required this.needed,
  });

  /// 'yes' (hay bomba), 'no' (no hay) o null (aún sin decidir).
  final String? status;
  final DateTime? decidedAt;

  /// Mientras no sea null, la votación está cerrada hasta esa fecha.
  final DateTime? lockedUntil;
  final int yes;
  final int no;

  /// true = voté que hay, false = que no hay, null = no he votado.
  final bool? myVote;

  /// Votos iguales necesarios para decidir (5).
  final int needed;

  bool get isLocked => lockedUntil != null;

  factory PumpStatus.fromJson(Map<String, dynamic> j) => PumpStatus(
    status: j['status'] as String?,
    decidedAt: DateTime.tryParse(j['decided_at']?.toString() ?? '')?.toLocal(),
    lockedUntil: DateTime.tryParse(
      j['locked_until']?.toString() ?? '',
    )?.toLocal(),
    yes: (j['yes'] as num?)?.toInt() ?? 0,
    no: (j['no'] as num?)?.toInt() ?? 0,
    myVote: j['my_vote'] as bool?,
    needed: (j['needed'] as num?)?.toInt() ?? 5,
  );
}

class PumpVoteException implements Exception {
  PumpVoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Votación «¿hay bomba de aire?»: 5 votos iguales deciden y la votación se
/// cierra 30 días. Todo lo valida el servidor (funciones `pump_status` y
/// `vote_pump`).
class PumpVoteService {
  PumpVoteService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<PumpStatus?> status(String serviceId) async {
    try {
      final res = await _sb.rpc('pump_status', params: {'p_service': serviceId});
      if (res is Map) return PumpStatus.fromJson(res.cast<String, dynamic>());
    } catch (_) {
      // Sin conexión o función aún no creada: la tarjeta no se muestra.
    }
    return null;
  }

  /// [vote]: true = hay, false = no hay, null = quitar mi voto.
  static Future<PumpStatus> vote(String serviceId, bool? vote) async {
    if (_sb.auth.currentUser == null) {
      throw PumpVoteException('Inicia sesión para votar');
    }
    try {
      final res = await _sb.rpc(
        'vote_pump',
        params: {'p_service': serviceId, 'p_vote': vote},
      );
      return PumpStatus.fromJson((res as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      if (e.message.contains('locked')) {
        throw PumpVoteException('La votación ya se cerró por este mes');
      }
      throw PumpVoteException('No se pudo registrar tu voto');
    } catch (_) {
      throw PumpVoteException('No se pudo registrar tu voto');
    }
  }
}

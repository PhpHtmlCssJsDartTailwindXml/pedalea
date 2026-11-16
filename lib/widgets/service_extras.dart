import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/opening_hours.dart';
import '../services/pump_vote_service.dart';

BoxDecoration _cardBox() => BoxDecoration(
  color: Colors.white.withOpacity(0.04),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: Colors.white.withOpacity(0.07)),
);

const _label = TextStyle(
  fontFamily: 'Poppins',
  color: Colors.white54,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1,
);

// ═══════════════════════════════════════════════════════════════════════════
//  Horario de atención (talleres, tiendas y bencineras)
// ═══════════════════════════════════════════════════════════════════════════

/// Muestra si el lugar está abierto ahora, cuándo abre o cierra y el horario
/// de la semana. Los datos vienen de OpenStreetMap; si el lugar no tiene
/// horario publicado lo dice y ofrece llamar para confirmar.
class OpeningHoursCard extends StatefulWidget {
  const OpeningHoursCard({
    super.key,
    required this.openingHours,
    this.phone,
    this.website,
    required this.accent,
  });

  final String? openingHours;
  final String? phone;
  final String? website;
  final Color accent;

  @override
  State<OpeningHoursCard> createState() => _OpeningHoursCardState();
}

class _OpeningHoursCardState extends State<OpeningHoursCard> {
  bool _expanded = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Actualiza «abierto/cerrado» si la hoja queda abierta un rato.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final oh = OpeningHours.parse(widget.openingHours);
    final now = DateTime.now();
    final status = oh?.status(now);
    final phone = widget.phone?.trim();
    final web = widget.website?.trim();
    final today = now.weekday - 1;

    final Color dot;
    final String headline;
    if (status != null) {
      dot = status.open ? const Color(0xFF34D399) : const Color(0xFFF87171);
      headline = status.text;
    } else if (widget.openingHours?.isNotEmpty == true) {
      dot = Colors.white38;
      headline = widget.openingHours!; // formato que no se pudo leer
    } else {
      dot = Colors.white24;
      headline = 'Horario no publicado';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: oh == null ? null : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (status?.open == true)
                          BoxShadow(color: dot.withOpacity(0.6), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HORARIO', style: _label),
                        const SizedBox(height: 2),
                        Text(
                          headline,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: status == null ? Colors.white60 : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (oh != null && !oh.isAlwaysOpen && !_expanded)
                          Text(
                            'Hoy: ${oh.dayText(today)}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        if (oh == null)
                          const Text(
                            'Confirma antes de ir',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (oh != null && !oh.isAlwaysOpen)
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Colors.white38,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && oh != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 14, 12),
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              OpeningHours.dayNames[d],
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: d == today ? Colors.white : Colors.white54,
                                fontWeight: d == today ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              oh.dayText(d),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: d == today ? Colors.white : Colors.white54,
                                fontWeight: d == today ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Fuente: OpenStreetMap. Los feriados pueden variar.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: Colors.white30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if ((phone?.isNotEmpty ?? false) || (web?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  if (phone?.isNotEmpty ?? false)
                    Expanded(
                      child: _action(
                        Icons.call_rounded,
                        'Llamar',
                        () => _open(Uri(scheme: 'tel', path: phone!.replaceAll(' ', ''))),
                      ),
                    ),
                  if ((phone?.isNotEmpty ?? false) && (web?.isNotEmpty ?? false))
                    const SizedBox(width: 8),
                  if (web?.isNotEmpty ?? false)
                    Expanded(
                      child: _action(Icons.language_rounded, 'Sitio web', () {
                        final u = web!.startsWith('http') ? web : 'https://$web';
                        final uri = Uri.tryParse(u);
                        if (uri != null) _open(uri);
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: widget.accent.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: widget.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: widget.accent,
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

// ═══════════════════════════════════════════════════════════════════════════
//  ¿Hay bomba de aire? (votación de la comunidad en bencineras)
// ═══════════════════════════════════════════════════════════════════════════

class PumpVoteCard extends StatefulWidget {
  const PumpVoteCard({super.key, required this.serviceId, required this.accent});

  final String serviceId;
  final Color accent;

  @override
  State<PumpVoteCard> createState() => _PumpVoteCardState();
}

class _PumpVoteCardState extends State<PumpVoteCard> {
  PumpStatus? _s;
  bool _loading = true;
  bool _sending = false;

  static const _green = Color(0xFF34D399);
  static const _red = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PumpVoteService.status(widget.serviceId);
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  Future<void> _vote(bool value) async {
    if (_sending) return;
    // Tocar el mismo voto otra vez lo quita.
    final next = _s?.myVote == value ? null : value;
    setState(() => _sending = true);
    try {
      final s = await PumpVoteService.vote(widget.serviceId, next);
      if (!mounted) return;
      setState(() => _s = s);
      if (s.isLocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.status == 'yes'
                  ? '¡Gracias! Quedó confirmado que hay bomba de aire'
                  : '¡Gracias! Quedó marcado que no hay bomba de aire',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
          ),
        );
      }
    } on PumpVoteException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message, style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.redAccent,
        ),
      );
      _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _date(DateTime d) {
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 74,
        decoration: _cardBox(),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    }
    final s = _s;
    if (s == null) return const SizedBox.shrink(); // sin conexión

    // Resultado vigente (votación cerrada por 30 días).
    if (s.isLocked) {
      final yes = s.status == 'yes';
      final c = yes ? _green : _red;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: _cardBox().copyWith(
          color: c.withOpacity(0.08),
          border: Border.all(color: c.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(yes ? Icons.check_circle_rounded : Icons.cancel_rounded, color: c, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    yes ? 'Tiene bomba de aire' : 'No tiene bomba de aire',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: c,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Confirmado por ${s.needed} ciclistas'
                    '${s.decidedAt != null ? ' el ${_date(s.decidedAt!)}' : ''}'
                    ' · se vuelve a votar el ${_date(s.lockedUntil!)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white54,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Votación abierta.
    final prev = s.status; // resultado del mes anterior, si lo hubo
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.air_rounded, color: widget.accent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '¿Tiene bomba de aire?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            prev == null
                ? 'Ayuda a otros ciclistas: con ${s.needed} votos iguales queda confirmado.'
                : 'El mes pasado se marcó que ${prev == 'yes' ? 'sí había' : 'no había'}. ¿Sigue igual?',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _voteButton(true, s)),
              const SizedBox(width: 10),
              Expanded(child: _voteButton(false, s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voteButton(bool value, PumpStatus s) {
    final c = value ? _green : _red;
    final selected = s.myVote == value;
    final count = value ? s.yes : s.no;
    return Material(
      color: selected ? c.withOpacity(0.2) : Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? c : Colors.white.withOpacity(0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _sending ? null : () => _vote(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    value ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
                    size: 18,
                    color: selected ? c : Colors.white60,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    value ? 'Sí hay' : 'No hay',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: selected ? c : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (count / s.needed).clamp(0, 1).toDouble(),
                  minHeight: 4,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation(c),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$count de ${s.needed}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

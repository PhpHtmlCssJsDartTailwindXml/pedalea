/// Formatos de fecha/hora relativos en español para chats y listas.
library;

const _diasCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _diasLargos = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Para listas: "ahora", "5 min", "3 h", "ayer", "lun", "12/10".
String timeAgoShort(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  final days = _day(now).difference(_day(t)).inDays;
  if (days == 0) return '${diff.inHours} h';
  if (days == 1) return 'ayer';
  if (days < 7) return _diasCortos[t.weekday - 1];
  return '${t.day}/${t.month}';
}

/// Para detalles: "hace un momento", "hace 5 min", "hoy a las 14:05",
/// "ayer a las 09:12", "el 12/10 a las 18:30".
String timeAgoLong(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  final days = _day(now).difference(_day(t)).inDays;
  if (days == 0) return 'hoy a las ${hhmm(t)}';
  if (days == 1) return 'ayer a las ${hhmm(t)}';
  return 'el ${t.day}/${t.month} a las ${hhmm(t)}';
}

/// Separador de día en el chat: "Hoy", "Ayer", "lunes 12 de octubre".
String dayLabel(DateTime t) {
  final days = _day(DateTime.now()).difference(_day(t)).inDays;
  if (days == 0) return 'Hoy';
  if (days == 1) return 'Ayer';
  final base = '${_diasLargos[t.weekday - 1]} ${t.day} de ${_meses[t.month - 1]}';
  return t.year == DateTime.now().year ? base : '$base de ${t.year}';
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

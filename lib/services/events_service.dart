import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'notification_service.dart';

class EventsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Columnas legibles de `events`. `password_hash` ya no se puede leer desde
  /// la app (la contraseña se valida en el servidor con `join_event`).
  static const eventColumns =
      'id, user_id, created_by, title, description, event_date, location_name, '
      'latitude, longitude, max_participants, participants_count, '
      'participants_ids, is_active, created_at, is_private';

  /// Nunca guardamos la contraseña en texto plano — solo el hash.
  String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  // Obtener eventos próximos (desde ahora hasta futuro)
  Future<List<Map<String, dynamic>>> getUpcomingEvents() async {
    try {
      // event_date es timestamptz → comparar en UTC, si no el filtro queda
      // corrido varias horas y esconde u oculta eventos cerca del límite.
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await _supabase
          .from('events')
          .select(eventColumns)
          .gte('event_date', now)
          .eq('is_active', true)
          .order('event_date', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error obteniendo eventos: $e');
      return [];
    }
  }

  // Obtener eventos creados por el usuario actual
  Future<List<Map<String, dynamic>>> getMyEvents() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('events')
          .select(eventColumns)
          .eq('user_id', userId)
          .order('event_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error obteniendo mis eventos: $e');
      return [];
    }
  }

  /// Cuenta cuántos eventos activos (no cancelados) tiene creados el usuario
  /// actual. Se usa para aplicar el límite del plan gratis (Pedalea Plus).
  Future<int> countMyActiveEvents() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;
      final rows = await _supabase
          .from('events')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true);
      return rows.length;
    } catch (e) {
      debugPrint('Error contando mis eventos: $e');
      return 0;
    }
  }

  // Crear un nuevo evento
  Future<Map<String, dynamic>?> createEvent({
    required String title,
    required String description,
    required DateTime eventDate,
    required String locationName,
    required double latitude,
    required double longitude,
    int? maxParticipants,
    bool isPrivate = false,
    String? password,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email ?? 'Usuario';

      if (userId == null) return null;

      final eventData = {
        'user_id': userId,
        'title': title,
        'description': description,
        // event_date es timestamptz: hay que mandar la hora en UTC explícito
        // (toUtc()), si no Postgres asume que la hora local ya es UTC y el
        // evento queda guardado ~horas antes de lo que el usuario eligió —
        // por eso podía parecer "vencido" apenas creado.
        'event_date': eventDate.toUtc().toIso8601String(),
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'max_participants': maxParticipants,
        'participants_count': 1,
        'participants_ids': [userId],
        'created_by': userEmail,
        'is_active': true,
        'is_private': isPrivate,
        if (isPrivate && password != null && password.isNotEmpty)
          'password_hash': hashPassword(password),
      };

      final response = await _supabase
          .from('events')
          .insert(eventData)
          .select(eventColumns)
          .single();

      // El creador queda unido automáticamente; programa su recordatorio.
      NotificationService.instance.scheduleEventReminder(
        eventId: response['id'] as String,
        title: title,
        eventDate: eventDate,
      );

      return response;
    } catch (e) {
      debugPrint('Error creando evento: $e');
      return null;
    }
  }

  /// Resultado de intentar unirse a un evento — distingue el motivo del
  /// fallo (contraseña incorrecta vs sin cupo, etc.) para poder mostrar el
  /// mensaje correcto en la UI.
  // Unirse a un evento. Si es privado, [password] debe coincidir con el hash
  // guardado — si no se entrega o no coincide, retorna 'wrong_password'.
  Future<String> joinEvent(String eventId, {String? password}) async {
    try {
      if (_supabase.auth.currentUser == null) return 'error';

      // Toda la validación (Plus, contraseña, cupo) ocurre en el servidor.
      final res = await _supabase.rpc('join_event', params: {
        'p_event_id': eventId,
        'p_password_hash': (password != null && password.isNotEmpty)
            ? hashPassword(password)
            : null,
      });
      final result = res is String ? res : 'error';

      if (result == 'ok') {
        final rows = await _supabase
            .from('events')
            .select('title, event_date')
            .eq('id', eventId);
        final event = rows.isNotEmpty ? rows.first : null;
        final eventDate =
            DateTime.tryParse(event?['event_date'] as String? ?? '');
        if (eventDate != null) {
          NotificationService.instance.scheduleEventReminder(
            eventId: eventId,
            title: event?['title'] as String? ?? 'Evento',
            eventDate: eventDate,
          );
        }
      }

      return result;
    } catch (e) {
      debugPrint('Error uniéndose al evento: $e');
      return 'error';
    }
  }

  // Salir de un evento
  Future<bool> leaveEvent(String eventId) async {
    try {
      if (_supabase.auth.currentUser == null) return false;

      final res = await _supabase
          .rpc('leave_event', params: {'p_event_id': eventId});
      if (res != true) return false;

      NotificationService.instance.cancelEventReminder(eventId);
      return true;
    } catch (e) {
      debugPrint('Error saliendo del evento: $e');
      return false;
    }
  }

  // Cancelar evento (solo creador)
  Future<bool> cancelEvent(String eventId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('events')
          .update({'is_active': false})
          .eq('id', eventId)
          .eq('user_id', userId);

      NotificationService.instance.cancelEventReminder(eventId);

      return true;
    } catch (e) {
      debugPrint('Error cancelando evento: $e');
      return false;
    }
  }

  // Stream de eventos en tiempo real
  Stream<List<Map<String, dynamic>>> streamUpcomingEvents() {
    // ignore: unused_local_variable
    final now = DateTime.now().toIso8601String();
    return _supabase
        .from('events')
        .stream(primaryKey: ['id'])
        .eq('is_active', true) // Filtro corregido
        .map((events) {
          // Filtrar eventos futuros manualmente ya que el stream no soporta .gte
          final futureEvents = events.where((event) {
            final eventDate = DateTime.parse(event['event_date']);
            return eventDate.isAfter(DateTime.now());
          }).toList();

          // Ordenar por fecha
          futureEvents.sort((a, b) {
            final dateA = DateTime.parse(a['event_date']);
            final dateB = DateTime.parse(b['event_date']);
            return dateA.compareTo(dateB);
          });

          return List<Map<String, dynamic>>.from(futureEvents);
        });
  }
}

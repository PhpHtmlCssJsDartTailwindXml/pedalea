import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventPhoto {
  final String id;
  final String photoUrl;
  final String? uploadedBy;

  const EventPhoto({required this.id, required this.photoUrl, this.uploadedBy});

  factory EventPhoto.fromMap(Map<String, dynamic> m) => EventPhoto(
        id: m['id'] as String,
        photoUrl: m['photo_url'] as String,
        uploadedBy: m['uploaded_by'] as String?,
      );
}

/// Fotos de referencia del lugar de un evento (público o privado), subidas
/// por el creador o los participantes, para guiar a los demás sobre dónde
/// será aproximadamente la junta.
class EventPhotosService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? get _uid => _supabase.auth.currentUser?.id;

  Future<List<EventPhoto>> getPhotos(String eventId) async {
    try {
      final rows = await _supabase
          .from('event_photos')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      return rows.map((r) => EventPhoto.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error cargando fotos del evento: $e');
      return [];
    }
  }

  Future<EventPhoto?> uploadPhoto({
    required String eventId,
    required File photoFile,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final fileName = '$uid/${eventId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage.from('event-photos').upload(fileName, photoFile);
      final url = _supabase.storage.from('event-photos').getPublicUrl(fileName);

      final row = await _supabase
          .from('event_photos')
          .insert({
            'event_id': eventId,
            'photo_url': url,
            'uploaded_by': uid,
          })
          .select()
          .single();
      return EventPhoto.fromMap(row);
    } catch (e) {
      debugPrint('Error subiendo foto del evento: $e');
      return null;
    }
  }

  Future<bool> deletePhoto(String id) async {
    try {
      await _supabase.from('event_photos').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error eliminando foto del evento: $e');
      return false;
    }
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PoiPhoto {
  final String id;
  final String photoUrl;
  final String? uploadedBy;

  const PoiPhoto({required this.id, required this.photoUrl, this.uploadedBy});

  factory PoiPhoto.fromMap(Map<String, dynamic> m) => PoiPhoto(
        id: m['id'] as String,
        photoUrl: m['photo_url'] as String,
        uploadedBy: m['uploaded_by'] as String?,
      );
}

/// Fotos de referencia subidas por los propios usuarios para los pines del
/// mapa (estacionamientos de bici, BiciMetro, talleres/inflado/agua) — no
/// vienen de ninguna API externa, se llenan con el uso de la comunidad.
class PoiPhotosService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? get _uid => _supabase.auth.currentUser?.id;

  Future<List<PoiPhoto>> getPhotos({
    required String poiType,
    required String poiId,
  }) async {
    try {
      final rows = await _supabase
          .from('poi_photos')
          .select()
          .eq('poi_type', poiType)
          .eq('poi_id', poiId)
          .order('created_at', ascending: false);
      return rows.map((r) => PoiPhoto.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error cargando fotos de POI: $e');
      return [];
    }
  }

  Future<PoiPhoto?> uploadPhoto({
    required String poiType,
    required String poiId,
    required File photoFile,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final fileName =
          '$uid/${poiType}_${poiId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage.from('poi-photos').upload(fileName, photoFile);
      final url = _supabase.storage.from('poi-photos').getPublicUrl(fileName);

      final row = await _supabase
          .from('poi_photos')
          .insert({
            'poi_type': poiType,
            'poi_id': poiId,
            'photo_url': url,
            'uploaded_by': uid,
          })
          .select()
          .single();
      return PoiPhoto.fromMap(row);
    } catch (e) {
      debugPrint('Error subiendo foto de POI: $e');
      return null;
    }
  }

  Future<bool> deletePhoto(String id) async {
    try {
      await _supabase.from('poi_photos').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error eliminando foto de POI: $e');
      return false;
    }
  }
}

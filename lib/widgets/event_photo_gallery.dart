import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/event_photos_service.dart';

/// Galería de fotos de referencia del lugar de un evento (sirve tanto para
/// eventos públicos como privados) — cualquier participante puede subir una
/// foto para guiar a los demás sobre dónde será aproximadamente la junta.
class EventPhotoGallery extends StatefulWidget {
  final String eventId;
  final Color accentColor;

  const EventPhotoGallery({
    super.key,
    required this.eventId,
    this.accentColor = Colors.orange,
  });

  @override
  State<EventPhotoGallery> createState() => _EventPhotoGalleryState();
}

class _EventPhotoGalleryState extends State<EventPhotoGallery> {
  final _service = EventPhotosService();
  List<EventPhoto> _photos = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await _service.getPhotos(widget.eventId);
    if (mounted) setState(() { _photos = photos; _loading = false; });
  }

  Future<void> _addPhoto() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para subir una foto')),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    final result = await _service.uploadPhoto(
      eventId: widget.eventId,
      photoFile: File(picked.path),
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result != null) {
      setState(() => _photos.insert(0, result));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo subir la foto, intenta de nuevo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Fotos de referencia del lugar',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _uploading ? null : _addPhoto,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _uploading
                      ? SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor),
                        )
                      : Icon(Icons.add_a_photo_outlined, size: 15, color: widget.accentColor),
                  const SizedBox(width: 4),
                  Text('Agregar', style: TextStyle(fontFamily: 'Poppins', color: widget.accentColor, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          Text(
            'Sube una foto para guiar dónde será aproximadamente la junta',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[600], fontSize: 12),
          )
        else
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _photos[i].photoUrl,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 76, height: 76,
                    color: Colors.white10,
                    child: const Icon(Icons.broken_image_outlined, color: Colors.white24),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

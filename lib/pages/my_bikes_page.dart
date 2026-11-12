import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/glass.dart';
import '../services/bike_service.dart';
import 'paywall_page.dart';

const _accent = Color(0xFF7CF0BC);
const _warn = Color(0xFFFFB74D);
const _sheetBg = Color(0xFF161622);

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color? c}) =>
    TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c ?? Colors.white);

String _km(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Foto de la bici, o su emoji sobre un fondo suave si no tiene foto.
class _BikePhoto extends StatelessWidget {
  final Bike bike;
  final double size;
  final double radius;
  const _BikePhoto({required this.bike, required this.size, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final url = bike.photoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : Container(
                color: _accent.withOpacity(0.10),
                alignment: Alignment.center,
                child: Text(bike.type.emoji, style: TextStyle(fontSize: size * 0.42)),
              ),
      ),
    );
  }
}

/// Lista de bicis del usuario.
class MyBikesPage extends StatefulWidget {
  const MyBikesPage({super.key});

  @override
  State<MyBikesPage> createState() => _MyBikesPageState();
}

class _MyBikesPageState extends State<MyBikesPage> {
  final _svc = BikeService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc.load().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _add() async {
    final saved = await showBikeEditor(context);
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Mis bicis', style: _t(19, w: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: Text('Agregar bici', style: _t(14, w: FontWeight.w700, c: Colors.black)),
        onPressed: _add,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : ValueListenableBuilder<List<Bike>>(
              valueListenable: _svc.bikes,
              builder: (context, bikes, _) {
                if (bikes.isEmpty) return _empty();
                return RefreshIndicator(
                  color: _accent,
                  onRefresh: _svc.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      if (bikes.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'Los km se suman a la bici activa. Cámbiala desde aquí o desde el mapa.',
                            style: _t(12, c: Colors.white54),
                          ),
                        ),
                      for (final b in bikes) _tile(b),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚲', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text('Registra tu bici', style: _t(19, w: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Ponle nombre y foto. La app suma sus km mientras pedaleas y te avisa cuando toca lubricar la cadena, revisar frenos o neumáticos.',
              textAlign: TextAlign.center,
              style: _t(13, c: Colors.white60).copyWith(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Bike b) {
    final due = b.dueMaintenance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BikeDetailPage(bikeId: b.id)),
          ),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: b.isActive ? _accent.withOpacity(0.45) : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                _BikePhoto(bike: b, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(b.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(16, w: FontWeight.w700)),
                          ),
                          if (b.isActive) ...[
                            const SizedBox(width: 8),
                            _pill('Activa', _accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${b.type.emoji} ${b.type.label} · ${_km(b.odometerKm)} km',
                          style: _t(12.5, c: Colors.white60)),
                      const SizedBox(height: 6),
                      due.isEmpty
                          ? Text('Mantención al día', style: _t(12, c: _accent))
                          : Text(
                              due.length == 1
                                  ? '🔧 Toca: ${due.first.kind.label.toLowerCase()}'
                                  : '🔧 ${due.length} mantenciones pendientes',
                              style: _t(12, w: FontWeight.w600, c: _warn),
                            ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: _t(10.5, w: FontWeight.w700, c: color)),
    );

/// Detalle de una bici: odómetro y mantenciones.
class BikeDetailPage extends StatefulWidget {
  final String bikeId;
  const BikeDetailPage({super.key, required this.bikeId});

  @override
  State<BikeDetailPage> createState() => _BikeDetailPageState();
}

class _BikeDetailPageState extends State<BikeDetailPage> {
  final _svc = BikeService.instance;

  @override
  void initState() {
    super.initState();
    _svc.load();
  }

  Bike? _find(List<Bike> list) {
    for (final b in list) {
      if (b.id == widget.bikeId) return b;
    }
    return null;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg, style: _t(13))));

  Future<void> _done(Bike b, Maintenance m) async {
    try {
      await _svc.markDone(m.id);
      _snack('Listo: ${m.kind.label.toLowerCase()} registrado a los ${_km(b.odometerKm)} km');
    } catch (e) {
      _snack('No se pudo guardar: $e');
    }
  }

  Future<void> _editInterval(Maintenance m) async {
    final ctrl = TextEditingController(text: m.intervalKm.toStringAsFixed(0));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(m.kind.label, style: _t(17, w: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: _t(15),
          cursorColor: _accent,
          decoration: InputDecoration(
            labelText: 'Cada cuántos km',
            labelStyle: _t(13, c: Colors.white54),
            suffixText: 'km',
            suffixStyle: _t(13, c: Colors.white54),
            helperText: 'Referencia: ${m.kind.defaultIntervalKm.toStringAsFixed(0)} km',
            helperStyle: _t(11.5, c: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: _t(14, c: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (v != null && v >= 50 && v <= 50000) Navigator.pop(ctx, v);
            },
            child: Text('Guardar', style: _t(14, w: FontWeight.w700, c: _accent)),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await _svc.setInterval(m.id, value);
    } catch (e) {
      _snack('No se pudo guardar: $e');
    }
  }

  Future<void> _delete(Bike b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Borrar "${b.name}"', style: _t(17, w: FontWeight.w700)),
        content: Text(
          'Se borran la bici y su historial de mantenciones. Tus km totales del perfil no cambian.',
          style: _t(13.5, c: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: _t(14, c: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Borrar', style: _t(14, w: FontWeight.w700, c: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.delete(b.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('No se pudo borrar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Bike>>(
      valueListenable: _svc.bikes,
      builder: (context, bikes, _) {
        final b = _find(bikes);
        return Scaffold(
          backgroundColor: kBgDark,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(b?.name ?? 'Bici', style: _t(19, w: FontWeight.w700)),
            actions: [
              if (b != null) ...[
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => showBikeEditor(context, bike: b),
                ),
                IconButton(
                  tooltip: 'Borrar',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(b),
                ),
              ],
            ],
          ),
          body: b == null
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : _body(b, bikes.length),
        );
      },
    );
  }

  Widget _body(Bike b, int bikeCount) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Center(child: _BikePhoto(bike: b, size: 150, radius: 32)),
        const SizedBox(height: 16),
        Center(
          child: Text('${b.type.emoji} ${b.type.label}', style: _t(13.5, c: Colors.white60)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('${_km(b.odometerKm)} km',
              style: _t(36, w: FontWeight.w800, c: _accent)),
        ),
        Center(
          child: Text(
            b.baseKm > 0
                ? '${_km(b.appKm)} km con Pedalea · ${_km(b.baseKm)} km de antes'
                : 'pedaleados con Pedalea',
            style: _t(12, c: Colors.white54),
          ),
        ),
        const SizedBox(height: 16),
        if (!b.isActive && bikeCount > 1)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _svc.setActive(b.id),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 19),
              label: Text('Usar esta bici', style: _t(14, w: FontWeight.w600, c: _accent)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          )
        else if (b.isActive)
          Center(child: _pill('Bici activa: aquí se suman tus km', _accent)),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('MANTENCIÓN',
              style: _t(11, w: FontWeight.w700, c: Colors.white54).copyWith(letterSpacing: 1.2)),
        ),
        for (final m in b.maintenance) _maintenanceCard(b, m),
        if (b.maintenance.isEmpty)
          Text('Sin mantenciones registradas.', style: _t(13, c: Colors.white54)),
        const SizedBox(height: 8),
        Text(
          'Los intervalos son referencias generales; tócalos para ajustarlos a tu bici.',
          style: _t(11.5, c: Colors.white38),
        ),
      ],
    );
  }

  Widget _maintenanceCard(Bike b, Maintenance m) {
    final odo = b.odometerKm;
    final due = m.isDue(odo);
    final p = m.progress(odo);
    final color = due ? _warn : (p > 0.8 ? _warn.withOpacity(0.8) : _accent);
    final remaining = m.remainingKm(odo);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: due ? _warn.withOpacity(0.5) : Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _editInterval(m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.kind.label, style: _t(14.5, w: FontWeight.w600)),
                      Text(
                        due
                            ? '¡Toca hacerla! (cada ${m.intervalKm.toStringAsFixed(0)} km)'
                            : 'Faltan ${_km(remaining)} km · cada ${m.intervalKm.toStringAsFixed(0)} km',
                        style: _t(12, c: due ? _warn : Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _done(b, m),
                style: TextButton.styleFrom(
                  foregroundColor: due ? Colors.black : _accent,
                  backgroundColor: due ? _warn : Colors.transparent,
                  minimumSize: const Size(48, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Listo',
                    style: _t(13, w: FontWeight.w700, c: due ? Colors.black : _accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja para agregar o editar una bici. Devuelve true si se guardó.
Future<bool?> showBikeEditor(BuildContext context, {Bike? bike}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BikeEditor(bike: bike),
  );
}

class _BikeEditor extends StatefulWidget {
  final Bike? bike;
  const _BikeEditor({this.bike});

  @override
  State<_BikeEditor> createState() => _BikeEditorState();
}

class _BikeEditorState extends State<_BikeEditor> {
  late final _name = TextEditingController(text: widget.bike?.name ?? '');
  late BikeType _type = widget.bike?.type ?? BikeType.urbana;
  File? _photo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !_saving;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 82,
    );
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final name = _name.text.trim();
    setState(() => _saving = true);
    final svc = BikeService.instance;
    try {
      String? url;
      if (_photo != null) url = await svc.uploadPhoto(_photo!);
      if (widget.bike == null) {
        await svc.create(name: name, type: _type, photoUrl: url);
      } else {
        await svc.update(widget.bike!.id,
            name: name, type: _type, baseKm: widget.bike!.baseKm, photoUrl: url);
      }
      if (mounted) Navigator.pop(context, true);
    } on BikeLimitException {
      if (!mounted) return;
      Navigator.pop(context, false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason: 'El plan gratis permite registrar 1 bici. Con Pedalea Plus puedes registrar todas las que tengas.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e', style: _t(13))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.bike != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(editing ? 'Editar bici' : 'Nueva bici',
                              style: _t(21, w: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            editing
                                ? 'Cambia su nombre, foto o tipo'
                                : 'Desde hoy suma sus km y te avisa sus mantenciones',
                            style: _t(12.5, c: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _photoPicker(),
                const SizedBox(height: 22),
                _label('¿Cómo se llama?'),
                const SizedBox(height: 8),
                _nameField(),
                const SizedBox(height: 22),
                _label('¿Qué tipo de bici es?'),
                const SizedBox(height: 10),
                _typeGrid(),
                const SizedBox(height: 26),
                _saveButton(editing),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: _t(13.5, w: FontWeight.w600, c: Colors.white70));

  /// Foto grande arriba: muestra la elegida, la actual o una invitación.
  Widget _photoPicker() {
    final existingUrl = widget.bike?.photoUrl ?? '';
    final hasImage = _photo != null || existingUrl.isNotEmpty;
    return GestureDetector(
      onTap: _pickPhoto,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_photo != null)
                Image.file(_photo!, fit: BoxFit.cover)
              else if (existingUrl.isNotEmpty)
                CachedNetworkImage(imageUrl: existingUrl, fit: BoxFit.cover)
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _accent.withOpacity(0.35), width: 1.4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_a_photo_rounded, color: _accent, size: 26),
                      ),
                      const SizedBox(height: 10),
                      Text('Agrega una foto de tu bici', style: _t(14, w: FontWeight.w600)),
                      Text('Opcional', style: _t(12, c: Colors.white38)),
                    ],
                  ),
                ),
              if (hasImage)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text('Cambiar', style: _t(12, w: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _name,
      maxLength: 40,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      style: _t(16, w: FontWeight.w600),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: 'Ej: La Negra, Rayo, La de ruta…',
        hintStyle: _t(15, c: Colors.white30),
        counterText: '',
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        prefixIcon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 19),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _accent, width: 1.4),
        ),
      ),
    );
  }

  /// Tipos en tarjetas de 3 por fila, con el emoji grande.
  Widget _typeGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in BikeType.values)
              SizedBox(width: w, child: _typeTile(t)),
          ],
        );
      },
    );
  }

  Widget _typeTile(BikeType t) {
    final selected = _type == t;
    return GestureDetector(
      onTap: () => setState(() => _type = t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 84,
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.14) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _accent : Colors.white.withOpacity(0.08),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 4),
                  Text(
                    t.label,
                    style: _t(12.5,
                        w: selected ? FontWeight.w700 : FontWeight.w500,
                        c: selected ? _accent : Colors.white70),
                  ),
                ],
              ),
            ),
            if (selected)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.check_circle_rounded, color: _accent, size: 17),
              ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton(bool editing) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _canSave ? _save : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.white.withOpacity(0.08),
          disabledForegroundColor: Colors.white38,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
              )
            : Text(
                editing
                    ? 'Guardar cambios'
                    : (_name.text.trim().isEmpty ? 'Ponle un nombre' : 'Agregar bici'),
                style: _t(15.5,
                    w: FontWeight.w700,
                    c: _canSave ? Colors.black : Colors.white38),
              ),
      ),
    );
  }
}

/// Selector rápido de bici activa (se abre desde el mapa).
Future<void> showActiveBikePicker(BuildContext context) {
  final svc = BikeService.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: _sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Con qué bici sales?', style: _t(17, w: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Los km de hoy se sumarán a esa bici.', style: _t(12.5, c: Colors.white54)),
              const SizedBox(height: 12),
              for (final b in svc.bikes.value)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: _BikePhoto(bike: b, size: 46, radius: 12),
                  title: Text(b.name, style: _t(15, w: FontWeight.w600)),
                  subtitle: Text('${_km(b.odometerKm)} km', style: _t(12, c: Colors.white54)),
                  trailing: b.isActive
                      ? const Icon(Icons.check_circle_rounded, color: _accent)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (!b.isActive) await svc.setActive(b.id);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

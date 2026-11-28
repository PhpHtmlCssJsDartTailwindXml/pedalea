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
  String? _uploadingFor; // bici a la que se le está cambiando la foto

  static const _green = Color(0xFF3DDC84);
  static const _card = Color(0xFF15171C);

  @override
  void initState() {
    super.initState();
    _svc.load().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg, style: _t(13))));

  Future<void> _add() async {
    final saved = await showBikeEditor(context);
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _changePhoto(Bike b) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingFor = b.id);
    try {
      final url = await _svc.uploadPhoto(File(picked.path));
      await _svc.update(b.id, name: b.name, type: b.type, baseKm: b.baseKm, photoUrl: url);
    } catch (e) {
      _snack('No se pudo cambiar la foto: $e');
    } finally {
      if (mounted) setState(() => _uploadingFor = null);
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
    } catch (e) {
      _snack('No se pudo borrar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado: volver · Mis bicis · agregar
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text('Mis bicis', style: _t(24, w: FontWeight.w700))),
                  Material(
                    color: _green,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _add,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.add_rounded, color: Colors.black, size: 26),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _green))
                  : ValueListenableBuilder<List<Bike>>(
                      valueListenable: _svc.bikes,
                      builder: (context, bikes, _) => RefreshIndicator(
                        color: _green,
                        onRefresh: _svc.load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: [
                            if (bikes.isEmpty) _emptyIntro(),
                            if (bikes.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 12),
                                child: Text(
                                  'Los km se suman a la bici en uso.',
                                  style: _t(12.5, c: Colors.white54),
                                ),
                              ),
                            for (final b in bikes) _bikeCard(b, bikes.length),
                            _addCard(bikes.isEmpty),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyIntro() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 24, 8, 20),
    child: Column(
      children: [
        const Text('🚲', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text('Registra tu bici', style: _t(19, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'La app suma sus km mientras pedaleas y te avisa cuando toca lubricar la cadena, revisar frenos o neumáticos.',
          textAlign: TextAlign.center,
          style: _t(13, c: Colors.white60).copyWith(height: 1.45),
        ),
      ],
    ),
  );

  /// Estado de una parte de la bici según sus mantenciones (la peor manda).
  (String, Color) _partStatus(Bike b, List<MaintenanceKind> kinds) {
    final odo = b.odometerKm;
    var worst = 0; // 0 ok · 1 pronto · 2 toca
    for (final m in b.maintenance.where((m) => kinds.contains(m.kind))) {
      final lvl = m.isDue(odo) ? 2 : (m.progress(odo) > 0.8 ? 1 : 0);
      if (lvl > worst) worst = lvl;
    }
    return switch (worst) {
      2 => ('Toca revisar', _warn),
      1 => ('Pronto', const Color(0xFFFFD54F)),
      _ => ('OK', _green),
    };
  }

  Widget _bikeCard(Bike b, int count) {
    final due = b.dueMaintenance;
    final url = b.photoUrl;
    final uploading = _uploadingFor == b.id;
    final parts = <(String, List<MaintenanceKind>)>[
      ('Cadena', [MaintenanceKind.lube, MaintenanceKind.chain]),
      ('Frenos', [MaintenanceKind.brakes]),
      ('Neumáticos', [MaintenanceKind.tires]),
    ];

    Widget stat(Widget value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            value,
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: _t(12.5, c: Colors.white54)),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: b.isActive ? _green.withOpacity(0.35) : Colors.white.withOpacity(0.07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Foto ──
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null && url.isNotEmpty)
                  CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                else
                  Container(
                    color: const Color(0xFF173222),
                    alignment: Alignment.center,
                    child: Icon(Icons.pedal_bike_rounded,
                        size: 92, color: _green.withOpacity(0.55)),
                  ),
                // En uso / Usar esta bici
                Positioned(
                  top: 12,
                  left: 12,
                  child: b.isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('En uso', style: _t(13, w: FontWeight.w700, c: Colors.black)),
                            ],
                          ),
                        )
                      : (count > 1
                          ? Material(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _svc.setActive(b.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Text('Usar esta bici',
                                      style: _t(13, w: FontWeight.w600, c: _green)),
                                ),
                              ),
                            )
                          : const SizedBox.shrink()),
                ),
                // Cambiar foto
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: uploading ? null : () => _changePhoto(b),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            uploading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(uploading ? 'Subiendo…' : 'Cambiar foto',
                                style: _t(13, w: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Nombre · tipo · editar ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: _t(22, w: FontWeight.w700)),
                          Text('Bici ${b.type.label.toLowerCase()}',
                              style: _t(13.5, c: Colors.white54)),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Editar',
                      color: _sheetBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onSelected: (v) {
                        if (v == 'edit') showBikeEditor(context, bike: b);
                        if (v == 'delete') _delete(b);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar nombre y tipo', style: _t(14)),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Borrar bici', style: _t(14, c: Colors.redAccent)),
                        ),
                      ],
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: const Icon(Icons.edit_outlined, color: Colors.white, size: 19),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── Km · mantención ──
                Row(
                  children: [
                    stat(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_km(b.odometerKm).replaceAll('.', ','),
                              style: _t(26, w: FontWeight.w800)),
                          const SizedBox(width: 4),
                          Text('km', style: _t(14, w: FontWeight.w700, c: _green)),
                        ],
                      ),
                      b.baseKm > 0 ? 'Con Pedalea y de antes' : 'Recorridos con ella',
                    ),
                    const SizedBox(width: 10),
                    stat(
                      Text(
                        due.isEmpty ? 'Al día' : '${due.length} pendiente${due.length == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(due.isEmpty ? 26 : 20, w: FontWeight.w800,
                            c: due.isEmpty ? _green : _warn),
                      ),
                      'Mantención',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // ── Estado ──
                Text('ESTADO',
                    style: _t(11.5, w: FontWeight.w700, c: Colors.white54)
                        .copyWith(letterSpacing: 1.4)),
                const SizedBox(height: 4),
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.white.withOpacity(0.06)),
                  Builder(builder: (_) {
                    final (label, color) = _partStatus(b, parts[i].$2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(parts[i].$1, style: _t(15))),
                          Text(label, style: _t(13.5, w: FontWeight.w600, c: color)),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 10),
                // ── Registrar mantención ──
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BikeDetailPage(bikeId: b.id)),
                    ),
                    icon: const Icon(Icons.build_outlined, color: _green, size: 19),
                    label: Text('Registrar mantención', style: _t(15, w: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.04),
                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta punteada para agregar otra bici.
  Widget _addCard(bool first) {
    return GestureDetector(
      onTap: _add,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: Colors.white.withOpacity(0.22), radius: 22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_rounded, color: _green, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(first ? 'Agregar mi bici' : 'Agregar otra bici',
                        style: _t(16, w: FontWeight.w600)),
                    Text('Ruta, MTB, plegable o eléctrica',
                        style: _t(13, c: Colors.white54)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Borde punteado con esquinas redondeadas.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
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

  static const _green = Color(0xFF3DDC84);

  String _num(double v) {
    // 1493 → «1.493», 6.8 → «6,8»
    if (v >= 100) {
      final s = v.round().toString();
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: Material(
      color: Colors.white.withOpacity(0.05),
      shape: CircleBorder(side: BorderSide(color: Colors.white.withOpacity(0.12))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 46, height: 46, child: Icon(icon, color: Colors.white, size: 20)),
      ),
    ),
  );

  /// Ajustar cada cuántos km se hace cada mantención.
  void _showIntervals(Bike b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(ctx).padding.bottom),
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        decoration: BoxDecoration(
          color: _sheetBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text('Ajustar intervalos', style: _t(17, w: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Cada cuántos km se hace cada mantención en tu bici.',
                  style: _t(12.5, c: Colors.white54)),
            ),
            for (final m in b.maintenance)
              ListTile(
                title: Text(m.kind.label, style: _t(14.5)),
                trailing: Text('cada ${_num(m.intervalKm)} km',
                    style: _t(13.5, w: FontWeight.w600, c: _green)),
                onTap: () {
                  Navigator.pop(ctx);
                  _editInterval(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Bike>>(
      valueListenable: _svc.bikes,
      builder: (context, bikes, _) {
        final b = _find(bikes);
        return Scaffold(
          backgroundColor: kBgDark,
          body: SafeArea(
            child: b == null
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _body(b, bikes.length),
          ),
        );
      },
    );
  }

  Widget _body(Bike b, int bikeCount) {
    final odo = b.odometerKm;
    final due = b.dueMaintenance;
    // Próxima mantención (la que queda más cerca).
    Maintenance? next;
    for (final m in b.maintenance) {
      if (m.isDue(odo)) continue;
      if (next == null || m.remainingKm(odo) < next.remainingKm(odo)) next = m;
    }
    final url = b.photoUrl;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ── Barra: volver · editar · más ──
        Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            _roundBtn(Icons.edit_outlined, 'Editar', () => showBikeEditor(context, bike: b)),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Más',
              color: _sheetBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (v) {
                if (v == 'use') _svc.setActive(b.id);
                if (v == 'delete') _delete(b);
              },
              itemBuilder: (_) => [
                if (!b.isActive && bikeCount > 1)
                  PopupMenuItem(value: 'use', child: Text('Usar esta bici', style: _t(14))),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Borrar bici', style: _t(14, c: Colors.redAccent)),
                ),
              ],
              child: IgnorePointer(
                child: _roundBtn(Icons.more_vert_rounded, 'Más', () {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Foto · nombre · estado ──
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 92,
                height: 92,
                child: url != null && url.isNotEmpty
                    ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                    : Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF173222),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _green.withOpacity(0.2)),
                        ),
                        child: Icon(Icons.pedal_bike_rounded, size: 52, color: _green.withOpacity(0.7)),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: _t(28, w: FontWeight.w700)),
                  Text('Bici ${b.type.label.toLowerCase()}', style: _t(14, c: Colors.white54)),
                  const SizedBox(height: 8),
                  if (b.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _green.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Text('Activa · suma tus km', style: _t(12.5, w: FontWeight.w600, c: _green)),
                        ],
                      ),
                    )
                  else if (bikeCount > 1)
                    GestureDetector(
                      onTap: () => _svc.setActive(b.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text('Usar esta bici', style: _t(12.5, w: FontWeight.w600, c: _green)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Km · resumen de mantención ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_num(odo), style: _t(32, w: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text('km', style: _t(15, w: FontWeight.w700, c: _green)),
                      ],
                    ),
                    Text(
                      b.baseKm > 0
                          ? '${_num(b.appKm)} con Pedalea · ${_num(b.baseKm)} de antes'
                          : 'pedaleados con Pedalea',
                      style: _t(12.5, c: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      due.isEmpty
                          ? 'Todo al día'
                          : '${due.length} pendiente${due.length == 1 ? '' : 's'}',
                      style: _t(16, w: FontWeight.w700, c: due.isEmpty ? _green : _warn),
                    ),
                    Text(
                      due.isNotEmpty
                          ? 'Toca: ${due.first.kind.action}'
                          : (next != null
                              ? 'Próxima: ${next.kind.action.split(' ').first} en ${_num(next.remainingKm(odo))} km'
                              : 'Sin mantenciones'),
                      textAlign: TextAlign.right,
                      style: _t(12.5, c: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Mantención ──
        Row(
          children: [
            Expanded(
              child: Text('MANTENCIÓN',
                  style: _t(12, w: FontWeight.w700, c: Colors.white54).copyWith(letterSpacing: 1.4)),
            ),
            GestureDetector(
              onTap: () => _showIntervals(b),
              child: Text('Ajustar intervalos', style: _t(13.5, w: FontWeight.w600, c: _green)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final m in b.maintenance) _maintenanceCard(b, m),
        if (b.maintenance.isEmpty)
          Text('Sin mantenciones registradas.', style: _t(13, c: Colors.white54)),
        const SizedBox(height: 10),
        Text(
          'La barra muestra cuánto queda antes de la próxima mantención. Los intervalos son referencias generales.',
          style: _t(12, c: Colors.white38).copyWith(height: 1.5),
        ),
      ],
    );
  }

  Widget _maintenanceCard(Bike b, Maintenance m) {
    final odo = b.odometerKm;
    final due = m.isDue(odo);
    final left = (1 - m.progress(odo)).clamp(0.0, 1.0);
    final color = due ? _warn : (left < 0.2 ? const Color(0xFFFFD54F) : _green);
    final remaining = m.remainingKm(odo);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: due ? _warn.withOpacity(0.5) : Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.kind == MaintenanceKind.chain ? 'Desgaste de cadena' : m.kind.label,
                      style: _t(16, w: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    due
                        ? Text('¡Toca hacerla! · cada ${_num(m.intervalKm)} km',
                            style: _t(12.5, w: FontWeight.w600, c: _warn))
                        : Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'Faltan '),
                              TextSpan(
                                text: '${_num(remaining)} km',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: ' · cada ${_num(m.intervalKm)} km'),
                            ]),
                            style: _t(12.5, c: Colors.white54),
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => _done(b, m),
                  icon: Icon(Icons.check_rounded, size: 17, color: due ? Colors.black : _green),
                  label: Text('Hecho',
                      style: _t(13.5, w: FontWeight.w600, c: due ? Colors.black : Colors.white)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: due ? _warn : Colors.white.withOpacity(0.04),
                    side: BorderSide(color: due ? _warn : Colors.white.withOpacity(0.14)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: left,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.08),
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

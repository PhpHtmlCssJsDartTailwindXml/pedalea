import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// Editor de foto para "Momentos" estilo Instagram: filtros de color, dibujo
/// a mano alzada, texto y emojis. Exporta un PNG cuadrado con todo aplicado.
class MomentEditorPage extends StatefulWidget {
  final File source;
  const MomentEditorPage({super.key, required this.source});

  @override
  State<MomentEditorPage> createState() => _MomentEditorPageState();
}

// ── Filtros (matrices de color 4x5) ─────────────────────────────────────
class _Filter {
  final String name;
  final List<double>? matrix; // null = sin filtro
  const _Filter(this.name, this.matrix);
}

const _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

const _filters = <_Filter>[
  _Filter('Original', null),
  _Filter('B/N', [
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Sepia', [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Vívido', [
    1.35, -0.15, -0.1, 0, 0, //
    -0.1, 1.3, -0.1, 0, 0, //
    -0.1, -0.15, 1.35, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Frío', [
    1.0, 0, 0, 0, -8, //
    0, 1.03, 0, 0, 0, //
    0, 0, 1.18, 0, 12, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Cálido', [
    1.15, 0.05, 0, 0, 12, //
    0.02, 1.05, 0, 0, 4, //
    0, 0, 0.9, 0, -8, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Retro', [
    0.9, 0.1, 0.1, 0, 18, //
    0.1, 0.85, 0.1, 0, 14, //
    0.1, 0.1, 0.8, 0, 8, //
    0, 0, 0, 1, 0, //
  ]),
  _Filter('Verano', [
    1.2, 0, 0, 0, 10, //
    0, 1.12, 0, 0, 8, //
    0, 0, 0.95, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
];

// ── Overlays (texto y emoji) ────────────────────────────────────────────
class _Sticker {
  String text;
  Offset pos;
  double scale;
  double rotation = 0;
  final bool isText;
  Color color;
  _Sticker({
    required this.text,
    required this.pos,
    this.scale = 1,
    this.isText = false,
    this.color = Colors.white,
  });
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke(this.points, this.color, this.width);
}

enum _Tool { none, draw, text, emoji }

class _MomentEditorPageState extends State<MomentEditorPage> {
  final _captureKey = GlobalKey();

  int _filterIndex = 0;
  _Tool _tool = _Tool.none;
  bool _exporting = false;

  // Dibujo
  final List<_Stroke> _strokes = [];
  _Stroke? _liveStroke;
  Color _brushColor = const Color(0xFF69FF47);
  double _brushWidth = 6;

  // Stickers
  final List<_Sticker> _stickers = [];
  int _selectedSticker = -1;

  // gesto activo por sticker
  double _gestureStartScale = 1;
  double _gestureStartRotation = 0;

  static const _drawColors = <Color>[
    Color(0xFF69FF47),
    Colors.white,
    Colors.black,
    Color(0xFFFF4D6D),
    Color(0xFF4FC3F7),
    Color(0xFFFFCA28),
    Color(0xFFBA68C8),
    Color(0xFFFF7043),
  ];

  static const _emojis = [
    '🚴', '🚵', '🚲', '🔥', '💪', '🌄', '🌅', '☀️', '🌈', '🍃',
    '⚡', '❤️', '💚', '✨', '🎉', '😎', '🥵', '🤙', '🙌', '🏆',
    '📍', '🗺️', '🌳', '🌸', '🐕', '☕', '🍺', '💨', '👀', '💯',
  ];

  Future<File> _export() async {
    final boundary = _captureKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/moment_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    return file;
  }

  Future<void> _done() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _tool = _Tool.none;
      _selectedSticker = -1;
    });
    // Espera a que se repinte sin los controles de selección.
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 30));
    try {
      final file = await _export();
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo procesar la foto: $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _addText() {
    final ctrl = TextEditingController();
    Color color = Colors.white;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF161622),
          title: const Text('Texto',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 80,
                style: TextStyle(fontFamily: 'Poppins', color: color),
                decoration: const InputDecoration(
                  hintText: 'Escribe algo…',
                  hintStyle:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white38),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _drawColors)
                    GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c ? Colors.white : Colors.white24,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar',
                  style:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isNotEmpty) {
                  setState(() {
                    _stickers.add(_Sticker(
                      text: t,
                      pos: const Offset(0, 0),
                      isText: true,
                      color: color,
                      scale: 1.2,
                    ));
                    _selectedSticker = _stickers.length - 1;
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Añadir',
                  style: TextStyle(
                      fontFamily: 'Poppins', color: Color(0xFF69FF47))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filters[_filterIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _exporting ? null : _done,
            child: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white54))
                : const Text('Siguiente',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF69FF47),
                        fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          // ── Lienzo cuadrado ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (context, c) {
                return GestureDetector(
                  onTapDown: (_) {
                    if (_selectedSticker != -1) {
                      setState(() => _selectedSticker = -1);
                    }
                  },
                  onPanStart: _tool == _Tool.draw
                      ? (d) {
                          _liveStroke = _Stroke(
                              [d.localPosition], _brushColor, _brushWidth);
                          setState(() {});
                        }
                      : null,
                  onPanUpdate: _tool == _Tool.draw
                      ? (d) => setState(
                          () => _liveStroke?.points.add(d.localPosition))
                      : null,
                  onPanEnd: _tool == _Tool.draw
                      ? (_) {
                          if (_liveStroke != null) {
                            _strokes.add(_liveStroke!);
                            _liveStroke = null;
                            setState(() {});
                          }
                        }
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: Stack(
                        children: [
                          // Imagen + filtro
                          Positioned.fill(
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(
                                  filter.matrix ?? _identity),
                              child: Image.file(widget.source,
                                  fit: BoxFit.cover),
                            ),
                          ),
                          // Trazos
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _StrokePainter([
                                ..._strokes,
                                ?_liveStroke,
                              ]),
                            ),
                          ),
                          // Stickers
                          for (int i = 0; i < _stickers.length; i++)
                            _buildSticker(i, c.biggest),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const Spacer(),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _buildSticker(int i, Size canvas) {
    final s = _stickers[i];
    final selected = _selectedSticker == i && !_exporting;
    final center = Offset(canvas.width / 2, canvas.height / 2);
    return Positioned(
      left: center.dx + s.pos.dx,
      top: center.dy + s.pos.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () => setState(() => _selectedSticker = i),
              onScaleStart: (d) {
                setState(() {
                  _selectedSticker = i;
                  _gestureStartScale = s.scale;
                  _gestureStartRotation = s.rotation;
                });
              },
              onScaleUpdate: (d) {
                setState(() {
                  s.pos += d.focalPointDelta;
                  s.scale =
                      (_gestureStartScale * d.scale).clamp(0.4, 6.0);
                  s.rotation = _gestureStartRotation + d.rotation;
                });
              },
              child: Transform.rotate(
                angle: s.rotation,
                child: Transform.scale(
                  scale: s.scale,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: selected
                        ? BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    child: s.isText
                        ? Text(
                            s.text,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: s.color,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black54)
                              ],
                            ),
                          )
                        : Text(s.text,
                            style: const TextStyle(fontSize: 40)),
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned(
                top: -10,
                right: -10,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _stickers.removeAt(i);
                    _selectedSticker = -1;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF4D6D), shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tool == _Tool.none) _filterStrip(),
          if (_tool == _Tool.draw) _drawControls(),
          if (_tool == _Tool.emoji) _emojiStrip(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _toolBtn(Icons.tune_rounded, 'Filtros', _Tool.none),
              _toolBtn(Icons.brush_rounded, 'Dibujar', _Tool.draw),
              _toolBtn(Icons.text_fields_rounded, 'Texto', _Tool.text),
              _toolBtn(Icons.emoji_emotions_outlined, 'Emoji', _Tool.emoji),
              _iconAction(Icons.undo_rounded, 'Deshacer', () {
                setState(() {
                  if (_stickers.isNotEmpty && _selectedSticker == -1) {
                    _stickers.removeLast();
                  } else if (_selectedSticker != -1) {
                    _stickers.removeAt(_selectedSticker);
                    _selectedSticker = -1;
                  } else if (_strokes.isNotEmpty) {
                    _strokes.removeLast();
                  }
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, _Tool tool) {
    final active = _tool == tool;
    return GestureDetector(
      onTap: () {
        if (tool == _Tool.text) {
          _addText();
          return;
        }
        setState(() => _tool = active ? _Tool.none : tool);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: active ? const Color(0xFF69FF47) : Colors.white70,
              size: 24),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: active ? const Color(0xFF69FF47) : Colors.white54)),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _filterStrip() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = _filterIndex == i;
          return GestureDetector(
            onTap: () => setState(() => _filterIndex = i),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? const Color(0xFF69FF47) : Colors.white24,
                      width: sel ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ColorFiltered(
                    colorFilter:
                        ColorFilter.matrix(f.matrix ?? _identity),
                    child: Image.file(widget.source,
                        fit: BoxFit.cover, cacheWidth: 140),
                  ),
                ),
                const SizedBox(height: 3),
                Text(f.name,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        color: sel ? const Color(0xFF69FF47) : Colors.white54)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _drawControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _drawColors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final c = _drawColors[i];
              return GestureDetector(
                onTap: () => setState(() => _brushColor = c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _brushColor == c ? Colors.white : Colors.white24,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.line_weight_rounded,
                color: Colors.white54, size: 18),
            Expanded(
              child: Slider(
                value: _brushWidth,
                min: 2,
                max: 24,
                activeColor: const Color(0xFF69FF47),
                onChanged: (v) => setState(() => _brushWidth = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emojiStrip() {
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _emojis.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            setState(() {
              _stickers.add(_Sticker(
                text: _emojis[i],
                pos: const Offset(0, 0),
              ));
              _selectedSticker = _stickers.length - 1;
              _tool = _Tool.none;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(_emojis[i], style: const TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, s.points, paint);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

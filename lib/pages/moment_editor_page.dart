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

  static const _lime = Color(0xFF69FF47);
  static const _panel = Color(0xFF0F0F1A);

  bool get _canUndo => _stickers.isNotEmpty || _strokes.isNotEmpty;

  void _undo() {
    setState(() {
      if (_selectedSticker != -1) {
        _stickers.removeAt(_selectedSticker);
        _selectedSticker = -1;
      } else if (_stickers.isNotEmpty) {
        _stickers.removeLast();
      } else if (_strokes.isNotEmpty) {
        _strokes.removeLast();
      }
    });
  }

  /// Hoja inferior para escribir un texto y elegir su color, con vista previa
  /// en el mismo campo.
  void _addText() {
    final ctrl = TextEditingController();
    Color color = Colors.white;
    void submit(BuildContext sheetContext) {
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
      Navigator.pop(sheetContext);
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161622),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.10)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('Añadir texto',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Cancelar',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white54)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        maxLength: 80,
                        textAlign: TextAlign.center,
                        cursorColor: _lime,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => submit(sheetContext),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(blurRadius: 6, color: Colors.black54)
                          ],
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Escribe algo…',
                          hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white30,
                              fontWeight: FontWeight.w600),
                          border: InputBorder.none,
                          counterStyle: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white30,
                              fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final c in _drawColors)
                          _colorDot(c, color == c,
                              () => setLocal(() => color = c)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => submit(sheetContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _lime,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        child: const Text('Añadir',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Punto de color seleccionable (pincel y texto). Zona táctil de 44 px.
  Widget _colorDot(Color c, bool selected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 34 : 26,
            height: selected ? 34 : 26,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 3 : 1.5,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: c.withOpacity(0.55), blurRadius: 12)]
                  : const [],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.08),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon,
                color: enabled ? Colors.white : Colors.white24, size: 21),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.close_rounded,
            tooltip: 'Cerrar',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Editar foto',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700)),
          ),
          _circleButton(
            icon: Icons.undo_rounded,
            tooltip: 'Deshacer',
            onTap: _canUndo ? _undo : null,
          ),
          const SizedBox(width: 10),
          Material(
            color: _lime,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _exporting ? null : _done,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.black))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Siguiente',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.black,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.black, size: 17),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filters[_filterIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            // ── Lienzo cuadrado ────────────────────────────────────────
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                              color: _lime.withOpacity(0.10), blurRadius: 40),
                        ],
                      ),
                      child: LayoutBuilder(builder: (context, c) {
                        return GestureDetector(
                          onTapDown: (_) {
                            if (_selectedSticker != -1) {
                              setState(() => _selectedSticker = -1);
                            }
                          },
                          onPanStart: _tool == _Tool.draw
                              ? (d) {
                                  _liveStroke = _Stroke([d.localPosition],
                                      _brushColor, _brushWidth);
                                  setState(() {});
                                }
                              : null,
                          onPanUpdate: _tool == _Tool.draw
                              ? (d) => setState(() =>
                                  _liveStroke?.points.add(d.localPosition))
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
                            borderRadius: BorderRadius.circular(26),
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
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
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

  /// Panel inferior: controles de la herramienta activa + selector de
  /// herramienta.
  Widget _bottomBar() {
    final Widget controls = switch (_tool) {
      _Tool.draw => _drawControls(),
      _Tool.emoji => _emojiStrip(),
      _ => _filterStrip(),
    };
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(key: ValueKey(_tool), child: controls),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  child: Row(
                    children: [
                      _toolBtn(Icons.tune_rounded, 'Filtros', _Tool.none),
                      _toolBtn(Icons.brush_rounded, 'Dibujar', _Tool.draw),
                      _toolBtn(Icons.text_fields_rounded, 'Texto', _Tool.text),
                      _toolBtn(
                          Icons.emoji_emotions_rounded, 'Emoji', _Tool.emoji),
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

  Widget _toolBtn(IconData icon, String label, _Tool tool) {
    final active = _tool == tool;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (tool == _Tool.text) {
            _addText();
            return;
          }
          setState(() => _tool = tool);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 52,
          decoration: BoxDecoration(
            color: active ? _lime : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            boxShadow: active
                ? [BoxShadow(color: _lime.withOpacity(0.35), blurRadius: 14)]
                : const [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: active ? Colors.black : Colors.white70, size: 21),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? Colors.black : Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterStrip() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = _filterIndex == i;
          return GestureDetector(
            onTap: () => setState(() => _filterIndex = i),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 70,
                  height: 70,
                  padding: EdgeInsets.all(sel ? 3 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? _lime : Colors.white.withOpacity(0.14),
                      width: sel ? 2.2 : 1,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: _lime.withOpacity(0.35), blurRadius: 14),
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(sel ? 14 : 19),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(f.matrix ?? _identity),
                      child: Image.file(widget.source,
                          fit: BoxFit.cover, cacheWidth: 180),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f.name,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? _lime : Colors.white54)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _drawControls() {
    return SizedBox(
      height: 100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in _drawColors)
                  _colorDot(c, _brushColor == c,
                      () => setState(() => _brushColor = c)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const Icon(Icons.line_weight_rounded,
                    color: Colors.white54, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 5,
                      activeTrackColor: _lime,
                      inactiveTrackColor: Colors.white.withOpacity(0.12),
                      thumbColor: Colors.white,
                      overlayColor: _lime.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: _brushWidth,
                      min: 2,
                      max: 24,
                      onChanged: (v) => setState(() => _brushWidth = v),
                    ),
                  ),
                ),
                // Vista previa del grosor y color del pincel.
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: Container(
                      width: _brushWidth,
                      height: _brushWidth,
                      decoration: BoxDecoration(
                        color: _brushColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30),
                      ),
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

  Widget _emojiStrip() {
    return SizedBox(
      height: 100,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
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
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Text(_emojis[i], style: const TextStyle(fontSize: 24)),
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

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  final bool isEraser;

  DrawingPoint({required this.offset, required this.paint, this.isEraser = false});
}

class DrawingCanvas extends StatefulWidget {
  final Function(ui.Image?) onDrawingChanged;
  final bool readOnly;
  const DrawingCanvas({super.key, required this.onDrawingChanged, this.readOnly = false});

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  List<DrawingPoint?> points = [];
  Color selectedColor = Colors.black;
  double strokeWidth = 3.0;
  bool isEraser = false;
  bool isToolbarExpanded = true;

  final List<Color> presets = [
    Colors.black,
    const Color(0xFF795548), // Brown
    const Color(0xFF2E7D32), // Green
    const Color(0xFFB71C1C), // Red
  ];

  void clear() {
    setState(() {
      points.clear();
      isEraser = false;
      selectedColor = Colors.black;
    });
    widget.onDrawingChanged(null);
  }

  void undo() {
    if (points.isEmpty) return;
    setState(() {
      if (points.last == null) points.removeLast();
      while (points.isNotEmpty && points.last != null) {
        points.removeLast();
      }
    });
    captureImage().then((img) => widget.onDrawingChanged(img));
  }

  Future<ui.Image?> captureImage() async {
    final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final size = renderBox.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Scale down if image is too large to save space (Firestore 1MB limit)
    // Downscaling more aggressively to ensure reliable sync for high-res sketches
    double scale = 1.0;
    const double maxDimension = 800.0;
    if (size.width > maxDimension || size.height > maxDimension) {
      if (size.width > size.height) {
        scale = maxDimension / size.width;
      } else {
        scale = maxDimension / size.height;
      }
    }
    
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
    
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        final paint = Paint()
          ..color = points[i]!.isEraser ? Colors.white : points[i]!.paint.color
          ..strokeCap = points[i]!.paint.strokeCap
          ..strokeWidth = points[i]!.paint.strokeWidth;
        canvas.drawLine(points[i]!.offset, points[i + 1]!.offset, paint);
      }
    }
    _drawTemplate(canvas, size, Colors.black);
    
    final picture = recorder.endRecording();
    return await picture.toImage(
      (size.width * scale).toInt(), 
      (size.height * scale).toInt()
    );
  }

  void _drawTemplate(Canvas canvas, Size size, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final textStyle = TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold);
    final textPainter = TextPainter(text: TextSpan(text: 'გეოჰორიზონტები', style: textStyle), textDirection: TextDirection.ltr);
    textPainter.layout();
    double colW = textPainter.width + 4;
    canvas.drawLine(Offset(size.width - colW, 0), Offset(size.width - colW, size.height), paint);
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width, size.height * 0.8), paint);
    textPainter.paint(canvas, Offset(size.width - colW + 2, 5));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!widget.readOnly)
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10)],
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToolButton(icon: Icons.undo_rounded, isSelected: false, onTap: undo, color: Colors.blueAccent),
                      _buildToolButton(icon: Icons.cleaning_services_rounded, isSelected: isEraser, onTap: () => setState(() => isEraser = !isEraser), color: Colors.orange),
                      _buildToolButton(icon: Icons.delete_sweep_outlined, isSelected: false, onTap: clear, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Container(height: 24, width: 1, color: Colors.white10),
                      const SizedBox(width: 12),
                      ...presets.map((c) => _buildColorPicker(c)),
                      _buildSpectrumButton(),
                      const SizedBox(width: 12),
                      Container(height: 24, width: 1, color: Colors.white10),
                      _buildToolButton(
                        icon: isToolbarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        isSelected: isToolbarExpanded,
                        onTap: () => setState(() => isToolbarExpanded = !isToolbarExpanded),
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),
              ),
              if (isToolbarExpanded) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(color: Colors.white10, height: 1)),
                Row(
                  children: [
                    const Icon(Icons.line_weight, color: Colors.white38, size: 18),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(activeTrackColor: Colors.orange, trackHeight: 4),
                        child: Slider(value: strokeWidth, min: 1.0, max: 30.0, onChanged: (v) => setState(() => strokeWidth = v)),
                      ),
                    ),
                    Text("${strokeWidth.toInt()}px", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            key: _canvasKey,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10, width: 2), color: const Color(0xFF1A1A1A)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onPanStart: widget.readOnly ? null : (d) => _addPoint(d.localPosition),
                onPanUpdate: widget.readOnly ? null : (d) => _addPoint(d.localPosition),
                onPanEnd: widget.readOnly ? null : (_) { setState(() => points.add(null)); captureImage().then((img) => widget.onDrawingChanged(img)); },
                child: CustomPaint(painter: MyPainter(pointsList: points, templateDrawer: (c, s) => _drawTemplate(c, s, Colors.white24)), size: Size.infinite),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _addPoint(Offset pos) {
    setState(() => points.add(DrawingPoint(offset: pos, isEraser: isEraser, paint: Paint()..color = isEraser ? const Color(0xFF1A1A1A) : selectedColor..strokeCap = StrokeCap.round..strokeWidth = strokeWidth)));
  }

  Widget _buildToolButton({required IconData icon, required bool isSelected, required VoidCallback onTap, required Color color}) {
    return IconButton(icon: Icon(icon, color: isSelected ? color : Colors.white70), onPressed: onTap);
  }

  Widget _buildColorPicker(Color color) {
    bool isSelected = !isEraser && selectedColor.value == color.value;
    return GestureDetector(
      onTap: () => setState(() { selectedColor = color; isEraser = false; }),
      child: Container(
        width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.orange : Colors.white24, width: isSelected ? 3 : 1)),
        child: isSelected ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 14) : null,
      ),
    );
  }

  Widget _buildSpectrumButton() {
    bool isCustom = !isEraser && !presets.any((c) => c.value == selectedColor.value);
    return GestureDetector(
      onTap: _showFullColorPicker,
      child: Container(
        width: 28, height: 28, margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red]),
          border: Border.all(color: isCustom ? Colors.white : Colors.white24, width: isCustom ? 2 : 1),
        ),
        child: isCustom ? const Icon(Icons.check, color: Colors.white, size: 14) : const Icon(Icons.palette_outlined, size: 14, color: Colors.white),
      ),
    );
  }

  void _showFullColorPicker() {
    HSVColor hsvColor = HSVColor.fromColor(selectedColor);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: _SaturationValuePicker(
                      hsvColor: hsvColor,
                      onChanged: (newHsv) => setDialogState(() => hsvColor = newHsv),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 12,
                  width: double.infinity,
                  child: _HuePicker(
                    hsvColor: hsvColor,
                    onChanged: (newHsv) => setDialogState(() => hsvColor = newHsv),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: hsvColor.toColor(), shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Text('#${hsvColor.toColor().value.toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            const Icon(Icons.copy, size: 14, color: Colors.black38),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        children: [
                          Text('Hex', style: TextStyle(color: Colors.black54, fontSize: 12)),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black38),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _rgbSlider('R', hsvColor.toColor().red, Colors.red, (v) {
                  final c = hsvColor.toColor();
                  setDialogState(() => hsvColor = HSVColor.fromColor(Color.fromARGB(255, v.toInt(), c.green, c.blue)));
                }),
                _rgbSlider('G', hsvColor.toColor().green, Colors.green, (v) {
                  final c = hsvColor.toColor();
                  setDialogState(() => hsvColor = HSVColor.fromColor(Color.fromARGB(255, c.red, v.toInt(), c.blue)));
                }),
                _rgbSlider('B', hsvColor.toColor().blue, Colors.blue, (v) {
                  final c = hsvColor.toColor();
                  setDialogState(() => hsvColor = HSVColor.fromColor(Color.fromARGB(255, c.red, c.green, v.toInt())));
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: Colors.black54))),
            TextButton(onPressed: () { setState(() { selectedColor = hsvColor.toColor(); isEraser = false; }); Navigator.pop(ctx); }, child: const Text('OK', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _rgbSlider(String label, int val, Color color, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 15, child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))),
        Expanded(child: SliderTheme(data: SliderThemeData(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)), child: Slider(value: val.toDouble(), min: 0, max: 255, activeColor: color, onChanged: onChanged))),
        SizedBox(width: 25, child: Text(val.toString(), style: const TextStyle(color: Colors.black54, fontSize: 10))),
      ],
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;
  const _SaturationValuePicker({required this.hsvColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => _handleGesture(context, d.localPosition),
      onPanDown: (d) => _handleGesture(context, d.localPosition),
      child: CustomPaint(painter: _SaturationValuePainter(hsvColor), size: Size.infinite),
    );
  }

  void _handleGesture(BuildContext context, Offset local) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final double s = local.dx.clamp(0.0, box.size.width) / box.size.width;
    final double v = 1.0 - (local.dy.clamp(0.0, box.size.height) / box.size.height);
    onChanged(hsvColor.withSaturation(s).withValue(v));
  }
}

class _SaturationValuePainter extends CustomPainter {
  final HSVColor hsvColor;
  _SaturationValuePainter(this.hsvColor);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint huePaint = Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1.0, hsvColor.hue, 1.0, 1.0).toColor()]).createShader(rect);
    canvas.drawRect(rect, huePaint);
    final Paint blackPaint = Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(rect);
    canvas.drawRect(rect, blackPaint);

    final Offset pos = Offset(hsvColor.saturation * size.width, (1.0 - hsvColor.value) * size.height);
    canvas.drawCircle(pos, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _HuePicker extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;
  const _HuePicker({required this.hsvColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => _handleGesture(context, d.localPosition),
      onPanDown: (d) => _handleGesture(context, d.localPosition),
      child: CustomPaint(painter: _HuePainter(hsvColor), size: Size.infinite),
    );
  }

  void _handleGesture(BuildContext context, Offset local) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final double h = (local.dx.clamp(0.0, box.size.width) / box.size.width) * 360.0;
    onChanged(hsvColor.withHue(h == 360.0 ? 0.0 : h));
  }
}

class _HuePainter extends CustomPainter {
  final HSVColor hsvColor;
  _HuePainter(this.hsvColor);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final List<Color> colors = [const Color(0xFFFF0000), const Color(0xFFFFFF00), const Color(0xFF00FF00), const Color(0xFF00FFFF), const Color(0xFF0000FF), const Color(0xFFFF00FF), const Color(0xFFFF0000)];
    final Paint paint = Paint()..shader = LinearGradient(colors: colors).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);

    final double x = (hsvColor.hue / 360.0) * size.width;
    canvas.drawCircle(Offset(x, size.height / 2), size.height / 2 + 2, Paint()..color = Colors.white..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class MyPainter extends CustomPainter {
  final List<DrawingPoint?> pointsList;
  final Function(Canvas, Size)? templateDrawer;
  MyPainter({required this.pointsList, this.templateDrawer});
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < pointsList.length - 1; i++) {
      if (pointsList[i] != null && pointsList[i + 1] != null) canvas.drawLine(pointsList[i]!.offset, pointsList[i + 1]!.offset, pointsList[i]!.paint);
      else if (pointsList[i] != null && pointsList[i + 1] == null) canvas.drawPoints(ui.PointMode.points, [pointsList[i]!.offset], pointsList[i]!.paint);
    }
    if (templateDrawer != null) templateDrawer!(canvas, size);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

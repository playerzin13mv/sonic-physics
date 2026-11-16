import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'game.dart';

Future<ui.Image> _load(String name) async {
  final data = await rootBundle.load('assets/$name');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final imgs = Images(
    atlas: await _load('sonic.png'),
    sdash: await _load('spindash.png'),
    dpad: [for (var i = 0; i < 5; i++) await _load('dpad_$i.png')],
    btn: [await _load('btn_0.png'), await _load('btn_1.png')],
    pause: await _load('pause.png'),
  );
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: GameScreen(game: Game(imgs)),
  ));
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class GameScreen extends StatefulWidget {
  final Game game;
  const GameScreen({super.key, required this.game});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = _Repaint();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      widget.game.update(dt);
      _repaint.ping();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => g.touchDown(e.pointer, e.localPosition.dx, e.localPosition.dy),
        onPointerMove: (e) => g.touchMove(e.pointer, e.localPosition.dx, e.localPosition.dy),
        onPointerUp: (e) => g.touchUp(e.pointer),
        onPointerCancel: (e) => g.touchUp(e.pointer),
        child: SizedBox.expand(
          child: CustomPaint(painter: _GamePainter(g, _repaint)),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final Game game;
  _GamePainter(this.game, Listenable repaint) : super(repaint: repaint);
  @override
  void paint(Canvas canvas, Size size) => game.draw(canvas, size);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

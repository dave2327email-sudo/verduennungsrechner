import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _inkBlue = Color(0xFF1E3A8A);
const _emerald = Color(0xFF10B981);
const _darkEmerald = Color(0xFF064E3B);
const _paper = Color(0xFFFAF6EE);
const _slate = Color(0xFF0F172A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: _paper,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const DilutionCalculatorApp());
}

class DilutionCalculatorApp extends StatelessWidget {
  const DilutionCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Labor - Verdünnungsrechner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _inkBlue,
          primary: _inkBlue,
          secondary: const Color(0xFF059669),
        ),
      ),
      home: const CalculatorHomeScreen(),
    );
  }
}

class _SingleDecimalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^[0-9.,]+$').hasMatch(t)) return oldValue;
    if (RegExp(r'[.,]').allMatches(t).length > 1) return oldValue;
    return newValue;
  }
}

class LabAssetIcon extends StatelessWidget {
  final String assetName;
  final double size;
  final bool withLightBadge;

  const LabAssetIcon(
    this.assetName, {
    super.key,
    this.size = 44,
    this.withLightBadge = false,
  });

  static const _whiteToTransparent = ColorFilter.matrix(<double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    -1.2,
    -1.2,
    0,
    2.275,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final Widget icon = ColorFiltered(
      colorFilter: _whiteToTransparent,
      child: Image.asset(
        'assets/images/$assetName',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
      ),
    );

    if (!withLightBadge) return icon;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
      ),
      child: icon,
    );
  }
}

class SerialStep {
  final double targetVolume;
  final double factor;
  final String unit;
  const SerialStep({
    required this.targetVolume,
    required this.factor,
    required this.unit,
  });
}

class CalculatorHomeScreen extends StatefulWidget {
  const CalculatorHomeScreen({super.key});

  @override
  State<CalculatorHomeScreen> createState() => _CalculatorHomeScreenState();
}

class _CalculatorHomeScreenState extends State<CalculatorHomeScreen> {
  // Ladebildschirm
  bool _showSplash = true;
  bool _splashFadingOut = false;
  Timer? _splashTimer;

  int _activeTab = 0;

  // Tab 1: Faktor-Verdünnung (1:X & Reihen)
  bool _factorGoalMode = true;
  final _targetVolCtrl = TextEditingController(text: '50');
  final _factorCtrl = TextEditingController(text: '10');
  final _stockMixCtrl = TextEditingController(text: '2');
  final _bufferMixCtrl = TextEditingController(text: '18');
  String _volUnit1 = 'mL';
  SerialStep? _serialBaseStep;
  final List<SerialStep> _serialSteps = [];

  // Tab 2: Konzentrations-Verdünnung (C1*V1 = C2*V2)
  bool _c1v1FromStockMode = true;
  final _c1Ctrl = TextEditingController(text: '100');
  final _v1Ctrl = TextEditingController(text: '5');
  final _c2Ctrl = TextEditingController(text: '10');
  final _v2Ctrl = TextEditingController(text: '50');
  String _c1Unit = 'mM';
  String _c2Unit = 'mM';
  String _vUnit2 = 'mL';

  static final _decimalFormatters = [_SingleDecimalFormatter()];
  static const _volFactors = {'L': 1.0, 'mL': 1e-3, 'µL': 1e-6};
  static const _concFactors = {
    'M': 1.0,
    'mM': 1e-3,
    'µM': 1e-6,
    'nM': 1e-9,
    'g/L': 1.0,
    'mg/mL': 1.0,
    'µg/mL': 1e-3,
    'ng/mL': 1e-6,
  };
  static const _concGroups = {
    'M': 'molar',
    'mM': 'molar',
    'µM': 'molar',
    'nM': 'molar',
    'g/L': 'mass',
    'mg/mL': 'mass',
    'µg/mL': 'mass',
    'ng/mL': 'mass',
  };

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && _showSplash) setState(() => _splashFadingOut = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    for (final c in [
      _targetVolCtrl,
      _factorCtrl,
      _stockMixCtrl,
      _bufferMixCtrl,
      _c1Ctrl,
      _v1Ctrl,
      _c2Ctrl,
      _v2Ctrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0.0;

  String _fmt(double v) {
    if (v <= 0 || v.isNaN || v.isInfinite) return '0.00';
    if (v < 0.0001) return v.toStringAsExponential(2);
    if (v < 0.01) {
      return v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
    }
    if (v < 10 && (v - double.parse(v.toStringAsFixed(2))).abs() > 1e-4) {
      return v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return v.toStringAsFixed(2);
  }

  String _fmtFactor(double v) {
    if (v <= 0 || v.isNaN || v.isInfinite) return '0';
    if (v >= 1e6) return v.toStringAsExponential(1);
    return (v - v.round()).abs() < 0.01
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _showHelpSheet();
              },
              tooltip: 'Labor-Hilfe & Erklärung',
              backgroundColor: _inkBlue,
              foregroundColor: Colors.white,
              shape: const CircleBorder(
                side: BorderSide(color: _emerald, width: 2.5),
              ),
              child: const Text(
                '?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/bg_paper.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: _paper),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      _buildTopSwitcher(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: KeyedSubtree(
                                  key: ValueKey(_activeTab),
                                  child: _activeTab == 0
                                      ? _buildFactorTab()
                                      : _buildC1V1Tab(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Rechenhilfe ohne Gewähr – Ergebnisse im Labor stets gegenprüfen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showSplash) _buildSplashOverlay(),
      ],
    );
  }

  Widget _buildSplashOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _splashFadingOut,
        child: GestureDetector(
          onTap: () {
            _splashTimer?.cancel();
            if (!_splashFadingOut) setState(() => _splashFadingOut = true);
          },
          child: AnimatedOpacity(
            opacity: _splashFadingOut ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 350),
            onEnd: () {
              if (_splashFadingOut && mounted) {
                setState(() => _showSplash = false);
              }
            },
            child: Material(
              color: _paper,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/bg_paper.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: _paper),
                    ),
                  ),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 24),
                      decoration: _cardDecoration(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LabAssetIcon('tube.jpg', size: 46),
                              SizedBox(width: 12),
                              LabAssetIcon('drop.jpg', size: 46),
                              SizedBox(width: 12),
                              LabAssetIcon('flask.jpg', size: 46),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Labor - Verdünnungsrechner',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: _inkBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Faktor- & Konzentrations-Verdünnung',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _slate,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: 48,
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: _emerald,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '1:X Reihen  •  C₁·V₁ = C₂·V₂',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSwitcher() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _slate,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _tabButton(0, 'Faktor-\nVerdünnung', 'tube.jpg')),
          const SizedBox(width: 6),
          Expanded(
              child: _tabButton(1, 'Konzentrations-\nVerdünnung', 'drop.jpg')),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label, String asset) {
    final selected = _activeTab == index;
    return GestureDetector(
      onTap: () {
        if (_activeTab != index) {
          HapticFeedback.selectionClick();
          setState(() => _activeTab = index);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? _emerald : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LabAssetIcon(asset, size: 20, withLightBadge: true),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: selected ? _slate : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquationHeader({bool c1v1 = false}) {
    Widget item(String asset, String label) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LabAssetIcon(asset, size: 42),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _inkBlue,
              ),
            ),
          ],
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        item('tube.jpg', c1v1 ? 'Stamm (V₁)' : 'Stamm'),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: LabAssetIcon('plus.jpg', size: 22),
        ),
        item('drop.jpg', 'Puffer'),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: LabAssetIcon('equal.jpg', size: 22),
        ),
        item('flask.jpg', c1v1 ? 'Ziel (V₂)' : 'Ziel'),
      ],
    );
  }

  // ==================== TAB 1: FAKTOR-VERDÜNNUNG ====================
  Widget _buildFactorTab() {
    double vStock = 0, vBuffer = 0, vTarget = 0, factor = 0;
    String? warning;

    if (_factorGoalMode) {
      vTarget = _parse(_targetVolCtrl);
      factor = _parse(_factorCtrl);
      if (vTarget <= 0) {
        warning = 'Hinweis: Bitte ein Zielvolumen größer als 0 eingeben.';
      } else if (factor < 1) {
        warning = 'Hinweis: Der Faktor X bei 1 : X muss mindestens 1 sein.';
      } else {
        vStock = vTarget / factor;
        vBuffer = math.max(0.0, vTarget - vStock);
      }
    } else {
      vStock = _parse(_stockMixCtrl);
      vBuffer = _parse(_bufferMixCtrl);
      if (vStock <= 0) {
        warning =
            'Hinweis: Bitte eine vorhandene Stammlösung größer als 0 eingeben.';
      } else {
        vTarget = vStock + vBuffer;
        factor = vTarget / vStock;
      }
    }

    final canAdd = warning == null && vTarget > 0 && factor >= 1;
    final stockL = vStock * (_volFactors[_volUnit1] ?? 1e-3);
    final tinyTip = _factorGoalMode && canAdd && stockL > 0 && stockL < 1e-6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubModeToggle(
          'Ziel vorgegeben',
          'Start vorgegeben',
          _factorGoalMode,
          (v) => setState(() => _factorGoalMode = v),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            children: [
              _buildEquationHeader(),
              const SizedBox(height: 14),
              if (_factorGoalMode) ...[
                _buildInputRow(
                  label: 'Gewünschtes Zielvolumen',
                  assetName: 'flask.jpg',
                  controller: _targetVolCtrl,
                  unit: _volUnit1,
                  units: const ['mL', 'µL', 'L'],
                  onUnitChanged: (u) {
                    HapticFeedback.selectionClick();
                    setState(() => _volUnit1 = u!);
                  },
                ),
                const SizedBox(height: 12),
                _buildInputRow(
                  label: 'Verdünnungsfaktor (1 : X)',
                  controller: _factorCtrl,
                  prefixText: '1 : ',
                ),
              ] else ...[
                _buildInputRow(
                  label: 'Vorhandene Stammlösung',
                  assetName: 'tube.jpg',
                  controller: _stockMixCtrl,
                  unit: _volUnit1,
                  units: const ['mL', 'µL', 'L'],
                  onUnitChanged: (u) {
                    HapticFeedback.selectionClick();
                    setState(() => _volUnit1 = u!);
                  },
                ),
                const SizedBox(height: 12),
                _buildInputRow(
                  label: 'Zugegebener Puffer',
                  assetName: 'drop.jpg',
                  controller: _bufferMixCtrl,
                  unit: _volUnit1,
                ),
              ],
              const Divider(height: 28, thickness: 1.5),
              if (warning != null)
                _banner(warning)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildResultBox(
                        title: _factorGoalMode ? 'Stammlösung' : 'Endvolumen',
                        assetName: _factorGoalMode ? 'tube.jpg' : 'flask.jpg',
                        value:
                            '${_fmt(_factorGoalMode ? vStock : vTarget)} $_volUnit1',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildResultBox(
                        title: _factorGoalMode ? 'Puffer' : 'Faktor (Stufe)',
                        assetName: _factorGoalMode ? 'drop.jpg' : null,
                        value: _factorGoalMode
                            ? '${_fmt(vBuffer)} $_volUnit1'
                            : '1 : ${_fmtFactor(factor)}',
                      ),
                    ),
                  ],
                ),
                if (tinyTip) ...[
                  const SizedBox(height: 10),
                  _banner(
                    'Praxistipp: Das Stammvolumen liegt unter 1 µL – für genaueres Pipettieren empfiehlt sich eine mehrstufige Reihe.',
                    isError: false,
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _inkBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF94A3B8),
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: canAdd
              ? () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    final step = SerialStep(
                      targetVolume: vTarget,
                      factor: factor,
                      unit: _volUnit1,
                    );
                    _serialBaseStep ??= step;
                    _serialSteps.add(step);
                  });
                }
              : null,
          icon: const Icon(Icons.arrow_downward),
          label: const Text(
            'In nächste Reihe übernehmen (+ Schritt)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (_serialSteps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _serialSteps.clear();
                  _serialBaseStep = null;
                });
              },
              icon: const Icon(Icons.delete_sweep, color: Color(0xFFB91C1C)),
              label: const Text(
                'Alle Schritte löschen',
                style: TextStyle(
                    color: Color(0xFFB91C1C), fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ..._buildSerialStepsList(),
        ],
      ],
    );
  }

  List<Widget> _buildSerialStepsList() {
    if (_serialSteps.isEmpty || _serialBaseStep == null) return [];
    final base = _serialBaseStep!;
    double cumFactor = base.factor;

    final widgets = <Widget>[
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _inkBlue, width: 1.5),
        ),
        child: Row(
          children: [
            const LabAssetIcon('flask.jpg', size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Basis (Schritt 1): 1 : ${_fmtFactor(base.factor)}  •  Endvolumen: ${_fmt(base.targetVolume)} ${base.unit}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: _inkBlue),
              ),
            ),
          ],
        ),
      ),
    ];

    for (int i = 0; i < _serialSteps.length; i++) {
      final step = _serialSteps[i];
      final prev = i == 0 ? base : _serialSteps[i - 1];
      cumFactor *= step.factor;
      final stepStock = step.targetVolume / step.factor;
      final stepBuffer = math.max(0.0, step.targetVolume - stepStock);
      final neededL = stepStock * (_volFactors[step.unit] ?? 1e-3);
      final availL = prev.targetVolume * (_volFactors[prev.unit] ?? 1e-3);
      final exceeded = neededL > availL * (1 + 1e-9);

      widgets.add(Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Reihe Schritt ${i + 2} (Gesamt: 1 : ${_fmtFactor(cumFactor)})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: _inkBlue),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFB91C1C)),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _serialSteps.removeAt(i);
                      if (_serialSteps.isEmpty) _serialBaseStep = null;
                    });
                  },
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 6,
              children: [
                const LabAssetIcon('tube.jpg', size: 18),
                Text(
                  '${_fmt(stepStock)} ${step.unit} (aus Schritt ${i + 1})  +',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _slate),
                ),
                const LabAssetIcon('drop.jpg', size: 18),
                Text(
                  '${_fmt(stepBuffer)} ${step.unit} Puffer  =',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _slate),
                ),
                const LabAssetIcon('flask.jpg', size: 18),
                Text(
                  '${_fmt(step.targetVolume)} ${step.unit}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _slate),
                ),
              ],
            ),
            if (exceeded) ...[
              const SizedBox(height: 10),
              _banner(
                'Volumen-Warnung: Schritt ${i + 2} benötigt ${_fmt(stepStock)} ${step.unit}, aber Schritt ${i + 1} liefert nur ${_fmt(prev.targetVolume)} ${prev.unit}.',
                isError: false,
              ),
            ],
          ],
        ),
      ));
    }
    return widgets;
  }

  // ==================== TAB 2: KONZENTRATIONS-VERDÜNNUNG ====================
  Widget _buildC1V1Tab() {
    final sameGroup = _concGroups[_c1Unit] == _concGroups[_c2Unit];
    final c1Base = _parse(_c1Ctrl) * (_concFactors[_c1Unit] ?? 1.0);
    final c2Base = _parse(_c2Ctrl) * (_concFactors[_c2Unit] ?? 1.0);
    final volIn = _c1v1FromStockMode ? _parse(_v1Ctrl) : _parse(_v2Ctrl);

    double v1 = 0, v2 = 0, vBuf = 0;
    String? warning;

    if (!sameGroup) {
      warning =
          'Hinweis: C₁ und C₂ müssen zur selben Einheiten-Art gehören (beide Molar oder beide Masse/Volumen).';
    } else if (c1Base <= 0 || c2Base <= 0) {
      warning = 'Hinweis: Bitte gültige Konzentrationen größer als 0 eingeben.';
    } else if (c1Base < c2Base * (1 - 1e-9)) {
      warning = 'Hinweis: C₁ muss größer oder gleich C₂ sein.';
    } else if (volIn <= 0) {
      warning = 'Hinweis: Bitte ein Volumen größer als 0 eingeben.';
    } else {
      final equalConc =
          (c1Base - c2Base).abs() <= math.max(c1Base, c2Base) * 1e-9;
      if (_c1v1FromStockMode) {
        v1 = volIn;
        v2 = equalConc ? v1 : math.max(v1, (c1Base * v1) / c2Base);
        vBuf = equalConc ? 0.0 : math.max(0.0, v2 - v1);
      } else {
        v2 = volIn;
        v1 = equalConc ? v2 : math.min(v2, (c2Base * v2) / c1Base);
        vBuf = equalConc ? 0.0 : math.max(0.0, v2 - v1);
      }
    }

    final v1L = v1 * (_volFactors[_vUnit2] ?? 1e-3);
    final tinyTip =
        warning == null && !_c1v1FromStockMode && v1L > 0 && v1L < 1e-6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubModeToggle(
          'Start (V₁) vorgegeben',
          'Ziel (V₂) vorgegeben',
          _c1v1FromStockMode,
          (v) => setState(() => _c1v1FromStockMode = v),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            children: [
              _buildEquationHeader(c1v1: true),
              const SizedBox(height: 14),
              _buildInputRow(
                label: 'Startkonzentration (C₁)',
                assetName: 'tube.jpg',
                controller: _c1Ctrl,
                unit: _c1Unit,
                units: _concFactors.keys.toList(),
                onUnitChanged: (u) {
                  HapticFeedback.selectionClick();
                  setState(() => _c1Unit = u!);
                },
              ),
              const SizedBox(height: 12),
              _buildInputRow(
                label: 'Zielkonzentration (C₂)',
                assetName: 'flask.jpg',
                controller: _c2Ctrl,
                unit: _c2Unit,
                units: _concFactors.keys.toList(),
                onUnitChanged: (u) {
                  HapticFeedback.selectionClick();
                  setState(() => _c2Unit = u!);
                },
              ),
              const SizedBox(height: 12),
              _buildInputRow(
                label: _c1v1FromStockMode
                    ? 'Vorhandene Stammlösung (V₁)'
                    : 'Gewünschtes Zielvolumen (V₂)',
                assetName: _c1v1FromStockMode ? 'tube.jpg' : 'flask.jpg',
                controller: _c1v1FromStockMode ? _v1Ctrl : _v2Ctrl,
                unit: _vUnit2,
                units: const ['mL', 'µL', 'L'],
                onUnitChanged: (u) {
                  HapticFeedback.selectionClick();
                  setState(() => _vUnit2 = u!);
                },
              ),
              const Divider(height: 28, thickness: 1.5),
              if (warning != null)
                _banner(warning)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildResultBox(
                        title: _c1v1FromStockMode ? 'Puffer' : 'Stamm (V₁)',
                        assetName: _c1v1FromStockMode ? 'drop.jpg' : 'tube.jpg',
                        value:
                            '${_fmt(_c1v1FromStockMode ? vBuf : v1)} $_vUnit2',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildResultBox(
                        title: _c1v1FromStockMode ? 'Ziel (V₂)' : 'Puffer',
                        assetName:
                            _c1v1FromStockMode ? 'flask.jpg' : 'drop.jpg',
                        value:
                            '${_fmt(_c1v1FromStockMode ? v2 : vBuf)} $_vUnit2',
                      ),
                    ),
                  ],
                ),
                if (tinyTip) ...[
                  const SizedBox(height: 10),
                  _banner(
                    'Praxistipp: V₁ liegt unter 1 µL – für genaueres Pipettieren empfiehlt sich eine Vorverdünnung im Tab „Faktor-Verdünnung“.',
                    isError: false,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==================== LABOR-HILFE (? BUTTON) ====================
  void _showHelpSheet() {
    String filter = 'Grundbegriffe';
    const filters = [
      'Grundbegriffe',
      'Faktor-Verdünnung',
      'Konzentrations-Verdünnung',
      'Alle',
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final showBasics = filter == 'Alle' || filter == 'Grundbegriffe';
          final showFactor = filter == 'Alle' || filter == 'Faktor-Verdünnung';
          final showC1V1 =
              filter == 'Alle' || filter == 'Konzentrations-Verdünnung';

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: _inkBlue, width: 3),
                  left: BorderSide(color: _inkBlue, width: 2),
                  right: BorderSide(color: _inkBlue, width: 2),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF94A3B8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.menu_book_rounded,
                                  color: _inkBlue, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'Labor-Hilfe & Erklärung',
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: _inkBlue),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(ctx).pop();
                            },
                            icon:
                                const Icon(Icons.close_rounded, color: _slate),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Row(
                        children: filters.map((f) {
                          final active = filter == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f),
                              selected: active,
                              showCheckmark: false,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setModalState(() => filter = f);
                              },
                              selectedColor: _inkBlue,
                              backgroundColor: Colors.white,
                              side:
                                  const BorderSide(color: _inkBlue, width: 1.5),
                              labelStyle: TextStyle(
                                color: active ? Colors.white : _inkBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 12, thickness: 1.2),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showBasics) ...[
                              _helpHeading('Grundbegriffe & Symbole'),
                              _helpCard(
                                'Stammlösung (Stock / V₁)',
                                'Deine hochkonzentrierte Ausgangslösung, aus der du ein Teilvolumen abpipettierst.',
                                asset: 'tube.jpg',
                              ),
                              _helpCard(
                                'Stammkonzentration (C₁)',
                                'Die bekannte Konzentration deiner Ausgangslösung – z. B. 100 mM, 1 M oder 10 mg/mL.',
                                asset: 'tube.jpg',
                              ),
                              _helpCard(
                                'Puffer / Lösungsmittel',
                                'Die wirkstofffreie Flüssigkeit (z. B. PBS, Wasser, Medium), mit der du bis zum Endvolumen auffüllst.',
                                asset: 'drop.jpg',
                              ),
                              _helpCard(
                                'Ziellösung (Endvolumen V₂ & C₂)',
                                'Deine fertige Arbeitslösung nach dem Mischen. Es gilt immer: Endvolumen = Stammlösung + Puffer.',
                                asset: 'flask.jpg',
                              ),
                            ],
                            if (showFactor) ...[
                              _helpHeading(
                                  'Tab 1: Faktor-Verdünnung (1:X & Reihen)'),
                              _helpFormulaBox(
                                'Goldene 1:X-Laborregel',
                                '1 : 10  =  1 Teil Stamm + 9 Teile Puffer  =  10 Teile gesamt',
                                'Der Faktor X steht immer für das Verhältnis zum Gesamtvolumen (nicht 1 + 10!).',
                              ),
                              _helpCard(
                                'Ziel vs. Start vorgegeben',
                                '• Ziel vorgegeben: Du gibst Endvolumen und Faktor (1:X) ein → erhältst Stamm und Puffer.\n'
                                    '• Start vorgegeben: Du gibst vorhandene Mengen ein → erhältst Endvolumen und Faktor.',
                              ),
                              _helpCard(
                                'Verdünnungsreihen (+ Schritt)',
                                'Fixiert Schritt 1 als Basis und hängt Folgestufen (z. B. 1:10 → 1:100 → 1:1000) an. Reicht das Volumen der Vorstufe nicht, erscheint eine gelbe Warnung.',
                              ),
                            ],
                            if (showC1V1) ...[
                              _helpHeading(
                                  'Tab 2: Konzentrations-Verdünnung (C₁·V₁ = C₂·V₂)'),
                              _helpFormulaBox(
                                'Verdünnungsformel',
                                'C₁ · V₁ = C₂ · V₂   |   Puffer = V₂ − V₁',
                                'Die Stoffmenge bleibt konstant. C₁ muss immer größer oder gleich C₂ sein.',
                              ),
                              _helpCard(
                                'Start (V₁) vs. Ziel (V₂)',
                                '• Start (V₁) vorgegeben: Berechnet Puffer und Endvolumen (V₂).\n'
                                    '• Ziel (V₂) vorgegeben: Berechnet benötigte Stammlösung (V₁) und Puffer.',
                              ),
                              _helpCard(
                                'Automatische Einheiten-Umrechnung',
                                'Molar (M, mM, µM, nM) und Masse/Volumen (g/L, mg/mL, µg/mL, ng/mL) werden innerhalb ihrer Gruppe automatisch umgerechnet. Unverträgliche Gruppen werden blockiert.',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _helpHeading(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: _inkBlue),
        ),
      );

  Widget _helpCard(String title, String body, {String? asset}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _inkBlue, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asset != null) ...[
            LabAssetIcon(asset, size: 30),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: _slate)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        fontSize: 13, height: 1.38, color: Color(0xFF334155))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpFormulaBox(String title, String formula, String note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _darkEmerald,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _emerald, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFFA7F3D0),
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(formula,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
          const SizedBox(height: 4),
          Text(note,
              style: const TextStyle(
                  color: Color(0xFFD1FAE5), fontSize: 12, height: 1.35)),
        ],
      ),
    );
  }

  // ==================== UI BAUSTEINE ====================
  BoxDecoration _cardDecoration() => BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _inkBlue, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      );

  Widget _banner(String text, {bool isError = true}) {
    final bg = isError ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
    final border = isError ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final fg = isError ? const Color(0xFFB91C1C) : const Color(0xFF92400E);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded,
              color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubModeToggle(
    String leftText,
    String rightText,
    bool isLeft,
    ValueChanged<bool> onChanged,
  ) {
    Widget btn(String text, bool active, bool val) => Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: active ? _inkBlue : Colors.white,
              foregroundColor: active ? Colors.white : _slate,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            ),
            onPressed: () {
              if (!active) {
                HapticFeedback.selectionClick();
                onChanged(val);
              }
            },
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );

    return Row(
      children: [
        btn(leftText, isLeft, true),
        const SizedBox(width: 8),
        btn(rightText, !isLeft, false),
      ],
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    String? assetName,
    String? unit,
    List<String>? units,
    ValueChanged<String?>? onUnitChanged,
    String? prefixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (assetName != null) ...[
              LabAssetIcon(assetName, size: 20),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: _slate),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _decimalFormatters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: _slate),
                decoration: InputDecoration(
                  prefixText: prefixText,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _inkBlue, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _emerald, width: 3),
                  ),
                ),
              ),
            ),
            if (unit != null && units != null && onUnitChanged != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _inkBlue, width: 2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: unit,
                    items: units
                        .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: _slate)),
                            ))
                        .toList(),
                    onChanged: onUnitChanged,
                  ),
                ),
              ),
            ] else if (unit != null) ...[
              const SizedBox(width: 12),
              Text(unit,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: _slate)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildResultBox({
    required String title,
    required String value,
    String? assetName,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _darkEmerald,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _emerald, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (assetName != null) ...[
                LabAssetIcon(assetName, size: 18, withLightBadge: true),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFFA7F3D0),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22)),
          ),
        ],
      ),
    );
  }
}

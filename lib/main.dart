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
    if (t.length > 10) return oldValue;
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
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    -1.2, -1.2, 0, 2.275, 0,
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
  // Sprache (automatisch nach Systemsprache, manuell umschaltbar)
  bool _isDe = true;

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
    'M': 1.0, 'mM': 1e-3, 'µM': 1e-6, 'nM': 1e-9,
    'g/L': 1.0, 'mg/mL': 1.0, 'µg/mL': 1e-3, 'ng/mL': 1e-6,
  };
  static const _concGroups = {
    'M': 'molar', 'mM': 'molar', 'µM': 'molar', 'nM': 'molar',
    'g/L': 'mass', 'mg/mL': 'mass', 'µg/mL': 'mass', 'ng/mL': 'mass',
  };

  @override
  void initState() {
    super.initState();
    final lang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
    _isDe = lang == 'de';
    _splashTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && _showSplash) setState(() => _splashFadingOut = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    for (final c in [
      _targetVolCtrl, _factorCtrl, _stockMixCtrl, _bufferMixCtrl,
      _c1Ctrl, _v1Ctrl, _c2Ctrl, _v2Ctrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String de, String en) => _isDe ? de : en;

  double _parse(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0.0;
    return v.isFinite ? v : 0.0;
  }

  bool _hasThousandsDot(List<TextEditingController> ctrls) {
    if (!_isDe) return false;
    final re = RegExp(r'^[1-9]\d*\.\d{3}$');
    return ctrls.any((c) => re.hasMatch(c.text.trim()));
  }

  String _fmtNum(double v) {
    if (v <= 0 || !v.isFinite) return _isDe ? '0,00' : '0.00';
    String s;
    if (v >= 1) {
      s = v.toStringAsFixed(2);
    } else if (v >= 0.1) {
      s = v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
    } else if (v >= 0.01) {
      s = v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
    } else if (v >= 0.001) {
      s = v.toStringAsFixed(5).replaceFirst(RegExp(r'0+$'), '');
    } else if (v >= 0.0001) {
      s = v.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
    } else {
      s = v.toStringAsExponential(2);
    }
    if (s.endsWith('.')) s = '${s}0';
    return _isDe ? s.replaceAll('.', ',') : s;
  }

  String _fmtVol(double v, String unit) {
    if (v <= 0 || !v.isFinite) {
      return '${_isDe ? '0,00' : '0.00'} $unit';
    }
    double val = v;
    String u = unit;
    if (u == 'L' && val < 0.01) {
      val *= 1000;
      u = 'mL';
    }
    if (u == 'mL' && val < 0.01) {
      val *= 1000;
      u = 'µL';
    }
    if (u == 'µL' && val < 0.01) {
      val *= 1000;
      u = 'nL';
    }
    return '${_fmtNum(val)} $u';
  }

  String _fmtFactor(double v) {
    if (v <= 0 || !v.isFinite) return '0';
    if (v >= 1e6) {
      final s = v.toStringAsExponential(1);
      return _isDe ? s.replaceAll('.', ',') : s;
    }
    final s = (v - v.round()).abs() < 0.01
        ? v.round().toString()
        : v.toStringAsFixed(1);
    return _isDe ? s.replaceAll('.', ',') : s;
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
              tooltip: _t('Labor-Hilfe & Erklärung', 'Lab Help & Guide'),
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
                      _buildLanguageBar(),
                      _buildTopSwitcher(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: KeyedSubtree(
                                  key: ValueKey('$_activeTab-$_isDe'),
                                  child: _activeTab == 0
                                      ? _buildFactorTab()
                                      : _buildC1V1Tab(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _t(
                                  'Rechenhilfe ohne Gewähr – Ergebnisse im Labor stets gegenprüfen.',
                                  'Calculation aid without warranty – always verify lab results.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
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

  Widget _buildLanguageBar() {
    Widget langBtn(String code, bool active, bool selectDe) => Semantics(
          button: true,
          selected: active,
          label: selectDe ? 'Deutsch' : 'English',
          child: GestureDetector(
            onTap: () {
              if (_isDe != selectDe) {
                HapticFeedback.selectionClick();
                setState(() => _isDe = selectDe);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? _inkBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: active ? Colors.white : _inkBlue,
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xE6FFFFFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _inkBlue, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                langBtn('DE', _isDe, true),
                langBtn('EN', !_isDe, false),
              ],
            ),
          ),
        ],
      ),
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
                        horizontal: 24,
                        vertical: 26,
                      ),
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
                          const SizedBox(height: 16),
                          Text(
                            _t(
                              'Labor - Verdünnungsrechner',
                              'Lab Dilution Calculator',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: _inkBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _t(
                              'Faktor- & Konzentrations-Verdünnung',
                              'Factor & Concentration Dilution',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _slate,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: 48,
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: _emerald,
                              borderRadius: BorderRadius.circular(4),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _slate,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              0,
              _t('Faktor-\nVerdünnung', 'Factor\nDilution'),
              'tube.jpg',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _tabButton(
              1,
              _t('Konzentrations-\nVerdünnung', 'Concentration\nDilution'),
              'drop.jpg',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label, String asset) {
    final selected = _activeTab == index;
    return Semantics(
      button: true,
      selected: selected,
      label: label.replaceAll('\n', ' '),
      child: GestureDetector(
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
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _inkBlue,
              ),
            ),
          ],
        );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          item(
            'tube.jpg',
            c1v1 ? _t('Stamm (V₁)', 'Stock (V₁)') : _t('Stamm', 'Stock'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: LabAssetIcon('plus.jpg', size: 22),
          ),
          item('drop.jpg', _t('Puffer', 'Buffer')),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: LabAssetIcon('equal.jpg', size: 22),
          ),
          item(
            'flask.jpg',
            c1v1 ? _t('Ziel (V₂)', 'Target (V₂)') : _t('Ziel', 'Target'),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: FAKTOR-VERDÜNNUNG ====================
  Widget _buildFactorTab() {
    double vStock = 0, vBuffer = 0, vTarget = 0, factor = 0;
    String? warning;

    final activeCtrls = _factorGoalMode
        ? [_targetVolCtrl, _factorCtrl]
        : [_stockMixCtrl, _bufferMixCtrl];
    final dotTrap = _hasThousandsDot(activeCtrls);

    if (_factorGoalMode) {
      vTarget = _parse(_targetVolCtrl);
      factor = _parse(_factorCtrl);
      if (vTarget <= 0) {
        warning = _t(
          'Hinweis: Bitte ein Zielvolumen größer als 0 eingeben.

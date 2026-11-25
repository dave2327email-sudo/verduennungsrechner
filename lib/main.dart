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
          'Hinweis: Bitte ein Zielvolumen größer als 0 eingeben.',
          'Note: Please enter a target volume greater than 0.',
        );
      } else if (factor < 1) {
        warning = _t(
          'Hinweis: Der Faktor X bei 1 : X muss mindestens 1 sein.',
          'Note: The dilution factor X in 1 : X must be at least 1.',
        );
      } else {
        vStock = vTarget / factor;
        vBuffer = math.max(0.0, vTarget - vStock);
      }
    } else {
      vStock = _parse(_stockMixCtrl);
      vBuffer = _parse(_bufferMixCtrl);
      if (vStock <= 0) {
        warning = _t(
          'Hinweis: Bitte eine vorhandene Stammlösung größer als 0 eingeben.',
          'Note: Please enter a stock volume greater than 0.',
        );
      } else {
        vTarget = vStock + vBuffer;
        factor = vTarget / vStock;
      }
    }

    final canAdd = warning == null &&
        vTarget > 0 &&
        vTarget.isFinite &&
        factor >= 1 &&
        factor.isFinite;
    final stockL = vStock * (_volFactors[_volUnit1] ?? 1e-3);
    final tinyTip = _factorGoalMode && canAdd && stockL > 0 && stockL < 1e-6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubModeToggle(
          _t('Ziel vorgegeben', 'Target given'),
          _t('Start vorgegeben', 'Stock given'),
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
                  label: _t('Gewünschtes Zielvolumen', 'Desired target volume'),
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
                  label: _t('Verdünnungsfaktor (1 : X)', 'Dilution factor (1 : X)'),
                  controller: _factorCtrl,
                  prefixText: '1 : ',
                ),
              ] else ...[
                _buildInputRow(
                  label: _t('Vorhandene Stammlösung', 'Available stock volume'),
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
                  label: _t('Zugegebener Puffer', 'Added buffer / diluent'),
                  assetName: 'drop.jpg',
                  controller: _bufferMixCtrl,
                  unit: _volUnit1,
                ),
              ],
              if (dotTrap) ...[
                const SizedBox(height: 10),
                _banner(
                  'Achtung: Der Punkt wird als Dezimalzeichen gelesen („1.000“ = 1). Für Tausender bitte keinen Punkt eingeben (z. B. 1000).',
                  isError: false,
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
                        title: _factorGoalMode
                            ? _t('Stammlösung', 'Stock')
                            : _t('Endvolumen', 'Final volume'),
                        assetName: _factorGoalMode ? 'tube.jpg' : 'flask.jpg',
                        value: _fmtVol(
                          _factorGoalMode ? vStock : vTarget,
                          _volUnit1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildResultBox(
                        title: _factorGoalMode
                            ? _t('Puffer', 'Buffer')
                            : _t('Faktor (Stufe)', 'Factor (Step)'),
                        assetName: _factorGoalMode ? 'drop.jpg' : null,
                        value: _factorGoalMode
                            ? _fmtVol(vBuffer, _volUnit1)
                            : '1 : ${_fmtFactor(factor)}',
                      ),
                    ),
                  ],
                ),
                if (tinyTip) ...[
                  const SizedBox(height: 10),
                  _banner(
                    _t(
                      'Praxistipp: Das Stammvolumen liegt unter 1 µL – für genaueres Pipettieren empfiehlt sich eine mehrstufige Reihe.',
                      'Lab tip: Stock volume is below 1 µL – consider a serial dilution for more accurate pipetting.',
                    ),
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
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    if (_serialBaseStep == null) {
                      _serialBaseStep = step;
                    } else {
                      _serialSteps.add(step);
                    }
                  });
                }
              : null,
          icon: const Icon(Icons.arrow_downward),
          label: Text(
            _serialBaseStep == null
                ? _t(
                    'Als Start-Basis (Schritt 1) festlegen',
                    'Set as Base (Step 1)',
                  )
                : _t(
                    'Nächsten Schritt anhängen (+ Schritt)',
                    'Add next step (+ Step)',
                  ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
          ),
        ),
        if (_serialBaseStep != null) ...[
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
              label: Text(
                _t('Reihe löschen', 'Clear series'),
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ..._buildSerialStepsList(),
        ],
      ],
    );
  }

  List<Widget> _buildSerialStepsList() {
    final base = _serialBaseStep;
    if (base == null) return [];
    double cumFactor = base.factor;
    final baseStock = base.targetVolume / base.factor;
    final baseBuffer = math.max(0.0, base.targetVolume - baseStock);

    final widgets = <Widget>[
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _inkBlue, width: 1.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LabAssetIcon('flask.jpg', size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(
                      'Basis (Schritt 1) – 1 : ${_fmtFactor(base.factor)}',
                      'Base (Step 1) – 1 : ${_fmtFactor(base.factor)}',
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _inkBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtVol(baseStock, base.unit)} ${_t('Stamm', 'stock')}  +  ${_fmtVol(baseBuffer, base.unit)} ${_t('Puffer', 'buffer')}  =  ${_fmtVol(base.targetVolume, base.unit)}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _slate,
              ),
            ),
            if (_serialSteps.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _t(
                  'Passe oben bei Bedarf Faktor oder Volumen an und tippe erneut auf „+ Schritt“.',
                  'Adjust factor or volume above if needed and tap "+ Step" again.',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
                    _t(
                      'Reihe Schritt ${i + 2} (Gesamt: 1 : ${_fmtFactor(cumFactor)})',
                      'Series Step ${i + 2} (Total: 1 : ${_fmtFactor(cumFactor)})',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: _inkBlue,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _serialSteps.removeAt(i));
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
                  '${_fmtVol(stepStock, step.unit)} ${_t('(aus Schritt ${i + 1})', '(from Step ${i + 1})')}  +',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _slate,
                  ),
                ),
                const LabAssetIcon('drop.jpg', size: 18),
                Text(
                  '${_fmtVol(stepBuffer, step.unit)} ${_t('Puffer', 'buffer')}  =',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _slate,
                  ),
                ),
                const LabAssetIcon('flask.jpg', size: 18),
                Text(
                  _fmtVol(step.targetVolume, step.unit),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _slate,
                  ),
                ),
              ],
            ),
            if (exceeded) ...[
              const SizedBox(height: 10),
              _banner(
                _t(
                  'Volumen-Warnung: Schritt ${i + 2} benötigt ${_fmtVol(stepStock, step.unit)}, aber Schritt ${i + 1} liefert nur ${_fmtVol(prev.targetVolume, prev.unit)}.',
                  'Volume warning: Step ${i + 2} needs ${_fmtVol(stepStock, step.unit)}, but Step ${i + 1} only provides ${_fmtVol(prev.targetVolume, prev.unit)}.',
                ),
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
    final volCtrl = _c1v1FromStockMode ? _v1Ctrl : _v2Ctrl;
    final volIn = _parse(volCtrl);
    final dotTrap = _hasThousandsDot([_c1Ctrl, _c2Ctrl, volCtrl]);

    double v1 = 0, v2 = 0, vBuf = 0;
    String? warning;

    if (!sameGroup) {
      warning = _t(
        'Hinweis: C₁ und C₂ müssen zur selben Einheiten-Art gehören (beide Molar oder beide Masse/Volumen).',
        'Note: C₁ and C₂ must use the same unit type (both molar or both mass/volume).',
      );
    } else if (c1Base <= 0 || c2Base <= 0) {
      warning = _t(
        'Hinweis: Bitte gültige Konzentrationen größer als 0 eingeben.',
        'Note: Please enter valid concentrations greater than 0.',
      );
    } else if (c1Base < c2Base * (1 - 1e-9)) {
      warning = _t(
        'Hinweis: C₁ muss größer oder gleich C₂ sein.',
        'Note: C₁ must be greater than or equal to C₂.',
      );
    } else if (volIn <= 0) {
      warning = _t(
        'Hinweis: Bitte ein Volumen größer als 0 eingeben.',
        'Note: Please enter a volume greater than 0.',
      );
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
          _t('Start (V₁) vorgegeben', 'Stock (V₁) given'),
          _t('Ziel (V₂) vorgegeben', 'Target (V₂) given'),
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
                label: _t('Startkonzentration (C₁)', 'Stock concentration (C₁)'),
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
                label: _t('Zielkonzentration (C₂)', 'Target concentration (C₂)'),
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
                    ? _t('Vorhandene Stammlösung (V₁)', 'Available stock (V₁)')
                    : _t('Gewünschtes Zielvolumen (V₂)', 'Desired target volume (V₂)'),
                assetName: _c1v1FromStockMode ? 'tube.jpg' : 'flask.jpg',
                controller: volCtrl,
                unit: _vUnit2,
                units: const ['mL', 'µL', 'L'],
                onUnitChanged: (u) {
                  HapticFeedback.selectionClick();
                  setState(() => _vUnit2 = u!);
                },
              ),
              if (dotTrap) ...[
                const SizedBox(height: 10),
                _banner(
                  'Achtung: Der Punkt wird als Dezimalzeichen gelesen („1.000“ = 1). Für Tausender bitte keinen Punkt eingeben (z. B. 1000).',
                  isError: false,
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
                        title: _c1v1FromStockMode
                            ? _t('Puffer', 'Buffer')
                            : _t('Stamm (V₁)', 'Stock (V₁)'),
                        assetName: _c1v1FromStockMode ? 'drop.jpg' : 'tube.jpg',
                        value: _fmtVol(
                          _c1v1FromStockMode ? vBuf : v1,
                          _vUnit2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildResultBox(
                        title: _c1v1FromStockMode
                            ? _t('Ziel (V₂)', 'Target (V₂)')
                            : _t('Puffer', 'Buffer'),
                        assetName: _c1v1FromStockMode ? 'flask.jpg' : 'drop.jpg',
                        value: _fmtVol(
                          _c1v1FromStockMode ? v2 : vBuf,
                          _vUnit2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (tinyTip) ...[
                  const SizedBox(height: 10),
                  _banner(
                    _t(
                      'Praxistipp: V₁ liegt unter 1 µL – für genaueres Pipettieren empfiehlt sich eine Vorverdünnung im Tab „Faktor-Verdünnung“.',
                      'Lab tip: V₁ is below 1 µL – consider a pre-dilution in the "Factor Dilution" tab for better accuracy.',
                    ),
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
    int filterIndex = 0; // 0: Basics, 1: Factor, 2: Conc, 3: All
    final filters = [
      _t('Grundbegriffe', 'Basics'),
      _t('Faktor-Verdünnung', 'Factor Dilution'),
      _t('Konzentrations-Verdünnung', 'Concentration Dilution'),
      _t('Alle', 'All'),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final showBasics = filterIndex == 3 || filterIndex == 0;
          final showFactor = filterIndex == 3 || filterIndex == 1;
          final showC1V1 = filterIndex == 3 || filterIndex == 2;

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
                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            color: _inkBlue,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _t('Labor-Hilfe & Erklärung', 'Lab Help & Guide'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _inkBlue,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(Icons.close_rounded, color: _slate),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: List.generate(filters.length, (idx) {
                          final active = filterIndex == idx;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(filters[idx]),
                              selected: active,
                              showCheckmark: false,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setModalState(() => filterIndex = idx);
                              },
                              selectedColor: _inkBlue,
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: _inkBlue, width: 1.5),
                              labelStyle: TextStyle(
                                color: active ? Colors.white : _inkBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }),
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
                              _helpHeading(
                                _t('Grundbegriffe & Symbole', 'Basics & Symbols'),
                              ),
                              _helpCard(
                                _t('Stammlösung (Stock / V₁)', 'Stock Solution (V₁)'),
                                _t(
                                  'Deine hochkonzentrierte Ausgangslösung, aus der du ein Teilvolumen abpipettierst.',
                                  'Your concentrated starting solution from which you pipette a portion.',
                                ),
                                asset: 'tube.jpg',
                              ),
                              _helpCard(
                                _t('Stammkonzentration (C₁)', 'Stock Concentration (C₁)'),
                                _t(
                                  'Die bekannte Konzentration deiner Ausgangslösung – z. B. 100 mM, 1 M oder 10 mg/mL.',
                                  'The known concentration of your starting solution – e.g. 100 mM, 1 M, or 10 mg/mL.',
                                ),
                                asset: 'tube.jpg',
                              ),
                              _helpCard(
                                _t('Puffer / Lösungsmittel', 'Buffer / Diluent'),
                                _t(
                                  'Die wirkstofffreie Flüssigkeit (z. B. PBS, Wasser, Medium), mit der du bis zum Endvolumen auffüllst.',
                                  'The blank liquid (e.g. PBS, water, media) used to fill up to the final volume.',
                                ),
                                asset: 'drop.jpg',
                              ),
                              _helpCard(
                                _t('Ziellösung (Endvolumen V₂ & C₂)', 'Target Solution (V₂ & C₂)'),
                                _t(
                                  'Deine fertige Arbeitslösung nach dem Mischen. Es gilt immer: Endvolumen = Stammlösung + Puffer.',
                                  'Your final working solution after mixing. Always: Final volume = Stock + Buffer.',
                                ),
                                asset: 'flask.jpg',
                              ),
                            ],
                            if (showFactor) ...[
                              _helpHeading(
                                _t(
                                  'Tab 1: Faktor-Verdünnung (1:X & Reihen)',
                                  'Tab 1: Factor Dilution (1:X & Series)',
                                ),
                              ),
                              _helpFormulaBox(
                                _t('Goldene 1:X-Laborregel', 'Golden 1:X Lab Rule'),
                                _t(
                                  '1 : 10  =  1 Teil Stamm + 9 Teile Puffer  =  10 Teile gesamt',
                                  '1 : 10  =  1 part stock + 9 parts buffer  =  10 parts total',
                                ),
                                _t(
                                  'Der Faktor X steht immer für das Verhältnis zum Gesamtvolumen (nicht 1 + 10!).',
                                  'Factor X always refers to the total final volume (not 1 + 10!).',
                                ),
                              ),
                              _helpCard(
                                _t('Ziel vs. Start vorgegeben', 'Target vs. Stock given'),
                                _t(
                                  '• Ziel vorgegeben: Du gibst Endvolumen und Faktor (1:X) ein → erhältst Stamm und Puffer.\n• Start vorgegeben: Du gibst vorhandene Mengen ein → erhältst Endvolumen und Faktor.',
                                  '• Target given: Enter final volume & factor (1:X) → get stock and buffer.\n• Stock given: Enter stock & buffer → get final volume and factor.',
                                ),
                              ),
                              _helpCard(
                                _t('Verdünnungsreihen (+ Schritt)', 'Serial Dilutions (+ Step)'),
                                _t(
                                  'Der 1. Tipp fixiert Schritt 1 als Basis. Danach kannst du beliebig viele Folgestufen (auch mit neuem Faktor oder Volumen) anhängen. Reicht das Volumen der Vorstufe nicht, erscheint eine Warnung.',
                                  'The 1st tap locks Step 1 as base. Then add as many follow-up steps as needed (even with new factors or volumes). If the previous volume is too small, a warning appears.',
                                ),
                              ),
                            ],
                            if (showC1V1) ...[
                              _helpHeading(
                                _t(
                                  'Tab 2: Konzentrations-Verdünnung (C₁·V₁ = C₂·V₂)',
                                  'Tab 2: Concentration Dilution (C₁·V₁ = C₂·V₂)',
                                ),
                              ),
                              _helpFormulaBox(
                                _t('Verdünnungsformel', 'Dilution Formula'),
                                _t(
                                  'C₁ · V₁ = C₂ · V₂   |   Puffer = V₂ − V₁',
                                  'C₁ · V₁ = C₂ · V₂   |   Buffer = V₂ − V₁',
                                ),
                                _t(
                                  'Die Stoffmenge bleibt konstant. C₁ muss immer größer oder gleich C₂ sein.',
                                  'Total amount of solute stays constant. C₁ must always be ≥ C₂.',
                                ),
                              ),
                              _helpCard(
                                _t('Start (V₁) vs. Ziel (V₂)', 'Stock (V₁) vs. Target (V₂)'),
                                _t(
                                  '• Start (V₁) vorgegeben: Berechnet Puffer und Endvolumen (V₂).\n• Ziel (V₂) vorgegeben: Berechnet benötigte Stammlösung (V₁) und Puffer.',
                                  '• Stock (V₁) given: Calculates buffer and final volume (V₂).\n• Target (V₂) given: Calculates required stock (V₁) and buffer.',
                                ),
                              ),
                              _helpCard(
                                _t(
                                  'Automatische Einheiten-Umrechnung',
                                  'Automatic Unit Conversion',
                                ),
                                _t(
                                  'Molar (M, mM, µM, nM) und Masse/Volumen (g/L, mg/mL, µg/mL, ng/mL) werden innerhalb ihrer Gruppe automatisch umgerechnet. Unverträgliche Gruppen werden blockiert.',
                                  'Molar (M, mM, µM, nM) and mass/volume (g/L, mg/mL, µg/mL, ng/mL) convert automatically within their group. Incompatible groups are blocked.',
                                ),
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
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _inkBlue,
          ),
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
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: _slate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.38,
                    color: Color(0xFF334155),
                  ),
                ),
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
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFA7F3D0),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formula,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(
              color: Color(0xFFD1FAE5),
              fontSize: 12,
              height: 1.35,
            ),
          ),
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
          BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 4)),
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
          Icon(
            isError ? Icons.error_outline : Icons.warning_amber_rounded,
            color: fg,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
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
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _slate,
                ),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _decimalFormatters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _slate,
                ),
                decoration: InputDecoration(
                  prefixText: prefixText,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                              child: Text(
                                u,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: _slate,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: onUnitChanged,
                  ),
                ),
              ),
            ] else if (unit != null) ...[
              const SizedBox(width: 12),
              Text(
                unit,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: _slate,
                ),
              ),
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
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

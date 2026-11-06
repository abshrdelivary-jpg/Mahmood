import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkTrackerApp());
}

class WorkTrackerApp extends StatefulWidget {
  const WorkTrackerApp({super.key});

  @override
  State<WorkTrackerApp> createState() => _WorkTrackerAppState();
}

class _WorkTrackerAppState extends State<WorkTrackerApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Color _themeColor = const Color(0xFF2563EB);
  double _buttonScale = 1;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _themeMode = prefs.getBool('darkMode') == true
          ? ThemeMode.dark
          : ThemeMode.light;
      _themeColor = Color(prefs.getInt('themeColor') ?? 0xFF2563EB);
      _buttonScale = prefs.getDouble('buttonScale') ?? 1;
      _loaded = true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _themeMode == ThemeMode.dark);
    await prefs.setInt('themeColor', _themeColor.value);
    await prefs.setDouble('buttonScale', _buttonScale);
  }

  void _updateSettings({
    ThemeMode? mode,
    Color? color,
    double? scale,
  }) {
    setState(() {
      if (mode != null) _themeMode = mode;
      if (color != null) _themeColor = color;
      if (scale != null) _buttonScale = scale;
    });
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final scheme = ColorScheme.fromSeed(
      seedColor: _themeColor,
      brightness:
          _themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تتبع ساعات العمل',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        brightness: Brightness.dark,
        cardTheme: CardThemeData(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: HomeScreen(
        themeColor: _themeColor,
        buttonScale: _buttonScale,
        onSettingsChanged: _updateSettings,
        themeMode: _themeMode,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Color themeColor;
  final double buttonScale;
  final ThemeMode themeMode;
  final void Function({ThemeMode? mode, Color? color, double? scale})
      onSettingsChanged;

  const HomeScreen({
    super.key,
    required this.themeColor,
    required this.buttonScale,
    required this.onSettingsChanged,
    required this.themeMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  DateTime? _startTime;
  DateTime? _targetEndTime;
  Duration _elapsed = Duration.zero;
  List<Map<String, dynamic>> _history = [];
  bool _isRunning = false;
  bool _loading = true;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRunning && _startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('workHistory');
    final runningStart = prefs.getString('runningStart');
    if (raw != null) {
      try {
        _history = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      } catch (_) {
        _history = [];
      }
    }
    if (runningStart != null) {
      _startTime = DateTime.tryParse(runningStart);
      if (_startTime != null) {
        _isRunning = true;
        _elapsed = DateTime.now().difference(_startTime!);
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workHistory', jsonEncode(_history));
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Duration _durationFromRecord(Map<String, dynamic> item) {
    final seconds = (item['seconds'] as num?)?.toInt() ?? 0;
    return Duration(seconds: seconds);
  }

  Duration get _todayTotal {
    final today = _dateKey(DateTime.now());
    var total = Duration.zero;
    for (final item in _history) {
      if (item['date'] == today) total += _durationFromRecord(item);
    }
    if (_isRunning) total += _elapsed;
    return total;
  }

  Duration get _weekTotal {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var total = Duration.zero;
    for (final item in _history) {
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date != null && !date.isBefore(monday)) {
        total += _durationFromRecord(item);
      }
    }
    if (_isRunning && _startTime != null && !_startTime!.isBefore(monday)) {
      total += _elapsed;
    }
    return total;
  }

  Future<void> _startWork() async {
    setState(() {
      _startTime = DateTime.now();
      _targetEndTime = null;
      _elapsed = Duration.zero;
      _isRunning = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('runningStart', _startTime!.toIso8601String());
  }

  Future<void> _stopWork() async {
    if (_startTime == null) return;
    final end = DateTime.now();
    final duration = end.difference(_startTime!);
    final record = <String, dynamic>{
      'date': _dateKey(_startTime!),
      'start': _startTime!.toIso8601String(),
      'end': end.toIso8601String(),
      'seconds': duration.inSeconds,
    };
    setState(() {
      _history.insert(0, record);
      _isRunning = false;
      _startTime = null;
      _targetEndTime = null;
      _elapsed = Duration.zero;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('runningStart');
    await _saveHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ ساعات العمل بنجاح')),
    );
  }

  Future<void> _chooseTargetTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _targetEndTime ?? DateTime.now().add(const Duration(hours: 8)),
      ),
    );
    if (picked == null) return;
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    setState(() => _targetEndTime = target);
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          history: _history,
          onClear: () async {
            setState(() => _history.clear());
            await _saveHistory();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تتبع ساعات العمل',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    themeMode: widget.themeMode,
                    themeColor: widget.themeColor,
                    buttonScale: widget.buttonScale,
                    onChanged: widget.onSettingsChanged,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _pageIndex,
          children: [
            _buildDashboard(),
            _buildWeekView(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (index) => setState(() => _pageIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'الأسبوع'),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const Text('وقت العمل الحالي',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 18),
                FittedBox(
                  child: Text(
                    _formatDuration(_elapsed),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: widget.themeColor,
                      fontFeatures: const [],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(_isRunning ? 'الدوام قيد التسجيل' : 'لم يبدأ تسجيل الدوام'),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: 15 * widget.buttonScale,
                      ),
                      backgroundColor:
                          _isRunning ? Colors.red.shade600 : widget.themeColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isRunning ? _stopWork : _startWork,
                    icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _isRunning ? 'إنهاء الدوام وحفظ الوقت' : 'بدء الدوام',
                      style: TextStyle(
                        fontSize: 16 * widget.buttonScale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_isRunning) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _chooseTargetTime,
                    icon: const Icon(Icons.alarm),
                    label: Text(_targetEndTime == null
                        ? 'تحديد وقت نهاية الدوام'
                        : 'النهاية: ${TimeOfDay.fromDateTime(_targetEndTime!).format(context)}'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                title: 'ساعات اليوم',
                value: _formatDuration(_todayTotal),
                icon: Icons.today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                title: 'ساعات الأسبوع',
                value: _formatDuration(_weekTotal),
                icon: Icons.date_range,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: widget.themeColor.withValues(alpha: 0.12),
              child: Icon(Icons.history, color: widget.themeColor),
            ),
            title: const Text('سجل الدوام'),
            subtitle: Text('عدد السجلات: ${_history.length}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _openHistory,
          ),
        ),
        if (_targetEndTime != null && _isRunning)
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('وقت نهاية الدوام المحدد'),
              subtitle: Text(
                TimeOfDay.fromDateTime(_targetEndTime!).format(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: widget.themeColor, size: 26),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                value,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ملخص هذا الأسبوع',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_formatDuration(_weekTotal),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor)),
              ],
            ),
          ),
        ),
        ...days.map((day) {
          final key = _dateKey(day);
          var total = Duration.zero;
          for (final item in _history) {
            if (item['date'] == key) total += _durationFromRecord(item);
          }
          if (_isRunning && _startTime != null && _dateKey(_startTime!) == key) {
            total += _elapsed;
          }
          const names = [
            'الاثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
            'الأحد'
          ];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: widget.themeColor.withValues(alpha: 0.12),
                child: Text('${day.day}',
                    style: TextStyle(color: widget.themeColor)),
              ),
              title: Text(names[day.weekday - 1]),
              subtitle: Text(_dateKey(day)),
              trailing: Text(
                _formatDuration(total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class HistoryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Future<void> Function() onClear;

  const HistoryScreen({
    super.key,
    required this.history,
    required this.onClear,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}س ${minutes}د';
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> get _filteredHistory {
    return widget.history.where((item) {
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null) return false;
      if (_fromDate != null &&
          date.isBefore(DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day))) {
        return false;
      }
      if (_toDate != null &&
          date.isAfter(DateTime(_toDate!.year, _toDate!.month, _toDate!.day))) {
        return false;
      }
      return true;
    }).toList();
  }

  Duration _calculateRangeTotal(List<Map<String, dynamic>> filtered) {
    var total = Duration.zero;
    for (final item in filtered) {
      total += Duration(seconds: (item['seconds'] as num?)?.toInt() ?? 0);
    }
    return total;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الدوام'),
        actions: [
          IconButton(
            tooltip: 'مسح السجل',
            onPressed: widget.history.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('مسح السجل'),
                        content: const Text('هل تريد حذف جميع سجلات الدوام؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await widget.onClear();
                      if (mounted) setState(() {});
                    }
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_fromDate == null
                              ? 'من تاريخ'
                              : _dateKey(_fromDate!)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.event),
                          label: Text(_toDate == null
                              ? 'إلى تاريخ'
                              : _dateKey(_toDate!)),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _fromDate = null;
                      _toDate = null;
                    }),
                    child: const Text('إلغاء التصفية'),
                  ),
                  const Divider(),
                  Text('المجموع: ${_formatDuration(_calculateRangeTotal(filtered))}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('لا توجد سجلات في هذه الفترة')),
            )
          else
            ...filtered.map((item) {
              final start = DateTime.tryParse(item['start']?.toString() ?? '');
              final end = DateTime.tryParse(item['end']?.toString() ?? '');
              final duration =
                  Duration(seconds: (item['seconds'] as num?)?.toInt() ?? 0);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.work_history_outlined),
                  ),
                  title: Text(item['date']?.toString() ?? ''),
                  subtitle: Text(
                    'البداية: ${start == null ? '--' : TimeOfDay.fromDateTime(start).format(context)}'
                    '  •  النهاية: ${end == null ? '--' : TimeOfDay.fromDateTime(end).format(context)}',
                  ),
                  trailing: Text(
                    _formatDuration(duration),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final Color themeColor;
  final double buttonScale;
  final void Function({ThemeMode? mode, Color? color, double? scale}) onChanged;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.themeColor,
    required this.buttonScale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF16A34A),
      Color(0xFF7C3AED),
      Color(0xFFEA580C),
      Color(0xFFDB2777),
      Color(0xFF0891B2),
      Color(0xFF475569),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('الوضع الداكن'),
              value: themeMode == ThemeMode.dark,
              onChanged: (value) => onChanged(
                mode: value ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('لون التطبيق',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: colors.map((color) {
                      final selected = color.value == themeColor.value;
                      return InkWell(
                        onTap: () => onChanged(color: color),
                        borderRadius: BorderRadius.circular(30),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: color,
                          child: selected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حجم الأزرار',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: buttonScale,
                    min: 0.8,
                    max: 1.3,
                    divisions: 5,
                    label: buttonScale.toStringAsFixed(1),
                    onChanged: (value) => onChanged(scale: value),
                  ),
                ],
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('تتبع ساعات العمل'),
              subtitle: Text('تطبيق بسيط لتسجيل ساعات الدوام وحفظ السجل على الهاتف.'),
            ),
          ),
        ],
      ),
    );
  }
}

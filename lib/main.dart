// ============================================================================
// Prayer Times — Android TV app
// ----------------------------------------------------------------------------
// pubspec.yaml dependencies needed:
//   dependencies:
//     flutter:
//       sdk: flutter
//     http: ^1.2.0
//     shared_preferences: ^2.2.0
//
// Android TV notes:
//   - In android/app/src/main/AndroidManifest.xml add the leanback launcher
//     intent-filter + <uses-feature android:name="android.software.leanback"
//     android:required="false" /> so it shows up on the TV home screen.
//   - This app uses Flutter's standard focus system (InkWell/Material), which
//     already responds to D-pad navigation and the remote's "select" button.
//
// How the two features work:
//   1) Search mosque by name -> PrayerApiService.searchMosques()
//      - useMockData = true filters a local JSON string, no network needed.
//      - Set useMockData = false and fill in baseUrl to hit your real API.
//   2) After picking a mosque -> PrayerTimesRepository.getMonth()
//      - Fetches the WHOLE month in one call and saves it via CacheService.
//      - On every later launch it reads from the cache for the *current*
//        month/year. It only calls the API again once the month changes
//        (i.e. there's no cache entry yet for the new month).
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prayer Times TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFEEEEEE),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D7A78),
          brightness: Brightness.light,
        ),
      ),
      home: const SplashRouter(),
    );
  }
}

// ============================================================================
// DESIGN TOKENS
// ============================================================================

class AppColors {
  static const background     = Color(0xFFEEEEEE);
  static const panelLeft      = Color(0xFFE5E5E5);
  static const panelRight     = Color(0xFFF5F5F5);
  static const activeTeal     = Color(0xFF3D7A78);
  static const activeTealLight= Color(0xFF4E9593);
  static const textPrimary    = Color(0xFF1A1A1A);
  static const textSecondary  = Color(0xFF555555);
  static const textMuted      = Color(0xFF888888);
  static const divider        = Color(0xFFCCCCCC);
  static const border         = Color(0xFFBBBBBB);
}

class AppTextStyles {
  static const salahLabel = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.8,
    color: AppColors.textPrimary,
  );
  static const timeNormal = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    letterSpacing: 1.2,
  );
  static const iqamahNormal = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: 1.0,
  );
  static const salahLabelActive = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    color: Colors.white,
  );
  static const timeActive = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w400,
    color: Colors.white70,
    letterSpacing: 1.2,
  );
  static const iqamahActive = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    letterSpacing: 1.0,
  );
  static const columnHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.5,
    color: AppColors.textMuted,
  );
  static const dateGregorian = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: AppColors.textPrimary,
  );
  static const dateHijri = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
  );
  static const clockMain = TextStyle(
    fontSize: 72,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -2,
  );
  static const clockAmPm = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );
  static const nextLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    color: AppColors.activeTeal,
  );
  static const nextCountdown = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w900,
    color: AppColors.activeTeal,
    letterSpacing: 1.0,
  );
  static const sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    color: AppColors.textSecondary,
  );
  static const sunriseLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: AppColors.textSecondary,
  );
  static const sunriseTime = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}

// ============================================================================
// MODELS
// ============================================================================

class Mosque {
  final String id;
  final String name;
  final String city;
  final String address;

  Mosque({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
  });

  factory Mosque.fromJson(Map<String, dynamic> json) => Mosque(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        city: json['city'] ?? '',
        address: json['address'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'address': address,
      };
}

class DayPrayerTimes {
  final String date;
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;

  DayPrayerTimes({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  factory DayPrayerTimes.fromJson(Map<String, dynamic> json) => DayPrayerTimes(
        date: json['date'],
        fajr: json['fajr'],
        sunrise: json['sunrise'],
        dhuhr: json['dhuhr'],
        asr: json['asr'],
        maghrib: json['maghrib'],
        isha: json['isha'],
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'fajr': fajr,
        'sunrise': sunrise,
        'dhuhr': dhuhr,
        'asr': asr,
        'maghrib': maghrib,
        'isha': isha,
      };
}

// ============================================================================
// MOCK DATA
// ============================================================================

class MockData {
  static const String mosquesJson = '''
  [
    {"id": "1", "name": "Al-Noor Mosque", "city": "Rabat", "address": "12 Avenue Hassan II"},
    {"id": "2", "name": "Masjid Al-Falah", "city": "Casablanca", "address": "45 Rue Mohammed V"},
    {"id": "3", "name": "Grand Mosque", "city": "Fez", "address": "Old Medina"},
    {"id": "4", "name": "Al-Rahma Mosque", "city": "Marrakech", "address": "Gueliz District"},
    {"id": "5", "name": "Masjid Al-Salam", "city": "Tangier", "address": "Boulevard Pasteur"},
    {"id": "6", "name": "Noor Al-Houda", "city": "Agadir", "address": "Avenue des FAR"}
  ]
  ''';

  static List<Map<String, dynamic>> generateMonthlyMock(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final List<Map<String, dynamic>> days = [];
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final shiftMin = d % 10;
      days.add({
        'date': dateStr,
        'fajr': _shiftTime('05:10', shiftMin),
        'sunrise': _shiftTime('06:35', shiftMin),
        'dhuhr': _shiftTime('13:05', 0),
        'asr': _shiftTime('16:20', shiftMin ~/ 2),
        'maghrib': _shiftTime('19:40', -shiftMin),
        'isha': _shiftTime('21:00', -shiftMin),
      });
    }
    return days;
  }

  static String _shiftTime(String base, int minutes) {
    final parts = base.split(':');
    int h = int.parse(parts[0]);
    int m = int.parse(parts[1]) + minutes;
    if (m < 0) { m += 60; h -= 1; }
    if (m >= 60) { m -= 60; h += 1; }
    h = h % 24;
    if (h < 0) h += 24;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// API SERVICE
// ============================================================================

class PrayerApiService {
  static const bool useMockData = true;
  static const String baseUrl = 'https://your-api.example.com/api';

  static Future<List<Mosque>> searchMosques(String query) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      final List<dynamic> all = json.decode(MockData.mosquesJson);
      final filtered = all
          .where((m) =>
              (m['name'] as String).toLowerCase().contains(query.toLowerCase()))
          .toList();
      return filtered.map((e) => Mosque.fromJson(e)).toList();
    }
    final uri = Uri.parse('$baseUrl/mosques/search?q=${Uri.encodeQueryComponent(query)}');
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final List<dynamic> data = json.decode(res.body);
      return data.map((e) => Mosque.fromJson(e)).toList();
    }
    throw Exception('Failed to search mosques (${res.statusCode})');
  }

  static Future<List<DayPrayerTimes>> fetchMonthlyTimes(
      String mosqueId, int year, int month) async {
    if (useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      final raw = MockData.generateMonthlyMock(year, month);
      return raw.map((e) => DayPrayerTimes.fromJson(e)).toList();
    }
    final uri = Uri.parse(
        '$baseUrl/mosques/$mosqueId/prayer-times?year=$year&month=$month');
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final List<dynamic> data = json.decode(res.body);
      return data.map((e) => DayPrayerTimes.fromJson(e)).toList();
    }
    throw Exception('Failed to fetch prayer times (${res.statusCode})');
  }
}

// ============================================================================
// LOCAL CACHE
// ============================================================================

class CacheService {
  static const _selectedMosqueKey = 'selected_mosque';
  static const _cachedDataPrefix = 'cached_prayer_times_';

  static Future<void> saveSelectedMosque(Mosque mosque) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedMosqueKey, json.encode(mosque.toJson()));
  }

  static Future<Mosque?> getSelectedMosque() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_selectedMosqueKey);
    if (raw == null) return null;
    return Mosque.fromJson(json.decode(raw));
  }

  static Future<void> clearSelectedMosque() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedMosqueKey);
  }

  static String _monthKey(String mosqueId, int year, int month) =>
      '$_cachedDataPrefix${mosqueId}_${year}_$month';

  static Future<List<DayPrayerTimes>?> getCachedMonth(
      String mosqueId, int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_monthKey(mosqueId, year, month));
    if (raw == null) return null;
    final List<dynamic> list = json.decode(raw);
    return list.map((e) => DayPrayerTimes.fromJson(e)).toList();
  }

  static Future<void> saveMonth(
      String mosqueId, int year, int month, List<DayPrayerTimes> days) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = json.encode(days.map((d) => d.toJson()).toList());
    await prefs.setString(_monthKey(mosqueId, year, month), raw);
  }

  static Future<void> clearOldMonths(
      String mosqueId, int currentYear, int currentMonth) async {
    final prefs = await SharedPreferences.getInstance();
    final keep = _monthKey(mosqueId, currentYear, currentMonth);
    final staleKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('$_cachedDataPrefix${mosqueId}_') && k != keep)
        .toList();
    for (final k in staleKeys) {
      await prefs.remove(k);
    }
  }
}

// ============================================================================
// IQAMAH SETTINGS — per-prayer offset in minutes, persisted locally
// ============================================================================

class IqamahSettings {
  final int fajr;
  final int dhuhr;
  final int asr;
  final int maghrib;
  final int isha;

  const IqamahSettings({
    this.fajr    = 20,
    this.dhuhr   = 20,
    this.asr     = 20,
    this.maghrib = 10,
    this.isha    = 20,
  });

  IqamahSettings copyWith({int? fajr, int? dhuhr, int? asr, int? maghrib, int? isha}) =>
      IqamahSettings(
        fajr:    fajr    ?? this.fajr,
        dhuhr:   dhuhr   ?? this.dhuhr,
        asr:     asr     ?? this.asr,
        maghrib: maghrib ?? this.maghrib,
        isha:    isha    ?? this.isha,
      );

  int forLabel(String upperLabel) {
    switch (upperLabel) {
      case 'FAJR':    return fajr;
      case 'DHUHR':   return dhuhr;
      case 'ASR':     return asr;
      case 'MAGHRIB': return maghrib;
      case 'ISHA':    return isha;
      default:        return 20;
    }
  }

  Map<String, dynamic> toJson() => {
    'fajr': fajr, 'dhuhr': dhuhr, 'asr': asr, 'maghrib': maghrib, 'isha': isha,
  };

  factory IqamahSettings.fromJson(Map<String, dynamic> j) => IqamahSettings(
    fajr:    (j['fajr']    as int?) ?? 20,
    dhuhr:   (j['dhuhr']   as int?) ?? 20,
    asr:     (j['asr']     as int?) ?? 20,
    maghrib: (j['maghrib'] as int?) ?? 10,
    isha:    (j['isha']    as int?) ?? 20,
  );
}

class IqamahService {
  static const _key = 'iqamah_settings';

  static Future<IqamahSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const IqamahSettings();
    return IqamahSettings.fromJson(json.decode(raw));
  }

  static Future<void> save(IqamahSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(s.toJson()));
  }
}

// ============================================================================
// REPOSITORY
// ============================================================================

class PrayerTimesRepository {
  static Future<List<DayPrayerTimes>> getMonth(String mosqueId,
      {bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh) {
      final cached = await CacheService.getCachedMonth(mosqueId, now.year, now.month);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final fresh = await PrayerApiService.fetchMonthlyTimes(mosqueId, now.year, now.month);
    await CacheService.saveMonth(mosqueId, now.year, now.month, fresh);
    await CacheService.clearOldMonths(mosqueId, now.year, now.month);
    return fresh;
  }
}

// ============================================================================
// SPLASH / ROUTER
// ============================================================================

class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final mosque = await CacheService.getSelectedMosque();
    if (!mounted) return;
    if (mosque != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PrayerTimesScreen(mosque: mosque)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MosqueSearchScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator(color: AppColors.activeTeal)),
    );
  }
}

// ============================================================================
// SCREEN 1 — SEARCH MOSQUE  (light theme)
// ============================================================================

class MosqueSearchScreen extends StatefulWidget {
  const MosqueSearchScreen({super.key});

  @override
  State<MosqueSearchScreen> createState() => _MosqueSearchScreenState();
}

class _MosqueSearchScreenState extends State<MosqueSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Mosque> _results = [];
  bool _loading = false;
  String? _error;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final results = await PrayerApiService.searchMosques(query.trim());
      setState(() => _results = results);
    } catch (_) {
      setState(() => _error = 'Could not search mosques. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectMosque(Mosque mosque) async {
    await CacheService.saveSelectedMosque(mosque);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PrayerTimesScreen(mosque: mosque)),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.activeTeal,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'FIND YOUR MOSQUE',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Search field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Search mosque name...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 20),
                    prefixIcon: Icon(Icons.search, color: AppColors.activeTeal, size: 26),
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (_loading)
                const Center(child: CircularProgressIndicator(color: AppColors.activeTeal)),
              if (_error != null)
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, index) {
                    final mosque = _results[index];
                    return _MosqueTile(mosque: mosque, onTap: () => _selectMosque(mosque));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MosqueTile extends StatelessWidget {
  final Mosque mosque;
  final VoidCallback onTap;
  const _MosqueTile({required this.mosque, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        focusColor: AppColors.activeTeal.withOpacity(0.12),
        hoverColor: AppColors.activeTeal.withOpacity(0.06),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              const Icon(Icons.mosque, size: 28, color: AppColors.activeTeal),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mosque.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 2),
                    Text('${mosque.address}, ${mosque.city}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 2 — PRAYER TIMES  (two-column mosque board layout)
// ============================================================================

class PrayerTimesScreen extends StatefulWidget {
  final Mosque mosque;
  const PrayerTimesScreen({super.key, required this.mosque});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  List<DayPrayerTimes> _month = [];
  bool _loading = true;
  String? _error;

  IqamahSettings _iqamahSettings = const IqamahSettings();

  Timer? _ticker;
  DateTime _now = DateTime.now();
  DateTime? _loadedForMonth;

  static const List<String> _prayerOrder = [
    'Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'
  ];

  @override
  void initState() {
    super.initState();
    _loadIqamahSettings();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      setState(() => _now = now);
      if (_loadedForMonth != null &&
          (now.month != _loadedForMonth!.month ||
              now.year != _loadedForMonth!.year)) {
        _load();
      }
    });
  }

  Future<void> _loadIqamahSettings() async {
    final s = await IqamahService.load();
    if (mounted) setState(() => _iqamahSettings = s);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final days = await PrayerTimesRepository.getMonth(
          widget.mosque.id, forceRefresh: forceRefresh);
      setState(() {
        _month = days;
        _loadedForMonth = DateTime.now();
      });
    } catch (_) {
      setState(() => _error = 'Could not load prayer times.');
    } finally {
      setState(() => _loading = false);
    }
  }

  DayPrayerTimes? get _today {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final match = _month.where((d) => d.date == todayStr);
    if (match.isNotEmpty) return match.first;
    return _month.isNotEmpty ? _month.first : null;
  }

  DateTime _parseTime(String hhmm, DateTime date) {
    final parts = hhmm.split(':');
    return DateTime(
        date.year, date.month, date.day,
        int.parse(parts[0]), int.parse(parts[1]));
  }

  Map<String, String> get _todayTimesMap {
    final todayDay = _today;
    if (todayDay == null) return {};
    return {
      'Fajr': todayDay.fajr,
      'Dhuhr': todayDay.dhuhr,
      'Asr': todayDay.asr,
      'Maghrib': todayDay.maghrib,
      'Isha': todayDay.isha,
    };
  }

  /// The prayer that has already started but the next one hasn't yet.
  /// This is the row that stays highlighted.
  ({String label, DateTime time})? get _currentPrayer {
    final timesMap = _todayTimesMap;
    if (timesMap.isEmpty) return null;
    ({String label, DateTime time})? last;
    for (final name in _prayerOrder) {
      final dt = _parseTime(timesMap[name]!, _now);
      if (!dt.isAfter(_now)) {
        last = (label: name.toUpperCase(), time: dt);
      }
    }
    return last;
  }

  /// The next prayer that hasn't started yet.
  ({String label, DateTime time})? get _nextPrayer {
    final timesMap = _todayTimesMap;
    if (timesMap.isEmpty) return null;
    for (final name in _prayerOrder) {
      final dt = _parseTime(timesMap[name]!, _now);
      if (dt.isAfter(_now)) return (label: name, time: dt);
    }
    final tomorrow = _now.add(const Duration(days: 1));
    final tomorrowStr =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final tomorrowMatches = _month.where((d) => d.date == tomorrowStr);
    if (tomorrowMatches.isNotEmpty) {
      return (label: 'Fajr', time: _parseTime(tomorrowMatches.first.fajr, tomorrow));
    }
    return null;
  }

  /// Iqamah countdown: visible only after the current prayer start and before
  /// iqamah time. Returns null when iqamah hasn't come yet or has already passed.
  ({String label, Duration remaining})? get _iqamahCountdown {
    final current = _currentPrayer;
    if (current == null) return null;
    final offsetMin = _iqamahSettings.forLabel(current.label);
    final iqamahTime = current.time.add(Duration(minutes: offsetMin));
    if (_now.isAfter(iqamahTime)) return null;
    final remaining = iqamahTime.difference(_now);
    return (label: current.label, remaining: remaining);
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<IqamahSettings>(
      MaterialPageRoute(
        builder: (_) => IqamahSettingsScreen(current: _iqamahSettings),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _iqamahSettings = updated);
    }
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatClockHHMM(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    return '${h.toString().padLeft(2, '0')}:$mm';
  }

  String _amPm(DateTime t) => t.hour >= 12 ? 'PM' : 'AM';

  String _formatDate() {
    final now = DateTime.now();
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _changeMosque() async {
    await CacheService.clearSelectedMosque();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MosqueSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.activeTeal)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(_error!,
              style: const TextStyle(fontSize: 22, color: Colors.redAccent)),
        ),
      );
    }

    final today = _today;
    final current = _currentPrayer;
    final next = _nextPrayer;
    final iqamah = _iqamahCountdown;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            _TopBar(
              mosqueName: widget.mosque.name,
              mosqueCity: widget.mosque.city,
              onRefresh: () => _load(forceRefresh: true),
              onChangeMosque: _changeMosque,
              onSettings: _openSettings,
            ),
            // ── Main body — two-column split ─────────────────────────────
            Expanded(
              child: Row(
                children: [
                  // LEFT: prayer table — highlighted row = current (started) prayer
                  Expanded(
                    flex: 58,
                    child: Container(
                      color: AppColors.panelLeft,
                      child: today == null
                          ? const SizedBox()
                          : _PrayerTable(
                              day: today,
                              activeLabel: current?.label,
                              iqamahSettings: _iqamahSettings,
                              now: _now,
                            ),
                    ),
                  ),
                  // divider
                  Container(width: 1, color: AppColors.divider),
                  // RIGHT: clock + next prayer + iqamah countdown
                  Expanded(
                    flex: 42,
                    child: Container(
                      color: AppColors.panelRight,
                      child: _RightPanel(
                        now: _now,
                        formatClock: _formatClockHHMM,
                        amPm: _amPm,
                        formatDate: _formatDate,
                        next: next,
                        iqamahCountdown: iqamah,
                        formatCountdown: _formatCountdown,
                        today: today,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Decorative footer strip ──────────────────────────────────
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.activeTeal, AppColors.activeTealLight, AppColors.activeTeal],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String mosqueName;
  final String mosqueCity;
  final VoidCallback onRefresh;
  final VoidCallback onChangeMosque;
  final VoidCallback onSettings;
  const _TopBar({
    required this.mosqueName,
    required this.mosqueCity,
    required this.onRefresh,
    required this.onChangeMosque,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.activeTeal,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.mosque, color: Colors.white70, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mosqueName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Colors.white,
                  ),
                ),
                Text(
                  mosqueCity,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          _RemoteButton(label: 'IQAMAH', icon: Icons.tune, onTap: onSettings),
          const SizedBox(width: 12),
          _RemoteButton(label: 'REFRESH', icon: Icons.refresh, onTap: onRefresh),
          const SizedBox(width: 12),
          _RemoteButton(label: 'CHANGE', icon: Icons.swap_horiz, onTap: onChangeMosque),
        ],
      ),
    );
  }
}

// ─── Left panel: prayer table ─────────────────────────────────────────────────

class _PrayerTable extends StatelessWidget {
  final DayPrayerTimes day;
  final String? activeLabel;
  final IqamahSettings iqamahSettings;
  final DateTime now;

  const _PrayerTable({
    required this.day,
    required this.now,
    required this.iqamahSettings,
    this.activeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData)>[
      ('FAJR',    day.fajr,    Icons.nightlight_round),
      ('DHUHR',   day.dhuhr,   Icons.wb_sunny),
      ('ASR',     day.asr,     Icons.cloud_outlined),
      ('MAGHRIB', day.maghrib, Icons.brightness_4),
      ('ISHA',    day.isha,    Icons.nights_stay),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          child: Row(
            children: const [
              Expanded(flex: 44, child: Text('SALAH',  style: AppTextStyles.columnHeader)),
              Expanded(flex: 28, child: Center(child: Text('STARTS', style: AppTextStyles.columnHeader))),
              Expanded(flex: 28, child: Center(child: Text('IQAMAH', style: AppTextStyles.columnHeader))),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) =>
                Container(height: 1, color: AppColors.divider),
            itemBuilder: (context, i) {
              final (label, starts, icon) = entries[i];
              final isActive = activeLabel != null && label == activeLabel;
              final offsetMin = iqamahSettings.forLabel(label);
              return _PrayerRow(
                label: label,
                icon: icon,
                starts: starts,
                iqamahOffset: offsetMin,
                isActive: isActive,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PrayerRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String starts;
  final int iqamahOffset;   // minutes after adhan
  final bool isActive;
  const _PrayerRow({
    required this.label,
    required this.icon,
    required this.starts,
    required this.iqamahOffset,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isActive ? AppColors.activeTeal : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 0),
      height: null,
      child: IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Salah label + icon
              Expanded(
                flex: 44,
                child: Row(
                  children: [
                    Icon(icon,
                        size: 26,
                        color: isActive ? Colors.white70 : AppColors.activeTeal),
                    const SizedBox(width: 14),
                    Text(label,
                        style: isActive
                            ? AppTextStyles.salahLabelActive
                            : AppTextStyles.salahLabel),
                  ],
                ),
              ),
              // Starts time
              Expanded(
                flex: 28,
                child: Center(
                  child: Text(starts,
                      style: isActive
                          ? AppTextStyles.timeActive
                          : AppTextStyles.timeNormal),
                ),
              ),
              // Iqamah offset badge: "+N min"
              Expanded(
                flex: 28,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withOpacity(0.18)
                          : AppColors.activeTeal.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive
                            ? Colors.white.withOpacity(0.35)
                            : AppColors.activeTeal.withOpacity(0.30),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '+$iqamahOffset min',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isActive ? Colors.white : AppColors.activeTeal,
                      ),
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
}

// ─── Right panel ─────────────────────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  final DateTime now;
  final String Function(DateTime) formatClock;
  final String Function(DateTime) amPm;
  final String Function() formatDate;
  final ({String label, DateTime time})? next;
  final ({String label, Duration remaining})? iqamahCountdown;
  final String Function(Duration) formatCountdown;
  final DayPrayerTimes? today;

  const _RightPanel({
    required this.now,
    required this.formatClock,
    required this.amPm,
    required this.formatDate,
    required this.next,
    required this.iqamahCountdown,
    required this.formatCountdown,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Date
          Text(formatDate(), style: AppTextStyles.dateGregorian),
          const SizedBox(height: 4),
          // Sunrise / Ishraq row
          if (today != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SunInfo(label: 'SUNRISE', time: today!.sunrise),
                const SizedBox(width: 24),
                _SunInfo(label: 'ISHRAQ', time: _ishraq(today!.sunrise)),
              ],
            ),
          const SizedBox(height: 16),
          // Big clock
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatClock(now), style: AppTextStyles.clockMain),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 6),
                child: Text(amPm(now), style: AppTextStyles.clockAmPm),
              ),
            ],
          ),
          // Ornamental divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _OrnamentDivider(),
          ),

          // ── Iqamah countdown (only visible when prayer has started and iqamah hasn't) ──
          if (iqamahCountdown != null) ...[
            const Text('IQAMAH IN', style: AppTextStyles.nextLabel),
            const SizedBox(height: 6),
            Text(
              formatCountdown(iqamahCountdown!.remaining),
              style: AppTextStyles.nextCountdown,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _OrnamentDivider(),
            ),
          ],

          // ── Next prayer block ──
          if (next != null) ...[
            const Text('NEXT PRAYER', style: AppTextStyles.nextLabel),
            const SizedBox(height: 8),
            Text(
              next!.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime12(next!.time),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: AppColors.activeTeal,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            // Countdown to next prayer start
            Text(
              formatCountdown(next!.time.difference(now)),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],

          const Spacer(),
        ],
      ),
    );
  }

  String _ishraq(String sunrise) {
    final parts = sunrise.split(':');
    int h = int.parse(parts[0]);
    int m = int.parse(parts[1]) + 15;
    if (m >= 60) { m -= 60; h += 1; }
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatTime12(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:$mm $ap';
  }
}

class _SunInfo extends StatelessWidget {
  final String label;
  final String time;
  const _SunInfo({required this.label, required this.time});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label ', style: AppTextStyles.sunriseLabel),
        Text(time, style: AppTextStyles.sunriseTime),
      ],
    );
  }
}

// ============================================================================
// IQAMAH SETTINGS SCREEN
// ============================================================================

class IqamahSettingsScreen extends StatefulWidget {
  final IqamahSettings current;
  const IqamahSettingsScreen({super.key, required this.current});

  @override
  State<IqamahSettingsScreen> createState() => _IqamahSettingsScreenState();
}

class _IqamahSettingsScreenState extends State<IqamahSettingsScreen> {
  late IqamahSettings _draft;
  bool _saving = false;

  static const List<(String, String)> _prayers = [
    ('FAJR',    'Fajr'),
    ('DHUHR',   'Dhuhr'),
    ('ASR',     'Asr'),
    ('MAGHRIB', 'Maghrib'),
    ('ISHA',    'Isha'),
  ];

  // Allowed minute steps on the TV remote — easy to scroll through
  static const List<int> _steps = [5, 10, 15, 20, 25, 30, 35, 40, 45, 60];

  @override
  void initState() {
    super.initState();
    _draft = widget.current;
  }

  void _setOffset(String upperKey, int value) {
    setState(() {
      switch (upperKey) {
        case 'FAJR':    _draft = _draft.copyWith(fajr: value);    break;
        case 'DHUHR':   _draft = _draft.copyWith(dhuhr: value);   break;
        case 'ASR':     _draft = _draft.copyWith(asr: value);     break;
        case 'MAGHRIB': _draft = _draft.copyWith(maghrib: value); break;
        case 'ISHA':    _draft = _draft.copyWith(isha: value);    break;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await IqamahService.save(_draft);
    if (mounted) Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Container(
              color: AppColors.activeTeal,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              child: Row(
                children: [
                  Material(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      focusColor: Colors.white.withOpacity(0.25),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    'IQAMAH SETTINGS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (_saving)
                    const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2,
                      ),
                    )
                  else
                    _RemoteButton(label: 'SAVE', icon: Icons.check, onTap: _save),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: const Text(
                'Set how many minutes after adhan the iqamah begins for each prayer.',
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 36),
            // Prayer rows
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                itemCount: _prayers.length,
                separatorBuilder: (_, __) =>
                    Container(height: 1, color: AppColors.divider, margin: const EdgeInsets.symmetric(vertical: 4)),
                itemBuilder: (context, i) {
                  final (key, label) = _prayers[i];
                  final current = _draft.forLabel(key);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        // Prayer name
                        SizedBox(
                          width: 160,
                          child: Text(label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.0,
                                color: AppColors.textPrimary,
                              )),
                        ),
                        const SizedBox(width: 32),
                        // Stepper buttons
                        _StepButton(
                          icon: Icons.remove,
                          enabled: current > _steps.first,
                          onTap: () {
                            final idx = _steps.indexOf(current);
                            if (idx > 0) _setOffset(key, _steps[idx - 1]);
                          },
                        ),
                        const SizedBox(width: 16),
                        // Current value display
                        Container(
                          width: 120,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.activeTeal.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.activeTeal.withOpacity(0.35),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '+$current min',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.activeTeal,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _StepButton(
                          icon: Icons.add,
                          enabled: current < _steps.last,
                          onTap: () {
                            final idx = _steps.indexOf(current);
                            if (idx < _steps.length - 1) _setOffset(key, _steps[idx + 1]);
                          },
                        ),
                        const SizedBox(width: 32),
                        // Quick-select chips
                        Expanded(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: _steps.map((m) {
                              final selected = m == current;
                              return _QuickChip(
                                label: '+$m',
                                selected: selected,
                                onTap: () => _setOffset(key, m),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.activeTeal : AppColors.divider,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        focusColor: AppColors.activeTealLight,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon,
              size: 22,
              color: enabled ? Colors.white : AppColors.textMuted),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.activeTeal : Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        focusColor: AppColors.activeTeal.withOpacity(0.2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.activeTeal : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Ornamental divider ───────────────────────────────────────────────────────

class _OrnamentDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppColors.activeTeal.withOpacity(0.4)],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.auto_awesome,
              size: 14, color: AppColors.activeTeal.withOpacity(0.6)),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.activeTeal.withOpacity(0.4), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared remote button ─────────────────────────────────────────────────────

class _RemoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _RemoteButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        focusColor: Colors.white.withOpacity(0.25),
        hoverColor: Colors.white.withOpacity(0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
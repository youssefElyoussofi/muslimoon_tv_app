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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1320),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1ABC9C),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashRouter(),
    );
  }
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
  final String date; // yyyy-MM-dd
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
// MOCK DATA (used while there is no live backend to hit)
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

  /// Generates a believable month of prayer times so the UI/caching logic
  /// can be tested end-to-end without a real API.
  static List<Map<String, dynamic>> generateMonthlyMock(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final List<Map<String, dynamic>> days = [];
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final shiftMin = d % 10; // tiny daily drift, like real solar tables
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
    if (m < 0) {
      m += 60;
      h -= 1;
    }
    if (m >= 60) {
      m -= 60;
      h += 1;
    }
    h = h % 24;
    if (h < 0) h += 24;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// API SERVICE
// ============================================================================

class PrayerApiService {
  /// Flip to false once a real backend is wired up.
  static const bool useMockData = true;

  /// Replace with your real API base URL.
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

    final uri =
        Uri.parse('$baseUrl/mosques/search?q=${Uri.encodeQueryComponent(query)}');
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final List<dynamic> data = json.decode(res.body);
      return data.map((e) => Mosque.fromJson(e)).toList();
    }
    throw Exception('Failed to search mosques (${res.statusCode})');
  }

  /// Fetches the FULL month of prayer times for a mosque in one call.
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
// LOCAL CACHE (shared_preferences)
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

  /// Returns cached data ONLY if it matches the requested year/month.
  /// If the month has rolled over, this naturally returns null and the
  /// caller knows it needs to hit the API again.
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

  /// Keeps storage tidy by dropping months other than the current one.
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
// REPOSITORY — ties API + cache together
// ============================================================================

class PrayerTimesRepository {
  /// Cache-first month loader.
  /// - If a cache entry exists for THIS year/month, returns it instantly,
  ///   no network call at all.
  /// - If not (first selection, or the month just changed), fetches the
  ///   whole month from the API once and stores it for next time.
  static Future<List<DayPrayerTimes>> getMonth(String mosqueId,
      {bool forceRefresh = false}) async {
    final now = DateTime.now();

    if (!forceRefresh) {
      final cached = await CacheService.getCachedMonth(
          mosqueId, now.year, now.month);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final fresh =
        await PrayerApiService.fetchMonthlyTimes(mosqueId, now.year, now.month);
    await CacheService.saveMonth(mosqueId, now.year, now.month, fresh);
    await CacheService.clearOldMonths(mosqueId, now.year, now.month);
    return fresh;
  }
}

// ============================================================================
// SPLASH / ROUTER — sends user to search or straight to today's times
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// ============================================================================
// SCREEN 1 — SEARCH MOSQUE
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
    setState(() {
      _loading = true;
      _error = null;
    });
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Find your mosque',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(fontSize: 24),
                decoration: InputDecoration(
                  hintText: 'Search mosque name...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final mosque = _results[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _MosqueTile(
                        mosque: mosque,
                        onTap: () => _selectMosque(mosque),
                      ),
                    );
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
      color: Colors.white10,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        focusColor: Colors.teal.withOpacity(0.35),
        hoverColor: Colors.teal.withOpacity(0.15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.mosque, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mosque.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    Text('${mosque.address}, ${mosque.city}',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 2 — PRAYER TIMES (today, from the cached/fetched month)
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

  // Live clock + countdown state.
  Timer? _ticker;
  DateTime _now = DateTime.now();
  DateTime? _loadedForMonth; // tracks which month the cache/API load covered

  static const List<String> _prayerOrder = [
    'Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // Ticks every second to refresh the clock + countdown, and quietly
    // reloads the month if it rolls over while the screen stays open.
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

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await PrayerTimesRepository.getMonth(widget.mosque.id,
          forceRefresh: forceRefresh);
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
        date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  /// Finds the next upcoming prayer (skips Sunrise, it isn't a prayer).
  /// Rolls over to tomorrow's Fajr once all of today's have passed.
  ({String label, DateTime time})? get _nextPrayer {
    final todayDay = _today;
    if (todayDay == null) return null;

    final timesMap = {
      'Fajr': todayDay.fajr,
      'Dhuhr': todayDay.dhuhr,
      'Asr': todayDay.asr,
      'Maghrib': todayDay.maghrib,
      'Isha': todayDay.isha,
    };

    for (final name in _prayerOrder) {
      final dt = _parseTime(timesMap[name]!, _now);
      if (dt.isAfter(_now)) {
        return (label: name, time: dt);
      }
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

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatClock(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  Future<void> _changeMosque() async {
    await CacheService.clearSelectedMosque();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MosqueSearchScreen()),
    );
  }

  String _formatToday() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final next = _nextPrayer;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(60),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 22, color: Colors.redAccent)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.mosque.name,
                                    style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.bold)),
                                Text(widget.mosque.city,
                                    style: const TextStyle(
                                        fontSize: 20, color: Colors.white70)),
                              ],
                            ),
                            Row(
                              children: [
                                _RemoteButton(
                                  label: 'Refresh',
                                  icon: Icons.refresh,
                                  onTap: () => _load(forceRefresh: true),
                                ),
                                const SizedBox(width: 16),
                                _RemoteButton(
                                  label: 'Change mosque',
                                  icon: Icons.swap_horiz,
                                  onTap: _changeMosque,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatToday(),
                                style: const TextStyle(
                                    fontSize: 22, color: Colors.tealAccent)),
                            Text(_formatClock(_now),
                                style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (next != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: Colors.tealAccent, width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time_filled,
                                    color: Colors.tealAccent, size: 28),
                                const SizedBox(width: 12),
                                Text('Next: ${next.label}',
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                Text(
                                  _formatCountdown(next.time.difference(_now)),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.tealAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        if (today != null)
                          Expanded(
                            child: _PrayerGrid(day: today, nextLabel: next?.label),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _PrayerGrid extends StatelessWidget {
  final DayPrayerTimes day;
  final String? nextLabel;
  const _PrayerGrid({required this.day, this.nextLabel});

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData)>[
      ('Fajr', day.fajr, Icons.nightlight_round),
      ('Sunrise', day.sunrise, Icons.wb_twilight),
      ('Dhuhr', day.dhuhr, Icons.wb_sunny),
      ('Asr', day.asr, Icons.cloud_outlined),
      ('Maghrib', day.maghrib, Icons.brightness_4),
      ('Isha', day.isha, Icons.nights_stay),
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 1.6,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final (label, time, icon) = entries[index];
        final isNext = nextLabel != null && label == nextLabel;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isNext ? Colors.tealAccent.withOpacity(0.20) : Colors.white10,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isNext ? Colors.tealAccent : Colors.white12,
              width: isNext ? 2.5 : 1,
            ),
            boxShadow: isNext
                ? [
                    BoxShadow(
                      color: Colors.tealAccent.withOpacity(0.35),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 32, color: isNext ? Colors.white : Colors.tealAccent),
              const SizedBox(height: 12),
              Text(label,
                  style: TextStyle(
                    fontSize: 22,
                    color: isNext ? Colors.white : Colors.white70,
                    fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                  )),
              const SizedBox(height: 8),
              Text(time,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: isNext ? Colors.tealAccent : Colors.white,
                  )),
              if (isNext)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'NEXT',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RemoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _RemoteButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        focusColor: Colors.tealAccent.withOpacity(0.25),
        hoverColor: Colors.tealAccent.withOpacity(0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
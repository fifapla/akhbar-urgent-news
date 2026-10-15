import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat, PlatformDispatcher;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  try {
    await initPush(app.pushOn).timeout(const Duration(seconds: 6));
  } catch (_) {}
  // أي خطأ غير متوقع يُسجَّل على الجهاز (الإعدادات ← سجل الأخطاء)
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    app.logError(d.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (e, st) {
    app.logError('$e');
    return true;
  };
  runApp(const AkhbarApp());
}

// ═════════════════════════ الألوان والخطوط ═════════════════════════

class Pal {
  final Color bg, card, border, ink, muted, chip;
  final Color tabOn, tabOnText, green, onGreen, red, onRed;
  final Color nav, navOn, navText, navOff, tagBg, tagText;
  final List<Color> thumbs;
  const Pal({
    required this.bg,
    required this.card,
    required this.border,
    required this.ink,
    required this.muted,
    required this.chip,
    required this.tabOn,
    required this.tabOnText,
    required this.green,
    required this.onGreen,
    required this.red,
    required this.onRed,
    required this.nav,
    required this.navOn,
    required this.navText,
    required this.navOff,
    required this.tagBg,
    required this.tagText,
    required this.thumbs,
  });

  static const light = Pal(
    bg: Color(0xFFF5EEE3),
    card: Color(0xFFFFFBF4),
    border: Color(0xFFE8DDCB),
    ink: Color(0xFF1B1916),
    muted: Color(0xFF6F6559),
    chip: Color(0xFFEADFCF),
    tabOn: Color(0xFF1B1916),
    tabOnText: Color(0xFFF5EEE3),
    green: Color(0xFF1E5B4F),
    onGreen: Color(0xFFFFFFFF),
    red: Color(0xFFC23B22),
    onRed: Color(0xFFFFFFFF),
    nav: Color(0xFF1B1916),
    navOn: Color(0xFF3A342D),
    navText: Color(0xFFF5EEE3),
    navOff: Color(0xFFBDB2A0),
    tagBg: Color(0xFFFBE3DD),
    tagText: Color(0xFFC23B22),
    thumbs: [Color(0xFFD9C9AE), Color(0xFFBFD2C8), Color(0xFFE3BFA9)],
  );

  static const dark = Pal(
    bg: Color(0xFF14110F),
    card: Color(0xFF211C18),
    border: Color(0xFF352E27),
    ink: Color(0xFFF3EBDD),
    muted: Color(0xFFB3A793),
    chip: Color(0xFF2A241F),
    tabOn: Color(0xFFF3EBDD),
    tabOnText: Color(0xFF14110F),
    green: Color(0xFF7FC3B1),
    onGreen: Color(0xFF14110F),
    red: Color(0xFFE5533A),
    onRed: Color(0xFF14110F),
    nav: Color(0xFF2A241F),
    navOn: Color(0xFF463D34),
    navText: Color(0xFFF3EBDD),
    navOff: Color(0xFFB3A793),
    tagBg: Color(0xFF3A1F18),
    tagText: Color(0xFFFF8A73),
    thumbs: [Color(0xFF3A332B), Color(0xFF2E3D37), Color(0xFF43332B)],
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

TextStyle ui(double size, {FontWeight w = FontWeight.w700, Color? c, double? h}) =>
    GoogleFonts.cairo(fontSize: size, fontWeight: w, color: c, height: h);

TextStyle body(double size, {Color? c, double h = 2.0}) =>
    GoogleFonts.notoNaskhArabic(fontSize: size, color: c, height: h);

final RegExp arabicChars = RegExp(r'[؀-ۿ]');
TextDirection dirOf(String s) =>
    arabicChars.hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

String arNum(Object v) {
  const d = '٠١٢٣٤٥٦٧٨٩';
  return v.toString().replaceAllMapped(RegExp(r'\d'), (m) => d[int.parse(m[0]!)]);
}

String dateText() {
  final n = DateTime.now();
  const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  return '${days[n.weekday - 1]} ${arNum(n.day)} ${months[n.month - 1]} ${arNum(n.year)}';
}

String ago(DateTime? t) {
  if (t == null) return '';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'الآن';
  if (m < 60) return 'منذ ${arNum(m)} دقيقة';
  final h = (m / 60).round();
  if (h < 24) return 'منذ ${arNum(h)} ساعة';
  return 'منذ ${arNum((h / 24).round())} يوم';
}

// ═════════════════════════ المصادر ═════════════════════════

class FeedDef {
  final String name;
  final List<String> urls;
  final bool translate;

  /// المواقع المصرية تنشر التاريخ أحيانًا بدون منطقة زمنية، فنعتبره بتوقيت الجهاز.
  final bool local;
  const FeedDef(this.name, this.urls, {this.translate = false, this.local = false});
}

const String _aj =
    'aljazeerarss/a7c186be-1baa-4bd4-9d80-a84db769f779/73d0e1b4-532f-45ef-b135-bfdff8b8cab9';

const Map<String, FeedDef> feeds = {
  'y7pol': FeedDef('اليوم السابع', ['https://www.youm7.com/rss/SectionRss?SectionID=319'], local: true),
  'y7acc': FeedDef('اليوم السابع', ['https://www.youm7.com/rss/SectionRss?SectionID=203'], local: true),
  'y7brk': FeedDef('اليوم السابع', ['https://www.youm7.com/rss/SectionRss?SectionID=65'], local: true),
  'y7arab': FeedDef('اليوم السابع', ['https://www.youm7.com/rss/SectionRss?SectionID=88'], local: true),
  'masry': FeedDef('المصري اليوم', [
    'https://www.almasryalyoum.com/rss/rssfeeds?sectionId=3',
    'https://www.almasryalyoum.com/rss/rssfeeds',
    'http://www.almasryalyoum.com/rss/rssfeeds',
  ], local: true),
  'masrymain': FeedDef('المصري اليوم', [
    'https://www.almasryalyoum.com/rss/rssfeeds',
    'http://www.almasryalyoum.com/rss/rssfeeds',
  ], local: true),
  'masrawy': FeedDef('مصراوي', [
    'https://www.masrawy.com/rss/feed/35/%D9%85%D8%B5%D8%B1',
  ], local: true),
  'masrawyacc': FeedDef('مصراوي', [
    'https://www.masrawy.com/rss/feed/205/%D8%AD%D9%88%D8%A7%D8%AF%D8%AB',
  ], local: true),
  'masrawyworld': FeedDef('مصراوي', [
    'https://www.masrawy.com/rss/feed/202/%D8%B9%D8%B1%D8%A8-%D9%88%D8%B9%D8%A7%D9%84%D9%85',
  ], local: true),
  'aj': FeedDef('الجزيرة', [
    'https://www.ajnet.me/$_aj',
    'https://www.aljazeera.net/$_aj',
  ]),
  'bbc': FeedDef('بي بي سي عربي', ['https://feeds.bbci.co.uk/arabic/rss.xml']),
  'arabiya': FeedDef('العربية', ['https://www.alarabiya.net/feed/rss2/ar.xml']),
  'gus': FeedDef('الغارديان', ['https://www.theguardian.com/us-news/rss'], translate: true),
  'bbcus': FeedDef('بي بي سي', ['https://feeds.bbci.co.uk/news/world/us_and_canada/rss.xml'], translate: true),
  'nyt': FeedDef('نيويورك تايمز', ['https://rss.nytimes.com/services/xml/rss/nyt/US.xml'], translate: true),
  'gukr': FeedDef('الغارديان', ['https://www.theguardian.com/world/ukraine/rss'], translate: true),
  'grus': FeedDef('الغارديان', ['https://www.theguardian.com/world/russia/rss'], translate: true),
  'geu': FeedDef('الغارديان', ['https://www.theguardian.com/world/europe-news/rss'], translate: true),
  'bbceu': FeedDef('بي بي سي', ['https://feeds.bbci.co.uk/news/world/europe/rss.xml'], translate: true),
  'nyteu': FeedDef('نيويورك تايمز', ['https://rss.nytimes.com/services/xml/rss/nyt/Europe.xml'], translate: true),
  'dw': FeedDef('دويتشه فيله', ['https://rss.dw.com/rdf/rss-en-eu'], translate: true),
  'gworld': FeedDef('الغارديان', ['https://www.theguardian.com/world/rss'], translate: true),
  'bbcw': FeedDef('بي بي سي', ['https://feeds.bbci.co.uk/news/world/rss.xml'], translate: true),
  // مصادر مضافة
  'skyar': FeedDef('سكاي نيوز عربية', ['https://www.skynewsarabia.com/web/rss']),
  'f24': FeedDef('فرانس ٢٤', ['https://www.france24.com/ar/rss']),
  'dwar': FeedDef('دويتشه فيله عربي', ['https://rss.dw.com/rdf/rss-ar-all']),
  'aje': FeedDef('الجزيرة الإنجليزية', ['https://www.aljazeera.com/xml/rss/all.xml'], translate: true),
  'skyw': FeedDef('سكاي نيوز', ['https://feeds.skynews.com/feeds/rss/world.xml'], translate: true),
  'shorouk': FeedDef('الشروق', ['https://www.shorouknews.com/egypt/rss']),
  'cairo24': FeedDef('القاهرة ٢٤', ['https://www.cairo24.com/rss.aspx']),
  'watan': FeedDef('الوطن', ['https://www.elwatannews.com/rss'], local: true),
  // الرياضة
  'masrawysport': FeedDef('مصراوي', [
    'https://www.masrawy.com/rss/feed/27/%D8%B1%D9%8A%D8%A7%D8%B6%D8%A9',
  ], local: true),
  'masrawysportw': FeedDef('مصراوي', [
    'https://www.masrawy.com/rss/feed/579/%D8%A3%D8%AE%D8%A8%D8%A7%D8%B1-%D8%B9%D8%B1%D8%A8%D9%8A%D8%A9-%D9%88%D8%B9%D8%A7%D9%84%D9%85%D9%8A%D8%A9',
  ], local: true),
  'arabiyasport': FeedDef('العربية', ['https://www.alarabiya.net/feed/rss2/ar/sport.xml']),
  // الاقتصاد
  'y7eco': FeedDef('اليوم السابع', ['https://www.youm7.com/rss/SectionRss?SectionID=297'], local: true),
  'arabiyaeco': FeedDef('العربية', ['https://www.alarabiya.net/feed/rss2/ar/aswaq.xml']),
};

/// المصادر كما تظهر في الإعدادات (لتشغيل كل مصدر أو إيقافه).
const Map<String, List<String>> sourceGroups = {
  'مصر': ['اليوم السابع', 'المصري اليوم', 'مصراوي', 'الشروق', 'القاهرة ٢٤', 'الوطن'],
  'عربية': ['الجزيرة', 'بي بي سي عربي', 'العربية', 'سكاي نيوز عربية', 'فرانس ٢٤', 'دويتشه فيله عربي'],
  'عالمية': ['الغارديان', 'بي بي سي', 'نيويورك تايمز', 'دويتشه فيله', 'الجزيرة الإنجليزية', 'سكاي نيوز'],
};

class ViewGroup {
  final String? label;
  final List<String> feedIds;
  final bool urgent;
  final String? pattern;
  const ViewGroup(this.label, this.feedIds, {this.urgent = false, this.pattern});
}

const List<(String, String)> tabList = [
  ('egypt', 'مصر'),
  ('arab', 'عربية'),
  ('world', 'عالمية'),
  ('sports', 'رياضة'),
  ('econ', 'اقتصاد'),
  ('now', 'الآن'),
  ('urgent', 'عاجل'),
  ('topics', 'مواضيعي'),
];

String tabLabel(String k) => tabList.firstWhere((t) => t.$1 == k).$2;

const String _ruUa =
    r'russia|ukrain|kyiv|kiev|moscow|putin|zelensky|zelenskyy|kremlin|donbas|crimea';

const Map<String, List<ViewGroup>> views = {
  'egypt': [
    ViewGroup(null, ['y7pol', 'y7acc', 'y7brk', 'masry', 'masrawy', 'masrawyacc', 'shorouk', 'cairo24', 'watan']),
  ],
  'arab': [
    ViewGroup(null, ['aj', 'bbc', 'arabiya', 'skyar', 'f24', 'dwar']),
  ],
  'world': [
    ViewGroup('أمريكا', ['gus', 'bbcus', 'nyt']),
    ViewGroup('روسيا وأوكرانيا', ['gukr', 'grus', 'bbceu', 'nyteu', 'aje', 'skyw'], pattern: _ruUa),
    ViewGroup('أوروبا', ['geu', 'bbceu', 'nyteu', 'dw']),
  ],
  'sports': [
    ViewGroup(null, ['masrawysport', 'masrawysportw', 'arabiyasport']),
  ],
  'econ': [
    ViewGroup(null, ['y7eco', 'arabiyaeco']),
  ],
  'urgent': [
    ViewGroup(
      null,
      [
        'y7brk', 'y7arab', 'y7acc', 'masrymain', 'masrawyworld', 'masrawyacc', 'shorouk', 'cairo24',
        'aj', 'bbc', 'arabiya', 'skyar', 'gworld', 'bbcw', 'skyw', 'aje',
      ],
      urgent: true,
    ),
  ],
};

final RegExp urgentRe = RegExp(
  r'عاجل|حرب|قصف|غارة|غارات|هجوم|هجمات|زلزال|هزة|إعصار|اعصار|عاصفة|فيضان|فيضانات|سيول|حريق|حرائق|كارثة|انفجار|انفجارات|مقتل|ضحايا|بركان|تسونامي|اشتباك|اشتباكات|صاروخ|صواريخ|مسيرة|مسيّرة|اغتيال|انهيار|غرق|تحطم|إخلاء|طوارئ|'
  r'war|strike|strikes|attack|earthquake|quake|hurricane|typhoon|cyclone|storm|flood|flooding|wildfire|disaster|explosion|blast|killed|dead|death toll|volcano|tsunami|missile|drone|shooting|evacuat|collapse|emergency|breaking',
  caseSensitive: false,
);

const Map<String, String> catLabels = {
  'war': 'حروب',
  'quake': 'زلازل',
  'storm': 'أعاصير',
  'flood': 'فيضانات',
  'disaster': 'كوارث',
};

final RegExp _reQuake = RegExp(r'زلزال|هزة|بركان|تسونامي|earthquake|quake|volcano|tsunami', caseSensitive: false);
final RegExp _reStorm = RegExp(r'إعصار|اعصار|عاصفة|typhoon|hurricane|cyclone|storm', caseSensitive: false);
final RegExp _reFlood = RegExp(r'فيضان|فيضانات|سيول|flood', caseSensitive: false);
final RegExp _reWar = RegExp(
  r'حرب|قصف|غارة|غارات|هجوم|هجمات|اشتباك|اشتباكات|صاروخ|صواريخ|مسيرة|مسيّرة|اغتيال|war|strike|attack|missile|drone|shooting|killed|dead',
  caseSensitive: false,
);

String urgentCategory(String t) {
  if (_reQuake.hasMatch(t)) return 'quake';
  if (_reStorm.hasMatch(t)) return 'storm';
  if (_reFlood.hasMatch(t)) return 'flood';
  if (_reWar.hasMatch(t)) return 'war';
  return 'disaster';
}

// ═════════════════════════ الترجمة ═════════════════════════

final Map<String, String> trCache = {};

Future<String> translateText(String text) async {
  if (text.trim().isEmpty) return text;
  if (text.length > 1800) {
    final parts = <String>[];
    var cur = '';
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+'))) {
      if (cur.isNotEmpty && (cur + s).length > 1500) {
        parts.add(cur);
        cur = s;
      } else {
        cur = cur.isEmpty ? s : '$cur $s';
      }
    }
    if (cur.isNotEmpty) parts.add(cur);
    final res = <String>[];
    for (final p in parts) {
      res.add(await translateText(p));
    }
    return res.join(' ');
  }
  final c = trCache[text];
  if (c != null) return c;
  try {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': 'ar',
      'dt': 't',
    });
    final r = await http.post(uri, body: {'q': text}).timeout(const Duration(seconds: 15));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final out = (j[0] as List).map((x) => x[0] as String).join();
    if (out.isNotEmpty) {
      trCache[text] = out;
      return out;
    }
  } catch (_) {}
  return text;
}

// ═════════════════════════ النماذج والحالة ═════════════════════════

class News extends ChangeNotifier {
  final String orig;
  String title;
  final String link;
  DateTime? time;
  final String? img;
  final String src;
  final bool foreign;
  final String summary;
  bool translated = false;
  bool busy = false;

  /// أسماء المصادر الأخرى التي نشرت الخبر نفسه (تُملأ عند منع التكرار).
  final Set<String> others = {};

  /// نسخ الخبر نفسه من مصادر أخرى (لعرض "خط القصة").
  final List<News> related = [];

  News(this.orig, this.link, this.time, this.img, this.src, this.foreign,
      {this.summary = ''})
      : title = orig;

  /// ترجمة العنوان إلى العربية، أو الرجوع إلى الأصل.
  Future<void> toggleTitle() async {
    if (translated) {
      title = orig;
      translated = false;
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    final t = await translateText(orig);
    busy = false;
    if (t != orig) {
      title = t;
      translated = true;
    }
    notifyListeners();
  }

  Map<String, dynamic> toJson({bool deep = true}) => {
        'o': orig,
        'l': link,
        't': time?.millisecondsSinceEpoch,
        'i': img,
        's': src,
        'f': foreign,
        'u': summary,
        'x': others.toList(),
        if (deep) 'r': [for (final r in related) r.toJson(deep: false)],
      };

  factory News.fromJson(Map<String, dynamic> j) {
    final n = News(
      j['o'] as String,
      j['l'] as String,
      j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      j['i'] as String?,
      j['s'] as String,
      (j['f'] as bool?) ?? false,
      summary: (j['u'] as String?) ?? '',
    );
    final x = j['x'];
    if (x is List) n.others.addAll(x.whereType<String>());
    final r = j['r'];
    if (r is List) {
      for (final e in r) {
        try {
          n.related.add(News.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    return n;
  }
}

class Group {
  final String? label;
  final List<News> items;
  Group(this.label, this.items);
}

class AppState extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  double fontScale = 1.0;
  final List<News> saved = [];
  final Set<String> disabled = {};
  final List<String> readList = [];
  final Set<String> read = {};
  SharedPreferences? _p;

  // ───── التابات والمواضيع ─────
  List<String> tabOrder = tabList.map((t) => t.$1).toList();
  final Set<String> hiddenTabs = {};
  final List<String> topics = [];

  // ───── اهتماماتك: تُحسب وتُحفظ على جهازك فقط ─────
  final Map<String, double> interest = {};

  void learn(News n, double w) {
    interest.updateAll((k, v) => v * 0.98);
    for (final k in keywordsOf(n.orig)) {
      interest[k] = (interest[k] ?? 0) + w;
    }
    if (interest.length > 300) {
      final top = interest.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      interest
        ..clear()
        ..addEntries(top.take(200));
    }
    try {
      _p?.setString('interest', jsonEncode(interest));
    } catch (_) {}
  }

  double scoreOf(News n) {
    if (interest.isEmpty) return 0;
    final ks = keywordsOf(n.orig);
    if (ks.isEmpty) return 0;
    var sum = 0.0;
    for (final k in ks) {
      sum += interest[k] ?? 0;
    }
    return sum / math.sqrt(ks.length);
  }

  // ───── سجل القراءة (للبحث في كل ما قرأت) ─────
  final List<News> history = [];

  void addHistory(News n) {
    history.removeWhere((h) => h.link == n.link);
    history.insert(0, n);
    while (history.length > 200) {
      history.removeLast();
    }
    try {
      _p?.setStringList('history', [for (final h in history) jsonEncode(h.toJson(deep: false))]);
    } catch (_) {}
  }

  // ───── النشرة المحفوظة وملخصات القصص ─────
  String briefDate = '';
  String briefText = '';
  final Map<String, String> storyCache = {};
  bool autoStories = true;
  bool pushOn = false;

  static String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  bool get briefFresh => briefText.isNotEmpty && briefDate == _todayKey();

  void saveBrief(String t) {
    briefDate = _todayKey();
    briefText = t;
    _p?.setString('briefD', briefDate);
    _p?.setString('briefT', t);
    notifyListeners();
  }

  void saveStory(String link, String t) {
    storyCache.remove(link);
    storyCache[link] = t;
    while (storyCache.length > 60) {
      storyCache.remove(storyCache.keys.first);
    }
    try {
      _p?.setString('stories', jsonEncode(storyCache));
    } catch (_) {}
    notifyListeners();
  }

  void setAutoStories(bool v) {
    autoStories = v;
    _p?.setBool('autoStories', v);
    notifyListeners();
  }

  void setPushOn(bool v) {
    pushOn = v;
    _p?.setBool('pushOn', v);
    notifyListeners();
  }

  void markAllRead(Iterable<String> links) {
    for (final l in links) {
      if (read.add(l)) readList.add(l);
    }
    while (readList.length > 1500) {
      read.remove(readList.removeAt(0));
    }
    _p?.setStringList('read', readList);
    notifyListeners();
  }

  // ───── المساعد الذكي (نموذج على حاسوبك عبر أولاما) ─────
  String aiUrl = '';
  String aiModel = 'qwen3.5:9b';
  bool get aiOn => aiUrl.trim().isNotEmpty;

  void setAi({String? url, String? model}) {
    if (url != null) aiUrl = url;
    if (model != null) aiModel = model;
    _p?.setString('aiUrl', aiUrl);
    _p?.setString('aiModel', aiModel);
    notifyListeners();
  }

  // ───── سجل الأخطاء المحلي ─────
  final List<String> errors = [];

  void logError(String m) {
    final t = m.length > 400 ? m.substring(0, 400) : m;
    errors.insert(0, '${DateTime.now().toIso8601String()}  $t');
    while (errors.length > 30) {
      errors.removeLast();
    }
    try {
      _p?.setStringList('errors', errors);
    } catch (_) {}
  }

  void clearErrors() {
    errors.clear();
    _p?.remove('errors');
    notifyListeners();
  }

  List<String> get visibleTabs {
    final v = tabOrder.where((k) => !hiddenTabs.contains(k)).toList();
    return v.isEmpty ? ['egypt'] : v;
  }

  void setTabOrder(List<String> o) {
    tabOrder = o;
    _p?.setStringList('tabOrder', o);
    notifyListeners();
  }

  void toggleTab(String k) {
    if (hiddenTabs.contains(k)) {
      hiddenTabs.remove(k);
    } else {
      if (tabOrder.where((t) => !hiddenTabs.contains(t)).length <= 1) return;
      hiddenTabs.add(k);
    }
    _p?.setStringList('tabHidden', hiddenTabs.toList());
    notifyListeners();
  }

  void addTopic(String k) {
    k = k.trim();
    if (k.isEmpty || topics.contains(k)) return;
    topics.add(k);
    _p?.setStringList('topics', topics);
    notifyListeners();
  }

  void removeTopic(String k) {
    topics.remove(k);
    _p?.setStringList('topics', topics);
    notifyListeners();
  }

  // ───── التخزين المؤقت للأخبار ─────
  Future<void> saveCache(String tab, List<Group> groups) async {
    try {
      await _p?.setString(
        'cache_$tab',
        jsonEncode({
          'g': [
            for (final g in groups)
              {'l': g.label, 'i': [for (final n in g.items) n.toJson()]},
          ],
        }),
      );
    } catch (_) {}
  }

  List<Group>? readCache(String tab) {
    final s = _p?.getString('cache_$tab');
    if (s == null) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return [
        for (final g in m['g'] as List)
          Group(g['l'] as String?, [
            for (final i in g['i'] as List)
              News.fromJson(Map<String, dynamic>.from(i as Map)),
          ]),
      ];
    } catch (_) {
      return null;
    }
  }

  // ───── نسخ الأخبار المحفوظة للقراءة بدون إنترنت ─────
  final Map<String, Map<String, dynamic>> offline = {};

  void storeOffline(String link, List<String> paras, String? image) {
    offline.remove(link);
    offline[link] = {'p': paras, 'i': image};
    while (offline.length > 40) {
      offline.remove(offline.keys.first);
    }
    _persistOffline();
  }

  void _persistOffline() {
    try {
      _p?.setString('offline', jsonEncode(offline));
    } catch (_) {}
  }

  bool isRead(String link) => read.contains(link);

  void markRead(String link) {
    if (!read.add(link)) return;
    readList.add(link);
    if (readList.length > 1500) read.remove(readList.removeAt(0));
    _p?.setStringList('read', readList);
    notifyListeners();
  }

  void toggleSource(String name) {
    if (!disabled.remove(name)) disabled.add(name);
    _p?.setStringList('off', disabled.toList());
    notifyListeners();
  }

  Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
      final m = _p!.getString('mode');
      mode = m == 'light'
          ? ThemeMode.light
          : m == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system;
      fontScale = _p!.getDouble('font') ?? 1.0;
      disabled.addAll(_p!.getStringList('off') ?? const <String>[]);
      final rd = _p!.getStringList('read') ?? const <String>[];
      readList.addAll(rd);
      read.addAll(rd);
      final known = tabList.map((t) => t.$1).toSet();
      final to = _p!.getStringList('tabOrder');
      if (to != null) {
        final o = to.where(known.contains).toList();
        for (final k in tabList.map((t) => t.$1)) {
          if (!o.contains(k)) o.add(k);
        }
        tabOrder = o;
      }
      if (!(_p!.getBool('nowMoved') ?? false)) {
        final o = [...tabOrder]..remove('now');
        final i = o.indexOf('urgent');
        o.insert(i < 0 ? o.length : i, 'now');
        tabOrder = o;
        _p!.setBool('nowMoved', true);
        if (to != null) _p!.setStringList('tabOrder', o);
      }
      hiddenTabs.addAll((_p!.getStringList('tabHidden') ?? const <String>[]).where(known.contains));
      topics.addAll(_p!.getStringList('topics') ?? const <String>[]);
      briefDate = _p!.getString('briefD') ?? '';
      briefText = _p!.getString('briefT') ?? '';
      autoStories = _p!.getBool('autoStories') ?? true;
      pushOn = _p!.getBool('pushOn') ?? false;
      final sv = _p!.getString('stories');
      if (sv != null) {
        try {
          (jsonDecode(sv) as Map<String, dynamic>).forEach((k, v) {
            storyCache[k] = v.toString();
          });
        } catch (_) {}
      }
      for (final h in _p!.getStringList('history') ?? const <String>[]) {
        try {
          history.add(News.fromJson(jsonDecode(h) as Map<String, dynamic>));
        } catch (_) {}
      }
      aiUrl = _p!.getString('aiUrl') ?? '';
      aiModel = _p!.getString('aiModel') ?? 'qwen3.5:9b';
      errors.addAll(_p!.getStringList('errors') ?? const <String>[]);
      final iv = _p!.getString('interest');
      if (iv != null) {
        try {
          (jsonDecode(iv) as Map<String, dynamic>).forEach((k, v) {
            interest[k] = (v as num).toDouble();
          });
        } catch (_) {}
      }
      final off = _p!.getString('offline');
      if (off != null) {
        try {
          (jsonDecode(off) as Map<String, dynamic>).forEach((k, v) {
            offline[k] = Map<String, dynamic>.from(v as Map);
          });
        } catch (_) {}
      }
      for (final s in _p!.getStringList('saved') ?? const <String>[]) {
        try {
          saved.add(News.fromJson(jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
    } catch (_) {}
  }

  void setMode(ThemeMode m) {
    mode = m;
    _p?.setString('mode', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
    notifyListeners();
  }

  void setFont(double v) {
    fontScale = v;
    _p?.setDouble('font', v);
    notifyListeners();
  }

  bool isSaved(String link) => saved.any((n) => n.link == link);

  void toggleSave(News n) {
    final i = saved.indexWhere((s) => s.link == n.link);
    if (i >= 0) {
      saved.removeAt(i);
      if (offline.remove(n.link) != null) _persistOffline();
    } else {
      saved.insert(0, n);
      learn(n, 3);
    }
    _p?.setStringList('saved', saved.map((s) => jsonEncode(s.toJson())).toList());
    notifyListeners();
  }
}

final AppState app = AppState();

// ═════════════════════════ التحليل ═════════════════════════

String _clean(String s) {
  return s
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _txt(XmlElement e, String name) {
  for (final c in e.childElements) {
    if (c.name.qualified == name) return c.innerText;
  }
  return '';
}

String _link(XmlElement e) {
  for (final c in e.childElements) {
    if (c.name.qualified == 'link') {
      final t = c.innerText.trim();
      if (t.isNotEmpty) return t;
      final h = c.getAttribute('href');
      if (h != null && h.isNotEmpty) return h;
    }
  }
  final g = _txt(e, 'guid').trim();
  return g.startsWith('http') ? g : '';
}

String? _img(XmlElement e) {
  for (final c in e.childElements) {
    final n = c.name.qualified;
    if (n == 'media:content' || n == 'media:thumbnail' || n == 'enclosure' || n == 'image') {
      final u = c.getAttribute('url');
      if (u == null || u.isEmpty) continue;
      final t = c.getAttribute('type');
      if (n == 'enclosure' && t != null && !t.startsWith('image')) continue;
      return u;
    }
  }
  final html = _txt(e, 'description') + _txt(e, 'content:encoded');
  final m = RegExp(r'''<img[^>]+src=["']([^"']+)''').firstMatch(html);
  return m?.group(1);
}

const Map<String, int> _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? parseDate(String raw, {bool local = false}) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  DateTime build(int y, int mo, int d, int h, int mi, int sec, String? zone) {
    if (zone != null) {
      var dt = DateTime.utc(y, mo, d, h, mi, sec);
      final m = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(zone);
      if (m != null) {
        final off = Duration(
          hours: int.parse(m.group(2)!),
          minutes: int.parse(m.group(3)!),
        );
        dt = m.group(1) == '-' ? dt.add(off) : dt.subtract(off);
      }
      return dt;
    }
    return local
        ? DateTime(y, mo, d, h, mi, sec).toUtc()
        : DateTime.utc(y, mo, d, h, mi, sec);
  }

  int hour(int h, String? ap) {
    if (ap == null) return h;
    final pm = ap.toLowerCase() == 'pm';
    if (pm && h < 12) return h + 12;
    if (!pm && h == 12) return 0;
    return h;
  }

  String? zoneOf(String? z) {
    if (z == null) return null;
    final u = z.toUpperCase();
    if (u == 'GMT' || u == 'UTC' || u == 'Z') return '+0000';
    return z;
  }

  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(s);
  if (iso != null) {
    return build(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
      int.parse(iso.group(4)!),
      int.parse(iso.group(5)!),
      int.parse(iso.group(6) ?? '0'),
      zoneOf(iso.group(7)),
    );
  }

  final us = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})[,\s]+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?',
  ).firstMatch(s);
  if (us != null) {
    final a = int.parse(us.group(1)!);
    final b = int.parse(us.group(2)!);
    final month = a > 12 ? b : a;
    final day = a > 12 ? a : b;
    return build(
      int.parse(us.group(3)!),
      month,
      day,
      hour(int.parse(us.group(4)!), us.group(7)),
      int.parse(us.group(5)!),
      int.parse(us.group(6) ?? '0'),
      null,
    );
  }

  final tx = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*,?\s+(\d{4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?\s*(GMT|UTC|Z|[+-]\d{4})?',
  ).firstMatch(s);
  if (tx != null) {
    final mo = _months[tx.group(2)!.toLowerCase()];
    if (mo != null) {
      return build(
        int.parse(tx.group(3)!),
        mo,
        int.parse(tx.group(1)!),
        hour(int.parse(tx.group(4)!), tx.group(7)),
        int.parse(tx.group(5)!),
        int.parse(tx.group(6) ?? '0'),
        zoneOf(tx.group(8)),
      );
    }
  }

  return DateTime.tryParse(s)?.toUtc();
}

/// المصادر التي فشل تحميلها في آخر محاولة.
final Set<String> failedSources = {};

Future<List<News>> loadFeed(String id) async {
  final f = feeds[id]!;
  if (app.disabled.contains(f.name)) {
    failedSources.remove(f.name);
    return [];
  }
  for (final u in f.urls) {
    try {
      final r = await http.get(Uri.parse(u), headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
      }).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) continue;
      var bodyText = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
      if (bodyText.startsWith('﻿')) bodyText = bodyText.substring(1);
      final doc = XmlDocument.parse(bodyText);
      var els = doc.findAllElements('item').toList();
      if (els.isEmpty) els = doc.findAllElements('entry').toList();
      final out = <News>[];
      final now = DateTime.now().toUtc();
      var idx = 0;
      for (final e in els) {
        final title = _clean(_txt(e, 'title'));
        final link = _link(e);
        var date = _txt(e, 'pubDate');
        if (date.isEmpty) date = _txt(e, 'published');
        if (date.isEmpty) date = _txt(e, 'updated');
        if (date.isEmpty) date = _txt(e, 'dc:date');
        final order = idx++;
        if (title.isEmpty || link.isEmpty) continue;
        final t = parseDate(date, local: f.local) ??
            now.subtract(Duration(minutes: order));
        final desc = _clean(_txt(e, 'description'));
        out.add(News(title, link, t, _img(e), f.name, f.translate,
            summary: desc.length > 700 ? desc.substring(0, 700) : desc));
      }
      if (out.isNotEmpty) {
        failedSources.remove(f.name);
        return out;
      }
    } catch (_) {}
  }
  failedSources.add(f.name);
  return [];
}

String norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[ً-ْـ]'), '')
    .replaceAll(RegExp(r'[إأآ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// يمنع تكرار الخبر الواحد، ويسجّل على النسخة المحتفظ بها أسماء المصادر
/// الأخرى التي نشرته (لعرض "تغطية ٣ مصادر").
Set<News> dedupe(List<News> items) {
  final out = <News>{};
  final seen = <String>{};
  final sets = <Set<String>>[];
  final kept = <News>[];
  for (final it in items) {
    final lk = it.link.split('?').first;
    if (seen.contains(lk)) continue;
    final tk = norm(it.orig).split(' ').where((w) => w.length > 2).toSet();
    var dupOf = -1;
    for (var i = 0; i < sets.length; i++) {
      final s = sets[i];
      final n = tk.where(s.contains).length;
      final u = tk.length + s.length - n;
      if (u == 0) continue;
      final r = n / u;
      if ((r > 0.55 && n >= 2) || (r > 0.38 && n >= 4)) {
        dupOf = i;
        break;
      }
    }
    if (dupOf >= 0) {
      final k = kept[dupOf];
      if (k.src != it.src) k.others.add(it.src);
      if (!k.related.any((x) => x.link == it.link)) k.related.add(it);
      continue;
    }
    seen.add(lk);
    sets.add(tk);
    kept.add(it);
    out.add(it);
  }
  return out;
}

String coverageText(News n) {
  final c = n.others.length + 1;
  return c == 2 ? 'مصدران' : '${arNum(c)} مصادر';
}

/// أهم الأخبار: الأكثر تغطية من مصادر مختلفة، ثم الأحدث.
List<News> pickTop(List<Group> groups) {
  final all = [for (final g in groups) ...g.items];
  if (all.isEmpty) return [];
  final byCov = [...all]..sort((a, b) {
      final c = b.others.length.compareTo(a.others.length);
      return c != 0
          ? c
          : (b.time ?? DateTime(2000)).compareTo(a.time ?? DateTime(2000));
    });
  final top = byCov.where((n) => n.others.isNotEmpty).take(5).toList();
  for (final n in all) {
    if (top.length >= 5) break;
    if (!top.contains(n)) top.add(n);
  }
  return top;
}

// ═════════════════════════ ذكاء يعمل على الجهاز ═════════════════════════

const Set<String> _stop = {
  'في', 'من', 'علي', 'الي', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'بعد', 'قبل', 'بين', 'خلال',
  'حتي', 'كان', 'كانت', 'يكون', 'لم', 'لن', 'قد', 'كل', 'ثم', 'هو', 'هي', 'هم', 'قال',
  'قالت', 'يوم', 'امس', 'بسبب', 'ضد', 'نحو', 'عند', 'حول', 'عبر', 'منذ', 'لدي', 'بعض',
  'غير', 'فقط', 'جدا', 'عاجل', 'اخبار', 'خبر', 'مصدر', 'ايضا', 'التي', 'الذي', 'الذين',
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'have', 'has', 'was', 'were',
  'will', 'are', 'its', 'not', 'but', 'about', 'after', 'over', 'into', 'than', 'their',
  'they', 'said', 'says', 'new', 'more', 'news', 'what', 'how', 'why', 'who', 'when',
  'could', 'would', 'been', 'his', 'her', 'you', 'your', 'out', 'amid', 'live',
};

/// كلمات الخبر المفيدة (بلا أدوات الربط)، لحساب الاهتمامات واقتراح المواضيع.
Set<String> keywordsOf(String text) {
  final out = <String>{};
  for (var w in norm(text).split(' ')) {
    if (w.startsWith('ال') && w.length > 4) w = w.substring(2);
    if (w.length < 3 || _stop.contains(w)) continue;
    if (RegExp(r'^\d+$').hasMatch(w)) continue;
    out.add(w);
  }
  return out;
}

/// خلاصة من أول جملتين في النص، بلا أي خدمة خارجية.
String quickSummary(List<String> paras) {
  final text = paras.take(3).join(' ').trim();
  if (text.isEmpty) return '';
  final sentences = text.split(RegExp(r'(?<=[.!؟?])\s+'));
  final out = <String>[];
  var len = 0;
  for (final s in sentences) {
    final t = s.trim();
    if (t.length < 25) continue;
    out.add(t);
    len += t.length;
    if (out.length >= 2 || len > 260) break;
  }
  if (out.isEmpty) return text.length > 220 ? '${text.substring(0, 220)}...' : text;
  return out.join(' ');
}

String clip(String s, int n) => s.length > n ? s.substring(0, n) : s;

class AiException implements Exception {
  final String msg;
  AiException(this.msg);
  @override
  String toString() => msg;
}

String _aiBase() {
  var u = app.aiUrl.trim();
  if (u.isEmpty) throw AiException('أدخل عنوان الخادم من الإعدادات أولًا');
  if (!u.startsWith('http')) u = 'http://$u';
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

String _aiModel() => app.aiModel.trim().isEmpty ? 'qwen3.5:9b' : app.aiModel.trim();

String _stripThink(String s) {
  var t = s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  final i = t.indexOf('<think>');
  if (i >= 0) t = t.substring(0, i);
  return t.trimLeft();
}

/// يرسل طلبًا إلى النموذج المحلي (أولاما) ويبث الجواب تدريجيًا:
/// كل عنصر في البث هو النص المتراكم حتى الآن.
Stream<String> askAiStream(String system, String user) async* {
  final base = _aiBase();
  final client = http.Client();
  try {
    final req = http.Request('POST', Uri.parse('$base/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': _aiModel(),
        'stream': true,
        'think': false,
        'options': {'temperature': 0.3, 'num_ctx': 8192},
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      });
    final res = await client.send(req).timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw AiException(res.statusCode == 404
          ? 'النموذج "${_aiModel()}" غير موجود على الخادم'
          : 'رد الخادم غير متوقع (${res.statusCode})');
    }
    var acc = '';
    await for (final line in res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 120))) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> m;
      try {
        m = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final c = ((m['message'] as Map?)?['content'] as String?) ?? '';
      if (c.isNotEmpty) {
        acc += c;
        final t = _stripThink(acc);
        if (t.isNotEmpty) yield t;
      }
      if (m['done'] == true) break;
    }
    if (_stripThink(acc).trim().isEmpty) throw AiException('لم يرجع النموذج جوابًا');
  } on AiException {
    rethrow;
  } on TimeoutException {
    throw AiException('انتهت المهلة، قد يكون النموذج بطيئًا أو الخادم متوقفًا');
  } catch (_) {
    throw AiException('تعذر الاتصال بالخادم، تأكد من العنوان ومن أن أولاما يعمل');
  } finally {
    client.close();
  }
}

/// نسخة تنتظر الجواب كاملًا (للمهام التي تعمل في الخلفية).
Future<String> askAi(String system, String user) async {
  var last = '';
  await for (final t in askAiStream(system, user)) {
    last = t;
  }
  return last.trim();
}

/// اختبار الاتصال: يعيد ok أو رسالة تشرح المشكلة.
Future<String> testAi() async {
  try {
    final base = _aiBase();
    final r = await http.get(Uri.parse('$base/api/tags')).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return 'رد الخادم غير متوقع (${r.statusCode})';
    final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final names = <String>[
      for (final e in (m['models'] as List? ?? const [])) (e as Map)['name'].toString(),
    ];
    final want = _aiModel();
    if (names.contains(want) || names.contains('$want:latest')) return 'ok';
    return names.isEmpty
        ? 'الخادم يعمل لكن لا توجد نماذج عليه'
        : 'الخادم يعمل لكن النموذج غير موجود. المتاح: ${names.join('، ')}';
  } on AiException catch (e) {
    return e.msg;
  } catch (_) {
    return 'تعذر الاتصال بالخادم';
  }
}

const String _sumSys =
    'أنت محرر أخبار عربي. لخّص الخبر بالعربية الفصحى المبسطة في ثلاث إلى خمس نقاط قصيرة، '
    'كل نقطة في سطر يبدأ بشرطة. اعتمد على النص فقط ولا تضف معلومات من عندك.';
const String _askSys =
    'أجب عن سؤال القارئ بالعربية اعتمادًا على نص الخبر فقط. إذا لم تجد الإجابة في النص '
    'فقل بوضوح إنها غير مذكورة فيه. اجعل الجواب قصيرًا ومباشرًا.';
const String _briefSys =
    'أنت مذيع نشرة أخبار. اكتب نشرة موجزة بالعربية من العناوين التالية: جملة افتتاحية واحدة، '
    'ثم نقاط مرتبة بحسب الأهمية يبدأ كل سطر بشرطة، لكل نقطة جملة أو جملتان. '
    'لا تضف أي معلومة غير موجودة في العناوين.';
const String _cmpSys =
    'ستقرأ عناوين وملخصات للخبر نفسه من مصادر مختلفة. اكتب بالعربية ثلاثة أقسام قصيرة: '
    'أولًا ما اتفقت عليه المصادر. ثانيًا الاختلافات في الأرقام أو الوقائع أو النبرة مع ذكر اسم '
    'المصدر. ثالثًا هل تبدو صياغة أحد المصادر مبالغًا فيها. إذا لم تجد اختلافًا فقل ذلك صراحة. '
    'اعتمد على المعطيات المعطاة فقط.';

const String _storySys =
    'اكتب فقرة موجزة بالعربية من جملتين على الأكثر تلخص القصة التالية التي نشرتها عدة مصادر. '
    'اعتمد على العناوين والملخصات فقط ولا تضف أي معلومة من عندك.';

Stream<String> aiSummary(News n, String text) =>
    askAiStream(_sumSys, 'العنوان: ${n.orig}\nالنص:\n${clip(text, 6000)}');

String storyInput(News n) {
  final b = StringBuffer();
  for (final x in [n, ...n.related]) {
    b.writeln('المصدر: ${x.src}');
    b.writeln('العنوان: ${x.orig}');
    if (x.summary.isNotEmpty && x.summary != x.orig) {
      b.writeln('الملخص: ${clip(x.summary, 250)}');
    }
    b.writeln();
  }
  return b.toString();
}

Stream<String> aiCompare(News n) => askAiStream(_cmpSys, storyInput(n));

String briefInput(List<News> items) {
  final b = StringBuffer();
  for (var i = 0; i < items.length; i++) {
    final x = items[i];
    final extra = x.others.isEmpty ? '' : '، ونشره أيضًا ${x.others.join('، ')}';
    b.writeln('${i + 1}. ${x.orig} (${x.src}$extra)');
  }
  return b.toString();
}

Stream<String> aiBrief(List<News> items) => askAiStream(_briefSys, briefInput(items));

Widget actionChip(Pal p, IconData icon, String text, VoidCallback? onTap, {bool on = false}) {
  return tap(
    onTap,
    Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: on ? p.green : p.chip,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: on ? p.onGreen : p.ink),
          const SizedBox(width: 6),
          Text(text, style: ui(14, c: on ? p.onGreen : p.ink)),
        ],
      ),
    ),
    label: text,
  );
}

BoxDecoration sheetDeco(Pal p) => BoxDecoration(
      color: p.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
    );

Widget sheetHandle(Pal p) => Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(3)),
      ),
    );

/// نافذة تعرض نتيجة طلب للنموذج المحلي مع حالة الانتظار والخطأ.
Future<void> showAiSheet(BuildContext context, String title, Stream<String> Function() run,
    {String? initial, ValueChanged<String>? onDone}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AiSheet(title: title, run: run, initial: initial, onDone: onDone),
  );
}

class AiSheet extends StatefulWidget {
  final String title;
  final Stream<String> Function() run;
  final String? initial;
  final ValueChanged<String>? onDone;
  const AiSheet({super.key, required this.title, required this.run, this.initial, this.onDone});
  @override
  State<AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<AiSheet> {
  String? text;
  String? error;
  bool busy = false;
  bool streaming = false;
  bool saved = false;
  StreamSubscription<String>? sub;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      text = widget.initial;
      saved = true;
    } else {
      go();
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  /// يشغّل الطلب ويعرض الجواب كلمة بعد كلمة.
  void go() {
    sub?.cancel();
    setState(() {
      busy = true;
      streaming = true;
      saved = false;
      error = null;
      text = null;
    });
    var last = '';
    var failed = false;
    sub = widget.run().listen(
      (t) {
        last = t;
        if (!mounted) return;
        setState(() {
          text = t;
          busy = false;
        });
      },
      onError: (Object e) {
        failed = true;
        if (!mounted) return;
        setState(() {
          error = e.toString();
          busy = false;
          streaming = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          busy = false;
          streaming = false;
        });
        if (!failed && last.trim().isNotEmpty) widget.onDone?.call(last.trim());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.8),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: sheetDeco(p),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHandle(p),
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: p.green),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title, style: ui(18, w: FontWeight.w800, c: p.ink))),
              if (text != null && !streaming)
                circleBtn(p, Icons.copy_rounded, 'نسخ', () {
                  Clipboard.setData(ClipboardData(text: text!));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('تم النسخ')));
                }),
            ],
          ),
          const SizedBox(height: 12),
          if (busy && text == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: p.green),
                    const SizedBox(height: 14),
                    Text('النموذج يفكر على جهازك...',
                        style: ui(14, w: FontWeight.w500, c: p.muted)),
                  ],
                ),
              ),
            ),
          if (text != null)
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  text!,
                  textDirection: dirOf(text!),
                  style: body(18, c: p.ink, h: 1.9),
                ),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: ui(15, w: FontWeight.w500, c: p.ink, h: 1.8)),
            const SizedBox(height: 12),
            actionChip(p, Icons.refresh_rounded, 'إعادة المحاولة', go),
          ],
          if (!streaming && error == null && text != null) ...[
            const SizedBox(height: 10),
            Text(
              saved
                  ? 'نسخة محفوظة لليوم.'
                  : 'أُنشئ بنموذج على جهازك وقد يخطئ، راجع الخبر الأصلي.',
              style: ui(12, w: FontWeight.w500, c: p.muted),
            ),
            if (saved) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: actionChip(p, Icons.refresh_rounded, 'تحديث', go),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

Future<void> showAskSheet(BuildContext context, News n, String source) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AskSheet(news: n, source: source),
  );
}

/// محادثة قصيرة عن خبر واحد: الجواب من نص الخبر فقط.
class AskSheet extends StatefulWidget {
  final News news;
  final String source;
  const AskSheet({super.key, required this.news, required this.source});
  @override
  State<AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<AskSheet> {
  final TextEditingController ctl = TextEditingController();
  final List<(String, String?)> log = [];
  bool busy = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> send([String? preset]) async {
    final q = (preset ?? ctl.text).trim();
    if (q.isEmpty || busy) return;
    ctl.clear();
    setState(() {
      log.add((q, null));
      busy = true;
    });
    final idx = log.length - 1;
    try {
      await for (final t in askAiStream(
        _askSys,
        'العنوان: ${widget.news.orig}\nنص الخبر:\n${clip(widget.source, 6000)}\n\nسؤال القارئ: $q',
      )) {
        if (!mounted) return;
        setState(() => log[idx] = (q, t));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => log[idx] = (q, e.toString()));
    }
    if (!mounted) return;
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: mq.size.height * 0.7,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: sheetDeco(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHandle(p),
            Text('اسأل عن الخبر', style: ui(18, w: FontWeight.w800, c: p.ink)),
            const SizedBox(height: 10),
            Expanded(
              child: log.isEmpty
                  ? ListView(
                      children: [
                        Text('يجيب من نص الخبر فقط. جرّب أحد الأسئلة:',
                            style: ui(14, w: FontWeight.w500, c: p.muted, h: 1.7)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final q in const [
                              'ما سبب هذا الخبر؟',
                              'من الأطراف المذكورة؟',
                              'ما الذي يعنيه ذلك للقارئ؟',
                            ])
                              actionChip(p, Icons.help_outline_rounded, q, () => send(q)),
                          ],
                        ),
                      ],
                    )
                  : ListView(
                      children: [
                        for (final e in log) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: p.chip,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(e.$1, style: ui(15, c: p.ink, h: 1.7)),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: cardDeco(p, 16),
                            child: e.$2 == null
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: p.green),
                                  )
                                : SelectableText(
                                    e.$2!,
                                    textDirection: dirOf(e.$2!),
                                    style: body(17, c: p.ink, h: 1.9),
                                  ),
                          ),
                        ],
                      ],
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctl,
                    onSubmitted: (_) => send(),
                    textInputAction: TextInputAction.send,
                    style: ui(15, w: FontWeight.w500, c: p.ink),
                    cursorColor: p.green,
                    decoration: InputDecoration(
                      hintText: 'اكتب سؤالك',
                      hintStyle: ui(15, w: FontWeight.w500, c: p.muted),
                      filled: true,
                      fillColor: p.chip,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                circleBtn(p, Icons.send_rounded, 'إرسال', busy ? null : () => send(),
                    bg: p.green, fg: p.onGreen),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void showShareCard(BuildContext context, News n) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ShareCardSheet(news: n),
  );
}

/// بطاقة جميلة للخبر تُشارَك كصورة.
class ShareCardSheet extends StatefulWidget {
  final News news;
  const ShareCardSheet({super.key, required this.news});
  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  final GlobalKey boundary = GlobalKey();
  bool busy = false;

  Future<void> doShare() async {
    final n = widget.news;
    setState(() => busy = true);
    try {
      final b = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final bd = await img.toByteData(format: ImageByteFormat.png);
      final bytes = bd!.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(
        text: n.link,
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: ['akhbarak.png'],
      ));
    } catch (_) {
      try {
        await SharePlus.instance.share(ShareParams(text: '${n.title}\n${n.link}'));
      } catch (_) {}
    }
    if (mounted) setState(() => busy = false);
  }

  Widget card(News n) {
    const p = Pal.light;
    return RepaintBoundary(
      key: boundary,
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5EEE3), Color(0xFFEADFCF)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/logo.png', height: 34),
                const SizedBox(width: 8),
                Text('أخبارك', style: ui(18, w: FontWeight.w800, c: p.ink)),
              ],
            ),
            const SizedBox(height: 14),
            if (n.img != null) ...[
              netImg(p, n.img, n.link, 304, 160, 16),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: p.green, borderRadius: BorderRadius.circular(10)),
                  child: Text(n.src, style: ui(12.5, c: p.onGreen)),
                ),
                const SizedBox(width: 8),
                Text(ago(n.time), style: ui(12.5, w: FontWeight.w500, c: p.muted)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              n.title,
              textDirection: dirOf(n.title),
              style: ui(21, w: FontWeight.w800, c: p.ink, h: 1.65),
            ),
            const SizedBox(height: 14),
            Text('اقرأ التفاصيل في تطبيق أخبارك',
                style: ui(12, w: FontWeight.w500, c: p.muted)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: sheetDeco(p),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sheetHandle(p),
          Flexible(child: SingleChildScrollView(child: Center(child: card(widget.news)))),
          const SizedBox(height: 14),
          actionChip(p, Icons.share_rounded, busy ? 'جاري التجهيز...' : 'مشاركة الصورة',
              busy ? null : doShare,
              on: true),
        ],
      ),
    );
  }
}

/// ضغطة مطوّلة على أي خبر: خلاصته قبل أن تفتحه.
void showQuick(BuildContext context, News n) {
  final raw = n.summary;
  final s = raw.length < n.orig.length + 20 ? '' : quickSummary([raw]);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final p = Pal.of(ctx);
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: sheetDeco(p),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHandle(p),
            Text(n.title,
                textDirection: dirOf(n.title),
                style: ui(17, w: FontWeight.w800, c: p.ink, h: 1.6)),
            const SizedBox(height: 10),
            Text(
              s.isEmpty ? 'لا توجد خلاصة لهذا الخبر، افتحه لقراءته.' : s,
              textDirection: s.isEmpty ? TextDirection.rtl : dirOf(s),
              style: body(17, c: p.ink, h: 1.9),
            ),
            const SizedBox(height: 14),
            actionChip(p, Icons.open_in_new_rounded, 'فتح الخبر', () {
              Navigator.of(ctx).pop();
              openArticle(context, n);
            }),
          ],
        ),
      );
    },
  );
}

// ═════════════════════════ استخراج نص الخبر ═════════════════════════

final RegExp _noiseStart = RegExp(
  r'^(اقرأ أيضا|اقرأ ايضا|اقرأ أيضًا|للمزيد|شاهد أيضا|شاهد أيضًا|إعلان|Read more|Related|Advertisement|Support the Guardian|Sign up|Subscribe)',
  caseSensitive: false,
);

class Extracted {
  final List<String> paras;
  final String? image;
  Extracted(this.paras, this.image);
}

int _pScore(dom.Element root) {
  var s = 0;
  for (final p in root.querySelectorAll('p')) {
    final t = p.text.trim();
    if (t.length > 40) s += t.length;
  }
  return s;
}

Extracted extractArticle(String bodyHtml) {
  final doc = html_parser.parse(bodyHtml);
  final img = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
      doc.querySelector('meta[name="twitter:image"]')?.attributes['content'];

  for (final sel in const [
    'script', 'style', 'noscript', 'nav', 'footer', 'aside', 'form', 'iframe', 'svg', 'button'
  ]) {
    for (final e in doc.querySelectorAll(sel)) {
      e.remove();
    }
  }

  const bodySel =
      '[itemprop="articleBody"], #articleBody, .articleBody, .article-body, .story-body, '
      '.entry-content, .post-content, .article-content, .details-text, #article-body, '
      '.article__body, .news-content, .newsContent, .article-text';

  dom.Element? root;
  for (final c in doc.querySelectorAll(bodySel)) {
    if (_pScore(c) >= 150) {
      root = c;
      break;
    }
  }
  if (root == null) {
    var best = 0;
    for (final a in doc.querySelectorAll('article')) {
      final s = _pScore(a);
      if (s > best) {
        best = s;
        root = a;
      }
    }
    if (best < 150) root = null;
  }
  root ??= doc.querySelector('main');
  root ??= doc.body;
  if (root == null) return Extracted([], img);

  final out = <String>[];
  final seen = <String>{};
  for (final e in root.querySelectorAll('p')) {
    final t = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length < 45) continue;
    if (_noiseStart.hasMatch(t)) continue;
    if (!seen.add(t)) continue;
    out.add(t);
  }
  return Extracted(out, img);
}

// ═════════════════════════ عناصر مشتركة ═════════════════════════

Widget tap(VoidCallback? onTap, Widget child, {String? label, VoidCallback? onLong}) => Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLong,
        child: child,
      ),
    );

Widget circleBtn(Pal p, IconData icon, String label, VoidCallback? onTap,
    {Color? bg, Color? fg}) {
  return tap(
    onTap,
    Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg ?? p.chip, shape: BoxShape.circle),
      child: Icon(icon, size: 22, color: fg ?? p.ink),
    ),
    label: label,
  );
}

// الصور زخرفية للقارئ الصوتي، فلا تُقرأ
Widget netImg(Pal p, String? url, String key, double w, double h, double r) =>
    ExcludeSemantics(child: _netImg(p, url, key, w, h, r));

Widget _netImg(Pal p, String? url, String key, double w, double h, double r) {
  final base = p.thumbs[key.hashCode.abs() % p.thumbs.length];
  final ph = Container(
    width: w,
    height: h,
    color: base,
    alignment: Alignment.center,
    child: Icon(Icons.image_outlined, color: p.muted, size: 30),
  );
  return ClipRRect(
    borderRadius: BorderRadius.circular(r),
    child: url == null
        ? ph
        : (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)
            // على الجوال: تُخزَّن الصور في الجهاز فلا تُحمَّل مرتين
            ? CachedNetworkImage(
                imageUrl: url,
                width: w,
                height: h,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, __) => ph,
                errorWidget: (_, __, ___) => ph,
              )
            : Image.network(
                url,
                width: w,
                height: h,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ph,
                loadingBuilder: (c, child, prog) => prog == null ? child : ph,
              ),
  );
}

void openArticle(BuildContext context, News n) {
  if (!app.isRead(n.link)) app.learn(n, 1);
  app.addHistory(n);
  app.markRead(n.link);
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => ArticlePage(news: n),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  ));
}

Widget translateChip(Pal p, News n) {
  final on = n.translated;
  return tap(
    n.busy ? null : n.toggleTitle,
    Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: on ? p.green : p.chip,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          n.busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.green),
                )
              : Icon(Icons.translate_rounded, size: 16, color: on ? p.onGreen : p.ink),
          const SizedBox(width: 6),
          Text(on ? 'الأصل' : 'ترجمة',
              style: ui(13, c: on ? p.onGreen : p.ink)),
        ],
      ),
    ),
    label: on ? 'عرض النص الأصلي' : 'ترجمة إلى العربية',
  );
}

Widget metaRow(Pal p, News n) {
  return Row(
    children: [
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: n.src, style: ui(12.5, w: FontWeight.w800, c: p.green)),
            TextSpan(text: '  ·  ${ago(n.time)}', style: ui(12.5, w: FontWeight.w500, c: p.muted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (n.foreign) translateChip(p, n),
    ],
  );
}

Widget coverPill(Pal p, News n) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.layers_rounded, size: 13, color: p.green),
        const SizedBox(width: 4),
        Text('تغطية ${coverageText(n)}', style: ui(12, w: FontWeight.w700, c: p.ink)),
      ],
    ),
  );
}

BoxDecoration cardDeco(Pal p, double r) => BoxDecoration(
      color: p.card,
      border: Border.all(color: p.border),
      borderRadius: BorderRadius.circular(r),
    );

/// بطاقة خبر مصغرة
class NewsTile extends StatelessWidget {
  final News news;
  const NewsTile({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: news,
      builder: (context, _) {
        final n = news;
        return tap(
          () => openArticle(context, n),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: cardDeco(p, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                netImg(p, n.img, n.link, 88, 88, 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        textDirection: dirOf(n.title),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: ui(16, c: app.isRead(n.link) ? p.muted : p.ink, h: 1.6),
                      ),
                      const SizedBox(height: 6),
                      metaRow(p, n),
                      if (n.others.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        coverPill(p, n),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          onLong: () => showQuick(context, n),
        );
      },
    );
  }
}

/// بطاقة الخبر الأحدث (كبيرة)
class HeroTile extends StatelessWidget {
  final News news;
  const HeroTile({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: news,
      builder: (context, _) {
        final n = news;
        return tap(
          () => openArticle(context, n),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: cardDeco(p, 22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    netImg(p, n.img, n.link, double.infinity, 168, 0),
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('الأحدث', style: ui(12, c: p.onGreen)),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        textDirection: dirOf(n.title),
                        style: ui(19, w: FontWeight.w800,
                            c: app.isRead(n.link) ? p.muted : p.ink, h: 1.6),
                      ),
                      const SizedBox(height: 8),
                      metaRow(p, n),
                      if (n.others.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        coverPill(p, n),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// بطاقة خبر عاجل
class UrgentTile extends StatelessWidget {
  final News news;
  const UrgentTile({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: news,
      builder: (context, _) {
        final n = news;
        final fresh = n.time != null && DateTime.now().difference(n.time!).inMinutes < 60;
        final label = catLabels[urgentCategory(n.orig)]!;
        return tap(
          () => openArticle(context, n),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(p, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: fresh ? p.tagBg : p.chip,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        fresh ? 'عاجل · $label' : label,
                        style: ui(12.5, w: FontWeight.w800, c: fresh ? p.tagText : p.muted),
                      ),
                    ),
                    const Spacer(),
                    Text(ago(n.time), style: ui(12.5, w: FontWeight.w500, c: p.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  n.title,
                  textDirection: dirOf(n.title),
                  style: ui(17, w: FontWeight.w800,
                      c: app.isRead(n.link) ? p.muted : p.ink, h: 1.65),
                ),
                if (n.others.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: coverPill(p, n),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(n.src, style: ui(12.5, w: FontWeight.w800, c: p.green)),
                    ),
                    if (n.foreign) translateChip(p, n),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// هياكل رمادية متحركة أثناء تحميل الأخبار
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key});
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(6)),
        );
    Widget tile() => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: cardDeco(p, 20),
          child: Row(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(double.infinity, 14),
                    const SizedBox(height: 10),
                    bar(double.infinity, 14),
                    const SizedBox(height: 10),
                    bar(120, 12),
                  ],
                ),
              ),
            ],
          ),
        );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_c),
      child: Column(
        children: [
          Container(
            height: 230,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(22)),
          ),
          tile(),
          tile(),
          tile(),
          tile(),
        ],
      ),
    );
  }
}

/// شريط أهم الأخبار: يُسحب جانبيًا
class TopCarousel extends StatefulWidget {
  final List<News> items;
  const TopCarousel({super.key, required this.items});
  @override
  State<TopCarousel> createState() => _TopCarouselState();
}

class _TopCarouselState extends State<TopCarousel> {
  final PageController _pc = PageController(viewportFraction: 0.92);
  int page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Widget _slide(BuildContext context, Pal p, News news) {
    return ListenableBuilder(
      listenable: news,
      builder: (context, _) {
        final n = news;
        return tap(
          () => openArticle(context, n),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                netImg(p, n.img, n.link, double.infinity, double.infinity, 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xE6000000)],
                      stops: [0.25, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (n.others.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x40FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('تغطية ${coverageText(n)}',
                              style: ui(12, w: FontWeight.w700, c: Colors.white)),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        n.title,
                        textDirection: dirOf(n.title),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: ui(18, w: FontWeight.w800, c: Colors.white, h: 1.55),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${n.src}  ·  ${ago(n.time)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ui(12.5, w: FontWeight.w500, c: const Color(0xFFE8E0D2)),
                            ),
                          ),
                          if (n.foreign) translateChip(p, n),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          label: n.title,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = widget.items;
    return Column(
      children: [
        SizedBox(
          height: 232,
          child: PageView.builder(
            controller: _pc,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _slide(context, p, items[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == page ? p.green : p.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ═════════════════════════ التطبيق ═════════════════════════

class AkhbarApp extends StatelessWidget {
  const AkhbarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'أخبارك',
        themeMode: app.mode,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Pal.light.bg,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Pal.dark.bg,
        ),
        builder: (context, child) {
          // يحترم حجم خط النظام مع سقف يمنع كسر التصميم
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4),
            ),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          );
        },
        home: const SplashGate(),
      ),
    );
  }
}

/// شاشة البداية: الشعار يظهر بحركة ناعمة بينما تُحمَّل الأخبار خلفها.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();
  bool fading = false;
  bool gone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => fading = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const HomePage(),
        if (!gone)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: fading,
              child: AnimatedOpacity(
                opacity: fading ? 0 : 1,
                duration: const Duration(milliseconds: 450),
                onEnd: () {
                  if (fading && mounted) setState(() => gone = true);
                },
                child: Material(
                  color: p.bg,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) {
                        final t = Curves.easeOutBack.transform(_c.value);
                        final o = (_c.value * 1.6).clamp(0.0, 1.0).toDouble();
                        return Opacity(
                          opacity: o,
                          child: Transform.scale(
                            scale: 0.7 + 0.3 * t,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset('assets/logo.png', height: 120),
                                const SizedBox(height: 18),
                                Text('أخبارك',
                                    style: ui(34, w: FontWeight.w800, c: p.ink, h: 1.2)),
                                const SizedBox(height: 6),
                                Text('كل الأخبار في مكان واحد',
                                    style: ui(15, w: FontWeight.w500, c: p.muted)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int section = 0; // 0 أخبار، 1 محفوظات، 2 بحث، 3 إعدادات
  String cur = app.visibleTabs.first;
  String urgentFilter = 'all';
  String query = '';
  String topicFilter = 'all';
  bool topicsLoading = false;
  final Map<String, List<Group>> data = {};
  final Map<String, int> tokens = {};
  final Set<String> loadingTabs = {};
  final Map<String, DateTime> updatedAt = {};
  final Map<String, List<String>> failedBy = {};
  final Set<String> offlineTabs = {};
  final TextEditingController searchCtl = TextEditingController();
  final TextEditingController topicCtl = TextEditingController();
  late final TextEditingController aiUrlCtl = TextEditingController(text: app.aiUrl);
  late final TextEditingController aiModelCtl = TextEditingController(text: app.aiModel);
  String? aiTest;
  bool unreadOnly = false;
  String searchScope = 'all';
  bool aiWorking = false;
  String? ensured;
  List<News>? nowCache;
  int nowSig = -1;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // آخر أخبار محفوظة تظهر فورًا، ثم تُحدَّث في الخلفية
    for (final t in views.keys) {
      final c = app.readCache(t);
      if (c != null && c.any((g) => g.items.isNotEmpty)) data[t] = c;
    }
    final first = cur;
    if (first == 'topics' || first == 'now') {
      loadTopicSources();
    } else {
      load(first).then((_) {
        if (first != 'urgent') load('urgent');
      });
    }
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final a = updatedAt[cur];
      if (a == null || now.difference(a).inMinutes >= (cur == 'urgent' ? 2 : 5)) {
        load(cur);
      }
      final u = updatedAt['urgent'];
      if (cur != 'urgent' && (u == null || now.difference(u).inMinutes >= 4)) {
        load('urgent');
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    searchCtl.dispose();
    topicCtl.dispose();
    aiUrlCtl.dispose();
    aiModelCtl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load(cur);
  }

  /// أسماء المصادر المفعّلة في تاب معين.
  List<String> enabledNames(String tab) => {
        for (final g in views[tab]!)
          for (final id in g.feedIds)
            if (!app.disabled.contains(feeds[id]!.name)) feeds[id]!.name,
      }.toList();

  /// تاب "مواضيعي" يبحث في أخبار كل التابات، فنحمّل ما لم يُحمَّل منها.
  Future<void> loadTopicSources({bool force = false}) async {
    if (topicsLoading) return;
    setState(() => topicsLoading = true);
    for (final t in views.keys) {
      if (!mounted) return;
      final u = updatedAt[t];
      if (force || u == null || DateTime.now().difference(u).inMinutes >= 10) {
        await load(t);
      }
    }
    if (mounted) setState(() => topicsLoading = false);
    if (cur == 'now') ensureAi();
  }

  Future<void> load(String tab) async {
    if (!views.containsKey(tab)) return;
    final my = (tokens[tab] ?? 0) + 1;
    tokens[tab] = my;
    if (mounted) setState(() => loadingTabs.add(tab));
    final groups = <Group>[];
    final now = DateTime.now();
    for (final g in views[tab]!) {
      final res = await Future.wait(g.feedIds.map(loadFeed));
      if (tokens[tab] != my) return;
      var items = <News>[];
      for (final n in res.expand((e) => e)) {
        var t = n.time;
        if (t == null) continue;
        if (t.isAfter(now)) {
          if (t.difference(now) > const Duration(hours: 6)) continue;
          t = now;
          n.time = t;
        }
        items.add(n);
      }
      if (g.pattern != null) {
        final re = RegExp(g.pattern!, caseSensitive: false);
        items = items.where((i) => re.hasMatch(i.orig)).toList();
      }
      if (g.urgent) {
        final lim = now.subtract(const Duration(hours: 24));
        items = items
            .where((i) => i.time!.isAfter(lim) && urgentRe.hasMatch(i.orig))
            .toList();
      }
      items.sort((a, b) => b.time!.compareTo(a.time!));
      groups.add(Group(g.label, items.take(g.feedIds.length > 2 ? 80 : 40).toList()));
    }
    final keep = dedupe([for (final g in groups) ...g.items]);
    for (final g in groups) {
      final filtered = g.items.where(keep.contains).toList();
      g.items
        ..clear()
        ..addAll(filtered.take(g.label != null ? 12 : 50));
    }
    if (!mounted || tokens[tab] != my) return;
    final names = enabledNames(tab);
    final failed = names.where(failedSources.contains).toSet().toList();
    final total = groups.fold<int>(0, (s, g) => s + g.items.length);
    final prev = data[tab];
    final hadOld = prev != null && prev.any((g) => g.items.isNotEmpty);
    if (total == 0 && hadOld && names.isNotEmpty && failed.length == names.toSet().length) {
      // لا يوجد اتصال: نُبقي آخر أخبار محفوظة ونُعلم المستخدم
      setState(() {
        failedBy[tab] = failed;
        offlineTabs.add(tab);
        loadingTabs.remove(tab);
      });
      return;
    }
    setState(() {
      data[tab] = groups;
      failedBy[tab] = failed;
      offlineTabs.remove(tab);
      loadingTabs.remove(tab);
      updatedAt[tab] = DateTime.now();
    });
    if (total > 0) app.saveCache(tab, groups);
  }

  void setTab(String t) {
    setState(() => cur = t);
    if (t == 'topics' || t == 'now') {
      loadTopicSources();
    } else if (updatedAt[t] == null && !loadingTabs.contains(t)) {
      load(t);
    }
  }

  void toggleTabVisible(String k) {
    app.toggleTab(k);
    if (!app.visibleTabs.contains(cur)) setTab(app.visibleTabs.first);
  }

  /// تشغيل أو إيقاف مصدر ثم إعادة تحميل الأخبار.
  void toggleSource(String name) {
    app.toggleSource(name);
    setState(() {
      data.clear();
      updatedAt.clear();
      offlineTabs.clear();
    });
    if (cur == 'topics' || cur == 'now') {
      loadTopicSources(force: true);
    } else {
      load(cur);
      if (cur != 'urgent') load('urgent');
    }
  }

  List<News> allLoaded() {
    final seen = <String>{};
    final out = <News>[];
    for (final gs in data.values) {
      for (final g in gs) {
        for (final n in g.items) {
          if (seen.add(n.link)) out.add(n);
        }
      }
    }
    out.sort((a, b) => (b.time ?? DateTime(2000)).compareTo(a.time ?? DateTime(2000)));
    return out;
  }

  // ───────────── البناء ─────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = Pal.of(context);
        final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        header(p),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey(section),
                              child: sectionBody(p),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!keyboard)
                      Positioned(left: 14, right: 14, bottom: 14, child: navBar(p)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget header(Pal p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          Image.asset('assets/logo.png', height: 54),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أخبارك', style: ui(26, w: FontWeight.w800, c: p.ink, h: 1.2)),
              Text(dateText(), style: ui(13, w: FontWeight.w500, c: p.muted)),
            ],
          ),
          const Spacer(),
          circleBtn(p, Icons.search_rounded, 'بحث', () => setState(() => section = 2)),
          const SizedBox(width: 8),
          circleBtn(p, Icons.tune_rounded, 'الإعدادات', () => setState(() => section = 3)),
        ],
      ),
    );
  }

  Widget navBar(Pal p) {
    const items = <(IconData, String)>[
      (Icons.home_rounded, 'الرئيسية'),
      (Icons.bookmark_rounded, 'المحفوظات'),
      (Icons.search_rounded, 'البحث'),
      (Icons.tune_rounded, 'الإعدادات'),
    ];
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.nav,
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            tap(
              () => setState(() => section = i),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: section == i ? p.navOn : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(items[i].$1, size: 22, color: section == i ? p.navText : p.navOff),
                    Text(items[i].$2,
                        style: ui(12, c: section == i ? p.navText : p.navOff)),
                  ],
                ),
              ),
              label: items[i].$2,
            ),
        ],
      ),
    );
  }

  Widget sectionBody(Pal p) {
    switch (section) {
      case 1:
        return savedBody(p);
      case 2:
        return searchBody(p);
      case 3:
        return settingsBody(p);
      default:
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: swipeTab,
          child: cur == 'topics'
              ? topicsBody(p)
              : cur == 'now'
                  ? nowBody(p)
                  : newsBody(p),
        );
    }
  }

  // ───────────── قسم الأخبار ─────────────

  /// تمرير الإصبع يمينًا يعرض التاب التالي ويسارًا السابق (الاتجاه من اليمين).
  void swipeTab(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 350) return;
    final keys = app.visibleTabs;
    final i = keys.indexOf(cur);
    if (i < 0) return;
    final j = v > 0 ? i + 1 : i - 1;
    if (j >= 0 && j < keys.length) setTab(keys[j]);
  }

  Widget tabChip(Pal p, String k, {required bool fit}) => Builder(builder: (ctx) {
        // التاب المحدد يتمرر إلى منتصف الشريط
        if (cur == k && ensured != k) {
          ensured = k;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) {
              Scrollable.ensureVisible(ctx,
                  alignment: 0.5, duration: const Duration(milliseconds: 250));
            }
          });
        }
        return _tabChip(p, k, fit: fit);
      });

  Widget _tabChip(Pal p, String k, {required bool fit}) {
    final on = cur == k;
    final isUrgent = k == 'urgent';
    final fg = on ? (isUrgent ? p.onRed : p.tabOnText) : p.ink;
    final label = Text(tabLabel(k), maxLines: 1, style: ui(15, w: FontWeight.w800, c: fg));
    return tap(
      () => setTab(k),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        padding: fit ? const EdgeInsets.symmetric(horizontal: 18) : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? (isUrgent ? p.red : p.tabOn) : p.chip,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUrgent && !on) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: p.red, shape: BoxShape.circle),
              ),
              const SizedBox(width: 3),
            ],
            if (fit)
              label
            else
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: label)),
          ],
        ),
      ),
      label: tabLabel(k),
    );
  }

  Widget tabsRow(Pal p) {
    final keys = app.visibleTabs;
    if (keys.length > 5) {
      // تابات كثيرة: شريط يُسحب جانبيًا
      return SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: tabChip(p, k, fit: true),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          for (final k in keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: tabChip(p, k, fit: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget? tickerBar(Pal p) {
    if (cur == 'urgent') return null;
    final g = data['urgent'];
    if (g == null || g.isEmpty || g.first.items.isEmpty) return null;
    final items = g.first.items;
    final n = items.firstWhere((i) => !i.foreign, orElse: () => items.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: tap(
        () => openArticle(context, n),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.red, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: p.onRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('عاجل', style: ui(13, w: FontWeight.w800, c: p.red)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  n.title,
                  textDirection: dirOf(n.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ui(14, c: p.onRed),
                ),
              ),
            ],
          ),
        ),
        label: 'آخر خبر عاجل',
      ),
    );
  }

  Widget urgentFilters(Pal p) {
    final keys = ['all', ...catLabels.keys];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          for (final k in keys)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: tap(
                () => setState(() => urgentFilter = k),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: urgentFilter == k ? p.tabOn : p.chip,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    k == 'all' ? 'الكل' : catLabels[k]!,
                    style: ui(14, c: urgentFilter == k ? p.tabOnText : p.ink),
                  ),
                ),
                label: k == 'all' ? 'الكل' : catLabels[k]!,
              ),
            ),
        ],
      ),
    );
  }

  Widget stateBox(Pal p, String text, {bool spinner = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
        child: Column(
          children: [
            if (spinner) ...[
              Image.asset('assets/logo.png', height: 96),
              const SizedBox(height: 18),
              CircularProgressIndicator(color: p.green),
              const SizedBox(height: 16),
            ],
            Text(text,
                textAlign: TextAlign.center,
                style: ui(16, w: FontWeight.w500, c: p.muted, h: 1.7)),
          ],
        ),
      );

  Widget sectionTitle(Pal p, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 20,
              decoration: BoxDecoration(color: p.green, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 8),
            Semantics(header: true, child: Text(text, style: ui(18, w: FontWeight.w800, c: p.ink))),
          ],
        ),
      );

  Widget readBar(Pal p, List<Group> groups) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            actionChip(p, Icons.filter_list_rounded, 'غير المقروء فقط',
                () => setState(() => unreadOnly = !unreadOnly),
                on: unreadOnly),
            actionChip(p, Icons.done_all_rounded, 'تمييز الكل كمقروء',
                () => app.markAllRead([for (final g in groups) for (final n in g.items) n.link])),
          ],
        ),
      );

  Widget newsBody(Pal p) {
    final groups = data[cur];
    final tk = tickerBar(p);
    final nb = noticeBar(p);
    final children = <Widget>[];
    if (groups == null) {
      children.add(const SkeletonList());
    } else {
      // العالمية تحافظ على ترتيبها (أمريكا أولًا)، وعاجل بقائمة خاصة.
      children.add(readBar(p, groups));
      final shown = unreadOnly
          ? [
              for (final g in groups)
                Group(g.label, g.items.where((i) => !app.isRead(i.link)).toList()),
            ]
          : groups;
      final top = (cur == 'world' || cur == 'urgent') ? <News>[] : pickTop(shown);
      if (top.isNotEmpty) {
        children.add(TopCarousel(
          key: ValueKey('$cur-${updatedAt[cur]?.millisecondsSinceEpoch}'),
          items: top,
        ));
      }
      var heroUsed = cur != 'world';
      var count = top.length;
      for (final g in shown) {
        var items = cur == 'urgent' && urgentFilter != 'all'
            ? g.items.where((i) => urgentCategory(i.orig) == urgentFilter).toList()
            : g.items.toList();
        if (top.isNotEmpty) items = items.where((i) => !top.contains(i)).toList();
        if (items.isEmpty) continue;
        if (g.label != null) children.add(sectionTitle(p, g.label!));
        for (final n in items) {
          count++;
          if (cur == 'urgent') {
            children.add(UrgentTile(news: n));
          } else if (!heroUsed) {
            heroUsed = true;
            children.add(HeroTile(news: n));
          } else {
            children.add(NewsTile(news: n));
          }
        }
      }
      if (count == 0) {
        children.add(stateBox(
          p,
          unreadOnly
              ? 'لا توجد أخبار غير مقروءة.'
              : cur == 'urgent'
              ? 'لا توجد أخبار عاجلة الآن'
              : 'تعذر تحميل الأخبار، تأكد من الاتصال ثم اسحب للتحديث',
        ));
      }
    }
    return Column(
      children: [
        tabsRow(p),
        if (tk != null) tk,
        if (nb != null) nb,
        if (cur == 'urgent')
          Padding(padding: const EdgeInsets.only(bottom: 10), child: urgentFilters(p)),
        if (loadingTabs.contains(cur))
          LinearProgressIndicator(
            minHeight: 2,
            color: p.green,
            backgroundColor: p.chip,
          ),
        Expanded(
          child: RefreshIndicator(
            color: p.green,
            onRefresh: () => load(cur),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  /// شريط تنبيه: انقطاع الاتصال أو تعذر تحميل بعض المصادر، مع إعادة المحاولة.
  Widget? noticeBar(Pal p) {
    if (loadingTabs.contains(cur)) return null;
    final f = failedBy[cur] ?? const <String>[];
    if (f.isEmpty) return null;
    final off = offlineTabs.contains(cur);
    final text = off ? 'تعذر الاتصال، تُعرض آخر أخبار محفوظة' : 'تعذر تحميل: ${f.join('، ')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: p.chip,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: p.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(text, style: ui(13, w: FontWeight.w500, c: p.ink, h: 1.5)),
              ),
            ),
            tap(
              () => load(cur),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.tabOn,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text('إعادة المحاولة', style: ui(13, w: FontWeight.w700, c: p.tabOnText)),
              ),
              label: 'إعادة المحاولة',
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── الآن: أهم ما يحدث واختيارات لك ─────────────

  /// كل الأخبار المحمّلة مرتبة بلا تكرار (تُحفظ نتيجتها حتى تتغير البيانات).
  List<News> nowUnique() {
    var sig = data.length;
    for (final d in updatedAt.values) {
      sig = (sig * 31 + d.millisecondsSinceEpoch) & 0x3fffffff;
    }
    if (nowCache != null && sig == nowSig) return nowCache!;
    nowSig = sig;
    nowCache = dedupe(allLoaded()).toList();
    return nowCache!;
  }

  List<Widget> suggestionWidgets(Pal p) {
    final cnt = <String, int>{};
    final srcs = <String, Set<String>>{};
    for (final n in nowUnique()) {
      for (final k in keywordsOf(n.orig)) {
        cnt[k] = (cnt[k] ?? 0) + 1;
        (srcs[k] ??= <String>{}).add(n.src);
      }
    }
    final have = app.topics.map(norm).toSet();
    final list = cnt.entries
        .where((e) => e.value >= 3 && (srcs[e.key]?.length ?? 0) >= 2 && !have.contains(e.key))
        .toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    final picks = list.take(8).map((e) => e.key).toList();
    if (picks.isEmpty) return const <Widget>[];
    return [
      const SizedBox(height: 12),
      Text('اقتراحات من أخبار اليوم', style: ui(13, w: FontWeight.w500, c: p.muted)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in picks)
            actionChip(p, Icons.add_rounded, k, () => app.addTopic(k)),
        ],
      ),
    ];
  }

  /// أهم القصص (تغطيها عدة مصادر) ثم اختيارات تناسب اهتماماتك.
  (List<News>, List<News>) nowLists() {
    final uniq = nowUnique();
    final t24 = DateTime.now().subtract(const Duration(hours: 24));
    final t48 = DateTime.now().subtract(const Duration(hours: 48));
    DateTime tm(News n) => n.time ?? DateTime(2000);
    final hot = uniq.where((n) => n.others.isNotEmpty && tm(n).isAfter(t24)).toList();
    hot.sort((a, b) {
      final c = b.others.length.compareTo(a.others.length);
      return c != 0 ? c : tm(b).compareTo(tm(a));
    });
    final top = hot.take(12).toList();
    final picks = uniq
        .where((n) =>
            !top.contains(n) &&
            !app.isRead(n.link) &&
            tm(n).isAfter(t48) &&
            app.scoreOf(n) > 0)
        .toList();
    picks.sort((a, b) => app.scoreOf(b).compareTo(app.scoreOf(a)));
    return (top, picks.take(8).toList());
  }

  /// يولّد في الخلفية نشرة اليوم وملخصات القصص الكبرى ويحفظها (مرة واحدة لكل منها).
  Future<void> ensureAi() async {
    if (!app.aiOn || aiWorking || !mounted) return;
    final (top, mine) = nowLists();
    if (top.isEmpty && mine.isEmpty) return;
    aiWorking = true;
    try {
      if (!app.briefFresh) {
        final items = [...top, ...mine].take(10).toList();
        app.saveBrief(await askAi(_briefSys, briefInput(items)));
      }
      if (app.autoStories) {
        for (final n in top.take(5)) {
          if (!mounted) break;
          if (app.storyCache.containsKey(n.link)) continue;
          app.saveStory(n.link, await askAi(_storySys, storyInput(n)));
        }
      }
    } catch (_) {
      // الخادم متوقف أو بطيء: نتجاهل بصمت ونحاول في الزيارة التالية
    }
    aiWorking = false;
  }

  Widget storyNote(Pal p, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: p.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  textDirection: dirOf(text),
                  style: ui(13.5, w: FontWeight.w500, c: p.ink, h: 1.7)),
            ),
          ],
        ),
      );

  Widget nowBody(Pal p) {
    final uniq = nowUnique();
    final (top, mine) = nowLists();

    final children = <Widget>[];
    if (uniq.isEmpty) {
      children.add(topicsLoading
          ? const SkeletonList()
          : stateBox(p, 'لا توجد أخبار محمّلة بعد، اسحب للتحديث.'));
    } else {
      if (app.aiOn && (top.isNotEmpty || mine.isNotEmpty)) {
        final items = [...top, ...mine].take(10).toList();
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: actionChip(p, Icons.auto_awesome_rounded, 'نشرة اليوم',
                () => showAiSheet(
                      context,
                      'نشرة اليوم',
                      () => aiBrief(items),
                      initial: app.briefFresh ? app.briefText : null,
                      onDone: app.saveBrief,
                    )),
          ),
        ));
      }
      children.add(sectionTitle(p, 'أهم ما يحدث الآن'));
      if (top.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Text('لا توجد قصة تغطيها عدة مصادر حاليًا.',
              style: ui(14, w: FontWeight.w500, c: p.muted, h: 1.7)),
        ));
      } else {
        for (final n in top) {
          children.add(NewsTile(news: n));
          final note = app.storyCache[n.link];
          if (note != null) children.add(storyNote(p, note));
        }
      }
      children.add(sectionTitle(p, 'مختارة لك'));
      if (mine.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Text(
            'كلما فتحت وحفظت أخبارًا أكثر، ظهرت هنا أخبار تناسب اهتماماتك. '
            'يُحسب ذلك على جهازك فقط.',
            style: ui(14, w: FontWeight.w500, c: p.muted, h: 1.7),
          ),
        ));
      } else {
        for (final n in mine) {
          children.add(NewsTile(news: n));
        }
      }
    }
    return Column(
      children: [
        tabsRow(p),
        if (topicsLoading)
          LinearProgressIndicator(minHeight: 2, color: p.green, backgroundColor: p.chip),
        Expanded(
          child: RefreshIndicator(
            color: p.green,
            onRefresh: () => loadTopicSources(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  // ───────────── مواضيعي ─────────────

  void submitTopic() {
    app.addTopic(topicCtl.text);
    topicCtl.clear();
    setState(() {});
  }

  Widget topicsBody(Pal p) {
    final kws = app.topics;
    if (topicFilter != 'all' && !kws.contains(topicFilter)) topicFilter = 'all';
    final active = topicFilter == 'all' ? kws : [topicFilter];
    final needles = [for (final k in active) norm(k)].where((k) => k.isNotEmpty).toList();
    final results = needles.isEmpty
        ? <News>[]
        : allLoaded().where((n) {
            final t = norm('${n.orig} ${n.title}');
            return needles.any(t.contains);
          }).toList();

    Widget chip(String k, String label, {bool removable = false}) {
      final on = topicFilter == k;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: tap(
          () => setState(() => topicFilter = k),
          Container(
            height: 36,
            padding: EdgeInsetsDirectional.only(start: 16, end: removable ? 6 : 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? p.tabOn : p.chip,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: ui(14, c: on ? p.tabOnText : p.ink)),
                if (removable) ...[
                  const SizedBox(width: 4),
                  tap(
                    () => app.removeTopic(k),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: on ? p.tabOnText : p.muted),
                    ),
                    label: 'حذف الكلمة $label',
                  ),
                ],
              ],
            ),
          ),
          label: label,
        ),
      );
    }

    return Column(
      children: [
        tabsRow(p),
        if (topicsLoading)
          LinearProgressIndicator(minHeight: 2, color: p.green, backgroundColor: p.chip),
        Expanded(
          child: RefreshIndicator(
            color: p.green,
            onRefresh: () => loadTopicSources(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
              children: [
                TextField(
                  controller: topicCtl,
                  onSubmitted: (_) => submitTopic(),
                  textInputAction: TextInputAction.done,
                  style: ui(16, w: FontWeight.w500, c: p.ink),
                  cursorColor: p.green,
                  decoration: InputDecoration(
                    hintText: 'أضف كلمة تتابعها، مثل: الدولار أو الأهلي',
                    hintStyle: ui(15, w: FontWeight.w500, c: p.muted),
                    prefixIcon: Icon(Icons.add_rounded, color: p.muted),
                    suffixIcon: IconButton(
                      tooltip: 'إضافة',
                      icon: Icon(Icons.check_rounded, color: p.green),
                      onPressed: submitTopic,
                    ),
                    filled: true,
                    fillColor: p.chip,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                ...suggestionWidgets(p),
                if (kws.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        chip('all', 'الكل'),
                        for (final k in kws) chip(k, k, removable: true),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (kws.isEmpty)
                  stateBox(p, 'أضف كلمات تهمك، وستظهر هنا كل الأخبار التي تذكرها من جميع المصادر.')
                else if (results.isEmpty)
                  stateBox(
                    p,
                    topicsLoading
                        ? 'جاري البحث في الأخبار...'
                        : 'لا توجد أخبار مطابقة حاليًا.',
                  )
                else
                  for (final n in results) NewsTile(news: n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ───────────── المحفوظات ─────────────

  Widget savedBody(Pal p) {
    final list = app.saved;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
      children: [
        sectionTitle(p, 'المحفوظات'),
        if (list.isEmpty)
          stateBox(p, 'لم تحفظ أي خبر بعد.\nافتح خبرًا واضغط على علامة الحفظ ليظهر هنا.')
        else
          for (final n in list) NewsTile(news: n),
      ],
    );
  }

  // ───────────── البحث ─────────────

  List<News> searchPool() {
    switch (searchScope) {
      case 'saved':
        return app.saved;
      case 'history':
        return app.history;
      case 'loaded':
        return allLoaded();
      default:
        final seen = <String>{};
        return [
          for (final n in [...allLoaded(), ...app.saved, ...app.history])
            if (seen.add(n.link)) n,
        ];
    }
  }

  Widget searchBody(Pal p) {
    final q = norm(query);
    final pool = searchPool();
    final results = q.isEmpty
        ? (searchScope == 'saved' || searchScope == 'history' ? pool : <News>[])
        : pool.where((n) => norm(n.title).contains(q) || norm(n.orig).contains(q)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
      children: [
        TextField(
          controller: searchCtl,
          onChanged: (v) => setState(() => query = v),
          style: ui(16, w: FontWeight.w500, c: p.ink),
          cursorColor: p.green,
          decoration: InputDecoration(
            hintText: 'ابحث في الأخبار المحمّلة',
            hintStyle: ui(16, w: FontWeight.w500, c: p.muted),
            prefixIcon: Icon(Icons.search_rounded, color: p.muted),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح',
                    icon: Icon(Icons.close_rounded, color: p.muted),
                    onPressed: () {
                      searchCtl.clear();
                      setState(() => query = '');
                    },
                  ),
            filled: true,
            fillColor: p.chip,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in const [
              ('all', 'الكل', Icons.search_rounded),
              ('loaded', 'المحمّلة', Icons.newspaper_rounded),
              ('saved', 'المحفوظات', Icons.bookmark_rounded),
              ('history', 'سجل القراءة', Icons.history_rounded),
            ])
              actionChip(p, e.$3, e.$2, () => setState(() => searchScope = e.$1),
                  on: searchScope == e.$1),
          ],
        ),
        const SizedBox(height: 10),
        if (q.isEmpty && results.isEmpty)
          stateBox(
              p,
              searchScope == 'saved' || searchScope == 'history'
                  ? 'لا يوجد شيء هنا بعد.'
                  : 'اكتب كلمة للبحث في الأخبار المحمّلة والمحفوظات وسجل القراءة.')
        else if (results.isEmpty)
          stateBox(p, 'لا توجد نتائج مطابقة.')
        else
          for (final n in results) NewsTile(news: n),
      ],
    );
  }

  // ───────────── الإعدادات ─────────────

  Widget settingsCard(Pal p, String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(p, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ui(16, w: FontWeight.w800, c: p.ink)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget aiField(Pal p, String label, TextEditingController c, String hint,
      ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ui(13, w: FontWeight.w700, c: p.ink)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          onChanged: onChanged,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          style: ui(15, w: FontWeight.w500, c: p.ink),
          cursorColor: p.green,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: ui(13, w: FontWeight.w500, c: p.muted),
            filled: true,
            fillColor: p.chip,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget switchRow(Pal p, String label, bool v, ValueChanged<bool>? onChanged) => Row(
        children: [
          Expanded(child: Text(label, style: ui(15, w: FontWeight.w500, c: p.ink))),
          Switch(
            value: v,
            onChanged: onChanged,
            trackColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? p.green : p.chip,
            ),
            thumbColor: WidgetStateProperty.resolveWith(
              (st) => st.contains(WidgetState.selected) ? p.onGreen : p.muted,
            ),
          ),
        ],
      );

  Future<void> runAiTest() async {
    setState(() => aiTest = 'جاري الاختبار...');
    final r = await testAi();
    if (!mounted) return;
    setState(() => aiTest = r == 'ok' ? 'متصل والنموذج جاهز' : r);
  }

  Widget settingsBody(Pal p) {
    Widget modeBtn(String label, ThemeMode m) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: tap(
              () => app.setMode(m),
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: app.mode == m ? p.tabOn : p.chip,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(label, style: ui(15, c: app.mode == m ? p.tabOnText : p.ink)),
              ),
              label: label,
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
      children: [
        sectionTitle(p, 'الإعدادات'),
        settingsCard(
          p,
          'المظهر',
          Row(
            children: [
              modeBtn('تلقائي', ThemeMode.system),
              modeBtn('فاتح', ThemeMode.light),
              modeBtn('داكن', ThemeMode.dark),
            ],
          ),
        ),
        settingsCard(
          p,
          'حجم خط قراءة الخبر',
          Column(
            children: [
              Slider(
                value: app.fontScale,
                min: 0.85,
                max: 1.5,
                divisions: 13,
                activeColor: p.green,
                inactiveColor: p.chip,
                onChanged: app.setFont,
              ),
              Text(
                'هكذا يظهر نص الخبر داخل التطبيق.',
                style: body(19 * app.fontScale, c: p.ink),
              ),
            ],
          ),
        ),
        settingsCard(
          p,
          'التابات',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'رتّب التابات بالسحب من المقبض، وأوقف ما لا تريد ظهوره.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (a, b) {
                  final o = [...app.tabOrder];
                  if (b > a) b--;
                  o.insert(b, o.removeAt(a));
                  app.setTabOrder(o);
                },
                children: [
                  for (var i = 0; i < app.tabOrder.length; i++)
                    Row(
                      key: ValueKey(app.tabOrder[i]),
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.drag_indicator_rounded, color: p.muted),
                          ),
                        ),
                        Expanded(
                          child: Text(tabLabel(app.tabOrder[i]),
                              style: ui(15, w: FontWeight.w500, c: p.ink)),
                        ),
                        Switch(
                          value: !app.hiddenTabs.contains(app.tabOrder[i]),
                          onChanged: (_) => toggleTabVisible(app.tabOrder[i]),
                          trackColor: WidgetStateProperty.resolveWith(
                            (st) => st.contains(WidgetState.selected) ? p.green : p.chip,
                          ),
                          thumbColor: WidgetStateProperty.resolveWith(
                            (st) => st.contains(WidgetState.selected) ? p.onGreen : p.muted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        settingsCard(
          p,
          'المصادر',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أوقف أي مصدر لا تريد أخباره، ويُطبَّق التغيير فورًا على كل التابات.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              for (final e in sourceGroups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(e.key, style: ui(14, w: FontWeight.w800, c: p.green)),
                ),
                for (final s in e.value)
                  Row(
                    children: [
                      Expanded(
                        child: Text(s, style: ui(15, w: FontWeight.w500, c: p.ink)),
                      ),
                      Switch(
                        value: !app.disabled.contains(s),
                        onChanged: (_) => toggleSource(s),
                        trackColor: WidgetStateProperty.resolveWith(
                          (st) => st.contains(WidgetState.selected) ? p.green : p.chip,
                        ),
                        thumbColor: WidgetStateProperty.resolveWith(
                          (st) => st.contains(WidgetState.selected) ? p.onGreen : p.muted,
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        settingsCard(
          p,
          'المساعد الذكي (اختياري)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'يشغّل التلخيص والأسئلة ونشرة اليوم ومقارنة الروايات بنموذج على حاسوبك '
                'عبر برنامج أولاما، فلا يخرج أي نص إلى خدمة خارجية. '
                'اترك العنوان فارغًا لإخفاء هذه الميزات.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              const SizedBox(height: 12),
              aiField(p, 'عنوان الخادم', aiUrlCtl, 'http://192.168.1.5:11434', (v) {
                aiTest = null;
                app.setAi(url: v);
              }),
              const SizedBox(height: 6),
              Text('على نفس الحاسوب اكتب العنوان المحلي، وعلى الجوال اكتب عنوان الحاسوب في الشبكة المنزلية.',
                  style: ui(12, w: FontWeight.w500, c: p.muted, h: 1.6)),
              const SizedBox(height: 12),
              aiField(p, 'اسم النموذج', aiModelCtl, 'qwen3.5:9b', (v) {
                aiTest = null;
                app.setAi(model: v);
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  actionChip(p, Icons.wifi_tethering_rounded, 'اختبار الاتصال',
                      app.aiOn ? runAiTest : null),
                  const SizedBox(width: 10),
                  if (aiTest != null)
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(aiTest!, style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.5)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        settingsCard(
          p,
          'الملخصات التلقائية',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'عند فتح تاب "الآن" يجهّز النموذج نشرة اليوم وفقرة موجزة تحت كل قصة كبرى، '
                'ويحفظها فلا تُحسب مرتين. تحتاج المساعد الذكي مفعّلًا.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              switchRow(p, 'ملخص تلقائي للقصص الكبرى', app.autoStories && app.aiOn,
                  app.aiOn ? app.setAutoStories : null),
            ],
          ),
        ),
        settingsCard(
          p,
          'إشعارات العاجل',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pushSupported
                    ? 'يصلك تنبيه عند ظهور خبر عاجل تؤكده عدة مصادر، حتى والتطبيق مغلق.'
                    : 'غير مفعّلة بعد. تحتاج إعدادًا مجانيًا مرة واحدة، وخطواته في ملف دليل الإشعارات المرفق.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              if (pushSupported)
                switchRow(p, 'تفعيل الإشعارات', app.pushOn, (v) async {
                  app.setPushOn(v);
                  await setPush(v);
                }),
            ],
          ),
        ),
        settingsCard(
          p,
          'سجل الأخطاء',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.errors.isEmpty
                    ? 'لا توجد أخطاء مسجلة.'
                    : 'سُجّل ${arNum(app.errors.length)} خطأ على هذا الجهاز ولم يُرسل إلى أي جهة. '
                        'يمكنك نسخه وإرساله لي لأصلحه.',
                style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.7),
              ),
              if (app.errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    actionChip(p, Icons.copy_rounded, 'نسخ السجل', () {
                      Clipboard.setData(ClipboardData(text: app.errors.join('\n\n')));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('تم نسخ السجل')));
                    }),
                    actionChip(p, Icons.delete_outline_rounded, 'مسح', app.clearErrors),
                  ],
                ),
              ],
            ],
          ),
        ),
        settingsCard(
          p,
          'عن التطبيق',
          Text(
            'تُجلب الأخبار مباشرة من مواقع المصادر المذكورة أعلاه. '
            'اسحب القائمة للأسفل لتحديثها، واضغط على زر "ترجمة" بجانب أي خبر أجنبي لقراءته بالعربية. '
            'واضغط مطولًا على أي خبر لقراءة خلاصته قبل فتحه.',
            style: ui(14, w: FontWeight.w500, c: p.muted, h: 1.8),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════ صفحة الخبر ═════════════════════════

class ArticlePage extends StatefulWidget {
  final News news;
  const ArticlePage({super.key, required this.news});

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  bool loading = true;
  bool partial = false;
  bool showTr = false;
  bool trBusy = false;
  bool fromOffline = false;
  List<String> orig = [];
  List<String>? tr;
  String? image;

  @override
  void initState() {
    super.initState();
    load();
  }

  final FlutterTts tts = FlutterTts();
  bool speaking = false;
  int speakToken = 0;

  @override
  void dispose() {
    speakToken++;
    tts.stop();
    super.dispose();
  }

  void snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> stopSpeak() async {
    speakToken++;
    try {
      await tts.stop();
    } catch (_) {}
    if (mounted) setState(() => speaking = false);
  }

  /// قراءة الخبر بصوت عالٍ فقرة بعد فقرة، من صوت الجهاز نفسه.
  Future<void> toggleSpeak() async {
    if (speaking) {
      await stopSpeak();
      return;
    }
    final n = widget.news;
    final paras = showTr && tr != null ? tr! : orig;
    final parts = <String>[n.title, ...paras];
    final my = ++speakToken;
    setState(() => speaking = true);
    try {
      await tts.awaitSpeakCompletion(true);
      var checked = false;
      for (final t in parts) {
        if (!mounted || my != speakToken) return;
        final ar = arabicChars.hasMatch(t);
        if (ar && !checked) {
          checked = true;
          final ok = await tts.isLanguageAvailable('ar');
          if (ok != true && ok != 1) {
            snack('لا يوجد صوت عربي على جهازك، ثبّته من إعدادات النطق في النظام');
            if (mounted && my == speakToken) setState(() => speaking = false);
            return;
          }
        }
        await tts.setLanguage(ar ? 'ar' : 'en-US');
        await tts.speak(clip(t, 3500));
      }
    } catch (_) {
      snack('تعذر تشغيل القراءة الصوتية');
    }
    if (mounted && my == speakToken) setState(() => speaking = false);
  }

  Widget actionsRow(Pal p, News n) {
    final hasText = orig.isNotEmpty;
    final src = orig.join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          actionChip(p, Icons.image_outlined, 'مشاركة كصورة', () => showShareCard(context, n)),
          if (hasText)
            actionChip(p, speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                speaking ? 'إيقاف' : 'استمع', toggleSpeak,
                on: speaking),
          if (app.aiOn && hasText) ...[
            actionChip(p, Icons.auto_awesome_rounded, 'ملخص ذكي',
                () => showAiSheet(context, 'ملخص ذكي', () => aiSummary(n, src))),
            actionChip(p, Icons.chat_bubble_outline_rounded, 'اسأل عن الخبر',
                () => showAskSheet(context, n, src)),
          ],
          if (app.aiOn && n.related.isNotEmpty)
            actionChip(p, Icons.compare_arrows_rounded, 'قارن الروايات',
                () => showAiSheet(context, 'مقارنة الروايات', () => aiCompare(n))),
        ],
      ),
    );
  }

  Widget summaryCard(Pal p, List<String> paras) {
    final s = quickSummary(paras);
    if (s.length < 40) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: p.green),
              const SizedBox(width: 6),
              Text('الخلاصة', style: ui(14, w: FontWeight.w800, c: p.green)),
            ],
          ),
          const SizedBox(height: 6),
          Text(s,
              textDirection: dirOf(s),
              style: ui(15, w: FontWeight.w500, c: p.ink, h: 1.8)),
        ],
      ),
    );
  }

  /// كل ما نُشر عن القصة نفسها من المصادر الأخرى، مرتبًا بالزمن.
  Widget timelineCard(Pal p, News n) {
    if (n.related.isEmpty) return const SizedBox.shrink();
    final all = [n, ...n.related];
    all.sort((a, b) => (a.time ?? DateTime(2000)).compareTo(b.time ?? DateTime(2000)));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(p, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 18, color: p.green),
              const SizedBox(width: 6),
              Text('خط القصة · تغطية ${coverageText(n)}',
                  style: ui(14, w: FontWeight.w800, c: p.green)),
            ],
          ),
          const SizedBox(height: 8),
          for (final x in all)
            tap(
              identical(x, n) ? null : () => openArticle(context, x),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 9, left: 10),
                      decoration: BoxDecoration(
                        color: identical(x, n) ? p.green : p.border,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${x.src}  ·  ${ago(x.time)}${identical(x, n) ? '  ·  هذا الخبر' : ''}',
                            style: ui(12.5, w: FontWeight.w700, c: p.green),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            x.title,
                            textDirection: dirOf(x.title),
                            style: ui(14.5, w: FontWeight.w500, c: p.ink, h: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              label: '${x.src}: ${x.title}',
            ),
        ],
      ),
    );
  }

  Future<void> load() async {
    final n = widget.news;
    // نسخة محفوظة للقراءة بدون إنترنت؟ نعرضها فورًا بلا طلب شبكة
    final off = app.offline[n.link];
    if (off != null) {
      setState(() {
        orig = List<String>.from(off['p'] as List);
        tr = null;
        image = (off['i'] as String?) ?? n.img;
        partial = false;
        fromOffline = true;
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      partial = false;
      fromOffline = false;
    });
    try {
      final r = await http.get(Uri.parse(n.link), headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'ar,en;q=0.8',
      }).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final ex = extractArticle(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      if (ex.paras.isEmpty) {
        useSummary(ex.image);
      } else {
        setState(() {
          orig = List<String>.from(ex.paras);
          tr = null;
          image = ex.image ?? n.img;
          loading = false;
        });
        // الخبر محفوظ من قبل: نحفظ نصه أيضًا للقراءة بدون إنترنت
        if (app.isSaved(n.link)) app.storeOffline(n.link, orig, image);
      }
    } catch (_) {
      if (!mounted) return;
      useSummary(null);
    }
  }

  void useSummary(String? img) {
    final n = widget.news;
    setState(() {
      orig = n.summary.isNotEmpty ? [n.summary] : [];
      tr = null;
      image = img ?? n.img;
      partial = true;
      loading = false;
    });
  }

  Future<void> toggleTranslate() async {
    final n = widget.news;
    if (showTr) {
      setState(() => showTr = false);
      if (n.translated) n.toggleTitle();
      return;
    }
    setState(() {
      showTr = true;
      trBusy = tr == null;
    });
    if (!n.translated && !n.busy) n.toggleTitle();
    if (tr == null) {
      final src = List<String>.from(orig);
      final out = <String>[];
      for (var i = 0; i < src.length; i += 4) {
        final batch = src.skip(i).take(4).toList();
        out.addAll(await Future.wait(batch.map(translateText)));
        if (!mounted) return;
      }
      if (!mounted) return;
      setState(() {
        tr = out;
        trBusy = false;
      });
    }
  }

  Future<void> share() async {
    final n = widget.news;
    try {
      await SharePlus.instance.share(ShareParams(text: '${n.title}\n${n.link}'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: n.link));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم نسخ الرابط')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, widget.news]),
      builder: (context, _) {
        final p = Pal.of(context);
        final n = widget.news;
        final saved = app.isSaved(n.link);
        return Scaffold(
          backgroundColor: p.bg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              tap(
                                () => Navigator.of(context).maybePop(),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: p.chip,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.arrow_back_rounded, size: 22, color: p.ink),
                                      const SizedBox(width: 6),
                                      Text('رجوع', style: ui(16, w: FontWeight.w800, c: p.ink)),
                                    ],
                                  ),
                                ),
                                label: 'رجوع',
                              ),
                              const Spacer(),
                              if (n.foreign) ...[
                                tap(
                                  loading ? null : toggleTranslate,
                                  Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: showTr ? p.green : p.chip,
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        trBusy
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: showTr ? p.onGreen : p.green,
                                                ),
                                              )
                                            : Icon(Icons.translate_rounded,
                                                size: 20, color: showTr ? p.onGreen : p.ink),
                                        const SizedBox(width: 6),
                                        Text(showTr ? 'الأصل' : 'ترجمة',
                                            style: ui(15, c: showTr ? p.onGreen : p.ink)),
                                      ],
                                    ),
                                  ),
                                  label: showTr ? 'عرض النص الأصلي' : 'ترجمة الخبر إلى العربية',
                                ),
                                const SizedBox(width: 8),
                              ],
                              circleBtn(
                                p,
                                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                saved ? 'إزالة من المحفوظات' : 'حفظ الخبر',
                                () {
                                  app.toggleSave(n);
                                  if (app.isSaved(n.link) && !partial && orig.isNotEmpty) {
                                    app.storeOffline(n.link, orig, image);
                                  }
                                },
                                bg: saved ? p.green : null,
                                fg: saved ? p.onGreen : null,
                              ),
                              const SizedBox(width: 8),
                              circleBtn(p, Icons.share_rounded, 'مشاركة', share),
                            ],
                          ),
                        ),
                        Expanded(child: articleBody(p, n)),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: fontBar(p),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget fontBar(Pal p) {
    Widget btn(String text, double size, VoidCallback onTap, String label) => tap(
          onTap,
          SizedBox(
            width: 52,
            height: 44,
            child: Center(child: Text(text, style: ui(size, c: p.navText))),
          ),
          label: label,
        );
    final divider = Container(width: 1, height: 22, color: p.navOn);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: p.nav,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn('أ−', 16, () => app.setFont(((app.fontScale - 0.1).clamp(0.85, 1.5)).toDouble()),
              'تصغير الخط'),
          divider,
          btn('أ+', 21, () => app.setFont(((app.fontScale + 0.1).clamp(0.85, 1.5)).toDouble()),
              'تكبير الخط'),
          divider,
          tap(
            () => app.setMode(
              Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
            ),
            SizedBox(
              width: 52,
              height: 44,
              child: Icon(Icons.dark_mode_rounded, size: 22, color: p.navText),
            ),
            label: 'تبديل الوضع الداكن',
          ),
        ],
      ),
    );
  }

  Widget articleBody(Pal p, News n) {
    if (loading) {
      return Center(child: CircularProgressIndicator(color: p.green));
    }
    final paras = showTr && tr != null ? tr! : orig;
    final children = <Widget>[];
    if (image != null) {
      children.add(netImg(p, image, n.link, double.infinity, 200, 20));
      children.add(const SizedBox(height: 14));
    }
    children.add(Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: p.green, borderRadius: BorderRadius.circular(10)),
          child: Text(n.src, style: ui(13, c: p.onGreen)),
        ),
        const SizedBox(width: 10),
        Text(ago(n.time), style: ui(13, w: FontWeight.w500, c: p.muted)),
      ],
    ));
    if (fromOffline) {
      children.add(const SizedBox(height: 8));
      children.add(Row(
        children: [
          Icon(Icons.download_done_rounded, size: 16, color: p.green),
          const SizedBox(width: 6),
          Text('نسخة محفوظة للقراءة بدون إنترنت',
              style: ui(13, w: FontWeight.w500, c: p.muted)),
        ],
      ));
    }
    if (n.others.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(Text(
        'نشره أيضًا: ${n.others.join('، ')}',
        style: ui(13, w: FontWeight.w500, c: p.muted, h: 1.6),
      ));
    }
    children.add(const SizedBox(height: 12));
    children.add(Text(
      n.title,
      textDirection: dirOf(n.title),
      style: ui(24, w: FontWeight.w800, c: p.ink, h: 1.6),
    ));
    children.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: p.border),
    ));
    children.add(actionsRow(p, n));
    if (trBusy) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('جاري ترجمة الخبر...', style: ui(13, w: FontWeight.w500, c: p.muted)),
      ));
    }
    if (paras.length >= 3) children.add(summaryCard(p, paras));
    for (final t in paras) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          t,
          textDirection: dirOf(t),
          style: body(19 * app.fontScale, c: p.ink),
        ),
      ));
    }
    children.add(timelineCard(p, n));
    if (partial) {
      children.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(p, 16),
        child: Column(
          children: [
            Text(
              'تعذر تحميل نص الخبر كاملًا من الموقع، وقد يكون محميًا أو يتطلب اشتراكًا.',
              textAlign: TextAlign.center,
              style: ui(15, w: FontWeight.w500, c: p.muted, h: 1.7),
            ),
            const SizedBox(height: 10),
            tap(
              load,
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(22)),
                alignment: Alignment.center,
                child: Text('إعادة المحاولة', style: ui(15, c: p.ink)),
              ),
              label: 'إعادة المحاولة',
            ),
          ],
        ),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
      children: children,
    );
  }
}

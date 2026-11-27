import 'package:intl/intl.dart';

import 'assistant_service.dart';
import 'todo_repository.dart';

/// A built-in assistant that understands common task commands with plain
/// rules: no AI service, no key, no cost, and it works offline.
///
/// It reads the same text snapshot the cloud assistant gets and answers with
/// the same kind of reply and actions.
class LocalAssistantService implements AssistantService {
  const LocalAssistantService();

  @override
  Future<AssistantReply> send({
    required String message,
    required List<ChatTurn> history,
    required String context,
  }) async => respondLocally(message, context);
}

/// Uses the cloud assistant when it is set up, and the built-in one
/// otherwise (or whenever the cloud one fails).
class SmartAssistantService implements AssistantService {
  SmartAssistantService(
    this._cloud, [
    this._local = const LocalAssistantService(),
  ]);

  final AssistantService _cloud;
  final AssistantService _local;
  bool _cloudAvailable = true;

  @override
  Future<AssistantReply> send({
    required String message,
    required List<ChatTurn> history,
    required String context,
  }) async {
    if (_cloudAvailable) {
      try {
        return await _cloud.send(
          message: message,
          history: history,
          context: context,
        );
      } on AssistantUnavailable {
        // Not set up: stop asking the server for the rest of this session.
        _cloudAvailable = false;
      } on TodoException {
        // A one-off failure (offline, busy, daily limit): answer locally.
      }
    }
    return _local.send(message: message, history: history, context: context);
  }
}

// ---------------------------------------------------------------------------
// Snapshot parsing

class _SnapTask {
  _SnapTask(
    this.ref,
    this.title, {
    this.due,
    this.start,
    this.end,
    this.done = false,
  });
  final String ref;
  final String title;
  final DateTime? due;

  /// Minutes after midnight.
  final int? start;
  final int? end;
  final bool done;
}

class _Snapshot {
  _Snapshot(this.now, this.projects, this.tasks);
  final DateTime now;
  final List<String> projects;
  final List<_SnapTask> tasks;

  DateTime get today => DateTime(now.year, now.month, now.day);
  List<_SnapTask> get open => tasks.where((t) => !t.done).toList();
  List<_SnapTask> get done => tasks.where((t) => t.done).toList();
}

_Snapshot _parseSnapshot(String context) {
  var now = DateTime.now();
  final projects = <String>[];
  final tasks = <_SnapTask>[];
  var inDone = false;

  for (final raw in context.split('\n')) {
    final line = raw.trim();
    final nowMatch = RegExp(
      r'^Now: \S+ (\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})',
    ).firstMatch(line);
    if (nowMatch != null) {
      now = DateTime(
        int.parse(nowMatch[1]!),
        int.parse(nowMatch[2]!),
        int.parse(nowMatch[3]!),
        int.parse(nowMatch[4]!),
        int.parse(nowMatch[5]!),
      );
      continue;
    }
    if (line.startsWith('Projects:')) {
      final list = line.substring('Projects:'.length).trim();
      if (list != '(none)') {
        projects.addAll(
          list.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty),
        );
      }
      continue;
    }
    if (line.startsWith('Recently completed')) {
      inDone = true;
      continue;
    }
    final taskMatch = RegExp(r'^(t\d+) \| (.+)$').firstMatch(line);
    if (taskMatch == null) continue;
    final parts = taskMatch[2]!.split(' | ');
    DateTime? due;
    int? start, end;
    for (final part in parts.skip(1)) {
      final d = RegExp(r'^due (\d{4})-(\d{2})-(\d{2})$').firstMatch(part);
      if (d != null) {
        due = DateTime(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!));
      }
      final s = RegExp(r'^(\d{2}):(\d{2})-(\d{2}):(\d{2})$').firstMatch(part);
      if (s != null) {
        start = int.parse(s[1]!) * 60 + int.parse(s[2]!);
        end = int.parse(s[3]!) * 60 + int.parse(s[4]!);
      }
    }
    tasks.add(
      _SnapTask(
        taskMatch[1]!,
        parts.first.trim(),
        due: due,
        start: start,
        end: end,
        done: inDone,
      ),
    );
  }
  return _Snapshot(now, projects, tasks);
}

// ---------------------------------------------------------------------------
// Date and time understanding

/// Text that pieces are cut out of as they are understood; what is left over
/// becomes the task title.
class _Text {
  _Text(this.value);
  String value;

  RegExpMatch? take(String pattern) {
    final m = RegExp(pattern, caseSensitive: false).firstMatch(value);
    if (m != null) remove(m);
    return m;
  }

  Iterable<RegExpMatch> all(String pattern) =>
      RegExp(pattern, caseSensitive: false).allMatches(value).toList();

  void remove(RegExpMatch m, [String replacement = ' ']) {
    value = value.substring(0, m.start) + replacement + value.substring(m.end);
  }
}

class _When {
  DateTime? date;

  /// Minutes after midnight.
  int? start;
  int? end;
  String? repeat;

  bool get isEmpty => date == null && start == null && repeat == null;
}

const _weekdays = {
  'monday': 1,
  'tuesday': 2,
  'wednesday': 3,
  'thursday': 4,
  'friday': 5,
  'saturday': 6,
  'sunday': 7,
};

const _weekdayNames =
    'monday|tuesday|wednesday|thursday|friday|saturday|sunday';

const _monthPattern =
    '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
    'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

const _monthNumbers = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// A clock time such as "6", "6pm", "6:30 pm" or "18:00".
const _clock = r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?';

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// The next [weekday] strictly after [from].
DateTime _nextWeekday(DateTime from, int weekday) {
  var d = _addDays(from, 1);
  while (d.weekday != weekday) {
    d = _addDays(d, 1);
  }
  return d;
}

/// Hour of day from a clock hour and optional am/pm. With neither, 1 to 6
/// is taken as afternoon ("at 3" means 3 pm).
int? _hour24(int hour, String? meridiem) {
  final mer = meridiem?.toLowerCase();
  if (mer != null) {
    if (hour < 1 || hour > 12) return null;
    if (mer == 'pm') return hour == 12 ? 12 : hour + 12;
    return hour == 12 ? 0 : hour;
  }
  if (hour > 23) return null;
  if (hour >= 1 && hour <= 6) return hour + 12;
  return hour;
}

int? _minutesOf(String hour, String? minute, String? meridiem) {
  final h = _hour24(int.parse(hour), meridiem);
  final m = minute == null ? 0 : int.parse(minute);
  if (h == null || m > 59) return null;
  return h * 60 + m;
}

/// Cuts dates, times, durations and repeat words out of [text].
_When _extractWhen(_Text text, DateTime today) {
  final when = _When();
  RegExpMatch? m;

  // Repeats.
  m = text.take('\\bevery\\s+($_weekdayNames)s?\\b');
  if (m != null) {
    when.repeat = 'weekly';
    final weekday = _weekdays[m[1]!.toLowerCase()]!;
    when.date = today.weekday == weekday ? today : _nextWeekday(today, weekday);
  } else if (text.take(r'\b(?:every\s*day|each\s+day|daily)\b') != null) {
    when.repeat = 'daily';
  } else if (text.take(r'\b(?:every\s+week|weekly)\b') != null) {
    when.repeat = 'weekly';
  } else if (text.take(r'\b(?:every\s+month|monthly)\b') != null) {
    when.repeat = 'monthly';
  }

  // Calendar dates: 2026-12-01, 5 Dec, December 5th.
  m = text.take(r'\b(?:on\s+)?(\d{4})-(\d{1,2})-(\d{1,2})\b');
  if (m != null) {
    when.date = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  if (when.date == null) {
    int? day;
    String? month;
    m = text.take(
      '\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthPattern\\b',
    );
    if (m != null) {
      day = int.parse(m[1]!);
      month = m[2];
    } else {
      m = text.take(
        '\\b(?:on\\s+)?$_monthPattern\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b',
      );
      if (m != null) {
        month = m[1];
        day = int.parse(m[2]!);
      }
    }
    if (day != null && month != null && day >= 1 && day <= 31) {
      final number = _monthNumbers[month.toLowerCase().substring(0, 3)]!;
      var date = DateTime(today.year, number, day);
      if (date.isBefore(today)) date = DateTime(today.year + 1, number, day);
      when.date = date;
    }
  }

  // Time ranges: "from 6 to 7 pm", "6-7pm", "18:00 to 19:30".
  int? duration;
  bool setRange(RegExpMatch r) {
    final startMer = r[3] ?? r[6];
    var start = _minutesOf(r[1]!, r[2], startMer);
    final end = _minutesOf(r[4]!, r[5], r[6] ?? r[3]);
    if (start == null || end == null) return false;
    // "11 to 1 pm" starts in the morning.
    if (r[3] == null && start >= end && start >= 12 * 60) start -= 12 * 60;
    when.start = start;
    when.end = end;
    return true;
  }

  m = RegExp(
    '\\bfrom\\s+$_clock\\s*(?:to|until|till|-|–)\\s*$_clock\\b',
    caseSensitive: false,
  ).firstMatch(text.value);
  if (m != null && setRange(m)) {
    text.remove(m);
  } else {
    for (final r in text.all(
      '\\b$_clock\\s*(?:to|until|till|-|–)\\s*$_clock\\b',
    )) {
      // Without "from", need am/pm or minutes so "2 to 3 pages" isn't a time.
      final looksLikeTime =
          r[2] != null || r[3] != null || r[5] != null || r[6] != null;
      if (looksLikeTime && setRange(r)) {
        text.remove(r);
        break;
      }
    }
  }

  // Single times: "at 6", "@ 6:30pm", "by 5pm", "6pm", "18:00", "noon".
  if (when.start == null) {
    m = RegExp(
      '(?:\\bat|@|\\bby)\\s*$_clock\\b',
      caseSensitive: false,
    ).firstMatch(text.value);
    final minutes = m == null ? null : _minutesOf(m[1]!, m[2], m[3]);
    if (m != null && minutes != null) {
      when.start = minutes;
      text.remove(m);
    }
  }
  if (when.start == null) {
    for (final r in text.all('\\b$_clock\\b')) {
      if (r[2] == null && r[3] == null) continue; // a bare number
      final minutes = _minutesOf(r[1]!, r[2], r[3]);
      if (minutes != null) {
        when.start = minutes;
        text.remove(r);
        break;
      }
    }
  }
  if (when.start == null) {
    if (text.take(r'\b(?:at\s+)?noon\b') != null) {
      when.start = 12 * 60;
    } else if (text.take(r'\b(?:at\s+)?midnight\b') != null) {
      when.start = 0;
    }
  }

  // Parts of the day, only in clear phrases ("tomorrow morning").
  const partTimes = {
    'morning': 9 * 60,
    'afternoon': 15 * 60,
    'evening': 19 * 60,
    'night': 20 * 60,
  };
  int? partOfDay;
  m = RegExp(
    r'\b(today|tomorrow)\s+(morning|afternoon|evening|night)\b',
    caseSensitive: false,
  ).firstMatch(text.value);
  if (m != null) {
    partOfDay = partTimes[m[2]!.toLowerCase()];
    text.remove(m, ' ${m[1]} '); // keep the day word for the date step
  } else {
    m = text.take(r'\b(?:in\s+the|this)\s+(morning|afternoon|evening)\b');
    if (m != null) {
      partOfDay = partTimes[m[1]!.toLowerCase()];
    } else if (text.take(r'\btonight\b') != null) {
      partOfDay = partTimes['night'];
      when.date ??= today;
    }
  }
  when.start ??= partOfDay;

  // Durations: "for 45 minutes", "for 2 hours", "for an hour".
  m = text.take(
    r'\bfor\s+(?:(\d+(?:\.\d+)?)|half\s+an?|an?)\s*(hours?|hrs?|h|minutes?|mins?)\b',
  );
  if (m != null) {
    final amount = m[1] != null
        ? double.parse(m[1]!)
        : (m[0]!.toLowerCase().contains('half') ? 0.5 : 1.0);
    final isHours = m[2]!.toLowerCase().startsWith('h');
    duration = (isHours ? amount * 60 : amount).round();
  }
  if (when.start != null &&
      when.end == null &&
      duration != null &&
      duration > 0) {
    when.end = (when.start! + duration) % (24 * 60);
  }

  // Relative days and weekdays.
  if (when.date == null) {
    if (text.take(r'\b(?:the\s+)?day\s+after\s+tomorrow\b') != null) {
      when.date = _addDays(today, 2);
    } else if (text.take(r'\b(?:tomorrow|tmrw|tmr)\b') != null) {
      when.date = _addDays(today, 1);
    } else if (text.take(r'\btoday\b') != null) {
      when.date = today;
    } else if ((m = text.take(r'\bin\s+(\d+)\s+days?\b')) != null) {
      when.date = _addDays(today, int.parse(m![1]!));
    } else if (text.take(r'\b(?:next\s+week|in\s+a\s+week)\b') != null) {
      when.date = _addDays(today, 7);
    } else if ((m = text.take(
          '\\b(?:on\\s+|this\\s+|next\\s+|coming\\s+)?($_weekdayNames)\\b',
        )) !=
        null) {
      when.date = _nextWeekday(today, _weekdays[m![1]!.toLowerCase()]!);
    }
  }
  return when;
}

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String _hm(int minutes) =>
    '${(minutes ~/ 60 % 24).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// "6:00 PM" from minutes after midnight.
String _clock12(int minutes) {
  final h = minutes ~/ 60 % 24, m = minutes % 60;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String _dayLabel(DateTime date, DateTime today) {
  final days = date.difference(today).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  return 'on ${DateFormat('EEE d MMM').format(date)}';
}

// ---------------------------------------------------------------------------
// Finding tasks by name

String _cleanName(String name) => name
    .trim()
    .replaceAll(RegExp('["“”\'‘’]'), '')
    .replaceFirst(RegExp(r'^(?:the|my)\s+', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^task\s+', caseSensitive: false), '')
    .replaceFirst(RegExp(r'\s+task$', caseSensitive: false), '')
    .replaceFirst(RegExp(r'[.!?]+$'), '')
    .trim();

/// Tasks in [candidates] that [name] could mean, best matches only.
List<_SnapTask> _find(String name, List<_SnapTask> candidates) {
  final wanted = _cleanName(name).toLowerCase();
  if (wanted.isEmpty) return const [];

  final byRef = candidates.where((t) => t.ref == wanted).toList();
  if (byRef.isNotEmpty) return byRef;

  final exact = candidates
      .where((t) => t.title.toLowerCase() == wanted)
      .toList();
  if (exact.isNotEmpty) return exact;

  final containing = candidates.where((t) {
    final title = t.title.toLowerCase();
    return title.contains(wanted) || wanted.contains(title);
  }).toList();
  if (containing.isNotEmpty) return containing;

  // Every meaningful word of the name appears in the title.
  final words = wanted
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toList();
  if (words.isEmpty) return const [];
  return candidates.where((t) {
    final title = t.title.toLowerCase();
    return words.every(title.contains);
  }).toList();
}

String _quote(String title) => '“$title”';

String _list(Iterable<String> titles) => titles.map(_quote).join(', ');

// ---------------------------------------------------------------------------
// Understanding a message

const _helpText =
    "Here's what I can do. Try:\n"
    '• Add gym tomorrow from 6 to 7 pm\n'
    '• Remind me to call mom every Sunday at 9am\n'
    '• What do I have today?\n'
    '• Complete buy milk\n'
    '• Move gym to Monday at 5pm\n'
    '• Move my overdue tasks to tomorrow\n'
    '• Delete pay rent\n'
    '• Create project Work';

AssistantReply _say(String text, [List<AssistantAction> actions = const []]) =>
    AssistantReply(text: text, actions: actions);

/// Runs [onOne] when [name] points at exactly one task; otherwise explains.
AssistantReply _withTask(
  String name,
  List<_SnapTask> candidates,
  AssistantReply Function(_SnapTask task) onOne, {
  String? notFound,
}) {
  final matches = _find(name, candidates);
  if (matches.length == 1) return onOne(matches.single);
  if (matches.isEmpty) {
    return _say(
      notFound ?? "I couldn't find a task called ${_quote(_cleanName(name))}.",
    );
  }
  return _say(
    'I found several tasks like that: ${_list(matches.take(5).map((t) => t.title))}. '
    'Which one do you mean?',
  );
}

RegExpMatch? _match(String pattern, String input) =>
    RegExp(pattern, caseSensitive: false).firstMatch(input);

/// Answers [message] using only rules, given the task [context] snapshot.
AssistantReply respondLocally(String message, String context) {
  final snap = _parseSnapshot(context);
  final today = snap.today;
  final text = message.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return _say(_helpText);
  RegExpMatch? m;

  if (_match(r'^(?:help|hi|hello|hey|what can you do)\b', text) != null) {
    return _say(_helpText);
  }

  // New project.
  m = _match(
    r'^(?:please\s+)?(?:create|add|new|make)\s+(?:a\s+)?(?:new\s+)?project\s+(?:called\s+|named\s+)?(.+?)[.!]?$',
    text,
  );
  if (m != null) {
    final name = _cleanName(m[1]!);
    return _say('Creating the project ${_quote(name)}.', [
      AssistantAction(type: 'create_project', title: name),
    ]);
  }

  // Questions about the list.
  if (_match(
        r"^(?:what|what's|whats|which|show|list|tell me|do i have|anything|how many|when|am i)\b",
        text,
      ) !=
      null) {
    return _answerQuestion(text, snap);
  }

  // Move every overdue task.
  m = _match(
    r'^(?:please\s+)?(?:move|reschedule|push|postpone)\s+(?:all\s+)?(?:of\s+)?(?:my\s+)?(?:the\s+)?overdue(?:\s+tasks?)?\s+to\s+(.+)$',
    text,
  );
  if (m != null) {
    final when = _extractWhen(_Text(m[1]!), today);
    if (when.date == null) {
      return _say("I didn't catch which day to move them to.");
    }
    final overdue = snap.open
        .where((t) => t.due != null && t.due!.isBefore(today))
        .toList();
    if (overdue.isEmpty) return _say('Nothing is overdue. Nice.');
    return _say(
      'Moving ${overdue.length} overdue task${overdue.length == 1 ? '' : 's'} to ${_dayLabel(when.date!, today).replaceFirst('on ', '')}.',
      [
        for (final t in overdue)
          AssistantAction(
            type: 'update_task',
            taskRef: t.ref,
            dueDate: _ymd(when.date!),
          ),
      ],
    );
  }

  // Priority.
  m = _match(
    r'^(?:please\s+)?(?:make|set|mark)\s+(.+?)\s+(?:as\s+|to\s+)?(high|medium|low|no)\s+priority[.!]?$',
    text,
  );
  if (m != null) {
    final level = m[2]!.toLowerCase() == 'no' ? 'none' : m[2]!.toLowerCase();
    return _withTask(
      m[1]!,
      snap.open,
      (t) => _say('Setting ${_quote(t.title)} to $level priority.', [
        AssistantAction(type: 'update_task', taskRef: t.ref, priority: level),
      ]),
    );
  }

  // Rename.
  m = _match(r'^(?:please\s+)?rename\s+(.+?)\s+to\s+(.+?)[.!]?$', text);
  if (m != null) {
    final typed = _cleanName(m[2]!);
    final newTitle = typed.isEmpty
        ? typed
        : typed[0].toUpperCase() + typed.substring(1);
    return _withTask(
      m[1]!,
      snap.open,
      (t) => _say('Renaming ${_quote(t.title)} to ${_quote(newTitle)}.', [
        AssistantAction(type: 'update_task', taskRef: t.ref, title: newTitle),
      ]),
    );
  }

  // Move one task to another day or time.
  m = _match(
    r'^(?:please\s+)?(?:move|reschedule|postpone|push)\s+(.+?)\s+to\s+(.+)$',
    text,
  );
  if (m != null) {
    final when = _extractWhen(_Text(m[2]!), today);
    if (when.date == null && when.start == null) {
      return _say(
        "I didn't catch when to move it to. Try “to tomorrow at 5pm”.",
      );
    }
    return _withTask(
      m[1]!,
      snap.open,
      (t) => _say('Moving ${_quote(t.title)}.', [
        AssistantAction(
          type: 'update_task',
          taskRef: t.ref,
          dueDate: when.date == null ? null : _ymd(when.date!),
          startTime: when.start == null ? null : _hm(when.start!),
          endTime: when.end == null ? null : _hm(when.end!),
        ),
      ]),
    );
  }

  // Complete.
  m =
      _match(
        r"^(?:i\s+(?:have\s+|already\s+|just\s+)?(?:finished|completed|did|done)|i've\s+(?:finished|completed|done))\s+(.+?)[.!]?$",
        text,
      ) ??
      _match(
        r'^(?:please\s+)?(?:complete|finish|tick(?:\s+off)?|check(?:\s+off)?|mark|done(?:\s+with)?)\s+(.+?)(?:\s+(?:as\s+)?(?:done|complete|completed|finished))?[.!]?$',
        text,
      );
  if (m != null) {
    final name = m[1]!;
    final alreadyDone = _find(name, snap.done);
    return _withTask(
      name,
      snap.open,
      (t) => _say('Marking ${_quote(t.title)} as done.', [
        AssistantAction(type: 'complete_task', taskRef: t.ref),
      ]),
      notFound: alreadyDone.length == 1
          ? '${_quote(alreadyDone.single.title)} is already done.'
          : null,
    );
  }

  // Reopen.
  m = _match(
    r'^(?:please\s+)?(?:reopen|undo|untick|uncheck)\s+(.+?)[.!]?$',
    text,
  );
  if (m != null) {
    return _withTask(
      m[1]!,
      snap.done,
      (t) => _say('Reopening ${_quote(t.title)}.', [
        AssistantAction(type: 'reopen_task', taskRef: t.ref),
      ]),
      notFound:
          "I couldn't find a finished task called ${_quote(_cleanName(m[1]!))}.",
    );
  }

  // Delete.
  m = _match(
    r'^(?:please\s+)?(?:delete|remove|cancel|trash)\s+(.+?)[.!]?$',
    text,
  );
  if (m != null) {
    return _withTask(
      m[1]!,
      snap.tasks,
      (t) => _say('Deleting ${_quote(t.title)}.', [
        AssistantAction(type: 'delete_task', taskRef: t.ref),
      ]),
    );
  }

  // Add.
  m = _match(
    r'^(?:please\s+)?(?:add|create|new|make|schedule|plan|remind me to|remind me|i need to|i have to|i want to|todo)\b[\s:,-]*(.*)$',
    text,
  );
  if (m != null) return _addTask(m[1]!, snap);

  // Something like "dentist tomorrow at 3pm" is still clearly a new task.
  if (!_extractWhen(_Text(text), today).isEmpty && !text.endsWith('?')) {
    return _addTask(text, snap);
  }
  if (text.endsWith('?')) return _answerQuestion(text, snap);

  return _say("I didn't understand that. $_helpText");
}

AssistantReply _addTask(String rest, _Snapshot snap) {
  final text = _Text(rest);

  String? priority;
  if (text.take(r'\b(?:high|top)\s+priority\b') != null ||
      text.take(r'\burgent(?:ly)?\b') != null) {
    priority = 'high';
  } else if (text.take(r'\b(?:medium|normal)\s+priority\b') != null) {
    priority = 'medium';
  } else if (text.take(r'\blow\s+priority\b') != null) {
    priority = 'low';
  }

  // Only known project names count, so "in the morning" isn't a project.
  String? project;
  for (final name in snap.projects) {
    final escaped = RegExp.escape(name);
    final hit =
        text.take(
          '\\b(?:in|to|under|for)\\s+(?:the\\s+|my\\s+)?(?:project\\s+)?$escaped(?:\\s+project)?(?!\\w)',
        ) ??
        text.take('#$escaped(?!\\w)');
    if (hit != null) {
      project = name;
      break;
    }
  }

  final when = _extractWhen(text, snap.today);

  var title = text.value
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(
        RegExp(
          r'^(?:(?:a|an)\s+)?(?:new\s+)?(?:(?:task|reminder|todo|to-do|event)\b\s*)?(?:(?:called|named|to|for|about)\b\s*)?[:\-]?\s*',
          caseSensitive: false,
        ),
        '',
      );
  // Drop words left dangling where a date or time was cut out.
  final dangling = RegExp(
    r'(?:\s+|^)(?:on|at|by|for|from|to|in|every|this|next|the|and|,)$',
    caseSensitive: false,
  );
  var previous = '';
  while (previous != title) {
    previous = title;
    title = title.replaceFirst(dangling, '').trim();
  }
  title = title.replaceFirst(RegExp(r'[.!,;:]+$'), '').trim();
  if (title.isEmpty) {
    return _say(
      'What should the task be called? Try “Add gym tomorrow at 6pm”.',
    );
  }
  title = title[0].toUpperCase() + title.substring(1);

  return _say('Adding ${_quote(title)}.', [
    AssistantAction(
      type: 'create_task',
      title: title,
      priority: priority,
      project: project,
      dueDate: when.date == null ? null : _ymd(when.date!),
      startTime: when.start == null ? null : _hm(when.start!),
      endTime: when.end == null ? null : _hm(when.end!),
      repeat: when.repeat,
    ),
  ]);
}

AssistantReply _answerQuestion(String text, _Snapshot snap) {
  final today = snap.today;
  final lower = text.toLowerCase();
  final open = snap.open;

  String line(_SnapTask t, {bool showDay = false}) {
    final extras = <String>[
      if (showDay && t.due != null)
        _dayLabel(t.due!, today).replaceFirst('on ', ''),
      if (t.start != null && t.end != null)
        '${_clock12(t.start!)} – ${_clock12(t.end!)}',
    ];
    return '• ${t.title}${extras.isEmpty ? '' : ' (${extras.join(', ')})'}';
  }

  int byTime(_SnapTask a, _SnapTask b) {
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    return (a.start ?? 24 * 60).compareTo(b.start ?? 24 * 60);
  }

  final overdue =
      open.where((t) => t.due != null && t.due!.isBefore(today)).toList()
        ..sort(byTime);

  if (RegExp(r'\b(?:overdue|late)\b').hasMatch(lower)) {
    if (overdue.isEmpty) return _say('Nothing is overdue. Nice.');
    return _say(
      'You have ${overdue.length} overdue task${overdue.length == 1 ? '' : 's'}:\n'
      '${overdue.map((t) => line(t, showDay: true)).join('\n')}',
    );
  }

  if (RegExp(r'\b(?:next|now)\b').hasMatch(lower)) {
    final nowMinutes = snap.now.hour * 60 + snap.now.minute;
    final upcoming = open.where((t) {
      if (t.due == null || t.due!.isBefore(today)) return false;
      if (t.due == today && t.end != null && t.end! <= nowMinutes) return false;
      return true;
    }).toList()..sort(byTime);
    if (upcoming.isEmpty) return _say('Nothing is coming up.');
    return _say('Next up:\n${line(upcoming.first, showDay: true)}');
  }

  if (RegExp(r'\b(?:all|everything|how many)\b').hasMatch(lower)) {
    if (open.isEmpty) return _say('You have no open tasks.');
    final sorted = [...open]..sort(byTime);
    final shown = sorted.take(10).map((t) => line(t, showDay: true)).join('\n');
    final more = open.length > 10 ? '\n…and ${open.length - 10} more.' : '';
    return _say(
      'You have ${open.length} open task${open.length == 1 ? '' : 's'}:\n$shown$more',
    );
  }

  // A particular day; today when none is named.
  final day = _extractWhen(_Text(text), today).date ?? today;
  final label = _dayLabel(day, today);
  final due = open.where((t) => t.due == day).toList()..sort(byTime);
  final buffer = StringBuffer();
  if (due.isEmpty) {
    buffer.write('Nothing is due $label.');
  } else {
    buffer.write(
      'You have ${due.length} task${due.length == 1 ? '' : 's'} $label:\n'
      '${due.map(line).join('\n')}',
    );
  }
  if (day == today && overdue.isNotEmpty) {
    buffer.write(
      '\nPlus ${overdue.length} overdue: ${overdue.map((t) => t.title).join(', ')}.',
    );
  }
  return _say(buffer.toString());
}

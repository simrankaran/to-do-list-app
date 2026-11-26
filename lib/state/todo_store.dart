import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/todo_repository.dart';

enum ViewKind { inbox, today, upcoming, all, completed, project, tag }

/// Which slice of tasks the user is looking at.
@immutable
class TodoView {
  const TodoView(this.kind, [this.id]);

  static const inbox = TodoView(ViewKind.inbox);
  static const today = TodoView(ViewKind.today);
  static const upcoming = TodoView(ViewKind.upcoming);
  static const all = TodoView(ViewKind.all);
  static const completed = TodoView(ViewKind.completed);

  final ViewKind kind;

  /// Project or tag id for [ViewKind.project] and [ViewKind.tag].
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is TodoView && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

enum SortBy {
  smart('Smart'),
  dueDate('Due date'),
  priority('Priority'),
  created('Newest first'),
  title('Title');

  const SortBy(this.label);
  final String label;
}

/// App state for one signed-in user. Changes are applied locally right away
/// and rolled back if the server rejects them.
class TodoStore extends ChangeNotifier {
  TodoStore(this._repo, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final TodoRepository _repo;
  final DateTime Function() _clock;
  final _errors = StreamController<String>.broadcast();

  List<Project> projects = [];
  List<Tag> tags = [];
  List<Task> tasks = [];
  bool loading = true;
  String? loadError;

  TodoView _view = TodoView.inbox;
  String _query = '';
  SortBy _sortBy = SortBy.smart;
  bool _showCompleted = false;

  /// User-facing messages for failed changes.
  Stream<String> get errors => _errors.stream;

  TodoView get view => _view;
  set view(TodoView value) {
    _view = value;
    notifyListeners();
  }

  String get query => _query;
  set query(String value) {
    _query = value;
    notifyListeners();
  }

  SortBy get sortBy => _sortBy;
  set sortBy(SortBy value) {
    _sortBy = value;
    notifyListeners();
  }

  bool get showCompleted => _showCompleted;
  set showCompleted(bool value) {
    _showCompleted = value;
    notifyListeners();
  }

  DateTime get today => dateOnly(_clock());

  Project? projectById(String? id) =>
      id == null ? null : projects.where((p) => p.id == id).firstOrNull;

  Tag? tagById(String id) => tags.where((t) => t.id == id).firstOrNull;

  String titleOf(TodoView v) => switch (v.kind) {
    ViewKind.inbox => 'Inbox',
    ViewKind.today => 'Today',
    ViewKind.upcoming => 'Upcoming',
    ViewKind.all => 'All tasks',
    ViewKind.completed => 'Completed',
    ViewKind.project => projectById(v.id)?.name ?? 'Project',
    ViewKind.tag => '#${tagById(v.id!)?.name ?? 'tag'}',
  };

  // Loading ------------------------------------------------------------------

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait<List<Object>>([
        _repo.fetchProjects(),
        _repo.fetchTags(),
        _repo.fetchTasks(),
      ]);
      projects = results[0].cast<Project>();
      tags = results[1].cast<Tag>();
      tasks = results[2].cast<Task>();
    } catch (e) {
      loadError = _message(e);
    }
    loading = false;
    notifyListeners();
  }

  // Queries ------------------------------------------------------------------

  bool _inView(Task t, TodoView v) => switch (v.kind) {
    ViewKind.inbox => t.projectId == null,
    ViewKind.today => t.dueAt != null && !t.dueAt!.isAfter(today),
    ViewKind.upcoming => t.dueAt != null && t.dueAt!.isAfter(today),
    ViewKind.all => true,
    ViewKind.completed => t.done,
    ViewKind.project => t.projectId == v.id,
    ViewKind.tag => t.tagIds.contains(v.id),
  };

  /// Number of open top-level tasks in [v], shown in the navigation.
  int countFor(TodoView v) => tasks
      .where(
        (t) =>
            !t.isSubtask &&
            _inView(t, v) &&
            (v.kind == ViewKind.completed || !t.done),
      )
      .length;

  /// Completed and total top-level tasks in [v], for the progress header.
  ({int done, int total}) progressFor(TodoView v) {
    var done = 0, total = 0;
    for (final t in tasks) {
      if (t.isSubtask || !_inView(t, v)) continue;
      total++;
      if (t.done) done++;
    }
    return (done: done, total: total);
  }

  /// Top-level tasks for the current view, search and sort settings.
  /// A search looks across all tasks, not just the current view.
  List<Task> get visibleTasks {
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final hideDone =
        !_showCompleted && !searching && _view.kind != ViewKind.completed;
    final list = tasks.where((t) {
      if (t.isSubtask) return false;
      if (hideDone && t.done) return false;
      if (searching) {
        return t.title.toLowerCase().contains(q) ||
            t.notes.toLowerCase().contains(q);
      }
      return _inView(t, _view);
    }).toList()..sort(_compare);
    return list;
  }

  List<Task> subtasksOf(String taskId) =>
      tasks.where((t) => t.parentId == taskId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  int _compare(Task a, Task b) {
    int byDue() {
      if (a.dueAt == b.dueAt) return 0;
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    }

    int byPriority() => b.priority.index.compareTo(a.priority.index);
    int byCreated() => a.createdAt.compareTo(b.createdAt);

    if (a.done != b.done) return a.done ? 1 : -1;
    return switch (_sortBy) {
      SortBy.smart => _firstNonZero([byDue(), byPriority(), byCreated()]),
      SortBy.dueDate => _firstNonZero([byDue(), byPriority()]),
      SortBy.priority => _firstNonZero([byPriority(), byDue()]),
      SortBy.created => -byCreated(),
      SortBy.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
  }

  static int _firstNonZero(List<int> values) =>
      values.firstWhere((v) => v != 0, orElse: () => 0);

  // Task changes -------------------------------------------------------------

  Future<Task?> addTask(Task draft) => _attempt(() async {
    final saved = await _repo.createTask(draft);
    tasks = [...tasks, saved];
    notifyListeners();
    return saved;
  });

  Future<void> updateTask(Task updated) async {
    final before = tasks;
    tasks = [for (final t in tasks) t.id == updated.id ? updated : t];
    notifyListeners();
    final ok = await _attempt(() async {
      await _repo.updateTask(updated);
      return true;
    });
    if (ok == null) {
      tasks = before;
      notifyListeners();
    }
  }

  Future<void> toggleDone(Task task) => updateTask(
    task.copyWith(done: !task.done, completedAt: task.done ? null : _clock()),
  );

  /// Removes [task] and its subtasks. Returns what was removed so it can be
  /// passed to [restore], or null if the delete failed.
  Future<List<Task>?> deleteTask(Task task) async {
    final removed = [task, ...subtasksOf(task.id)];
    final ids = {for (final t in removed) t.id};
    final before = tasks;
    tasks = tasks.where((t) => !ids.contains(t.id)).toList();
    notifyListeners();
    final ok = await _attempt(() async {
      await _repo.deleteTask(task.id);
      return true;
    });
    if (ok == null) {
      tasks = before;
      notifyListeners();
      return null;
    }
    return removed;
  }

  Future<void> restore(List<Task> removed) => _attempt(() async {
    // Drop tag links to tags deleted in the meantime.
    final tagIds = {for (final t in tags) t.id};
    final cleaned = [
      for (final t in removed)
        t.copyWith(
          tagIds: t.tagIds.where(tagIds.contains).toList(),
          projectId: projectById(t.projectId)?.id,
        ),
    ];
    await _repo.restoreTasks(cleaned);
    tasks = [...tasks, ...cleaned];
    notifyListeners();
  });

  // Project changes ----------------------------------------------------------

  Future<Project?> addProject(String name, int color) => _attempt(() async {
    final p = await _repo.createProject(name, color);
    projects = [...projects, p];
    notifyListeners();
    return p;
  });

  Future<void> updateProject(Project updated) => _attempt(() async {
    await _repo.updateProject(updated);
    projects = [for (final p in projects) p.id == updated.id ? updated : p];
    notifyListeners();
  });

  /// Deletes a project. Its tasks move to the Inbox.
  Future<void> deleteProject(String id) => _attempt(() async {
    await _repo.deleteProject(id);
    projects = projects.where((p) => p.id != id).toList();
    tasks = [
      for (final t in tasks)
        t.projectId == id ? t.copyWith(projectId: null) : t,
    ];
    if (_view == TodoView(ViewKind.project, id)) _view = TodoView.inbox;
    notifyListeners();
  });

  // Tag changes --------------------------------------------------------------

  Future<Tag?> addTag(String name, int color) => _attempt(() async {
    final tag = await _repo.createTag(name, color);
    tags = [...tags, tag]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return tag;
  });

  Future<void> updateTag(Tag updated) => _attempt(() async {
    await _repo.updateTag(updated);
    tags = [for (final t in tags) t.id == updated.id ? updated : t];
    notifyListeners();
  });

  Future<void> deleteTag(String id) => _attempt(() async {
    await _repo.deleteTag(id);
    tags = tags.where((t) => t.id != id).toList();
    tasks = [
      for (final t in tasks)
        t.tagIds.contains(id)
            ? t.copyWith(tagIds: t.tagIds.where((x) => x != id).toList())
            : t,
    ];
    if (_view == TodoView(ViewKind.tag, id)) _view = TodoView.inbox;
    notifyListeners();
  });

  // Helpers ------------------------------------------------------------------

  Future<T?> _attempt<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      if (!_errors.isClosed) _errors.add(_message(e));
      return null;
    }
  }

  static String _message(Object e) =>
      e is TodoException ? e.message : 'Something went wrong: $e';

  @override
  void dispose() {
    _errors.close();
    super.dispose();
  }
}

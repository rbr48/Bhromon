// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';

/// In-memory Firestore for repository and sync tests.
///
/// Supports the query shapes the app uses (equality / range / whereIn /
/// arrayContains filters, orderBy, limit, startAfterDocument, count) and
/// write batches. Every document a query returns is counted in
/// [documentsRead], matching how Firestore bills reads, so tests can assert
/// how much a screen reads.
class FakeFirestore implements FirebaseFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};

  /// Documents returned by queries and document gets (billed reads).
  int documentsRead = 0;

  /// Query gets per collection path.
  final Map<String, int> queriesByCollection = {};

  /// Aggregation (count) queries run.
  int aggregateQueries = 0;

  /// Committed write batches and the writes in each.
  final List<int> committedBatchSizes = [];

  /// Individual (non-batched) document writes.
  int singleWrites = 0;

  /// Document paths whose writes fail with this error code, batched or not.
  final Map<String, String> failingWrites = {};

  void seed(String collectionPath, String id, Map<String, dynamic> data) {
    (_collections[collectionPath] ??= {})[id] = Map.of(data);
  }

  Map<String, Map<String, dynamic>> docsIn(String collectionPath) =>
      _collections[collectionPath] ??= {};

  Map<String, dynamic>? read(String path) {
    final i = path.lastIndexOf('/');
    return _collections[path.substring(0, i)]?[path.substring(i + 1)];
  }

  void resetCounters() {
    documentsRead = 0;
    queriesByCollection.clear();
    aggregateQueries = 0;
    committedBatchSizes.clear();
    singleWrites = 0;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      FakeCollection(this, collectionPath);

  @override
  WriteBatch batch() => _FakeWriteBatch(this);

  void _checkWrite(String path) {
    final code = failingWrites[path];
    if (code != null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: code);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Filter = bool Function(String id, Map<String, dynamic> data);

class FakeQuery implements Query<Map<String, dynamic>> {
  final FakeFirestore store;
  final String path;
  final List<_Filter> _filters;
  final List<(String field, bool descending)> _orders;
  final int? _limit;
  final String? _startAfterId;
  final Object? _startAt;
  final Object? _endAt;

  FakeQuery(this.store, this.path,
      [this._filters = const [],
      this._orders = const [],
      this._limit,
      this._startAfterId,
      this._startAt,
      this._endAt]);

  FakeQuery _copy({
    List<_Filter>? filters,
    List<(String, bool)>? orders,
    int? limit,
    String? startAfterId,
    Object? startAt,
    Object? endAt,
  }) =>
      FakeQuery(
          store,
          path,
          filters ?? _filters,
          orders ?? _orders,
          limit ?? _limit,
          startAfterId ?? _startAfterId,
          startAt ?? _startAt,
          endAt ?? _endAt);

  @override
  Query<Map<String, dynamic>> startAt(Iterable<Object?> values) =>
      _copy(startAt: values.first);

  @override
  Query<Map<String, dynamic>> endAt(Iterable<Object?> values) =>
      _copy(endAt: values.first);

  static dynamic _value(String id, Map<String, dynamic> data, Object field) {
    if (field == FieldPath.documentId) return id;
    dynamic current = data;
    for (final part in (field as String).split('.')) {
      if (current is! Map) return null;
      current = current[part];
    }
    return current;
  }

  static int _compare(dynamic a, dynamic b) {
    if (a is Timestamp) a = a.millisecondsSinceEpoch;
    if (b is Timestamp) b = b.millisecondsSinceEpoch;
    if (a is DateTime) a = a.millisecondsSinceEpoch;
    if (b is DateTime) b = b.millisecondsSinceEpoch;
    return Comparable.compare(a as Comparable, b as Comparable);
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    bool filter(String id, Map<String, dynamic> data) {
      final v = _value(id, data, field);
      if (isEqualTo != null && v != isEqualTo) return false;
      if (isNotEqualTo != null && (v == null || v == isNotEqualTo)) {
        return false;
      }
      if (isLessThan != null && (v == null || _compare(v, isLessThan) >= 0)) {
        return false;
      }
      if (isLessThanOrEqualTo != null &&
          (v == null || _compare(v, isLessThanOrEqualTo) > 0)) {
        return false;
      }
      if (isGreaterThan != null &&
          (v == null || _compare(v, isGreaterThan) <= 0)) {
        return false;
      }
      if (isGreaterThanOrEqualTo != null &&
          (v == null || _compare(v, isGreaterThanOrEqualTo) < 0)) {
        return false;
      }
      if (arrayContains != null && !(v is List && v.contains(arrayContains))) {
        return false;
      }
      if (whereIn != null) {
        if (whereIn.length > 30) {
          throw ArgumentError('whereIn supports at most 30 values');
        }
        if (!whereIn.contains(v)) return false;
      }
      return true;
    }

    return _copy(filters: [..._filters, filter]);
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field,
          {bool descending = false}) =>
      _copy(orders: [..._orders, (field as String, descending)]);

  @override
  Query<Map<String, dynamic>> limit(int limit) => _copy(limit: limit);

  @override
  Query<Map<String, dynamic>> startAfterDocument(
          DocumentSnapshot documentSnapshot) =>
      _copy(startAfterId: documentSnapshot.id);

  List<MapEntry<String, Map<String, dynamic>>> _matches() {
    var entries = store
        .docsIn(path)
        .entries
        .where((e) => _filters.every((f) => f(e.key, e.value)))
        .toList();
    for (final (field, _) in _orders) {
      // Firestore drops documents missing an orderBy field.
      entries =
          entries.where((e) => _value(e.key, e.value, field) != null).toList();
    }
    if (_orders.isNotEmpty) {
      entries.sort((a, b) {
        for (final (field, descending) in _orders) {
          final c = _compare(
              _value(a.key, a.value, field), _value(b.key, b.value, field));
          if (c != 0) return descending ? -c : c;
        }
        return a.key.compareTo(b.key);
      });
    }
    if (_orders.isNotEmpty && (_startAt != null || _endAt != null)) {
      final field = _orders.first.$1;
      entries = entries.where((e) {
        final v = _value(e.key, e.value, field);
        if (_startAt != null && _compare(v, _startAt) < 0) return false;
        if (_endAt != null && _compare(v, _endAt) > 0) return false;
        return true;
      }).toList();
    }
    if (_startAfterId != null) {
      final i = entries.indexWhere((e) => e.key == _startAfterId);
      entries = i == -1 ? entries : entries.sublist(i + 1);
    }
    if (_limit != null && entries.length > _limit) {
      entries = entries.sublist(0, _limit);
    }
    return entries;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    store.queriesByCollection[path] =
        (store.queriesByCollection[path] ?? 0) + 1;
    final docs = [
      for (final e in _matches())
        FakeQueryDocumentSnapshot(
            FakeDocumentReference(store, '$path/${e.key}'), Map.of(e.value)),
    ];
    // An empty result still costs one read.
    store.documentsRead += docs.isEmpty ? 1 : docs.length;
    return FakeQuerySnapshot(docs);
  }

  @override
  AggregateQuery count() => _FakeAggregateQuery(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCollection extends FakeQuery
    implements CollectionReference<Map<String, dynamic>> {
  FakeCollection(super.store, super.path);

  @override
  String get id => path.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      FakeDocumentReference(store,
          '${this.path}/${path ?? 'auto_${store.docsIn(this.path).length}'}');
}

class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final FakeFirestore store;
  @override
  final String path;

  FakeDocumentReference(this.store, this.path);

  String get _collectionPath => path.substring(0, path.lastIndexOf('/'));

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      FakeCollection(store, '$path/$collectionPath');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    store.documentsRead++;
    final data = store.read(path);
    return FakeQueryDocumentSnapshot(this, data == null ? null : Map.of(data));
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    store._checkWrite(path);
    store.singleWrites++;
    _apply('set', data, options);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    store._checkWrite(path);
    store.singleWrites++;
    _apply('update', data.map((k, v) => MapEntry(k.toString(), v)), null);
  }

  @override
  Future<void> delete() async {
    store._checkWrite(path);
    store.singleWrites++;
    _apply('delete', const {}, null);
  }

  void _apply(String op, Map<String, dynamic> data, SetOptions? options) {
    final docs = store.docsIn(_collectionPath);
    switch (op) {
      case 'delete':
        docs.remove(id);
      case 'update':
        if (!docs.containsKey(id)) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
        }
        docs[id] = {...docs[id]!, ...data};
      default:
        docs[id] =
            options?.merge == true ? {...?docs[id], ...data} : Map.of(data);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FakeDocumentReference && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  @override
  final FakeDocumentReference reference;
  final Map<String, dynamic>? _data;

  FakeQueryDocumentSnapshot(this.reference, this._data);

  @override
  String get id => reference.id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic> data() => _data ?? {};

  @override
  dynamic get(Object field) => FakeQuery._value(id, data(), field);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  FakeQuerySnapshot(this.docs);

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAggregateQuery implements AggregateQuery {
  final FakeQuery _source;
  _FakeAggregateQuery(this._source);

  @override
  Future<AggregateQuerySnapshot> get(
      {AggregateSource source = AggregateSource.server}) async {
    _source.store.aggregateQueries++;
    final n = _source._matches().length;
    // Billed as one read per 1,000 index entries (minimum one).
    _source.store.documentsRead += n == 0 ? 1 : (n + 999) ~/ 1000;
    return _FakeAggregateSnapshot(n);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAggregateSnapshot implements AggregateQuerySnapshot {
  @override
  final int count;
  _FakeAggregateSnapshot(this.count);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWriteBatch implements WriteBatch {
  final FakeFirestore store;
  final List<
      (
        FakeDocumentReference ref,
        String op,
        Map<String, dynamic> data,
        SetOptions?
      )> _ops = [];

  _FakeWriteBatch(this.store);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _ops.add((
        document as FakeDocumentReference,
        'set',
        Map<String, dynamic>.from(data as Map),
        options
      ));

  @override
  void update(DocumentReference document, Map<Object, Object?> data) =>
      _ops.add((
        document as FakeDocumentReference,
        'update',
        data.map((k, v) => MapEntry(k.toString(), v)),
        null
      ));

  @override
  void delete(DocumentReference document) =>
      _ops.add((document as FakeDocumentReference, 'delete', const {}, null));

  @override
  Future<void> commit() async {
    if (_ops.length > 500) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'invalid-argument');
    }
    // All or nothing, like Firestore.
    for (final (ref, _, _, _) in _ops) {
      store._checkWrite(ref.path);
    }
    for (final (ref, op, _, _) in _ops) {
      if (op == 'update' && store.read(ref.path) == null) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
    }
    for (final (ref, op, data, options) in _ops) {
      ref._apply(op, data, options);
    }
    store.committedBatchSizes.add(_ops.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

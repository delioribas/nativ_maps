// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

import 'dart:collection';

/// Fixed-capacity cache with expiry, in least-recently-used order.
///
/// It exists because the three most-called operations are also the ones most
/// often repeated verbatim: an autocomplete resends the same query when the
/// user deletes a letter and types it again; opening and closing a detail
/// card requests the same route twice. Every repetition is a billed request.
///
/// It relies on a Dart `Map` keeping insertion order: reading a key
/// reinserts it at the end, so the first key in the map is always the least
/// recently used.
class LruCache<K, V> {
  /// Creates a cache of up to [capacity] entries, each one valid for [ttl].
  LruCache(this.capacity, {this.ttl}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'debe ser positiva');
    }
  }

  /// Maximum number of entries. Once reached, the least used one is dropped.
  final int capacity;

  /// How long an entry lives. `null` means it never expires.
  final Duration? ttl;

  final LinkedHashMap<K, _CacheEntry<V>> _entries =
      LinkedHashMap<K, _CacheEntry<V>>();

  /// The value for [key], or `null` if it is missing or has expired.
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.expiresAt != null && DateTime.now().isAfter(entry.expiresAt!)) {
      return null;
    }
    _entries[key] = entry; // promotion: back to the end
    return entry.value;
  }

  /// Stores [value] under [key], dropping the oldest entry if needed.
  void set(K key, V value) {
    _entries.remove(key);
    if (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _CacheEntry<V>(
      value,
      ttl == null ? null : DateTime.now().add(ttl!),
    );
  }

  /// Forgets the entry for [key], if there was one.
  void invalidate(K key) => _entries.remove(key);

  /// Empties the cache. Done when the language or the session changes: the
  /// stored results are in the previous language.
  void clear() => _entries.clear();

  /// How many entries are stored, expired ones included.
  int get length => _entries.length;

  /// Is it empty?
  bool get isEmpty => _entries.isEmpty;
}

class _CacheEntry<V> {
  _CacheEntry(this.value, this.expiresAt);

  final V value;
  final DateTime? expiresAt;
}

// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'dart:collection';

/// Caché de capacidad fija con caducidad, en orden de uso menos reciente.
///
/// Existe porque las tres operaciones más llamadas son también las que más se
/// repiten idénticas: un autocompletado reenvía la misma consulta cuando el
/// usuario borra una letra y la vuelve a escribir; abrir y cerrar una ficha
/// pide la misma ruta dos veces. Cada repetición es una petición facturada.
///
/// Aprovecha que un `Map` de Dart conserva el orden de inserción: leer una
/// clave la reinserta al final, así que la primera clave del mapa es siempre
/// la menos usada recientemente.
class LruCache<K, V> {
  /// Crea una caché de hasta [capacity] entradas, cada una válida [ttl].
  LruCache(this.capacity, {this.ttl}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'debe ser positiva');
    }
  }

  /// Número máximo de entradas. Al llegar, se descarta la menos usada.
  final int capacity;

  /// Cuánto vive una entrada. `null` significa que no caduca.
  final Duration? ttl;

  final LinkedHashMap<K, _CacheEntry<V>> _entries =
      LinkedHashMap<K, _CacheEntry<V>>();

  /// El valor de [key], o `null` si no está o ya caducó.
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (entry.expiresAt != null && DateTime.now().isAfter(entry.expiresAt!)) {
      return null;
    }
    _entries[key] = entry; // promoción: vuelve al final
    return entry.value;
  }

  /// Guarda [value] bajo [key], descartando la entrada más antigua si hace
  /// falta.
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

  /// Olvida la entrada de [key], si existía.
  void invalidate(K key) => _entries.remove(key);

  /// Vacía la caché. Se hace al cambiar de idioma o de sesión: los resultados
  /// guardados están en el idioma anterior.
  void clear() => _entries.clear();

  /// Cuántas entradas hay guardadas, caducadas incluidas.
  int get length => _entries.length;

  /// ¿Está vacía?
  bool get isEmpty => _entries.isEmpty;
}

class _CacheEntry<V> {
  _CacheEntry(this.value, this.expiresAt);

  final V value;
  final DateTime? expiresAt;
}

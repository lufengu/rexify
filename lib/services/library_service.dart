import 'package:hive/hive.dart';

/// Servicio simple para favoritos, historial y etiquetas.
/// Guarda en una Box de Hive: 'rexify_library'.
class LibraryService {
  static final LibraryService instance = LibraryService._internal();
  LibraryService._internal();

  Box? _box;

  Future<void> _ensureBox() async {
    _box ??= await Hive.openBox('rexify_library');
  }

  // -------- Favoritos --------
  Future<bool> toggleFavorite(String path) async {
    await _ensureBox();
    final favs = List<String>.from(_box!.get('favorites', defaultValue: <String>[]) as List);
    final exists = favs.contains(path);
    if (exists) {
      favs.remove(path);
    } else {
      favs.add(path);
    }
    await _box!.put('favorites', favs);
    return !exists;
  }

  Future<bool> isFavorite(String path) async {
    await _ensureBox();
    final favs = List<String>.from(_box!.get('favorites', defaultValue: <String>[]) as List);
    return favs.contains(path);
  }

  Future<List<String>> favorites() async {
    await _ensureBox();
    return List<String>.from(_box!.get('favorites', defaultValue: <String>[]) as List);
  }

  // -------- Historial --------
  Future<void> addHistory(String path, {String? title, String? artist}) async {
    await _ensureBox();
    final hist = List<Map>.from(_box!.get('history', defaultValue: <Map>[]) as List);
    hist.insert(0, {
      'path': path,
      'title': title,
      'artist': artist,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    // mantener tamaño razonable
    if (hist.length > 200) hist.removeRange(200, hist.length);
    await _box!.put('history', hist);
  }

  Future<List<Map<String, dynamic>>> recent({int limit = 30}) async {
    await _ensureBox();
    final hist = List<Map>.from(_box!.get('history', defaultValue: <Map>[]) as List);
    return hist.take(limit).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // -------- Etiquetas --------
  Future<List<String>> getTags(String path) async {
    await _ensureBox();
    final map = Map<String, dynamic>.from(_box!.get('tags', defaultValue: <String, dynamic>{}) as Map);
    final list = map[path];
    if (list is List) {
      return List<String>.from(list);
    }
    return <String>[];
  }

  Future<void> setTags(String path, List<String> tags) async {
    await _ensureBox();
    final map = Map<String, dynamic>.from(_box!.get('tags', defaultValue: <String, dynamic>{}) as Map);
    map[path] = tags;
    await _box!.put('tags', map);
  }
}

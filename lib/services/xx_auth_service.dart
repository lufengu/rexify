import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para manejo de verificación de edad y acceso privado del Dashboard XX.
class XXAuthService {
  // Llaves de almacenamiento
  static const _kBirthdate = 'xx_birthdate'; // ISO8601
  static const _kAgeVerified = 'xx_age_verified';
  static const _kPasswordHash = 'xx_password_hash';
  // Eliminamos persistencia de "recordar" para que al reiniciar la app siempre pida contraseña.

  static final XXAuthService _instance = XXAuthService._internal();
  factory XXAuthService() => _instance;
  XXAuthService._internal();

  // Almacenamiento seguro solo para el hash de contraseña
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // Flag de sesión (memoria) para saltar el prompt mientras la app siga abierta.
  bool _sessionRemember = false;

  /// Devuelve la fecha de nacimiento si está guardada.
  Future<DateTime?> getBirthdate() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_kBirthdate);
    if (iso == null) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  /// Guarda la fecha y marca verificado si cumple 18+.
  Future<bool> setBirthdate(DateTime dob) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBirthdate, dob.toIso8601String());
    final ok = isOfAge(dob);
    await prefs.setBool(_kAgeVerified, ok);
    return ok;
  }

  /// ¿Ya pasó verificación de edad (y cumple)?
  Future<bool> isAgeVerified() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_kAgeVerified) ?? false;
    if (!flag) return false;
    // Validación defensiva: recalcular por si el dato fuera inconsistente
    final dob = await getBirthdate();
    if (dob == null) return false;
    return isOfAge(dob);
  }

  /// Valida si la fecha es 18+.
  bool isOfAge(DateTime dob, {DateTime? now}) {
    final today = now ?? DateTime.now();
    int years = today.year - dob.year;
    final hasHadBirthday =
        (today.month > dob.month) || (today.month == dob.month && today.day >= dob.day);
    if (!hasHadBirthday) years -= 1;
    return years >= 18;
  }

  /// Calcula hash SHA-256 del password. (Se podría añadir salt/pepper si fuera necesario.)
  @protected
  String _hash(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// ¿Existe contraseña configurada?
  Future<bool> hasPassword() async {
    final h = await _secure.read(key: _kPasswordHash);
    return (h != null && h.isNotEmpty);
  }

  /// Define una nueva contraseña y la persiste como hash.
  Future<void> setPassword(String password) async {
    final hash = _hash(password);
    await _secure.write(key: _kPasswordHash, value: hash);
    // No se persiste "remember" aquí.
  }

  /// Verifica la contraseña ingresada contra el hash almacenado.
  Future<bool> verifyPassword(String input) async {
    final stored = await _secure.read(key: _kPasswordHash);
    if (stored == null) return false;
    final inputHash = _hash(input);
  return stored == inputHash;
  }

  /// Define el flag de sesión (no se persiste). Si es true, se omitirá el prompt mientras la app siga viva.
  void setSessionRemember(bool remember) {
    _sessionRemember = remember;
  }

  /// ¿Se debe omitir el prompt en esta sesión?
  bool shouldSkipPassword() {
    return _sessionRemember;
  }

  /// Restablece flujo (olvido contraseña): borra hash, flags y fecha.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBirthdate);
    await prefs.remove(_kAgeVerified);
    _sessionRemember = false;
    await _secure.delete(key: _kPasswordHash);
  }
}

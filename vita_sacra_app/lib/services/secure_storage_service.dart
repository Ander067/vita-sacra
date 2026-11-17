import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Servicio encargado del almacenamiento seguro.
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyCorreo = 'saved_email';
  static const String _keyBiometricEnabled = 'biometric_enabled';
  static const String _keyBiometricCredential = 'biometric_credential';
  static const String _keyDeviceId = 'biometric_device_id';

  // Guardar el correo del usuario.
  static Future<void> guardarCorreo(String correo) async {
    await _storage.write(key: _keyCorreo, value: correo);
  }

  // Recuperar el correo guardado.
  static Future<String?> obtenerCorreo() async {
    return await _storage.read(key: _keyCorreo);
  }

  // Guardar el estado de la biometria.
  static Future<void> guardarBiometriaHabilitada(bool habilitada) async {
    await _storage.write(
      key: _keyBiometricEnabled,
      value: habilitada.toString(),
    );
  }

  // Consultar si la biometria esta habilitada.
  static Future<bool> esBiometriaHabilitada() async {
    final String? valor = await _storage.read(key: _keyBiometricEnabled);

    return valor == 'true';
  }

  // Guardar la credencial biometrica del dispositivo.
  static Future<void> guardarCredencialBiometrica(String credencial) async {
    await _storage.write(key: _keyBiometricCredential, value: credencial);
  }

  // Recuperar la credencial biometrica.
  static Future<String?> obtenerCredencialBiometrica() async {
    return await _storage.read(key: _keyBiometricCredential);
  }

  // Generar y recuperar un identificador unico del dispositivo.
  static Future<String> obtenerIdDispositivo() async {
    String? idDispositivo = await _storage.read(key: _keyDeviceId);

    if (idDispositivo == null || idDispositivo.isEmpty) {
      final Random random = Random.secure();

      final List<int> valores = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      );

      idDispositivo = base64UrlEncode(valores);

      await _storage.write(key: _keyDeviceId, value: idDispositivo);
    }

    return idDispositivo;
  }

  // Desactivar el acceso biometrico.
  static Future<void> desactivarBiometria() async {
    await _storage.delete(key: _keyBiometricEnabled);
    await _storage.delete(key: _keyBiometricCredential);
  }

  // Limpiar los datos guardados del acceso.
  static Future<void> limpiarCredenciales() async {
    await _storage.delete(key: _keyCorreo);
    await _storage.delete(key: _keyBiometricEnabled);
    await _storage.delete(key: _keyBiometricCredential);
    await _storage.delete(key: _keyDeviceId);
  }
}

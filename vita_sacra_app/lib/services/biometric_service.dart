import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  // Verificar si el dispositivo tiene biometria registrada.
  static Future<bool> puedeAutenticarse() async {
    try {
      final bool soportaBiometria = await _auth.canCheckBiometrics;
      final bool dispositivoSoportado = await _auth.isDeviceSupported();

      if (!soportaBiometria || !dispositivoSoportado) {
        return false;
      }

      final List<BiometricType> disponibles = await _auth
          .getAvailableBiometrics();

      return disponibles.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  // Obtener los tipos de biometria disponibles.
  static Future<List<BiometricType>> obtenerBiometriasDisponibles() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  // Solicitar autenticacion mediante huella o reconocimiento biometrico.
  static Future<bool> autenticarUsuario({
    String mensaje = 'Autenticate para continuar en Vita Sacra',
  }) async {
    try {
      final bool disponible = await puedeAutenticarse();

      if (!disponible) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: mensaje,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

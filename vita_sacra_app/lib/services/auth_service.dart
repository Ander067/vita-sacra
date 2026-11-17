import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/usuario.dart';
import 'api_service.dart';
import 'secure_storage_service.dart';

class AuthService {
  static const String rutaLogin = '/autenticacion/login';
  static const String rutaRegistro = '/usuarios/registro';
  static const String rutaVerificarCorreo = '/usuarios/verificar-email';
  static const String rutaReenviarVerificacion =
      '/usuarios/reenviar-verificacion';
  static const String rutaSolicitarRecuperacion =
      '/usuarios/solicitar-recuperacion';
  static const String rutaRestablecerContrasena =
      '/usuarios/restablecer-contrasena';
  static const String rutaCambiarContrasena = '/usuarios/mi-contrasena';
  static const String rutaPerfil = '/usuarios/mi-perfil';
  static const String rutaFotoPerfil = '/usuarios/mi-perfil/foto';
  static const String rutaRefresh = '/autenticacion/refresh';
  static const String rutaLogout = '/autenticacion/logout';
  static const String rutaRegistroBiometrico =
      '/autenticacion/biometria/registrar';
  static const String rutaLoginBiometrico = '/autenticacion/biometria/login';
  static const String rutaCatalogoRoles = '/roles/';
  static const String rutaMisRoles = '/roles/mis-roles';
  static const String rutaSolicitudesRol = '/roles/solicitudes';
  static const String rutaMisSolicitudesRol = '/roles/mis-solicitudes';

  static const String _claveToken = 'vita_sacra_token';
  static const String _claveRefreshToken = 'vita_sacra_refresh_token';

  final ApiService _api;
  final FlutterSecureStorage _almacenamiento;

  Future<void>? _refreshEnCurso;

  AuthService({ApiService? api, FlutterSecureStorage? almacenamiento})
    : _api = api ?? ApiService(),
      _almacenamiento = almacenamiento ?? const FlutterSecureStorage();

  Future<dynamic> registrar({
    required String nombre,
    required String correo,
    required String contrasena,
  }) async {
    if (nombre.trim().isEmpty || correo.trim().isEmpty || contrasena.isEmpty) {
      throw const ApiException('Todos los campos son obligatorios.');
    }

    return _api.post(
      rutaRegistro,
      datos: {
        'nom_usr': nombre.trim(),
        'mail': correo.trim().toLowerCase(),
        'contrasena': contrasena,
      },
    );
  }

  Future<String> verificarCorreo({required String token}) async {
    final String tokenLimpio = token.trim();
    if (tokenLimpio.isEmpty) {
      throw const ApiException('Ingresa el código de verificación.');
    }

    final dynamic respuesta = await _api.post(
      rutaVerificarCorreo,
      datos: {'token': tokenLimpio},
    );
    return _leerMensajeRespuesta(respuesta);
  }

  Future<String> reenviarVerificacion({required String correo}) async {
    final String correoLimpio = correo.trim().toLowerCase();
    if (correoLimpio.isEmpty) {
      throw const ApiException('Ingresa tu correo electrónico.');
    }

    final dynamic respuesta = await _api.post(
      rutaReenviarVerificacion,
      datos: {'mail': correoLimpio},
    );
    return _leerMensajeRespuesta(respuesta);
  }

  Future<String> solicitarRecuperacion({required String correo}) async {
    final String correoLimpio = correo.trim().toLowerCase();
    if (correoLimpio.isEmpty) {
      throw const ApiException('Ingresa tu correo electrónico.');
    }

    final dynamic respuesta = await _api.post(
      rutaSolicitarRecuperacion,
      datos: {'mail': correoLimpio},
    );
    return _leerMensajeRespuesta(respuesta);
  }

  Future<String> restablecerContrasena({
    required String token,
    required String contrasenaNueva,
  }) async {
    final String tokenLimpio = token.trim();

    if (tokenLimpio.length < 30 || tokenLimpio.length > 256) {
      throw const ApiException('El código de recuperación no es válido.');
    }

    if (contrasenaNueva.length < 8 || contrasenaNueva.length > 128) {
      throw const ApiException(
        'La contraseña debe tener entre 8 y 128 caracteres.',
      );
    }

    final dynamic respuesta = await _api.post(
      rutaRestablecerContrasena,
      datos: {'token': tokenLimpio, 'contrasena_nueva': contrasenaNueva},
    );
    return _leerMensajeRespuesta(respuesta);
  }

  Future<String> cambiarContrasena({
    required String contrasenaActual,
    required String contrasenaNueva,
  }) async {
    if (contrasenaActual.isEmpty) {
      throw const ApiException('Ingresa tu contraseña actual.');
    }
    if (contrasenaNueva.length < 8 || contrasenaNueva.length > 128) {
      throw const ApiException(
        'La contraseña nueva debe tener entre 8 y 128 caracteres.',
      );
    }
    if (contrasenaActual == contrasenaNueva) {
      throw const ApiException(
        'La contraseña nueva debe ser diferente a la actual.',
      );
    }

    final String token = await _tokenRequerido();
    final dynamic respuesta = await _api.put(
      rutaCambiarContrasena,
      token: token,
      datos: {
        'contrasena_actual': contrasenaActual,
        'contrasena_nueva': contrasenaNueva,
      },
    );

    final String mensaje = _leerMensajeRespuesta(respuesta);
    await _eliminarTokens();
    return mensaje;
  }

  String _leerMensajeRespuesta(dynamic respuesta) {
    if (respuesta is Map) {
      final dynamic mensaje = respuesta['mensaje'];
      if (mensaje is String && mensaje.trim().isNotEmpty) {
        return mensaje.trim();
      }
    }
    throw const ApiException('El servidor devolvió una respuesta no válida.');
  }

  Future<void> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    if (correo.trim().isEmpty || contrasena.isEmpty) {
      throw const ApiException('Ingresa tu correo y contraseña.');
    }

    final dynamic respuesta = await _api.post(
      rutaLogin,
      datos: {'mail': correo.trim().toLowerCase(), 'contrasena': contrasena},
    );
    await _guardarTokenRespuesta(respuesta);
  }

  Future<String> registrarBiometria({required String idDispositivo}) async {
    final String token = await _tokenRequerido();

    final dynamic respuesta = await _api.post(
      '/autenticacion/biometria/registrar',
      token: token,
      datos: {'id_dispositivo': idDispositivo},
    );

    if (respuesta is! Map || respuesta['credencial'] is! String) {
      throw const ApiException(
        'El servidor no devolvió una credencial biométrica válida.',
      );
    }

    final String credencial = (respuesta['credencial'] as String).trim();
    if (credencial.isEmpty) {
      throw const ApiException(
        'El servidor no devolvió una credencial biométrica válida.',
      );
    }
    return credencial;
  }

  Future<void> iniciarSesionBiometrica({
    required String correo,
    required String idDispositivo,
    required String credencial,
  }) async {
    if (correo.trim().isEmpty ||
        idDispositivo.trim().isEmpty ||
        credencial.trim().isEmpty) {
      throw const ApiException(
        'No se encontraron los datos del acceso biométrico.',
      );
    }

    final dynamic respuesta = await _api.post(
      rutaLoginBiometrico,
      datos: {
        'mail': correo.trim().toLowerCase(),
        'id_dispositivo': idDispositivo,
        'credencial': credencial,
      },
    );
    await _guardarTokenRespuesta(respuesta);
  }

  Future<void> revocarBiometria({required String idDispositivo}) async {
    final String token = await _tokenRequerido();
    await _api.delete(
      '/autenticacion/biometria/${Uri.encodeComponent(idDispositivo)}',
      token: token,
    );
  }

  Future<void> _guardarTokenRespuesta(dynamic respuesta) async {
    if (respuesta is! Map) {
      throw const ApiException('La respuesta de autenticación no es válida.');
    }

    final dynamic token = respuesta['access_token'];
    final dynamic tipoToken = respuesta['token_type'];
    final dynamic refreshToken = respuesta['refresh_token'];

    if (token is! String || token.trim().isEmpty) {
      throw const ApiException('El servidor no devolvió un token válido.');
    }
    if (tipoToken is! String || tipoToken.toLowerCase() != 'bearer') {
      throw const ApiException('El tipo de token devuelto no es válido.');
    }
    if (refreshToken is! String || refreshToken.trim().isEmpty) {
      throw const ApiException(
        'El servidor no devolvió un refresh token válido.',
      );
    }

    await _almacenamiento.write(key: _claveToken, value: token.trim());
    await _almacenamiento.write(
      key: _claveRefreshToken,
      value: refreshToken.trim(),
    );
  }

  Future<String?> obtenerToken() async {
    String? token = await _almacenamiento.read(key: _claveToken);
    final String? refreshToken = await _almacenamiento.read(
      key: _claveRefreshToken,
    );

    if ((token == null || token.trim().isEmpty) &&
        (refreshToken == null || refreshToken.trim().isEmpty)) {
      return null;
    }

    if (token == null || token.trim().isEmpty || _tokenCercaDeExpirar(token)) {
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        await _eliminarTokens();
        return null;
      }

      await _renovarToken();
      token = await _almacenamiento.read(key: _claveToken);
    }

    if (token == null || token.trim().isEmpty) {
      return null;
    }
    return token.trim();
  }

  Future<String> _tokenRequerido() async {
    final String? token = await obtenerToken();
    if (token == null) {
      throw const ApiException(
        'Tu sesión expiró. Inicia sesión nuevamente.',
        codigoEstado: 401,
      );
    }
    return token;
  }

  Future<bool> tieneToken() async => await obtenerToken() != null;

  Future<Usuario> obtenerPerfil() async {
    final String token = await _tokenRequerido();

    try {
      final dynamic respuesta = await _api.get(rutaPerfil, token: token);
      if (respuesta is! Map<String, dynamic>) {
        throw const ApiException('El servidor devolvió un perfil no válido.');
      }
      return Usuario.fromJson(respuesta);
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    } on FormatException {
      throw const ApiException(
        'El perfil devuelto por el servidor no es válido.',
      );
    }
  }

  Future<Usuario> actualizarPerfil({
    required String nombre,
    String? direccion,
  }) async {
    final String nombreLimpio = nombre.trim();
    final String? direccionLimpia = direccion?.trim();

    if (nombreLimpio.length < 3 || nombreLimpio.length > 100) {
      throw const ApiException(
        'El nombre debe tener entre 3 y 100 caracteres.',
      );
    }
    if ((direccionLimpia?.length ?? 0) > 255) {
      throw const ApiException(
        'La dirección no puede superar los 255 caracteres.',
      );
    }

    final String token = await _tokenRequerido();

    try {
      final dynamic respuesta = await _api.put(
        rutaPerfil,
        token: token,
        datos: {
          'nom_usr': nombreLimpio,
          'dir_usr': direccionLimpia == null || direccionLimpia.isEmpty
              ? null
              : direccionLimpia,
        },
      );

      if (respuesta is! Map<String, dynamic> ||
          respuesta['usuario'] is! Map<String, dynamic>) {
        throw const ApiException(
          'El servidor no devolvió los datos actualizados del perfil.',
        );
      }

      return Usuario.fromJson(respuesta['usuario'] as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    } on FormatException {
      throw const ApiException(
        'Los datos actualizados del perfil no son válidos.',
      );
    }
  }

  Future<String> subirFotoPerfil({required String rutaArchivo}) async {
    final String token = await _tokenRequerido();

    try {
      final dynamic respuesta = await _api.putArchivo(
        rutaFotoPerfil,
        campoArchivo: 'archivo',
        rutaArchivo: rutaArchivo,
        token: token,
      );

      if (respuesta is! Map ||
          respuesta['foto_perfil_url'] is! String ||
          (respuesta['foto_perfil_url'] as String).trim().isEmpty) {
        throw const ApiException('El servidor no devolvió la ruta de la foto.');
      }

      return (respuesta['foto_perfil_url'] as String).trim();
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  Future<void> eliminarFotoPerfil() async {
    final String token = await _tokenRequerido();
    try {
      await _api.delete(rutaFotoPerfil, token: token);
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> obtenerCatalogoRoles() async {
    final dynamic respuesta = await _api.get(rutaCatalogoRoles);
    return _leerListaMapas(respuesta, 'El catálogo de roles no es válido.');
  }

  Future<Map<String, dynamic>> obtenerMisRoles() async {
    final String token = await _tokenRequerido();
    try {
      final dynamic respuesta = await _api.get(rutaMisRoles, token: token);
      if (respuesta is! Map<String, dynamic>) {
        throw const ApiException('La respuesta de roles no es válida.');
      }
      return respuesta;
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> obtenerMisSolicitudesRol() async {
    final String token = await _tokenRequerido();
    try {
      final dynamic respuesta = await _api.get(
        rutaMisSolicitudesRol,
        token: token,
      );
      return _leerListaMapas(
        respuesta,
        'La respuesta de solicitudes de rol no es válida.',
      );
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> solicitarRolAdicional({
    required int rolId,
    required String motivo,
  }) async {
    final String motivoLimpio = motivo.trim();

    if (rolId <= 0) {
      throw const ApiException('Selecciona el rol que deseas solicitar.');
    }
    if (motivoLimpio.length < 10) {
      throw const ApiException('El motivo debe tener al menos 10 caracteres.');
    }

    final String token = await _tokenRequerido();

    try {
      final dynamic respuesta = await _api.post(
        rutaSolicitudesRol,
        token: token,
        datos: {'rol_id': rolId, 'motivo': motivoLimpio},
      );

      if (respuesta is! Map<String, dynamic>) {
        throw const ApiException(
          'El servidor devolvió una respuesta de solicitud no válida.',
        );
      }
      return respuesta;
    } on ApiException catch (error) {
      if (error.codigoEstado == 401) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  List<Map<String, dynamic>> _leerListaMapas(
    dynamic respuesta,
    String mensajeError,
  ) {
    if (respuesta is! List) {
      throw ApiException(mensajeError);
    }

    return respuesta.map((elemento) {
      if (elemento is! Map) {
        throw ApiException(mensajeError);
      }
      return Map<String, dynamic>.from(elemento);
    }).toList();
  }

  Future<bool> sesionValida() async {
    try {
      if (!await tieneToken()) {
        return false;
      }
      await obtenerPerfil();
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<bool> cerrarSesion() async {
    bool operacionesRemotasCompletas = true;

    try {
      final String idDispositivo =
          await SecureStorageService.obtenerIdDispositivo();

      try {
        await revocarBiometria(idDispositivo: idDispositivo);
      } on ApiException {
        operacionesRemotasCompletas = false;
      }

      try {
        final String? token = await obtenerToken();
        if (token != null) {
          await _api.post(rutaLogout, token: token);
        } else {
          operacionesRemotasCompletas = false;
        }
      } on ApiException catch (error) {
        if (error.codigoEstado != 401) {
          operacionesRemotasCompletas = false;
        }
      }

      return operacionesRemotasCompletas;
    } finally {
      try {
        await SecureStorageService.desactivarBiometria();
      } finally {
        await _eliminarTokens();
      }
    }
  }

  Future<void> _renovarToken() async {
    final Future<void>? refreshActivo = _refreshEnCurso;
    if (refreshActivo != null) {
      await refreshActivo;
      return;
    }

    final Future<void> refresh = _hacerRefresh();
    _refreshEnCurso = refresh;

    try {
      await refresh;
    } finally {
      if (identical(_refreshEnCurso, refresh)) {
        _refreshEnCurso = null;
      }
    }
  }

  Future<void> _hacerRefresh() async {
    final String? refreshToken = await _almacenamiento.read(
      key: _claveRefreshToken,
    );

    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await _eliminarTokens();
      throw const ApiException(
        'La sesión expiró. Inicia sesión nuevamente.',
        codigoEstado: 401,
      );
    }

    try {
      final dynamic respuesta = await _api.post(
        rutaRefresh,
        datos: {'refresh_token': refreshToken.trim()},
      );
      await _guardarTokenRespuesta(respuesta);
    } on ApiException catch (error) {
      if (error.codigoEstado == 401 || error.codigoEstado == 403) {
        await _eliminarTokens();
      }
      rethrow;
    }
  }

  bool _tokenCercaDeExpirar(String token) {
    final List<String> partes = token.split('.');
    if (partes.length != 3) {
      return true;
    }

    try {
      final String payload = utf8.decode(
        base64Url.decode(base64Url.normalize(partes[1])),
      );
      final dynamic datos = jsonDecode(payload);
      if (datos is! Map || datos['exp'] is! num) {
        return true;
      }

      final int expiraEnSegundos = (datos['exp'] as num).toInt();
      final DateTime expiraEn = DateTime.fromMillisecondsSinceEpoch(
        expiraEnSegundos * 1000,
        isUtc: true,
      );

      return expiraEn.isBefore(
        DateTime.now().toUtc().add(const Duration(seconds: 60)),
      );
    } on FormatException {
      return true;
    } on ArgumentError {
      return true;
    }
  }

  Future<void> _eliminarTokens() async {
    await _almacenamiento.delete(key: _claveToken);
    await _almacenamiento.delete(key: _claveRefreshToken);
  }

  void cerrarServicio() {
    _api.cerrar();
  }
}

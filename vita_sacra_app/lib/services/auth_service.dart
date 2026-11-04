import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/usuario.dart';
import 'api_service.dart';

// Servicio encargado de la autenticacion.
class AuthService {
  // Rutas que deben coincidir con FastAPI.
  static const String rutaLogin = '/autenticacion/login';
  static const String rutaRegistro = '/usuarios/registro';
  static const String rutaPerfil = '/usuarios/mi-perfil';

  // Clave utilizada para guardar el token.
  static const String _claveToken = 'vita_sacra_token';

  // Servicio de comunicacion con FastAPI.
  final ApiService _api;

  // Almacenamiento seguro del dispositivo.
  final FlutterSecureStorage _almacenamiento;

  // Constructor del servicio.
  AuthService({ApiService? api, FlutterSecureStorage? almacenamiento})
    : _api = api ?? ApiService(),
      _almacenamiento = almacenamiento ?? const FlutterSecureStorage();

  // Registrar un nuevo usuario.
  Future<dynamic> registrar({
    required String nombre,
    required String correo,
    required String contrasena,
  }) async {
    // Validar los datos obligatorios.
    if (nombre.trim().isEmpty || correo.trim().isEmpty || contrasena.isEmpty) {
      throw const ApiException('Todos los campos son obligatorios.');
    }

    // Enviar los datos con los nombres esperados por FastAPI.
    return _api.post(
      rutaRegistro,
      datos: {
        'nom_usr': nombre.trim(),
        'mail': correo.trim().toLowerCase(),
        'contrasena': contrasena,
      },
    );
  }

  // Iniciar sesion mediante FastAPI.
  Future<void> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    // Validar las credenciales obligatorias.
    if (correo.trim().isEmpty || contrasena.isEmpty) {
      throw const ApiException('Ingresa tu correo y contrasena.');
    }

    // Solicitar el token mediante JSON.
    final dynamic respuesta = await _api.post(
      rutaLogin,
      datos: {'mail': correo.trim().toLowerCase(), 'contrasena': contrasena},
    );

    // Comprobar la estructura de la respuesta.
    if (respuesta is! Map) {
      throw const ApiException('La respuesta de autenticacion no es valida.');
    }

    final dynamic token = respuesta['access_token'];
    final dynamic tipoToken = respuesta['token_type'];

    // Verificar que el servidor devuelva un JWT valido.
    if (token is! String || token.trim().isEmpty) {
      throw const ApiException('El servidor no devolvio un token valido.');
    }

    // Comprobar que el esquema de autenticacion sea Bearer.
    if (tipoToken is! String || tipoToken.toLowerCase() != 'bearer') {
      throw const ApiException(
        'El servidor devolvio un tipo de token no valido.',
      );
    }

    // Guardar el token en el almacenamiento seguro.
    await _almacenamiento.write(key: _claveToken, value: token.trim());
  }

  // Recuperar el token almacenado.
  Future<String?> obtenerToken() async {
    final String? token = await _almacenamiento.read(key: _claveToken);

    // Evitar devolver tokens vacios.
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  // Comprobar si existe un token almacenado.
  Future<bool> tieneToken() async {
    final String? token = await obtenerToken();

    return token != null;
  }

  // Consultar el perfil del usuario autenticado.
  Future<Usuario> obtenerPerfil() async {
    final String? token = await obtenerToken();

    // Comprobar que exista una sesion almacenada.
    if (token == null) {
      throw const ApiException('Debes iniciar sesion.');
    }

    try {
      // Consultar el perfil mediante el token JWT.
      final dynamic respuesta = await _api.get(rutaPerfil, token: token);

      // Validar la estructura de los datos recibidos.
      if (respuesta is! Map<String, dynamic>) {
        throw const ApiException('El servidor devolvio un perfil no valido.');
      }

      // Convertir el JSON recibido al modelo Usuario.
      return Usuario.fromJson(respuesta);
    } on ApiException catch (error) {
      // Eliminar el token si el servidor rechaza la sesion.
      if (error.codigoEstado == 401) {
        await cerrarSesion();
      }

      rethrow;
    }
  }

  // Comprobar la vigencia de la sesion con FastAPI.
  Future<bool> sesionValida() async {
    // Verificar que exista un token.
    if (!await tieneToken()) {
      return false;
    }

    try {
      // Consultar el perfil para validar la sesion.
      await obtenerPerfil();

      return true;
    } on ApiException {
      return false;
    }
  }

  // Cerrar la sesion local.
  Future<void> cerrarSesion() async {
    await _almacenamiento.delete(key: _claveToken);
  }

  // Liberar el cliente HTTP.
  void cerrarServicio() {
    _api.cerrar();
  }
}

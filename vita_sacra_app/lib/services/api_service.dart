import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiException implements Exception {
  final String mensaje;
  final int? codigoEstado;

  const ApiException(this.mensaje, {this.codigoEstado});

  @override
  String toString() => mensaje;
}

class ApiService {
  final http.Client _cliente;

  ApiService({http.Client? cliente}) : _cliente = cliente ?? http.Client();

  Uri _crearUri(String ruta, {Map<String, String>? parametros}) {
    final Uri uri = ApiConfig.crearUri(ruta);

    if (parametros == null || parametros.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...parametros},
    );
  }

  Map<String, String> _crearHeaders({String? token, bool formulario = false}) {
    final Map<String, String> headers = formulario
        ? ApiConfig.headersFormulario
        : ApiConfig.headersJson;

    final String? tokenLimpio = token?.trim();

    if (tokenLimpio != null && tokenLimpio.isNotEmpty) {
      return {...headers, 'Authorization': 'Bearer $tokenLimpio'};
    }

    return headers;
  }

  dynamic _procesarRespuesta(http.Response respuesta) {
    dynamic datos;

    if (respuesta.bodyBytes.isNotEmpty) {
      try {
        datos = jsonDecode(utf8.decode(respuesta.bodyBytes));
      } on FormatException {
        throw ApiException(
          'El servidor devolvió una respuesta no válida.',
          codigoEstado: respuesta.statusCode,
        );
      }
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return datos;
    }

    String mensaje = 'Ocurrió un error en el servidor.';

    if (datos is Map) {
      final dynamic detalle =
          datos['detail'] ?? datos['mensaje'] ?? datos['message'];

      if (detalle is String && detalle.trim().isNotEmpty) {
        mensaje = detalle;
      } else if (detalle is List && detalle.isNotEmpty) {
        mensaje = detalle
            .map((error) {
              if (error is Map && error['msg'] != null) {
                return error['msg'].toString();
              }
              return error.toString();
            })
            .join('\n');
      }
    }

    if (mensaje == 'Ocurrió un error en el servidor.') {
      switch (respuesta.statusCode) {
        case 400:
          mensaje = 'La solicitud contiene datos incorrectos.';
          break;
        case 401:
          mensaje = 'La sesión no es válida o ha expirado.';
          break;
        case 403:
          mensaje = 'No tienes permiso para realizar esta acción.';
          break;
        case 404:
          mensaje = 'No se encontró el recurso solicitado.';
          break;
        case 405:
          mensaje = 'El método HTTP no está permitido.';
          break;
        case 409:
          mensaje = 'Existe un conflicto con la información registrada.';
          break;
        case 413:
          mensaje = 'El archivo supera el tamaño permitido.';
          break;
        case 415:
          mensaje = 'El formato del archivo no está permitido.';
          break;
        case 422:
          mensaje = 'Los datos enviados no cumplen las validaciones.';
          break;
        case 429:
          mensaje = 'Demasiadas solicitudes. Intenta nuevamente.';
          break;
        case 500:
          mensaje = 'Error interno del servidor.';
          break;
        case 502:
        case 503:
        case 504:
          mensaje = 'El servicio no se encuentra disponible.';
          break;
      }
    }

    throw ApiException(mensaje, codigoEstado: respuesta.statusCode);
  }

  Future<dynamic> _ejecutar(
    Future<http.Response> Function() solicitud, {
    Duration? tiempoEspera,
  }) async {
    try {
      final http.Response respuesta = await solicitud().timeout(
        tiempoEspera ?? ApiConfig.timeout,
      );
      return _procesarRespuesta(respuesta);
    } on TimeoutException {
      throw const ApiException('Se agotó el tiempo de espera del servidor.');
    } on http.ClientException {
      throw const ApiException('No fue posible conectar con el servidor.');
    } on FormatException {
      throw const ApiException(
        'No fue posible interpretar la respuesta del servidor.',
      );
    }
  }

  Future<dynamic> get(
    String ruta, {
    String? token,
    Map<String, String>? parametros,
  }) async {
    return _ejecutar(
      () => _cliente.get(
        _crearUri(ruta, parametros: parametros),
        headers: _crearHeaders(token: token),
      ),
    );
  }

  Future<dynamic> post(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(
      () => _cliente.post(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      ),
    );
  }

  Future<dynamic> postArchivo(
    String ruta, {
    required Map<String, String> campos,
    String? rutaArchivo,
    String campoArchivo = 'archivo',
    String? token,
  }) async {
    return _ejecutar(() async {
      final http.MultipartRequest solicitud = http.MultipartRequest(
        'POST',
        _crearUri(ruta),
      );

      solicitud.headers['Accept'] = 'application/json';

      final String? tokenLimpio = token?.trim();
      if (tokenLimpio != null && tokenLimpio.isNotEmpty) {
        solicitud.headers['Authorization'] = 'Bearer $tokenLimpio';
      }

      solicitud.fields.addAll(campos);

      final String? archivoLimpio = rutaArchivo?.trim();
      if (archivoLimpio != null && archivoLimpio.isNotEmpty) {
        solicitud.files.add(
          await http.MultipartFile.fromPath(campoArchivo, archivoLimpio),
        );
      }

      final http.StreamedResponse respuesta = await _cliente.send(solicitud);
      return http.Response.fromStream(respuesta);
    }, tiempoEspera: const Duration(seconds: 60));
  }

  Future<dynamic> postFormulario(
    String ruta, {
    required Map<String, String> datos,
    String? token,
  }) async {
    return _ejecutar(
      () => _cliente.post(
        _crearUri(ruta),
        headers: _crearHeaders(token: token, formulario: true),
        body: datos,
      ),
    );
  }

  Future<dynamic> put(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(
      () => _cliente.put(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      ),
    );
  }

  Future<dynamic> putArchivo(
    String ruta, {
    required String campoArchivo,
    required String rutaArchivo,
    String? token,
  }) async {
    return _ejecutar(() async {
      final http.MultipartRequest solicitud = http.MultipartRequest(
        'PUT',
        _crearUri(ruta),
      );

      solicitud.headers['Accept'] = 'application/json';

      final String? tokenLimpio = token?.trim();
      if (tokenLimpio != null && tokenLimpio.isNotEmpty) {
        solicitud.headers['Authorization'] = 'Bearer $tokenLimpio';
      }

      solicitud.files.add(
        await http.MultipartFile.fromPath(campoArchivo, rutaArchivo),
      );

      final http.StreamedResponse respuesta = await _cliente.send(solicitud);
      return http.Response.fromStream(respuesta);
    });
  }

  Future<dynamic> patch(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(
      () => _cliente.patch(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      ),
    );
  }

  Future<dynamic> delete(String ruta, {String? token}) async {
    return _ejecutar(
      () => _cliente.delete(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
      ),
    );
  }

  Future<bool> verificarConexion() async {
    try {
      final dynamic respuesta = await get(ApiConfig.verificarConexion);

      return respuesta is Map &&
          respuesta['estado'] == 'Conexion exitosa' &&
          respuesta['base_datos'] != null;
    } on ApiException {
      return false;
    }
  }

  void cerrar() {
    _cliente.close();
  }
}

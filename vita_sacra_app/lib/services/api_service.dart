import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

// Excepcion para identificar errores de la API.
class ApiException implements Exception {
  final String mensaje;
  final int? codigoEstado;

  const ApiException(this.mensaje, {this.codigoEstado});

  @override
  String toString() {
    return mensaje;
  }
}

// Servicio encargado de las solicitudes HTTP.
class ApiService {
  final http.Client _cliente;

  // Constructor del servicio.
  ApiService({http.Client? cliente}) : _cliente = cliente ?? http.Client();

  // Construir la URL del endpoint.
  Uri _crearUri(String ruta, {Map<String, String>? parametros}) {
    final Uri uri = ApiConfig.crearUri(ruta);

    if (parametros == null || parametros.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...parametros},
    );
  }

  // Construir las cabeceras de una solicitud.
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

  // Interpretar la respuesta recibida del servidor.
  dynamic _procesarRespuesta(http.Response respuesta) {
    dynamic datos;

    // Decodificar el contenido JSON de la respuesta.
    if (respuesta.bodyBytes.isNotEmpty) {
      try {
        datos = jsonDecode(utf8.decode(respuesta.bodyBytes));
      } on FormatException {
        throw ApiException(
          'El servidor devolvio una respuesta no valida.',
          codigoEstado: respuesta.statusCode,
        );
      }
    }

    // Devolver los datos cuando la solicitud sea exitosa.
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return datos;
    }

    // Establecer un mensaje general de error.
    String mensaje = 'Ocurrio un error en el servidor.';

    // Recuperar el mensaje proporcionado por FastAPI.
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

    // Asignar mensajes cuando el servidor no proporcione detalles.
    if (mensaje == 'Ocurrio un error en el servidor.') {
      switch (respuesta.statusCode) {
        case 400:
          mensaje = 'La solicitud contiene datos incorrectos.';
          break;

        case 401:
          mensaje = 'La sesion no es valida o ha expirado.';
          break;

        case 403:
          mensaje = 'No tienes permiso para realizar esta accion.';
          break;

        case 404:
          mensaje = 'No se encontro el recurso solicitado.';
          break;

        case 405:
          mensaje = 'El metodo HTTP no esta permitido.';
          break;

        case 409:
          mensaje = 'Existe un conflicto con la informacion registrada.';
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

    // Lanzar la excepcion con el codigo HTTP correspondiente.
    throw ApiException(mensaje, codigoEstado: respuesta.statusCode);
  }

  // Ejecutar una solicitud y controlar errores de conexion.
  Future<dynamic> _ejecutar(Future<http.Response> Function() solicitud) async {
    try {
      final http.Response respuesta = await solicitud().timeout(
        ApiConfig.timeout,
      );

      return _procesarRespuesta(respuesta);
    } on TimeoutException {
      throw const ApiException('Se agoto el tiempo de espera del servidor.');
    } on http.ClientException {
      throw const ApiException('No fue posible conectar con el servidor.');
    } on FormatException {
      throw const ApiException(
        'No fue posible interpretar la respuesta del servidor.',
      );
    }
  }

  // Consultar informacion mediante GET.
  Future<dynamic> get(
    String ruta, {
    String? token,
    Map<String, String>? parametros,
  }) async {
    return _ejecutar(() {
      return _cliente.get(
        _crearUri(ruta, parametros: parametros),
        headers: _crearHeaders(token: token),
      );
    });
  }

  // Enviar informacion mediante POST.
  Future<dynamic> post(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(() {
      return _cliente.post(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      );
    });
  }

  // Enviar formularios mediante POST.
  Future<dynamic> postFormulario(
    String ruta, {
    required Map<String, String> datos,
    String? token,
  }) async {
    return _ejecutar(() {
      return _cliente.post(
        _crearUri(ruta),
        headers: _crearHeaders(token: token, formulario: true),
        body: datos,
      );
    });
  }

  // Actualizar informacion mediante PUT.
  Future<dynamic> put(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(() {
      return _cliente.put(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      );
    });
  }

  // Actualizar parcialmente mediante PATCH.
  Future<dynamic> patch(
    String ruta, {
    Map<String, dynamic>? datos,
    String? token,
  }) async {
    return _ejecutar(() {
      return _cliente.patch(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
        body: jsonEncode(datos ?? {}),
      );
    });
  }

  // Eliminar informacion mediante DELETE.
  Future<dynamic> delete(String ruta, {String? token}) async {
    return _ejecutar(() {
      return _cliente.delete(
        _crearUri(ruta),
        headers: _crearHeaders(token: token),
      );
    });
  }

  // Comprobar la conexion con FastAPI y MariaDB.
  Future<bool> verificarConexion() async {
    try {
      final dynamic respuesta = await get(ApiConfig.verificarConexion);

      if (respuesta is Map) {
        return respuesta['estado'] == 'Conexion exitosa' &&
            respuesta['base_datos'] != null;
      }

      return false;
    } on ApiException {
      return false;
    }
  }

  // Cerrar el cliente HTTP cuando deje de utilizarse.
  void cerrar() {
    _cliente.close();
  }
}

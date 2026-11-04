class ApiConfig {
  // Direccion principal del servidor FastAPI.
  // Puede configurarse mediante --dart-define=API_BASE_URL.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  // Tiempo maximo de espera de las solicitudes HTTP.
  static const Duration timeout = Duration(seconds: 15);

  // Modulos principales de la API REST.
  static const String autenticacion = '/autenticacion';
  static const String usuarios = '/usuarios';
  static const String roles = '/roles';
  static const String publicaciones = '/publicaciones';
  static const String comentarios = '/comentarios';
  static const String interacciones = '/interacciones';
  static const String personalizacion = '/personalizacion';
  static const String recursos = '/recursos';
  static const String establecimientos = '/establecimientos';
  static const String moderacion = '/moderacion';
  static const String promociones = '/promociones';
  static const String pagos = '/pagos';

  // Endpoints generales definidos en main.py.
  static const String inicio = '/';
  static const String verificarConexion = '/verificar-conexion';
  static const String categorias = '/categorias';
  static const String plantillas = '/plantillas';
  static const String posts = '/posts';

  // Construir una URL completa a partir de una ruta.
  static Uri crearUri(String ruta) {
    final String servidor = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    final String endpoint = ruta.startsWith('/') ? ruta : '/$ruta';

    return Uri.parse('$servidor$endpoint');
  }

  // Construir una URL con parametros de consulta opcionales.
  static Uri crearUriConParametros(
    String ruta, [
    Map<String, String>? parametros,
  ]) {
    final Uri uri = crearUri(ruta);

    if (parametros == null || parametros.isEmpty) {
      return uri;
    }

    return uri.replace(queryParameters: parametros);
  }

  // Encabezados para solicitudes JSON.
  static Map<String, String> get headersJson {
    return {'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  // Encabezados para solicitudes con autenticacion JWT.
  static Map<String, String> headersAutenticados(String token) {
    return {...headersJson, 'Authorization': 'Bearer ${token.trim()}'};
  }

  // Encabezados para autenticacion mediante formularios.
  static Map<String, String> get headersFormulario {
    return {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
    };
  }
}

class Categoria {
  // Atributos de la categoria.
  final int idCategoria;
  final String nombre;
  final String? descripcion;
  final bool? activa;

  // Constructor del modelo.
  const Categoria({
    required this.idCategoria,
    required this.nombre,
    this.descripcion,
    this.activa,
  });

  // Convertir un identificador recibido desde la API.
  static int? _convertirEntero(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      if (!valor.isFinite || valor != valor.truncateToDouble()) {
        return null;
      }

      return valor.toInt();
    }

    return int.tryParse(valor.toString().trim());
  }

  // Convertir el estado recibido desde MariaDB.
  static bool? _convertirEstado(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      if (valor == 1) {
        return true;
      }

      if (valor == 0) {
        return false;
      }

      return null;
    }

    if (valor is String) {
      final String estado = valor.trim().toLowerCase();

      if (estado == 'true' || estado == '1') {
        return true;
      }

      if (estado == 'false' || estado == '0') {
        return false;
      }
    }

    return null;
  }

  // Convertir una respuesta JSON a un objeto Categoria.
  factory Categoria.fromJson(Map<String, dynamic> json) {
    // Validar el identificador de la categoria.
    final int? idCategoria = _convertirEntero(json['id_categoria']);

    if (idCategoria == null || idCategoria <= 0) {
      throw const FormatException(
        'La categoria no contiene un id_categoria valido.',
      );
    }

    // Validar el nombre de la categoria.
    final String nombre = (json['nombre'] ?? '').toString().trim();

    if (nombre.isEmpty) {
      throw const FormatException('La categoria no contiene un nombre valido.');
    }

    // Recuperar la descripcion cuando este disponible.
    final String? descripcion = json['descripcion']?.toString();

    // El endpoint publico puede omitir el estado.
    final bool? activa = _convertirEstado(json['activa']);

    return Categoria(
      idCategoria: idCategoria,
      nombre: nombre,
      descripcion: descripcion,
      activa: activa,
    );
  }

  // Convertir el objeto Categoria a JSON.
  Map<String, dynamic> toJson() {
    return {
      'id_categoria': idCategoria,
      'nombre': nombre,
      'descripcion': descripcion,
      'activa': activa,
    };
  }

  // Comprobar si la categoria esta disponible.
  bool get estaActiva {
    // Solo confirmar el estado cuando la API lo proporciona.
    return activa == true;
  }

  // Comprobar si el estado de la categoria es conocido.
  bool get tieneEstadoDefinido {
    return activa != null;
  }

  // Comprobar si contiene una descripcion.
  bool get tieneDescripcion {
    return descripcion != null && descripcion!.trim().isNotEmpty;
  }

  // Crear una copia modificada de la categoria.
  Categoria copyWith({
    int? idCategoria,
    String? nombre,
    Object? descripcion = _sinCambio,
    Object? activa = _sinCambio,
  }) {
    return Categoria(
      idCategoria: idCategoria ?? this.idCategoria,
      nombre: nombre ?? this.nombre,
      descripcion: identical(descripcion, _sinCambio)
          ? this.descripcion
          : descripcion as String?,
      activa: identical(activa, _sinCambio) ? this.activa : activa as bool?,
    );
  }

  // Valor interno para diferenciar un campo omitido de uno nulo.
  static const Object _sinCambio = Object();
}

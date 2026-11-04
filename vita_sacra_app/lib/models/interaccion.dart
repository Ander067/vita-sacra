class Interaccion {
  // Identificadores de la interaccion.
  final int? usrId;
  final int blogId;

  // Valoracion de la publicacion.
  final int? estrellas;

  // Fecha en que se guardo la publicacion.
  final DateTime? fecha;

  // Constructor del modelo.
  const Interaccion({
    this.usrId,
    required this.blogId,
    this.estrellas,
    this.fecha,
  });

  // Convertir valores numericos opcionales a enteros.
  static int? _entero(dynamic valor) {
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

  // Convertir fechas opcionales.
  static DateTime? _fecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is DateTime) {
      return valor;
    }

    return DateTime.tryParse(valor.toString().trim());
  }

  // Crear una interaccion desde una respuesta JSON.
  factory Interaccion.fromJson(Map<String, dynamic> json) {
    // El identificador de la publicacion es obligatorio.
    final int? blogId = _entero(json['blog_id'] ?? json['id_blog']);

    if (blogId == null || blogId <= 0) {
      throw const FormatException(
        'La interaccion no contiene un blog_id valido.',
      );
    }

    // El usuario puede identificarse mediante el token JWT.
    final int? usrId = _entero(json['usr_id']);

    // Recuperar la valoracion cuando este disponible.
    final int? estrellas = _entero(json['estrellas']);

    // Comprobar el rango de la valoracion recibida.
    if (json['estrellas'] != null &&
        (estrellas == null || estrellas < 1 || estrellas > 5)) {
      throw const FormatException(
        'La valoracion debe contener entre 1 y 5 estrellas.',
      );
    }

    // Aceptar la fecha original o la fecha de guardado.
    final dynamic fechaOriginal = json['fecha'] ?? json['fecha_guardado'];

    final DateTime? fecha = _fecha(fechaOriginal);

    // Evitar fechas invalidas cuando la API proporciona el campo.
    if (fechaOriginal != null && fecha == null) {
      throw const FormatException(
        'La interaccion contiene una fecha no valida.',
      );
    }

    return Interaccion(
      usrId: usrId,
      blogId: blogId,
      estrellas: estrellas,
      fecha: fecha,
    );
  }

  // Convertir el objeto a un mapa JSON.
  Map<String, dynamic> toJson() {
    return {
      if (usrId != null) 'usr_id': usrId,
      'blog_id': blogId,
      if (estrellas != null) 'estrellas': estrellas,
      if (fecha != null) 'fecha': fecha!.toIso8601String(),
    };
  }

  // Comprobar si contiene una valoracion.
  bool get tieneValoracion {
    return estrellas != null;
  }

  // Comprobar si la valoracion es valida.
  bool get valoracionValida {
    return estrellas != null && estrellas! >= 1 && estrellas! <= 5;
  }

  // Comprobar si contiene una fecha de guardado.
  bool get tieneFechaGuardado {
    return fecha != null;
  }

  // Comprobar si se conoce el identificador del usuario.
  bool get tieneUsuario {
    return usrId != null && usrId! > 0;
  }

  // Crear una copia modificada de la interaccion.
  Interaccion copyWith({
    Object? usrId = _sinCambio,
    int? blogId,
    Object? estrellas = _sinCambio,
    Object? fecha = _sinCambio,
  }) {
    return Interaccion(
      usrId: identical(usrId, _sinCambio) ? this.usrId : usrId as int?,
      blogId: blogId ?? this.blogId,
      estrellas: identical(estrellas, _sinCambio)
          ? this.estrellas
          : estrellas as int?,
      fecha: identical(fecha, _sinCambio) ? this.fecha : fecha as DateTime?,
    );
  }

  // Valor interno para distinguir un campo omitido de uno nulo.
  static const Object _sinCambio = Object();
}

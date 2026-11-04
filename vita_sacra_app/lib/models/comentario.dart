class Comentario {
  // Atributos del comentario.
  final int idCom;
  final String comentario;
  final DateTime fecha;
  final int? estatus;
  final int? usrId;
  final int? blogId;
  final int? comPadreId;

  // Informacion adicional proporcionada por la API.
  final String? autor;

  // Constructor del modelo.
  const Comentario({
    required this.idCom,
    required this.comentario,
    required this.fecha,
    this.estatus,
    this.usrId,
    this.blogId,
    this.comPadreId,
    this.autor,
  });

  // Convertir un valor numerico opcional a entero.
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

  // Convertir una fecha opcional de la API.
  static DateTime? _fecha(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is DateTime) {
      return valor;
    }

    return DateTime.tryParse(valor.toString().trim());
  }

  // Convertir un valor opcional a texto.
  static String? _texto(dynamic valor) {
    if (valor == null) {
      return null;
    }

    return valor.toString();
  }

  // Convertir una respuesta JSON a un objeto Comentario.
  factory Comentario.fromJson(Map<String, dynamic> json) {
    // El identificador debe existir para reconocer el comentario.
    final int? idCom = _entero(json['id_com']);

    if (idCom == null || idCom <= 0) {
      throw const FormatException(
        'El comentario no contiene un id_com valido.',
      );
    }

    // El contenido es obligatorio para representar el comentario.
    final String? contenido = _texto(json['comentario']);

    if (contenido == null || contenido.trim().isEmpty) {
      throw const FormatException('El comentario no contiene texto valido.');
    }

    // La fecha debe tener un formato que Dart pueda interpretar.
    final DateTime? fecha = _fecha(json['fecha']);

    if (fecha == null) {
      throw const FormatException(
        'El comentario no contiene una fecha valida.',
      );
    }

    // Los endpoints publicos pueden omitir estos campos.
    final int? estatus = _entero(json['estatus']);
    final int? usrId = _entero(json['usr_id']);
    final int? blogId = _entero(json['blog_id']);

    // El identificador del comentario padre es opcional.
    final int? comPadreId = _entero(json['com_padre_id']);

    return Comentario(
      idCom: idCom,
      comentario: contenido,
      fecha: fecha,
      estatus: estatus,
      usrId: usrId,
      blogId: blogId,
      comPadreId: comPadreId,
      autor: _texto(json['autor']),
    );
  }

  // Convertir el objeto Comentario a JSON.
  Map<String, dynamic> toJson() {
    return {
      'id_com': idCom,
      'comentario': comentario,
      'fecha': fecha.toIso8601String(),
      'estatus': estatus,
      'usr_id': usrId,
      'blog_id': blogId,
      'com_padre_id': comPadreId,
      'autor': autor,
    };
  }

  // Comprobar si es un comentario principal.
  bool get esPrincipal {
    return comPadreId == null;
  }

  // Comprobar si responde a otro comentario.
  bool get esRespuesta {
    return comPadreId != null;
  }

  // Comprobar si el comentario esta activo.
  bool get estaActivo {
    // El estado debe estar disponible y ser igual a 1.
    return estatus == 1;
  }

  // Comprobar si contiene texto.
  bool get tieneContenido {
    return comentario.trim().isNotEmpty;
  }

  // Crear una copia modificada del comentario.
  Comentario copyWith({
    int? idCom,
    String? comentario,
    DateTime? fecha,
    Object? estatus = _sinCambio,
    Object? usrId = _sinCambio,
    Object? blogId = _sinCambio,
    Object? comPadreId = _sinCambio,
    Object? autor = _sinCambio,
  }) {
    return Comentario(
      idCom: idCom ?? this.idCom,
      comentario: comentario ?? this.comentario,
      fecha: fecha ?? this.fecha,
      estatus: identical(estatus, _sinCambio) ? this.estatus : estatus as int?,
      usrId: identical(usrId, _sinCambio) ? this.usrId : usrId as int?,
      blogId: identical(blogId, _sinCambio) ? this.blogId : blogId as int?,
      comPadreId: identical(comPadreId, _sinCambio)
          ? this.comPadreId
          : comPadreId as int?,
      autor: identical(autor, _sinCambio) ? this.autor : autor as String?,
    );
  }

  // Valor interno para diferenciar un campo omitido de uno nulo.
  static const Object _sinCambio = Object();
}

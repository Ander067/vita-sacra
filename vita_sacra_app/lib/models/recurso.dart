class Recurso {
  // Atributos del recurso multimedia.
  final int idRecurso;
  final int? usrId;
  final String tipo;
  final String url;
  final String? mime;
  final String? titulo;
  final String? licencia;
  final String? procedencia;
  final String? estatus;
  final int? revisadoPor;
  final DateTime? fechaRevision;
  final DateTime? fecha;

  // Constructor del modelo.
  const Recurso({
    required this.idRecurso,
    this.usrId,
    required this.tipo,
    required this.url,
    this.mime,
    this.titulo,
    this.licencia,
    this.procedencia,
    this.estatus,
    this.revisadoPor,
    this.fechaRevision,
    this.fecha,
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

  // Convertir una fecha opcional.
  static DateTime? _fechaOpcional(dynamic valor) {
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

  // Convertir una respuesta JSON a un objeto Recurso.
  factory Recurso.fromJson(Map<String, dynamic> json) {
    // Validar el identificador del recurso.
    final int? idRecurso = _entero(json['id_recurso']);

    if (idRecurso == null || idRecurso <= 0) {
      throw const FormatException(
        'El recurso no contiene un id_recurso valido.',
      );
    }

    // Validar el tipo de recurso multimedia.
    final String tipo = _texto(json['tipo'])?.trim() ?? '';

    if (tipo.isEmpty) {
      throw const FormatException('El recurso no contiene un tipo valido.');
    }

    // Validar que exista una direccion del recurso.
    final String url = _texto(json['url'])?.trim() ?? '';

    if (url.isEmpty) {
      throw const FormatException('El recurso no contiene una URL valida.');
    }

    // Los endpoints publicos pueden omitir estos campos.
    final int? usrId = _entero(json['usr_id']);
    final String? estatus = _texto(json['estatus']);
    final DateTime? fecha = _fechaOpcional(json['fecha']);

    // Recuperar los datos de revision cuando esten disponibles.
    final int? revisadoPor = _entero(json['revisado_por']);

    final DateTime? fechaRevision = _fechaOpcional(json['fecha_revision']);

    return Recurso(
      idRecurso: idRecurso,
      usrId: usrId,
      tipo: tipo,
      url: url,
      mime: _texto(json['mime']),
      titulo: _texto(json['titulo']),
      licencia: _texto(json['licencia']),
      procedencia: _texto(json['procedencia']),
      estatus: estatus,
      revisadoPor: revisadoPor,
      fechaRevision: fechaRevision,
      fecha: fecha,
    );
  }

  // Convertir el objeto Recurso a JSON.
  Map<String, dynamic> toJson() {
    return {
      'id_recurso': idRecurso,
      'usr_id': usrId,
      'tipo': tipo,
      'url': url,
      'mime': mime,
      'titulo': titulo,
      'licencia': licencia,
      'procedencia': procedencia,
      'estatus': estatus,
      'revisado_por': revisadoPor,
      'fecha_revision': fechaRevision?.toIso8601String(),
      'fecha': fecha?.toIso8601String(),
    };
  }

  // Identificar el tipo de recurso multimedia.
  String get nombreTipo {
    switch (tipo) {
      case 'imagen':
        return 'Imagen';
      case 'pdf':
        return 'Documento PDF';
      case 'video':
        return 'Video';
      case 'gif':
        return 'GIF';
      case 'sticker':
        return 'Sticker';
      case 'modelo_3d':
        return 'Modelo 3D';
      default:
        return 'Recurso desconocido';
    }
  }

  // Comprobar si el recurso esta aprobado.
  bool get estaAprobado {
    // El estado solo se confirma cuando esta disponible.
    return estatus == 'aprobado';
  }

  // Comprobar si la API proporciono el estado del recurso.
  bool get tieneEstadoDefinido {
    return estatus != null && estatus!.trim().isNotEmpty;
  }

  // Identificar recursos visuales.
  bool get esImagen {
    return tipo == 'imagen' || tipo == 'gif' || tipo == 'sticker';
  }

  // Identificar documentos PDF.
  bool get esPdf {
    return tipo == 'pdf';
  }

  // Identificar videos.
  bool get esVideo {
    return tipo == 'video';
  }

  // Identificar modelos anatomicos 3D.
  bool get esModelo3D {
    return tipo == 'modelo_3d';
  }

  // Comprobar si contiene informacion de licencia.
  bool get tieneLicencia {
    return licencia != null && licencia!.trim().isNotEmpty;
  }

  // Comprobar si contiene informacion de procedencia.
  bool get tieneProcedencia {
    return procedencia != null && procedencia!.trim().isNotEmpty;
  }

  // Comprobar si contiene una direccion HTTPS.
  bool get tieneUrlSegura {
    final Uri? direccion = Uri.tryParse(url);

    return direccion != null &&
        direccion.scheme == 'https' &&
        direccion.host.isNotEmpty &&
        direccion.userInfo.isEmpty;
  }

  // Comprobar si el recurso es un modelo GLB.
  bool get esArchivoGlb {
    if (!esModelo3D) {
      return false;
    }

    final Uri? direccion = Uri.tryParse(url);

    final bool extensionGlb =
        direccion != null && direccion.path.toLowerCase().endsWith('.glb');

    final bool mimeGlb = mime?.trim().toLowerCase() == 'model/gltf-binary';

    return extensionGlb || mimeGlb;
  }

  // Crear una copia modificada del recurso.
  Recurso copyWith({
    int? idRecurso,
    Object? usrId = _sinCambio,
    String? tipo,
    String? url,
    Object? mime = _sinCambio,
    Object? titulo = _sinCambio,
    Object? licencia = _sinCambio,
    Object? procedencia = _sinCambio,
    Object? estatus = _sinCambio,
    Object? revisadoPor = _sinCambio,
    Object? fechaRevision = _sinCambio,
    Object? fecha = _sinCambio,
  }) {
    return Recurso(
      idRecurso: idRecurso ?? this.idRecurso,
      usrId: identical(usrId, _sinCambio) ? this.usrId : usrId as int?,
      tipo: tipo ?? this.tipo,
      url: url ?? this.url,
      mime: identical(mime, _sinCambio) ? this.mime : mime as String?,
      titulo: identical(titulo, _sinCambio) ? this.titulo : titulo as String?,
      licencia: identical(licencia, _sinCambio)
          ? this.licencia
          : licencia as String?,
      procedencia: identical(procedencia, _sinCambio)
          ? this.procedencia
          : procedencia as String?,
      estatus: identical(estatus, _sinCambio)
          ? this.estatus
          : estatus as String?,
      revisadoPor: identical(revisadoPor, _sinCambio)
          ? this.revisadoPor
          : revisadoPor as int?,
      fechaRevision: identical(fechaRevision, _sinCambio)
          ? this.fechaRevision
          : fechaRevision as DateTime?,
      fecha: identical(fecha, _sinCambio) ? this.fecha : fecha as DateTime?,
    );
  }

  // Valor interno para distinguir un campo omitido de uno nulo.
  static const Object _sinCambio = Object();
}

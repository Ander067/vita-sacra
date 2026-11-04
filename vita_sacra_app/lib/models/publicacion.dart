class Publicacion {
  // Atributos de la publicacion.
  final int idBlog;
  final int? usrId;
  final int? categoriaId;
  final int? plantillaId;
  final String titulo;
  final String? descripcion;
  final String? img;
  final String? slug;
  final String tipo;
  final String? estatus;
  final int? versionPublica;
  final DateTime? fechaCreacion;
  final DateTime? fechaPublicacion;

  // Datos adicionales que puede proporcionar la API.
  final String? autor;
  final String? advertencia;

  // Constructor del modelo.
  const Publicacion({
    required this.idBlog,
    this.usrId,
    this.categoriaId,
    this.plantillaId,
    required this.titulo,
    this.descripcion,
    this.img,
    this.slug,
    required this.tipo,
    this.estatus,
    this.versionPublica,
    this.fechaCreacion,
    this.fechaPublicacion,
    this.autor,
    this.advertencia,
  });

  // Convertir un valor numerico opcional.
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

  // Convertir una respuesta JSON en una publicacion.
  factory Publicacion.fromJson(Map<String, dynamic> json) {
    // El identificador es obligatorio para reconocer la publicacion.
    final int? idBlog = _entero(json['id_blog']);

    if (idBlog == null || idBlog <= 0) {
      throw const FormatException(
        'La publicacion no contiene un id_blog valido.',
      );
    }

    // El titulo debe existir para representar la publicacion.
    final String? titulo = _texto(json['titulo']);

    if (titulo == null || titulo.trim().isEmpty) {
      throw const FormatException(
        'La publicacion no contiene un titulo valido.',
      );
    }

    // Los endpoints publicos pueden omitir estos identificadores.
    final int? usrId = _entero(json['usr_id']);

    final int? categoriaId = _entero(
      json['categoria_id'] ?? json['id_categoria'],
    );

    // FastAPI utiliza id_version en las consultas publicas.
    final int? versionPublica = _entero(
      json['id_version'] ?? json['version_publica'],
    );

    return Publicacion(
      idBlog: idBlog,
      usrId: usrId,
      categoriaId: categoriaId,
      plantillaId: _entero(json['plantilla_id']),
      titulo: titulo.trim(),
      descripcion: _texto(json['desc'] ?? json['descripcion']),
      img: _texto(json['img']),
      slug: _texto(json['slug']),
      tipo: _texto(json['tipo']) ?? 'articulo',
      estatus: _texto(json['estatus']),
      versionPublica: versionPublica,
      fechaCreacion: _fecha(json['fecha_creacion']),
      fechaPublicacion: _fecha(json['fecha_publicacion']),
      autor: _texto(json['autor']),
      advertencia: _texto(json['advertencia']),
    );
  }

  // Convertir el objeto Publicacion a JSON.
  Map<String, dynamic> toJson() {
    return {
      'id_blog': idBlog,
      'usr_id': usrId,
      'categoria_id': categoriaId,
      'plantilla_id': plantillaId,
      'titulo': titulo,
      'desc': descripcion,
      'img': img,
      'slug': slug,
      'tipo': tipo,
      'estatus': estatus,
      'id_version': versionPublica,
      'fecha_creacion': fechaCreacion?.toIso8601String(),
      'fecha_publicacion': fechaPublicacion?.toIso8601String(),
      'autor': autor,
      'advertencia': advertencia,
    };
  }

  // Identificar el tipo de publicacion.
  String get nombreTipo {
    switch (tipo) {
      case 'articulo':
        return 'Articulo';
      case 'ficha_medicamento':
        return 'Ficha de medicamento';
      case 'ficha_producto':
        return 'Ficha de producto';
      default:
        return 'Publicacion';
    }
  }

  // Comprobar el estado de publicacion.
  bool get estaPublicada {
    // El estado solo se confirma cuando la API lo proporciona.
    return estatus == 'publicado';
  }

  // Comprobar si contiene una imagen de portada.
  bool get tieneImagen {
    return img != null && img!.trim().isNotEmpty;
  }

  // Comprobar si contiene una advertencia.
  bool get tieneAdvertencia {
    return advertencia != null && advertencia!.trim().isNotEmpty;
  }

  // Crear una copia modificada de la publicacion.
  Publicacion copyWith({
    int? idBlog,
    Object? usrId = _sinCambio,
    Object? categoriaId = _sinCambio,
    Object? plantillaId = _sinCambio,
    String? titulo,
    Object? descripcion = _sinCambio,
    Object? img = _sinCambio,
    Object? slug = _sinCambio,
    String? tipo,
    Object? estatus = _sinCambio,
    Object? versionPublica = _sinCambio,
    Object? fechaCreacion = _sinCambio,
    Object? fechaPublicacion = _sinCambio,
    Object? autor = _sinCambio,
    Object? advertencia = _sinCambio,
  }) {
    return Publicacion(
      idBlog: idBlog ?? this.idBlog,
      usrId: identical(usrId, _sinCambio) ? this.usrId : usrId as int?,
      categoriaId: identical(categoriaId, _sinCambio)
          ? this.categoriaId
          : categoriaId as int?,
      plantillaId: identical(plantillaId, _sinCambio)
          ? this.plantillaId
          : plantillaId as int?,
      titulo: titulo ?? this.titulo,
      descripcion: identical(descripcion, _sinCambio)
          ? this.descripcion
          : descripcion as String?,
      img: identical(img, _sinCambio) ? this.img : img as String?,
      slug: identical(slug, _sinCambio) ? this.slug : slug as String?,
      tipo: tipo ?? this.tipo,
      estatus: identical(estatus, _sinCambio)
          ? this.estatus
          : estatus as String?,
      versionPublica: identical(versionPublica, _sinCambio)
          ? this.versionPublica
          : versionPublica as int?,
      fechaCreacion: identical(fechaCreacion, _sinCambio)
          ? this.fechaCreacion
          : fechaCreacion as DateTime?,
      fechaPublicacion: identical(fechaPublicacion, _sinCambio)
          ? this.fechaPublicacion
          : fechaPublicacion as DateTime?,
      autor: identical(autor, _sinCambio) ? this.autor : autor as String?,
      advertencia: identical(advertencia, _sinCambio)
          ? this.advertencia
          : advertencia as String?,
    );
  }

  // Valor interno para distinguir un campo omitido de uno nulo.
  static const Object _sinCambio = Object();
}

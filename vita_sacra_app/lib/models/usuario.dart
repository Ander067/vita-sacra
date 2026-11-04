class Usuario {
  // Atributos del usuario.
  final int idUsr;
  final String nomUsr;
  final String mail;
  final String? dirUsr;
  final int tipUsu;
  final String estatus;
  final DateTime? fechaRegistro;

  // Constructor del modelo.
  const Usuario({
    required this.idUsr,
    required this.nomUsr,
    required this.mail,
    this.dirUsr,
    required this.tipUsu,
    required this.estatus,
    this.fechaRegistro,
  });

  // Convertir la respuesta JSON de FastAPI a un objeto Usuario.
  factory Usuario.fromJson(Map<String, dynamic> json) {
    // Comprobar que exista un identificador valido.
    final dynamic identificador = json['id_usr'];

    if (identificador is! num && identificador is! String) {
      throw const FormatException('El identificador del usuario no es valido.');
    }

    final int? idUsuario = identificador is num
        ? identificador.toInt()
        : int.tryParse(identificador);

    if (idUsuario == null || idUsuario <= 0) {
      throw const FormatException('El identificador del usuario no es valido.');
    }

    // Recuperar los datos principales del usuario.
    final String nombre = (json['nom_usr'] ?? '').toString().trim();
    final String correo = (json['mail'] ?? '').toString().trim();

    if (nombre.isEmpty || correo.isEmpty) {
      throw const FormatException(
        'La informacion del usuario esta incompleta.',
      );
    }

    // Interpretar el rol principal.
    final dynamic rol = json['tip_usu'];

    final int? tipoUsuario = rol is num
        ? rol.toInt()
        : int.tryParse(rol?.toString() ?? '');

    if (tipoUsuario == null || tipoUsuario <= 0) {
      throw const FormatException('El rol principal del usuario no es valido.');
    }

    // Recuperar el estado de la cuenta.
    final String estado = (json['estatus'] ?? '').toString().trim();

    if (estado.isEmpty) {
      throw const FormatException('El estado del usuario no es valido.');
    }

    // Recuperar la direccion cuando se encuentre disponible.
    final String? direccion = json['dir_usr'] == null
        ? null
        : json['dir_usr'].toString();

    // Interpretar la fecha de registro cuando exista.
    DateTime? fecha;

    if (json['fecha_registro'] != null) {
      fecha = DateTime.tryParse(json['fecha_registro'].toString());
    }

    // Crear el objeto con la informacion recibida.
    return Usuario(
      idUsr: idUsuario,
      nomUsr: nombre,
      mail: correo,
      dirUsr: direccion,
      tipUsu: tipoUsuario,
      estatus: estado,
      fechaRegistro: fecha,
    );
  }

  // Convertir el objeto Usuario a un mapa JSON.
  Map<String, dynamic> toJson() {
    return {
      'id_usr': idUsr,
      'nom_usr': nomUsr,
      'mail': mail,
      'dir_usr': dirUsr,
      'tip_usu': tipUsu,
      'estatus': estatus,
      'fecha_registro': fechaRegistro?.toIso8601String(),
    };
  }

  // Obtener el nombre del rol principal.
  String get nombreRol {
    switch (tipUsu) {
      case 1:
        return 'Usuario';

      case 2:
        return 'Autor';

      case 3:
        return 'Administrador';

      case 4:
        return 'Anunciante';

      default:
        return 'Desconocido';
    }
  }

  // Comprobar si la cuenta se encuentra activa.
  bool get estaActivo {
    return estatus.toLowerCase() == 'activo';
  }

  // Comprobar si el usuario tiene rol principal de autor.
  bool get esAutor {
    return tipUsu == 2;
  }

  // Comprobar si el usuario tiene rol principal de administrador.
  bool get esAdministrador {
    return tipUsu == 3;
  }

  // Comprobar si el usuario tiene rol principal de anunciante.
  bool get esAnunciante {
    return tipUsu == 4;
  }

  // Crear una copia modificada del usuario.
  Usuario copyWith({
    int? idUsr,
    String? nomUsr,
    String? mail,
    String? dirUsr,
    int? tipUsu,
    String? estatus,
    DateTime? fechaRegistro,
  }) {
    return Usuario(
      idUsr: idUsr ?? this.idUsr,
      nomUsr: nomUsr ?? this.nomUsr,
      mail: mail ?? this.mail,
      dirUsr: dirUsr ?? this.dirUsr,
      tipUsu: tipUsu ?? this.tipUsu,
      estatus: estatus ?? this.estatus,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
    );
  }
}

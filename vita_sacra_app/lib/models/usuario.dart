class Usuario {
  final int idUsr;
  final String nomUsr;
  final String mail;
  final String? dirUsr;
  final String? fotoPerfilUrl;
  final int tipUsu;
  final String estatus;
  final DateTime? fechaRegistro;

  const Usuario({
    required this.idUsr,
    required this.nomUsr,
    required this.mail,
    this.dirUsr,
    this.fotoPerfilUrl,
    required this.tipUsu,
    required this.estatus,
    this.fechaRegistro,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    final dynamic identificador = json['id_usr'];

    if (identificador is! num && identificador is! String) {
      throw const FormatException('El identificador del usuario no es válido.');
    }

    final int? idUsuario = identificador is num
        ? identificador.toInt()
        : int.tryParse(identificador);

    if (idUsuario == null || idUsuario <= 0) {
      throw const FormatException('El identificador del usuario no es válido.');
    }

    final String nombre = (json['nom_usr'] ?? '').toString().trim();
    final String correo = (json['mail'] ?? '').toString().trim();

    if (nombre.isEmpty || correo.isEmpty) {
      throw const FormatException(
        'La información del usuario está incompleta.',
      );
    }

    final dynamic rol = json['tip_usu'];
    final int? tipoUsuario = rol is num
        ? rol.toInt()
        : int.tryParse(rol?.toString() ?? '');

    if (tipoUsuario == null || tipoUsuario <= 0) {
      throw const FormatException('El rol principal no es válido.');
    }

    final String estado = (json['estatus'] ?? '').toString().trim();

    if (estado.isEmpty) {
      throw const FormatException('El estado del usuario no es válido.');
    }

    final String? direccion = json['dir_usr']?.toString();
    final String? foto = json['foto_perfil_url']?.toString().trim();

    DateTime? fecha;
    if (json['fecha_registro'] != null) {
      fecha = DateTime.tryParse(json['fecha_registro'].toString());
    }

    return Usuario(
      idUsr: idUsuario,
      nomUsr: nombre,
      mail: correo,
      dirUsr: direccion,
      fotoPerfilUrl: foto == null || foto.isEmpty ? null : foto,
      tipUsu: tipoUsuario,
      estatus: estado,
      fechaRegistro: fecha,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_usr': idUsr,
      'nom_usr': nomUsr,
      'mail': mail,
      'dir_usr': dirUsr,
      'foto_perfil_url': fotoPerfilUrl,
      'tip_usu': tipUsu,
      'estatus': estatus,
      'fecha_registro': fechaRegistro?.toIso8601String(),
    };
  }

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

  bool get estaActivo => estatus.toLowerCase() == 'activo';
  bool get esAutor => tipUsu == 2;
  bool get esAdministrador => tipUsu == 3;
  bool get esAnunciante => tipUsu == 4;

  Usuario copyWith({
    int? idUsr,
    String? nomUsr,
    String? mail,
    String? dirUsr,
    String? fotoPerfilUrl,
    int? tipUsu,
    String? estatus,
    DateTime? fechaRegistro,
  }) {
    return Usuario(
      idUsr: idUsr ?? this.idUsr,
      nomUsr: nomUsr ?? this.nomUsr,
      mail: mail ?? this.mail,
      dirUsr: dirUsr ?? this.dirUsr,
      fotoPerfilUrl: fotoPerfilUrl ?? this.fotoPerfilUrl,
      tipUsu: tipUsu ?? this.tipUsu,
      estatus: estatus ?? this.estatus,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
    );
  }
}

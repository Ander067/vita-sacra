import 'package:flutter/material.dart';

import '../views/detalle_publicacion_view.dart';

// Componente reutilizable para mostrar publicaciones.
class PublicacionCard extends StatelessWidget {
  // Datos de la publicacion.
  final Map<String, dynamic> publicacion;

  // Funcion opcional para actualizar la pantalla.
  final VoidCallback? onActualizar;

  // Mostrar u ocultar el boton de lectura.
  final bool mostrarBoton;

  const PublicacionCard({
    super.key,
    required this.publicacion,
    this.onActualizar,
    this.mostrarBoton = true,
  });

  // Obtener el texto de los campos disponibles.
  String _obtenerTexto(List<String> campos, {String defecto = ''}) {
    for (final String campo in campos) {
      final dynamic valor = publicacion[campo];

      if (valor != null) {
        final String texto = valor.toString().trim();

        if (texto.isNotEmpty) {
          return texto;
        }
      }
    }

    return defecto;
  }

  // Obtener el identificador de la publicacion.
  int? _obtenerIdBlog() {
    final dynamic identificador =
        publicacion['id_blog'] ?? publicacion['blog_id'];

    if (identificador is int) {
      return identificador > 0 ? identificador : null;
    }

    if (identificador is num) {
      if (!identificador.isFinite ||
          identificador != identificador.truncateToDouble()) {
        return null;
      }

      final int id = identificador.toInt();

      return id > 0 ? id : null;
    }

    final int? id = int.tryParse(identificador?.toString().trim() ?? '');

    return id != null && id > 0 ? id : null;
  }

  // Obtener la direccion de la imagen.
  String _obtenerImagen() {
    return _obtenerTexto(['img', 'imagen', 'imagen_url', 'url_imagen']);
  }

  // Verificar que la imagen tenga una URL valida.
  bool _imagenValida(String imagen) {
    if (imagen.trim().isEmpty) {
      return false;
    }

    final Uri? direccion = Uri.tryParse(imagen.trim());

    if (direccion == null) {
      return false;
    }

    // Aceptar direcciones HTTP o HTTPS con un dominio valido.
    return (direccion.scheme == 'http' || direccion.scheme == 'https') &&
        direccion.host.isNotEmpty &&
        direccion.userInfo.isEmpty;
  }

  // Obtener el nombre del autor.
  String _obtenerAutor() {
    final dynamic autor = publicacion['autor'];

    // Verificar si el autor es un objeto.
    if (autor is Map) {
      final dynamic nombre =
          autor['nombre'] ?? autor['nombre_usuario'] ?? autor['nom_usr'];

      if (nombre != null && nombre.toString().trim().isNotEmpty) {
        return nombre.toString().trim();
      }
    }

    // Verificar si el autor es texto.
    if (autor is String && autor.trim().isNotEmpty) {
      return autor.trim();
    }

    // Buscar otros campos disponibles.
    return _obtenerTexto([
      'nombre_autor',
      'nombre_usuario',
      'nom_usr',
    ], defecto: 'Autor no disponible');
  }

  // Obtener la categoria de la publicacion.
  String _obtenerCategoria() {
    final dynamic categoria = publicacion['categoria'];

    // Verificar si la categoria es un objeto.
    if (categoria is Map) {
      final dynamic nombre =
          categoria['nombre'] ?? categoria['nombre_categoria'];

      if (nombre != null && nombre.toString().trim().isNotEmpty) {
        return nombre.toString().trim();
      }
    }

    // Verificar si la categoria es texto.
    if (categoria is String && categoria.trim().isNotEmpty) {
      return categoria.trim();
    }

    // Buscar otros campos disponibles.
    return _obtenerTexto(['nombre_categoria'], defecto: 'Publicación');
  }

  // Obtener la fecha de la publicacion.
  String _obtenerFecha() {
    final String fecha = _obtenerTexto([
      'fecha_publicacion',
      'fecha_creacion',
      'fecha',
    ]);

    if (fecha.isEmpty) {
      return 'Fecha no disponible';
    }

    // Intentar interpretar la fecha recibida.
    final DateTime? fechaConvertida = DateTime.tryParse(fecha);

    if (fechaConvertida == null) {
      return fecha;
    }

    // Mostrar la fecha en formato dia/mes/ano.
    final String dia = fechaConvertida.day.toString().padLeft(2, '0');

    final String mes = fechaConvertida.month.toString().padLeft(2, '0');

    final String anio = fechaConvertida.year.toString();

    return '$dia/$mes/$anio';
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir el detalle de la publicacion.
  Future<void> _abrirPublicacion(BuildContext context) async {
    // Obtener el identificador de la publicacion.
    final int? idBlog = _obtenerIdBlog();

    // Validar el identificador.
    if (idBlog == null) {
      _mostrarMensaje(
        context,
        'No se encontro un identificador '
        'valido para esta publicacion.',
      );

      return;
    }

    // Abrir la pantalla de detalle.
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (contexto) => DetallePublicacionView(idBlog: idBlog),
      ),
    );

    // Verificar que el componente siga disponible.
    if (!context.mounted) {
      return;
    }

    // Actualizar la pantalla anterior si se solicita.
    onActualizar?.call();
  }

  // Construir el espacio de la imagen.
  Widget _construirImagen(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String imagen = _obtenerImagen();

    // Mostrar un icono si no existe imagen valida.
    if (!_imagenValida(imagen)) {
      return Container(
        width: double.infinity,
        height: 170,
        alignment: Alignment.center,
        color: colores.primaryContainer,
        child: Icon(
          Icons.article_outlined,
          size: 60,
          color: colores.onPrimaryContainer,
        ),
      );
    }

    // Mostrar la imagen de la publicacion.
    return Image.network(
      imagen,
      width: double.infinity,
      height: 170,
      fit: BoxFit.cover,

      // Mostrar un indicador mientras carga.
      loadingBuilder: (contexto, child, progreso) {
        if (progreso == null) {
          return child;
        }

        final int? totalBytes = progreso.expectedTotalBytes;

        final double? avance = totalBytes != null && totalBytes > 0
            ? progreso.cumulativeBytesLoaded / totalBytes
            : null;

        return Container(
          width: double.infinity,
          height: 170,
          alignment: Alignment.center,
          color: colores.primaryContainer,
          child: CircularProgressIndicator(value: avance),
        );
      },

      // Mostrar un icono si ocurre un error.
      errorBuilder: (contexto, error, stackTrace) {
        return Container(
          width: double.infinity,
          height: 170,
          alignment: Alignment.center,
          color: colores.primaryContainer,
          child: Icon(
            Icons.broken_image_outlined,
            size: 55,
            color: colores.onPrimaryContainer,
          ),
        );
      },
    );
  }

  // Construir la informacion del autor.
  Widget _construirAutor(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_outline, size: 16, color: colores.onSurfaceVariant),

        const SizedBox(width: 5),

        Flexible(
          child: Text(
            _obtenerAutor(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // Construir la informacion de la fecha.
  Widget _construirFecha(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 15,
          color: colores.onSurfaceVariant,
        ),

        const SizedBox(width: 5),

        Flexible(
          child: Text(
            _obtenerFecha(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los datos de la publicacion.
    final String titulo = _obtenerTexto([
      'titulo',
      'nombre',
    ], defecto: 'Publicación sin título');

    final String descripcion = _obtenerTexto([
      'descripcion',
      'desc',
      'resumen',
    ], defecto: 'Sin descripción disponible.');

    final String categoria = _obtenerCategoria();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Abrir el detalle al seleccionar la tarjeta.
        onTap: () {
          _abrirPublicacion(context);
        },

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen principal de la publicacion.
            _construirImagen(context),

            // Contenido informativo.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categoria de la publicacion.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      categoria,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colores.onPrimaryContainer,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Titulo de la publicacion.
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Descripcion breve.
                  Text(
                    descripcion,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colores.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Separador de informacion.
                  const Divider(),

                  const SizedBox(height: 10),

                  // Autor y fecha.
                  Row(
                    children: [
                      Expanded(child: _construirAutor(context)),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _construirFecha(context),
                        ),
                      ),
                    ],
                  ),

                  // Boton para abrir la publicacion.
                  if (mostrarBoton) ...[
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _abrirPublicacion(context);
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Leer publicación'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

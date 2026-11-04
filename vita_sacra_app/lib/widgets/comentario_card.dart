import 'package:flutter/material.dart';

import '../views/reportar_contenido_view.dart';

// Componente reutilizable para mostrar comentarios.
class ComentarioCard extends StatelessWidget {
  // Datos del comentario.
  final Map<String, dynamic> comentario;

  // Funcion opcional para responder.
  final VoidCallback? onResponder;

  // Funcion opcional para actualizar comentarios.
  final VoidCallback? onActualizar;

  // Mostrar u ocultar las opciones.
  final bool mostrarOpciones;

  const ComentarioCard({
    super.key,
    required this.comentario,
    this.onResponder,
    this.onActualizar,
    this.mostrarOpciones = true,
  });

  // Obtener el texto de los campos disponibles.
  String _obtenerTexto(List<String> campos, {String defecto = ''}) {
    for (final String campo in campos) {
      final dynamic valor = comentario[campo];

      if (valor != null) {
        final String texto = valor.toString().trim();

        if (texto.isNotEmpty) {
          return texto;
        }
      }
    }

    return defecto;
  }

  // Obtener el identificador del comentario.
  int? _obtenerIdComentario() {
    // FastAPI devuelve id_com como identificador principal.
    final dynamic identificador =
        comentario['id_com'] ?? comentario['id_comentario'] ?? comentario['id'];

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

  // Obtener el nombre del autor.
  String _obtenerAutor() {
    final dynamic autor = comentario['autor'];

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
      'nombre_usuario',
      'nombre_autor',
      'nom_usr',
      'usuario',
    ], defecto: 'Usuario');
  }

  // Obtener el contenido del comentario.
  String _obtenerContenido() {
    return _obtenerTexto([
      'comentario',
      'contenido',
      'texto',
    ], defecto: 'Comentario sin contenido disponible.');
  }

  // Obtener la fecha del comentario.
  String _obtenerFecha() {
    final String fecha = _obtenerTexto([
      'fecha',
      'fecha_creacion',
      'fecha_comentario',
    ]);

    if (fecha.isEmpty) {
      return 'Fecha no disponible';
    }

    // Convertir la fecha si tiene formato compatible.
    final DateTime? fechaConvertida = DateTime.tryParse(fecha);

    if (fechaConvertida == null) {
      return fecha;
    }

    // Obtener dia, mes y ano.
    final String dia = fechaConvertida.day.toString().padLeft(2, '0');
    final String mes = fechaConvertida.month.toString().padLeft(2, '0');
    final String anio = fechaConvertida.year.toString();

    // Obtener hora y minutos.
    final String hora = fechaConvertida.hour.toString().padLeft(2, '0');
    final String minutos = fechaConvertida.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio - $hora:$minutos';
  }

  // Mostrar un mensaje informativo.
  void _mostrarMensaje(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Ejecutar la opcion de responder.
  void _responderComentario(BuildContext context) {
    // Verificar si existe una funcion configurada.
    if (onResponder != null) {
      onResponder!();
      return;
    }

    // Informar cuando la respuesta no esta integrada.
    _mostrarMensaje(
      context,
      'La funcion para responder comentarios '
      'todavia no esta disponible.',
    );
  }

  // Abrir la pantalla para reportar un comentario.
  Future<void> _reportarComentario(BuildContext context) async {
    // Obtener el identificador del comentario.
    final int? idComentario = _obtenerIdComentario();

    // Validar el identificador.
    if (idComentario == null) {
      _mostrarMensaje(
        context,
        'No se encontro un identificador '
        'valido para reportar este comentario.',
      );

      return;
    }

    // Abrir la pantalla de reportes.
    final bool? reportado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (contexto) =>
            ReportarContenidoView(idComentario: idComentario),
      ),
    );

    // Verificar que el componente siga disponible.
    if (!context.mounted) {
      return;
    }

    // Actualizar los comentarios si el reporte fue enviado.
    if (reportado == true) {
      onActualizar?.call();
    }
  }

  // Mostrar el menu de opciones del comentario.
  void _mostrarOpciones(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (contextoHoja) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Encabezado del menu.
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Opciones del comentario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),
                ),

                // Opcion para responder.
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Responder'),
                  onTap: () {
                    Navigator.pop(contextoHoja);

                    // Comprobar que el contexto siga disponible.
                    if (context.mounted) {
                      _responderComentario(context);
                    }
                  },
                ),

                // Opcion para reportar.
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Reportar comentario'),
                  onTap: () {
                    Navigator.pop(contextoHoja);

                    // Comprobar que el contexto siga disponible.
                    if (context.mounted) {
                      _reportarComentario(context);
                    }
                  },
                ),

                // Opcion para cerrar.
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancelar'),
                  onTap: () {
                    Navigator.pop(contextoHoja);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Construir el encabezado del comentario.
  Widget _construirEncabezado(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar representativo del usuario.
        CircleAvatar(
          radius: 23,
          backgroundColor: colores.primaryContainer,
          child: Icon(Icons.person_outline, color: colores.onPrimaryContainer),
        ),

        const SizedBox(width: 12),

        // Autor y fecha del comentario.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _obtenerAutor(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                _obtenerFecha(),
                style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
              ),
            ],
          ),
        ),

        // Menu de opciones.
        if (mostrarOpciones)
          IconButton(
            tooltip: 'Opciones del comentario',
            onPressed: () {
              _mostrarOpciones(context);
            },
            icon: const Icon(Icons.more_vert),
          ),
      ],
    );
  }

  // Construir las acciones del comentario.
  Widget _construirAcciones(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Accion para responder.
        TextButton.icon(
          onPressed: () {
            _responderComentario(context);
          },
          icon: const Icon(Icons.reply_outlined, size: 18),
          label: const Text('Responder'),
        ),

        // Accion para reportar.
        TextButton.icon(
          onPressed: () {
            _reportarComentario(context);
          },
          icon: Icon(
            Icons.flag_outlined,
            size: 18,
            color: colores.onSurfaceVariant,
          ),
          label: Text(
            'Reportar',
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con autor y fecha.
            _construirEncabezado(context),

            const SizedBox(height: 14),

            // Contenido principal del comentario.
            Text(
              _obtenerContenido(),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colores.onSurface,
              ),
            ),

            // Mostrar acciones si estan habilitadas.
            if (mostrarOpciones) ...[
              const SizedBox(height: 14),

              const Divider(),

              // Botones para responder y reportar.
              _construirAcciones(context),
            ],
          ],
        ),
      ),
    );
  }
}

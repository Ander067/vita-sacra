import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../views/reportar_contenido_view.dart';

class ComentarioCard extends StatelessWidget {
  final Map<String, dynamic> comentario;
  final VoidCallback? onResponder;
  final VoidCallback? onActualizar;
  final bool mostrarOpciones;

  const ComentarioCard({
    super.key,
    required this.comentario,
    this.onResponder,
    this.onActualizar,
    this.mostrarOpciones = true,
  });

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

  int? _obtenerIdComentario() {
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

  String _obtenerAutor() {
    final dynamic autor = comentario['autor'];

    if (autor is Map) {
      final dynamic nombre =
          autor['nombre'] ?? autor['nombre_usuario'] ?? autor['nom_usr'];

      if (nombre != null && nombre.toString().trim().isNotEmpty) {
        return nombre.toString().trim();
      }
    }

    if (autor is String && autor.trim().isNotEmpty) {
      return autor.trim();
    }

    return _obtenerTexto([
      'nombre_usuario',
      'nombre_autor',
      'nom_usr',
      'usuario',
    ], defecto: 'Usuario');
  }

  String _obtenerContenido() {
    return _obtenerTexto([
      'comentario',
      'contenido',
      'texto',
    ], defecto: 'Comentario sin contenido disponible.');
  }

  String _obtenerFecha() {
    final String fecha = _obtenerTexto([
      'fecha',
      'fecha_creacion',
      'fecha_comentario',
    ]);

    if (fecha.isEmpty) {
      return 'Fecha no disponible';
    }

    final DateTime? fechaConvertida = DateTime.tryParse(fecha);
    if (fechaConvertida == null) {
      return fecha;
    }

    final String dia = fechaConvertida.day.toString().padLeft(2, '0');
    final String mes = fechaConvertida.month.toString().padLeft(2, '0');
    final String anio = fechaConvertida.year.toString();
    final String hora = fechaConvertida.hour.toString().padLeft(2, '0');
    final String minutos = fechaConvertida.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$anio - $hora:$minutos';
  }

  List<Map<String, dynamic>> _obtenerAdjuntos() {
    final dynamic datos = comentario['adjuntos'];

    if (datos is! List) {
      return [];
    }

    return datos
        .whereType<Map>()
        .map((Map elemento) => Map<String, dynamic>.from(elemento))
        .toList();
  }

  String? _crearUrlAdjunto(dynamic valor) {
    if (valor is! String || valor.trim().isEmpty) {
      return null;
    }

    final String url = valor.trim();
    final Uri? uri = Uri.tryParse(url);

    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'https' || uri.scheme == 'http') {
        return uri.toString();
      }
      return null;
    }

    return ApiConfig.crearUri(url).toString();
  }

  void _mostrarMensaje(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _responderComentario(BuildContext context) {
    if (onResponder != null) {
      onResponder!();
      return;
    }

    _mostrarMensaje(
      context,
      'La función para responder comentarios todavía no está disponible.',
    );
  }

  Future<void> _reportarComentario(BuildContext context) async {
    final int? idComentario = _obtenerIdComentario();

    if (idComentario == null) {
      _mostrarMensaje(
        context,
        'No se encontró un identificador válido para reportar este comentario.',
      );
      return;
    }

    final bool? reportado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (contexto) =>
            ReportarContenidoView(idComentario: idComentario),
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (reportado == true) {
      onActualizar?.call();
    }
  }

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
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Responder'),
                  onTap: () {
                    Navigator.pop(contextoHoja);
                    if (context.mounted) {
                      _responderComentario(context);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Reportar comentario'),
                  onTap: () {
                    Navigator.pop(contextoHoja);
                    if (context.mounted) {
                      _reportarComentario(context);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.pop(contextoHoja),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _construirEncabezado(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: colores.primaryContainer,
          child: Icon(Icons.person_outline, color: colores.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
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
        if (mostrarOpciones)
          IconButton(
            tooltip: 'Opciones del comentario',
            onPressed: () => _mostrarOpciones(context),
            icon: const Icon(Icons.more_vert),
          ),
      ],
    );
  }

  Widget _construirAdjuntos(BuildContext context) {
    final List<Map<String, dynamic>> adjuntos = _obtenerAdjuntos();

    if (adjuntos.isEmpty) {
      return const SizedBox.shrink();
    }

    final ColorScheme colores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: adjuntos.map((Map<String, dynamic> adjunto) {
        final String? url = _crearUrlAdjunto(adjunto['url']);
        final String tipo = adjunto['tipo']?.toString() ?? 'recurso';
        final String titulo = adjunto['titulo']?.toString().trim() ?? '';

        if (url == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  width: double.infinity,
                  color: colores.surfaceContainerHighest,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined),
                            SizedBox(width: 8),
                            Text('No se pudo cargar el adjunto.'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (titulo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tipo == 'gif'
                        ? 'GIF'
                        : tipo == 'sticker'
                        ? 'Sticker'
                        : 'Imagen',
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _construirAcciones(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: () => _responderComentario(context),
          icon: const Icon(Icons.reply_outlined, size: 18),
          label: const Text('Responder'),
        ),
        TextButton.icon(
          onPressed: () => _reportarComentario(context),
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
            _construirEncabezado(context),
            const SizedBox(height: 14),
            Text(
              _obtenerContenido(),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colores.onSurface,
              ),
            ),
            _construirAdjuntos(context),
            if (mostrarOpciones) ...[
              const SizedBox(height: 14),
              const Divider(),
              _construirAcciones(context),
            ],
          ],
        ),
      ),
    );
  }
}

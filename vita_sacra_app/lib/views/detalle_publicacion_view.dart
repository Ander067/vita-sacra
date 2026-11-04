import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'anatomia_3d_view.dart';
import 'comentarios_view.dart';

// Pantalla de detalle de una publicacion.
class DetallePublicacionView extends StatefulWidget {
  // Identificador de la publicacion seleccionada.
  final int idBlog;

  const DetallePublicacionView({super.key, required this.idBlog});

  @override
  State<DetallePublicacionView> createState() => _DetallePublicacionViewState();
}

class _DetallePublicacionViewState extends State<DetallePublicacionView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Informacion de la publicacion y sus bloques.
  Map<String, dynamic>? _publicacion;
  List<Map<String, dynamic>> _bloques = [];

  // Variables de estado.
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _errorBloques;

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar la publicacion seleccionada.
    _cargarPublicacion();
  }

  @override
  void didUpdateWidget(covariant DetallePublicacionView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Actualizar la informacion cuando cambie la publicacion.
    if (oldWidget.idBlog != widget.idBlog) {
      _numeroSolicitud++;
      _publicacion = null;
      _bloques = [];
      _errorBloques = null;

      _cargarPublicacion();
    }
  }

  // Consultar el articulo y sus bloques publicados.
  Future<void> _cargarPublicacion() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;
    final int idBlog = widget.idBlog;

    setState(() {
      _cargando = true;
      _error = null;
      _errorBloques = null;
    });

    try {
      // Validar el identificador del articulo.
      if (idBlog <= 0) {
        throw const ApiException(
          'El identificador de la publicacion no es valido.',
        );
      }

      // Consultar el detalle publico del articulo.
      final dynamic respuesta = await _apiService.get('/posts/$idBlog');

      if (respuesta is! Map) {
        throw const ApiException('El formato de la publicacion no es valido.');
      }

      final Map<String, dynamic> publicacion = Map<String, dynamic>.from(
        respuesta,
      );

      // Consultar los bloques de la version publicada.
      List<Map<String, dynamic>> bloques = [];
      String? errorBloques;

      try {
        final dynamic respuestaBloques = await _apiService.get(
          '/recursos/publicaciones/$idBlog/bloques',
        );

        if (respuestaBloques is! List) {
          throw const FormatException(
            'El formato de los bloques no es valido.',
          );
        }

        for (final dynamic registro in respuestaBloques) {
          if (registro is! Map) {
            throw const FormatException('Se recibio un bloque no valido.');
          }

          bloques.add(Map<String, dynamic>.from(registro));
        }

        // Conservar el orden establecido por la publicacion.
        bloques.sort((primero, segundo) {
          final int ordenPrimero = int.tryParse('${primero['orden']}') ?? 0;

          final int ordenSegundo = int.tryParse('${segundo['orden']}') ?? 0;

          return ordenPrimero.compareTo(ordenSegundo);
        });
      } on ApiException catch (error) {
        // Permitir leer el articulo aunque fallen los bloques.
        errorBloques = error.mensaje;
      } catch (error) {
        errorBloques = 'No fue posible cargar el contenido adicional.';
      }

      // Evitar mostrar resultados de solicitudes anteriores.
      if (!mounted ||
          solicitud != _numeroSolicitud ||
          idBlog != widget.idBlog) {
        return;
      }

      setState(() {
        _publicacion = publicacion;
        _bloques = bloques;
        _errorBloques = errorBloques;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicacion = null;
        _bloques = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicacion = null;
        _bloques = [];
        _error = 'No fue posible cargar la publicacion.';
        _cargando = false;
      });
    }
  }

  // Obtener un campo de texto de la publicacion.
  String _obtenerTexto(String campo, {String alternativo = ''}) {
    final dynamic valor = _publicacion?[campo];

    if (valor == null) {
      return alternativo;
    }

    return valor.toString();
  }

  // Mostrar un mensaje informativo.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir los comentarios de la publicacion.
  void _abrirComentarios() {
    if (_publicacion == null || widget.idBlog <= 0) {
      _mostrarMensaje('No fue posible identificar la publicacion.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComentariosView(idBlog: widget.idBlog),
      ),
    );
  }

  // Abrir los modelos 3D de la publicacion.
  void _abrirModelos3D() {
    if (_publicacion == null || widget.idBlog <= 0) {
      _mostrarMensaje('No fue posible identificar la publicacion.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Anatomia3DView(idBlog: widget.idBlog),
      ),
    );
  }

  // Guardar la publicacion en la biblioteca personal.
  Future<void> _guardarPublicacion() async {
    if (!mounted || _guardando) {
      return;
    }

    if (_publicacion == null || widget.idBlog <= 0) {
      _mostrarMensaje('No fue posible identificar la publicacion.');
      return;
    }

    final int idBlog = widget.idBlog;

    setState(() {
      _guardando = true;
    });

    try {
      // Obtener el token JWT de la sesion.
      final String? token = await _authService.obtenerToken();

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      if (token == null || token.trim().isEmpty) {
        _mostrarMensaje('Debes iniciar sesion para guardar publicaciones.');
        return;
      }

      // Preparar los campos requeridos por FastAPI.
      final Map<String, dynamic> datos = {'blog_id': idBlog};

      // Registrar la publicacion en la biblioteca.
      final dynamic respuesta = await _apiService.post(
        '/interacciones/guardar',
        datos: datos,
        token: token,
      );

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      String mensaje = 'Publicacion guardada correctamente.';

      if (respuesta is Map &&
          respuesta['mensaje'] is String &&
          respuesta['mensaje'].toString().trim().isNotEmpty) {
        mensaje = respuesta['mensaje'].toString();
      }

      _mostrarMensaje(mensaje);
    } on ApiException catch (error) {
      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      if (error.codigoEstado == 401) {
        _mostrarMensaje('Tu sesion ha expirado. Inicia sesion nuevamente.');
      } else {
        _mostrarMensaje(error.mensaje);
      }
    } catch (error) {
      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      _mostrarMensaje('No fue posible guardar la publicacion.');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // Construir una imagen con un icono alternativo.
  Widget _construirImagenAlternativa({double altura = 180}) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      height: altura,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.menu_book_outlined,
        size: 55,
        color: colores.onPrimaryContainer,
      ),
    );
  }

  // Construir una imagen recibida desde FastAPI.
  Widget _construirImagenUrl(String imagen, {double altura = 200}) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final Uri? direccion = Uri.tryParse(imagen.trim());

    if (direccion == null ||
        !direccion.hasAuthority ||
        (direccion.scheme != 'http' && direccion.scheme != 'https')) {
      return _construirImagenAlternativa(altura: altura);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imagen,
        width: double.infinity,
        height: altura,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: altura,
            alignment: Alignment.center,
            color: colores.primaryContainer,
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 55,
              color: colores.onPrimaryContainer,
            ),
          );
        },
      ),
    );
  }

  // Construir la imagen principal del articulo.
  Widget _construirImagen() {
    final String imagen = _obtenerTexto('img');

    if (imagen.trim().isEmpty) {
      return _construirImagenAlternativa();
    }

    return _construirImagenUrl(imagen);
  }

  // Construir un bloque de contenido publicado.
  Widget _construirBloque(Map<String, dynamic> bloque) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String tipo = (bloque['tipo'] ?? '').toString().trim().toLowerCase();

    final String contenido = (bloque['contenido'] ?? '').toString().trim();

    final String recursoUrl = (bloque['recurso_url'] ?? '').toString().trim();

    final int? recursoId = int.tryParse('${bloque['recurso_id']}');

    switch (tipo) {
      case 'titulo':
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            contenido,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colores.primary,
            ),
          ),
        );

      case 'parrafo':
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SelectableText(
            contenido,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: colores.onSurface,
            ),
          ),
        );

      case 'lista':
        final List<String> elementos = contenido
            .split('\n')
            .map((elemento) => elemento.trim())
            .where((elemento) => elemento.isNotEmpty)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: elementos.map((elemento) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 7, color: colores.primary),

                    const SizedBox(width: 10),

                    Expanded(
                      child: SelectableText(
                        elemento,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: colores.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );

      case 'cita':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colores.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote, color: colores.onPrimaryContainer),

              const SizedBox(width: 10),

              Expanded(
                child: SelectableText(
                  contenido,
                  style: TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: colores.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );

      case 'imagen':
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _construirImagenUrl(recursoUrl),

              if (contenido.isNotEmpty) ...[
                const SizedBox(height: 8),

                Text(
                  contenido,
                  style: TextStyle(
                    fontSize: 12,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );

      case 'video':
        return _construirTarjetaRecurso(
          icono: Icons.play_circle_outline,
          titulo: 'Video educativo',
          descripcion: contenido.isNotEmpty
              ? contenido
              : 'Recurso multimedia asociado al articulo.',
          url: recursoUrl,
        );

      case 'modelo_3d':
        // Mostrar acceso solo a recursos vinculados y aprobados.
        if (recursoId == null || recursoId <= 0 || recursoUrl.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.view_in_ar_outlined,
                      size: 34,
                      color: colores.primary,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Modelo anatomico 3D',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colores.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),

                if (contenido.isNotEmpty) ...[
                  const SizedBox(height: 10),

                  Text(
                    contenido,
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                ],

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _abrirModelos3D,
                  icon: const Icon(Icons.view_in_ar_outlined),
                  label: const Text('Explorar recurso 3D'),
                ),
              ],
            ),
          ),
        );

      default:
        // Evitar inventar una representacion para tipos desconocidos.
        return const SizedBox.shrink();
    }
  }

  // Mostrar un recurso multimedia sin instalar dependencias.
  Widget _construirTarjetaRecurso({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required String url,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final Uri? direccion = Uri.tryParse(url);

    final bool enlaceValido =
        direccion != null &&
        direccion.hasAuthority &&
        direccion.scheme == 'https';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 32, color: colores.primary),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              descripcion,
              style: TextStyle(color: colores.onSurfaceVariant),
            ),

            if (enlaceValido) ...[
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));

                  _mostrarMensaje('Enlace del recurso copiado.');
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copiar enlace'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir la informacion del articulo.
  Widget _construirDetalle() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los campos disponibles.
    final String titulo = _obtenerTexto('titulo', alternativo: 'Sin titulo');

    final String descripcion = _obtenerTexto('descripcion');
    final String fecha = _obtenerTexto('fecha_publicacion');
    final String autor = _obtenerTexto('autor');
    final String advertencia = _obtenerTexto('advertencia');

    // Identificar si existen bloques de texto estructurado.
    final bool contieneTexto = _bloques.any((bloque) {
      final String tipo = (bloque['tipo'] ?? '').toString().toLowerCase();

      return tipo == 'titulo' ||
          tipo == 'parrafo' ||
          tipo == 'lista' ||
          tipo == 'cita';
    });

    return RefreshIndicator(
      onRefresh: _cargarPublicacion,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Imagen principal de la publicacion.
          _construirImagen(),

          const SizedBox(height: 22),

          // Titulo del articulo.
          Text(
            titulo,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: colores.primary,
            ),
          ),

          const SizedBox(height: 14),

          // Autor cuando este disponible.
          if (autor.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 19,
                  color: colores.onSurfaceVariant,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    autor,
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
          ],

          // Fecha cuando este disponible.
          if (fecha.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: colores.onSurfaceVariant,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    fecha,
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
          ],

          const Divider(height: 30),

          // Encabezado del contenido.
          Text(
            'Contenido del articulo',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),

          const SizedBox(height: 14),

          // Mostrar la descripcion general como introduccion.
          if (descripcion.isNotEmpty) ...[
            SelectableText(
              descripcion,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: colores.onSurface,
              ),
            ),

            const SizedBox(height: 18),
          ],

          // Mostrar los bloques reales de la version publicada.
          if (_bloques.isNotEmpty) ...[
            for (final Map<String, dynamic> bloque in _bloques)
              _construirBloque(bloque),
          ],

          // Mostrar un mensaje si no existe contenido textual.
          if (descripcion.isEmpty && !contieneTexto)
            Text(
              'No hay una descripcion disponible.',
              style: TextStyle(fontSize: 15, color: colores.onSurfaceVariant),
            ),

          // Informar si fallo solamente la consulta de bloques.
          if (_errorBloques != null) ...[
            const SizedBox(height: 12),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: colores.onSurfaceVariant,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    'No se pudo cargar el contenido adicional. '
                    'Desliza hacia abajo para reintentar.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // Advertencia particular de la publicacion.
          if (advertencia.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colores.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: colores.onPrimaryContainer),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      advertencia,
                      style: TextStyle(color: colores.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],

          // Aviso informativo general.
          Text(
            'La informacion publicada es de caracter '
            'informativo y no sustituye la consulta '
            'con un profesional de la salud.',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),

          const SizedBox(height: 30),

          // Accesos a comentarios y guardados.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _abrirComentarios,
                  icon: const Icon(Icons.comment_outlined),
                  label: const Text('Comentarios'),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _guardando ? null : _guardarPublicacion,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_border),
                  label: Text(_guardando ? 'Guardando...' : 'Guardar'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Construir el estado de la pantalla.
  Widget _construirContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 50),

              const SizedBox(height: 14),

              Text(_error!, textAlign: TextAlign.center),

              const SizedBox(height: 18),

              OutlinedButton.icon(
                onPressed: _cargarPublicacion,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_publicacion == null) {
      return const Center(child: Text('No se encontro la publicacion.'));
    }

    return _construirDetalle();
  }

  @override
  void dispose() {
    // Invalidar las solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar los servicios utilizados.
    _apiService.cerrar();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de la publicacion.
      appBar: AppBar(
        title: const Text('Detalle de publicacion'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar publicacion',
            onPressed: _cargando ? null : _cargarPublicacion,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      // Contenido del articulo.
      body: SafeArea(child: _construirContenido()),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/comentario_card.dart';

// Pantalla para consultar, publicar y responder comentarios.
class ComentariosView extends StatefulWidget {
  // Identificador de la publicacion.
  final int idBlog;

  const ComentariosView({super.key, required this.idBlog});

  @override
  State<ComentariosView> createState() => _ComentariosViewState();
}

class _ComentariosViewState extends State<ComentariosView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Controlador y clave del formulario.
  final TextEditingController _comentarioController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _comentarioFocus = FocusNode();

  // Comentarios recibidos desde FastAPI.
  List<Map<String, dynamic>> _comentarios = [];

  // Comentario al que se esta respondiendo.
  int? _comentarioPadreId;
  String? _autorRespuesta;

  // Variables de estado.
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  // Identificador de la ultima solicitud de lectura.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar los comentarios al abrir la pantalla.
    _cargarComentarios();
  }

  @override
  void didUpdateWidget(covariant ComentariosView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Actualizar la informacion si cambia la publicacion.
    if (oldWidget.idBlog != widget.idBlog) {
      _numeroSolicitud++;
      _comentarioController.clear();
      _comentarioPadreId = null;
      _autorRespuesta = null;
      _comentarios = [];
      _cargarComentarios();
    }
  }

  // Convertir identificadores recibidos desde FastAPI.
  int? _convertirEntero(dynamic valor) {
    if (valor is int) {
      return valor > 0 ? valor : null;
    }

    if (valor is num) {
      if (!valor.isFinite || valor != valor.truncateToDouble()) {
        return null;
      }
      final int numero = valor.toInt();
      return numero > 0 ? numero : null;
    }

    final int? numero = int.tryParse(valor?.toString().trim() ?? '');
    return numero != null && numero > 0 ? numero : null;
  }

  // Consultar los comentarios de una publicacion.
  Future<void> _cargarComentarios() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;
    final int idBlog = widget.idBlog;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Validar el identificador de la publicacion.
      if (idBlog <= 0) {
        throw const ApiException(
          'El identificador de la publicacion no es valido.',
        );
      }

      // Consultar el endpoint publico de comentarios.
      final dynamic respuesta = await _apiService.get(
        '/posts/$idBlog/comentarios',
      );

      if (respuesta is! List) {
        throw const ApiException('El formato de los comentarios no es valido.');
      }

      // Convertir los registros recibidos.
      final List<Map<String, dynamic>> comentarios = [];
      for (final dynamic registro in respuesta) {
        if (registro is! Map) {
          throw const ApiException('Se recibio un comentario no valido.');
        }
        comentarios.add(Map<String, dynamic>.from(registro));
      }

      // Evitar actualizar una pantalla cerrada o una consulta anterior.
      if (!mounted ||
          solicitud != _numeroSolicitud ||
          idBlog != widget.idBlog) {
        return;
      }

      setState(() {
        _comentarios = comentarios;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted ||
          solicitud != _numeroSolicitud ||
          idBlog != widget.idBlog) {
        return;
      }

      setState(() {
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted ||
          solicitud != _numeroSolicitud ||
          idBlog != widget.idBlog) {
        return;
      }

      setState(() {
        _error = 'No fue posible cargar los comentarios.';
        _cargando = false;
      });
    }
  }

  // Validar el contenido del comentario.
  String? _validarComentario(String? valor) {
    final String contenido = valor?.trim() ?? '';

    if (contenido.isEmpty) {
      return 'Escribe un comentario antes de publicarlo.';
    }

    if (contenido.length > 5000) {
      return 'El comentario no puede superar los 5000 caracteres.';
    }

    return null;
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Seleccionar el comentario al que se desea responder.
  void _responderComentario(Map<String, dynamic> comentario) {
    if (_enviando) {
      return;
    }

    final int? idComentario = _convertirEntero(comentario['id_com']);

    if (idComentario == null) {
      _mostrarMensaje('No fue posible identificar el comentario.');
      return;
    }

    final dynamic autor = comentario['autor'];
    final String nombreAutor = autor is String && autor.trim().isNotEmpty
        ? autor.trim()
        : 'Usuario';

    setState(() {
      _comentarioPadreId = idComentario;
      _autorRespuesta = nombreAutor;
    });

    // Facilitar la escritura de la respuesta.
    _comentarioFocus.requestFocus();
  }

  // Cancelar la respuesta y regresar al comentario general.
  void _cancelarRespuesta() {
    if (_enviando) {
      return;
    }

    setState(() {
      _comentarioPadreId = null;
      _autorRespuesta = null;
    });
  }

  // Registrar un comentario o respuesta mediante FastAPI.
  Future<void> _publicarComentario() async {
    if (!mounted || _enviando) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final int idBlog = widget.idBlog;
    final int? comentarioPadreId = _comentarioPadreId;
    final String contenido = _comentarioController.text.trim();

    if (idBlog <= 0) {
      _mostrarMensaje('El identificador de la publicacion no es valido.');
      return;
    }

    setState(() {
      _enviando = true;
    });

    try {
      // Recuperar el token JWT del usuario.
      final String? token = await _authService.obtenerToken();

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      if (token == null || token.trim().isEmpty) {
        _mostrarMensaje('Debes iniciar sesion para comentar.');
        return;
      }

      // Preparar los campos exactos de ComentarioRegistro.
      final Map<String, dynamic> datos = {
        'blog_id': idBlog,
        'comentario': contenido,
      };

      // Agregar el identificador padre solamente para respuestas.
      if (comentarioPadreId != null) {
        datos['com_padre_id'] = comentarioPadreId;
      }

      // Registrar el comentario en el endpoint real.
      await _apiService.post(
        '/comentarios/registrar',
        datos: datos,
        token: token,
      );

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      // Limpiar el formulario despues del registro exitoso.
      _comentarioController.clear();
      _comentarioFocus.unfocus();
      setState(() {
        _comentarioPadreId = null;
        _autorRespuesta = null;
      });
      _formKey.currentState?.reset();

      _mostrarMensaje(
        comentarioPadreId == null
            ? 'Comentario publicado correctamente.'
            : 'Respuesta publicada correctamente.',
      );

      // Actualizar el listado con los datos del servidor.
      await _cargarComentarios();
    } on ApiException catch (error) {
      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      _mostrarMensaje(
        error.codigoEstado == 401
            ? 'Tu sesion ha expirado. Inicia sesion nuevamente.'
            : error.mensaje,
      );
    } catch (error) {
      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      _mostrarMensaje('No fue posible publicar el comentario.');
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  // Construir la tarjeta reutilizable de un comentario.
  Widget _crearComentario(Map<String, dynamic> comentario) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final int? comentarioPadreId = _convertirEntero(comentario['com_padre_id']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Identificar las respuestas a otros comentarios.
        if (comentarioPadreId != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 17,
                  color: colores.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Respuesta al comentario #$comentarioPadreId',
                    style: TextStyle(
                      fontSize: 12,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Utilizar el widget compartido para mostrar y reportar comentarios.
        ComentarioCard(
          comentario: comentario,
          onResponder: _enviando
              ? null
              : () => _responderComentario(comentario),
          onActualizar: _cargarComentarios,
        ),
      ],
    );
  }

  // Construir la lista de comentarios.
  Widget _construirComentarios() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 45),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _cargarComentarios,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_comentarios.isEmpty) {
      return const Center(
        child: Text(
          'Todavia no hay comentarios. Se el primero en participar.',
          textAlign: TextAlign.center,
        ),
      );
    }

    // Mostrar los comentarios recibidos.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
      itemCount: _comentarios.length,
      itemBuilder: (context, indice) {
        final Map<String, dynamic> comentario = _comentarios[indice];
        return _crearComentario(comentario);
      },
    );
  }

  @override
  void dispose() {
    // Invalidar solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar los recursos utilizados.
    _comentarioFocus.dispose();
    _comentarioController.dispose();
    _apiService.cerrar();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      // Barra superior de comentarios.
      appBar: AppBar(
        title: const Text('Comentarios'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar comentarios',
            onPressed: _cargando ? null : _cargarComentarios,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado de la pantalla.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comunidad Vita Sacra',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: colores.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Comparte tus opiniones y participa en la conversacion.',
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // Listado de comentarios.
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargarComentarios,
                child: _cargando || _error != null || _comentarios.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: 250, child: _construirComentarios()),
                        ],
                      )
                    : _construirComentarios(),
              ),
            ),

            // Formulario para registrar comentarios.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colores.surface,
                border: Border(top: BorderSide(color: colores.outlineVariant)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mostrar el comentario que se respondera.
                    if (_comentarioPadreId != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colores.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.reply,
                              color: colores.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Respondiendo a ${_autorRespuesta ?? "Usuario"}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colores.onPrimaryContainer,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cancelar respuesta',
                              onPressed: _enviando ? null : _cancelarRespuesta,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Campo de escritura.
                    TextFormField(
                      controller: _comentarioController,
                      focusNode: _comentarioFocus,
                      enabled: !_enviando,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 5000,
                      decoration: InputDecoration(
                        labelText: _comentarioPadreId == null
                            ? 'Escribir comentario'
                            : 'Escribir respuesta',
                        hintText: 'Comparte tu opinion...',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validarComentario,
                    ),
                    const SizedBox(height: 10),

                    // Boton para publicar.
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _enviando ? null : _publicarComentario,
                        icon: _enviando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(
                          _enviando
                              ? 'Publicando...'
                              : _comentarioPadreId == null
                              ? 'Publicar comentario'
                              : 'Publicar respuesta',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

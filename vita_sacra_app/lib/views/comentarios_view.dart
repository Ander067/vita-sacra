import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/comentario_card.dart';

class ComentariosView extends StatefulWidget {
  final int idBlog;

  const ComentariosView({super.key, required this.idBlog});

  @override
  State<ComentariosView> createState() => _ComentariosViewState();
}

class _ComentariosViewState extends State<ComentariosView> {
  static const int _maximoBytesImagen = 3 * 1024 * 1024;

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final ImagePicker _selectorImagen = ImagePicker();

  final TextEditingController _comentarioController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _comentarioFocus = FocusNode();

  List<Map<String, dynamic>> _comentarios = [];
  List<Map<String, dynamic>> _catalogo = [];

  XFile? _imagenSeleccionada;
  Map<String, dynamic>? _recursoCatalogoSeleccionado;

  int? _comentarioPadreId;
  String? _autorRespuesta;

  bool _cargando = true;
  bool _cargandoCatalogo = false;
  bool _enviando = false;
  String? _error;

  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();
    _cargarComentarios();
  }

  @override
  void didUpdateWidget(covariant ComentariosView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.idBlog != widget.idBlog) {
      _numeroSolicitud++;
      _comentarioController.clear();
      _comentarioPadreId = null;
      _autorRespuesta = null;
      _imagenSeleccionada = null;
      _recursoCatalogoSeleccionado = null;
      _comentarios = [];
      _cargarComentarios();
    }
  }

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

  String? _urlRecurso(dynamic valor) {
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
      if (idBlog <= 0) {
        throw const ApiException(
          'El identificador de la publicación no es válido.',
        );
      }

      final dynamic respuesta = await _apiService.get(
        '/comentarios/publicacion/$idBlog',
      );

      if (respuesta is! List) {
        throw const ApiException('El formato de los comentarios no es válido.');
      }

      final List<Map<String, dynamic>> comentarios = [];

      for (final dynamic registro in respuesta) {
        if (registro is! Map) {
          throw const ApiException('Se recibió un comentario no válido.');
        }
        comentarios.add(Map<String, dynamic>.from(registro));
      }

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

  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

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

    _comentarioFocus.requestFocus();
  }

  void _cancelarRespuesta() {
    if (_enviando) {
      return;
    }

    setState(() {
      _comentarioPadreId = null;
      _autorRespuesta = null;
    });
  }

  Future<void> _seleccionarImagen() async {
    if (_enviando) {
      return;
    }

    try {
      final XFile? seleccionada = await _selectorImagen.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (seleccionada == null || !mounted) {
        return;
      }

      final int bytes = await File(seleccionada.path).length();

      if (bytes > _maximoBytesImagen) {
        _mostrarMensaje('La imagen seleccionada supera el límite de 3 MB.');
        return;
      }

      setState(() {
        _imagenSeleccionada = seleccionada;
      });
    } catch (error) {
      _mostrarMensaje('No fue posible seleccionar la imagen.');
    }
  }

  Future<void> _cargarCatalogo() async {
    if (_catalogo.isNotEmpty) {
      return;
    }

    if (_cargandoCatalogo) {
      return;
    }

    setState(() {
      _cargandoCatalogo = true;
    });

    try {
      final dynamic respuesta = await _apiService.get('/comentarios/catalogo');

      if (respuesta is! List) {
        throw const ApiException('El catálogo recibido no es válido.');
      }

      final List<Map<String, dynamic>> catalogo = [];

      for (final dynamic recurso in respuesta) {
        if (recurso is Map) {
          catalogo.add(Map<String, dynamic>.from(recurso));
        }
      }

      if (mounted) {
        setState(() {
          _catalogo = catalogo;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargandoCatalogo = false;
        });
      }
    }
  }

  Future<void> _abrirCatalogo() async {
    if (_enviando) {
      return;
    }

    try {
      await _cargarCatalogo();

      if (!mounted) {
        return;
      }

      if (_catalogo.isEmpty) {
        _mostrarMensaje('Todavía no hay stickers o GIF aprobados.');
        return;
      }

      final Map<String, dynamic>?
      seleccionado = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (contextoHoja) {
          final ColorScheme colores = Theme.of(contextoHoja).colorScheme;

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(contextoHoja).size.height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Stickers y GIF aprobados',
                      style: Theme.of(contextoHoja).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _catalogo.length,
                      itemBuilder: (contexto, indice) {
                        final Map<String, dynamic> recurso = _catalogo[indice];
                        final String titulo =
                            recurso['titulo']?.toString().trim() ?? '';
                        final String tipo =
                            recurso['tipo']?.toString() ?? 'recurso';
                        final String licencia =
                            recurso['licencia']?.toString() ?? '';
                        final String procedencia =
                            recurso['procedencia']?.toString() ?? '';
                        final String? url = _urlRecurso(recurso['url']);

                        return ListTile(
                          leading: SizedBox(
                            width: 52,
                            height: 52,
                            child: url == null
                                ? const Icon(Icons.broken_image_outlined)
                                : Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (contexto, error, traza) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                          title: Text(
                            titulo.isEmpty ? tipo : titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$tipo · $licencia · $procedencia',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colores.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(contextoHoja, recurso);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (seleccionado != null && mounted) {
        setState(() {
          _recursoCatalogoSeleccionado = seleccionado;
        });
      }
    } on ApiException catch (error) {
      _mostrarMensaje(error.mensaje);
    } catch (error) {
      _mostrarMensaje('No fue posible cargar el catálogo.');
    }
  }

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
    final XFile? imagen = _imagenSeleccionada;
    final int? recursoCatalogoId = _convertirEntero(
      _recursoCatalogoSeleccionado?['id_recurso'],
    );

    if (idBlog <= 0) {
      _mostrarMensaje('El identificador de la publicación no es válido.');
      return;
    }

    setState(() {
      _enviando = true;
    });

    try {
      final String? token = await _authService.obtenerToken();

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      if (token == null || token.trim().isEmpty) {
        _mostrarMensaje('Debes iniciar sesión para comentar.');
        return;
      }

      dynamic respuesta;

      if (imagen != null || recursoCatalogoId != null) {
        final Map<String, String> campos = {
          'blog_id': idBlog.toString(),
          'comentario': contenido,
        };

        if (comentarioPadreId != null) {
          campos['com_padre_id'] = comentarioPadreId.toString();
        }

        if (recursoCatalogoId != null) {
          campos['recurso_catalogo_id'] = recursoCatalogoId.toString();
        }

        respuesta = await _apiService.postArchivo(
          '/comentarios/registrar-multimedia',
          campos: campos,
          rutaArchivo: imagen?.path,
          token: token,
        );
      } else {
        final Map<String, dynamic> datos = {
          'blog_id': idBlog,
          'comentario': contenido,
        };

        if (comentarioPadreId != null) {
          datos['com_padre_id'] = comentarioPadreId;
        }

        respuesta = await _apiService.post(
          '/comentarios/registrar',
          datos: datos,
          token: token,
        );
      }

      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      _comentarioController.clear();
      _comentarioFocus.unfocus();

      setState(() {
        _comentarioPadreId = null;
        _autorRespuesta = null;
        _imagenSeleccionada = null;
        _recursoCatalogoSeleccionado = null;
      });

      _formKey.currentState?.reset();

      final bool imagenPendiente =
          respuesta is Map && respuesta['estatus_imagen'] == 'pendiente';

      final String mensaje = imagenPendiente
          ? 'Comentario publicado. La imagen quedará visible después de su revisión.'
          : recursoCatalogoId != null
          ? 'Comentario publicado con el recurso aprobado.'
          : comentarioPadreId == null
          ? 'Comentario publicado correctamente.'
          : 'Respuesta publicada correctamente.';

      _mostrarMensaje(mensaje);
      await _cargarComentarios();
    } on ApiException catch (error) {
      if (!mounted || idBlog != widget.idBlog) {
        return;
      }

      _mostrarMensaje(
        error.codigoEstado == 401
            ? 'Tu sesión ha expirado. Inicia sesión nuevamente.'
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

  Widget _crearComentario(Map<String, dynamic> comentario) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final int? comentarioPadreId = _convertirEntero(comentario['com_padre_id']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          'Todavía no hay comentarios. Sé el primero en participar.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
      itemCount: _comentarios.length,
      itemBuilder: (context, indice) {
        return _crearComentario(_comentarios[indice]);
      },
    );
  }

  Widget _construirAdjuntosSeleccionados() {
    final List<Widget> elementos = [];

    if (_imagenSeleccionada != null) {
      elementos.add(
        Chip(
          avatar: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Imagen seleccionada'),
          onDeleted: _enviando
              ? null
              : () => setState(() {
                  _imagenSeleccionada = null;
                }),
        ),
      );
    }

    if (_recursoCatalogoSeleccionado != null) {
      final String titulo =
          _recursoCatalogoSeleccionado!['titulo']?.toString().trim() ?? '';
      final String tipo =
          _recursoCatalogoSeleccionado!['tipo']?.toString() ?? 'recurso';

      elementos.add(
        Chip(
          avatar: Icon(
            tipo == 'gif'
                ? Icons.gif_box_outlined
                : Icons.emoji_emotions_outlined,
            size: 18,
          ),
          label: Text(titulo.isEmpty ? tipo : titulo),
          onDeleted: _enviando
              ? null
              : () => setState(() {
                  _recursoCatalogoSeleccionado = null;
                }),
        ),
      );
    }

    if (elementos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: elementos),
    );
  }

  @override
  void dispose() {
    _numeroSolicitud++;
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
                    'Comparte tus opiniones, emojis y recursos aprobados.',
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                ],
              ),
            ),
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
                    TextFormField(
                      controller: _comentarioController,
                      focusNode: _comentarioFocus,
                      enabled: !_enviando,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 5000,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: _comentarioPadreId == null
                            ? 'Escribir comentario'
                            : 'Escribir respuesta',
                        hintText: 'Comparte tu opinión o usa emojis...',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validarComentario,
                    ),
                    _construirAdjuntosSeleccionados(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _enviando ? null : _seleccionarImagen,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Imagen (máx. 3 MB)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _enviando ? null : _abrirCatalogo,
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          label: const Text('Sticker/GIF'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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

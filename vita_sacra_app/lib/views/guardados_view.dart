import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para consultar las publicaciones guardadas.
class GuardadosView extends StatefulWidget {
  const GuardadosView({super.key});

  @override
  State<GuardadosView> createState() => _GuardadosViewState();
}

class _GuardadosViewState extends State<GuardadosView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Lista de publicaciones guardadas.
  List<Map<String, dynamic>> _guardados = [];

  // Variables de estado.
  bool _cargando = true;
  bool _requiereSesion = false;
  bool _eliminando = false;
  String? _error;

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar los guardados al iniciar la pantalla.
    _cargarGuardados();
  }

  // Consultar las publicaciones guardadas del usuario.
  Future<void> _cargarGuardados() async {
    if (!mounted) {
      return;
    }

    // Registrar la solicitud actual.
    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _requiereSesion = false;
      _error = null;
    });

    try {
      // Obtener el token de la sesion.
      final String? token = await _authService.obtenerToken();

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Comprobar que el usuario inicio sesion.
      if (token == null || token.trim().isEmpty) {
        setState(() {
          _guardados = [];
          _requiereSesion = true;
          _cargando = false;
        });

        return;
      }

      // Consultar los guardados mediante FastAPI.
      final dynamic respuesta = await _apiService.get(
        '/interacciones/guardados',
        token: token,
      );

      // Identificar la lista de registros.
      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['guardados'] ??
            respuesta['publicaciones'] ??
            respuesta['results'];
      }

      // Validar el formato de la respuesta.
      if (registros is! List) {
        throw const ApiException('El formato de los guardados no es valido.');
      }

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> guardados = registros.map((registro) {
        if (registro is! Map) {
          throw const ApiException('Se recibio un registro no valido.');
        }

        return Map<String, dynamic>.from(registro);
      }).toList();

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _guardados = guardados;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _guardados = [];
        _error = error.mensaje;
        _requiereSesion = error.codigoEstado == 401;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _guardados = [];
        _error = 'No fue posible cargar los guardados.';
        _cargando = false;
      });
    }
  }

  // Obtener los datos de una publicacion guardada.
  Map<String, dynamic> _obtenerPublicacion(Map<String, dynamic> guardado) {
    // Algunas respuestas contienen un objeto anidado.
    final dynamic publicacion = guardado['publicacion'];

    if (publicacion is Map) {
      return Map<String, dynamic>.from(publicacion);
    }

    // Utilizar el registro completo si no esta anidado.
    return guardado;
  }

  // Obtener el identificador de una publicacion.
  int? _obtenerId(Map<String, dynamic> guardado) {
    final Map<String, dynamic> publicacion = _obtenerPublicacion(guardado);

    final dynamic identificador =
        publicacion['id_blog'] ??
        publicacion['blog_id'] ??
        guardado['id_blog'] ??
        guardado['blog_id'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir el detalle de una publicacion guardada.
  Future<void> _abrirPublicacion(Map<String, dynamic> guardado) async {
    // Obtener el identificador del articulo.
    final int? idBlog = _obtenerId(guardado);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La publicacion no tiene un identificador valido.');
      return;
    }

    // Navegar hacia el detalle de la publicacion.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );

    // Actualizar la biblioteca al regresar.
    if (mounted) {
      await _cargarGuardados();
    }
  }

  // Eliminar una publicacion de la biblioteca.
  Future<void> _eliminarGuardado(Map<String, dynamic> guardado) async {
    if (!mounted || _eliminando) {
      return;
    }

    // Obtener el identificador de la publicacion.
    final int? idBlog = _obtenerId(guardado);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('No se encontro el identificador del articulo.');
      return;
    }

    // Solicitar confirmacion al usuario.
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar guardado'),
          content: const Text(
            '¿Deseas quitar esta publicacion '
            'de tu biblioteca personal?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmar != true || _eliminando) {
      return;
    }

    setState(() {
      _eliminando = true;
    });

    try {
      // Recuperar el token del usuario.
      final String? token = await _authService.obtenerToken();

      if (!mounted) {
        return;
      }

      // Verificar que exista una sesion iniciada.
      if (token == null || token.trim().isEmpty) {
        _mostrarMensaje('Debes iniciar sesion para modificar tus guardados.');
        return;
      }

      // Eliminar el registro mediante FastAPI.
      await _apiService.delete(
        '/interacciones/guardados/$idBlog',
        token: token,
      );

      if (!mounted) {
        return;
      }

      _mostrarMensaje('Publicacion retirada de guardados correctamente.');

      // Consultar nuevamente los registros actualizados.
      await _cargarGuardados();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje(error.mensaje);

      // Actualizar la biblioteca si el registro ya no existe.
      if (error.codigoEstado == 404) {
        await _cargarGuardados();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible eliminar la publicacion guardada.');
    } finally {
      if (mounted) {
        setState(() {
          _eliminando = false;
        });
      }
    }
  }

  // Construir una tarjeta de publicacion guardada.
  Widget _crearGuardado(Map<String, dynamic> guardado) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los datos de la publicacion.
    final Map<String, dynamic> publicacion = _obtenerPublicacion(guardado);

    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion =
        (publicacion['descripcion'] ?? publicacion['desc'] ?? '').toString();

    final String? imagen = publicacion['img']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _abrirPublicacion(guardado);
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mostrar imagen o icono alternativo.
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imagen != null && imagen.trim().isNotEmpty
                    ? Image.network(
                        imagen,
                        width: 75,
                        height: 85,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _crearIconoImagen(colores);
                        },
                      )
                    : _crearIconoImagen(colores),
              ),

              const SizedBox(width: 12),

              // Informacion de la publicacion.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Text(
                      descripcion.isNotEmpty
                          ? descripcion
                          : 'Sin descripcion disponible.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Leer articulo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colores.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Opcion para quitar el guardado.
              IconButton(
                tooltip: 'Quitar de guardados',
                onPressed: _eliminando
                    ? null
                    : () {
                        _eliminarGuardado(guardado);
                      },
                icon: Icon(
                  Icons.bookmark_remove_outlined,
                  color: colores.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir el icono alternativo de imagen.
  Widget _crearIconoImagen(ColorScheme colores) {
    return Container(
      width: 75,
      height: 85,
      alignment: Alignment.center,
      color: colores.primaryContainer,
      child: Icon(
        Icons.bookmark_added_outlined,
        size: 35,
        color: colores.onPrimaryContainer,
      ),
    );
  }

  // Construir los mensajes de estado.
  Widget _construirEstado({
    required IconData icono,
    required String titulo,
    required String descripcion,
    bool mostrarReintento = false,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 55, color: colores.primary),

            const SizedBox(height: 14),

            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colores.onSurface,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurfaceVariant),
            ),

            if (mostrarReintento) ...[
              const SizedBox(height: 18),

              OutlinedButton.icon(
                onPressed: _cargarGuardados,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir el listado de guardados.
  Widget _construirGuardados() {
    // Mostrar indicador de carga.
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar mensaje cuando no existe una sesion.
    if (_requiereSesion) {
      return _construirEstado(
        icono: Icons.lock_outline,
        titulo: 'Inicia sesion',
        descripcion:
            'Necesitas iniciar sesion para consultar '
            'tus publicaciones guardadas.',
      );
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return _construirEstado(
        icono: Icons.error_outline,
        titulo: 'No se pudieron cargar',
        descripcion: _error!,
        mostrarReintento: true,
      );
    }

    // Mostrar mensaje si no hay publicaciones guardadas.
    if (_guardados.isEmpty) {
      return _construirEstado(
        icono: Icons.bookmark_border,
        titulo: 'Tu biblioteca esta vacia',
        descripcion:
            'Cuando guardes publicaciones, '
            'apareceran en esta seccion.',
      );
    }

    // Mostrar las publicaciones guardadas.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _guardados.length,
      itemBuilder: (context, indice) {
        return _crearGuardado(_guardados[indice]);
      },
    );
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

      // Barra superior de guardados.
      appBar: AppBar(
        title: const Text('Mis guardados'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar guardados',
            onPressed: _cargando || _eliminando ? null : _cargarGuardados,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la biblioteca.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.bookmark_added_outlined,
                      size: 30,
                      color: colores.onPrimaryContainer,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mi biblioteca',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Consulta las publicaciones '
                          'que guardaste para despues.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colores.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Encabezado de resultados.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Publicaciones guardadas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                  ),

                  if (!_cargando && !_requiereSesion && _error == null)
                    Text(
                      '${_guardados.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Listado de publicaciones guardadas.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarGuardados,
                  child:
                      _cargando ||
                          _requiereSesion ||
                          _error != null ||
                          _guardados.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: 300, child: _construirGuardados()),
                          ],
                        )
                      : _construirGuardados(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

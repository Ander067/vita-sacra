import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para consultar las categorias del blog.
class CategoriasView extends StatefulWidget {
  const CategoriasView({super.key});

  @override
  State<CategoriasView> createState() => _CategoriasViewState();
}

class _CategoriasViewState extends State<CategoriasView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Controlador del buscador.
  final TextEditingController _buscarController = TextEditingController();

  // Listas de categorias.
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _filtradas = [];

  // Variables de estado.
  bool _cargando = true;
  String? _error;

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Escuchar los cambios del buscador.
    _buscarController.addListener(_filtrarCategorias);

    // Consultar las categorias al iniciar.
    _cargarCategorias();
  }

  // Consultar las categorias mediante FastAPI.
  Future<void> _cargarCategorias() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Consultar las categorias activas.
      final dynamic respuesta = await _apiService.get('/categorias');

      // El endpoint devuelve directamente una lista.
      if (respuesta is! List) {
        throw const ApiException('El formato de las categorias no es valido.');
      }

      // Convertir los registros recibidos.
      final List<Map<String, dynamic>> categorias = [];

      for (final dynamic registro in respuesta) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una categoria no valida.');
        }

        categorias.add(Map<String, dynamic>.from(registro));
      }

      // Evitar sobrescribir una consulta mas reciente.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _categorias = categorias;
        _cargando = false;
      });

      // Aplicar el termino de busqueda actual.
      _filtrarCategorias();
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _categorias = [];
        _filtradas = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _categorias = [];
        _filtradas = [];
        _error = 'No fue posible cargar las categorias.';
        _cargando = false;
      });
    }
  }

  // Filtrar las categorias por nombre o descripcion.
  void _filtrarCategorias() {
    if (!mounted) {
      return;
    }

    final String busqueda = _buscarController.text.trim().toLowerCase();

    final List<Map<String, dynamic>> resultados = _categorias.where((
      categoria,
    ) {
      final String nombre = (categoria['nombre'] ?? '')
          .toString()
          .toLowerCase();

      final String descripcion = (categoria['descripcion'] ?? '')
          .toString()
          .toLowerCase();

      return nombre.contains(busqueda) || descripcion.contains(busqueda);
    }).toList();

    setState(() {
      _filtradas = resultados;
    });
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Obtener el identificador de una categoria.
  int? _obtenerIdCategoria(Map<String, dynamic> categoria) {
    final dynamic identificador = categoria['id_categoria'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Abrir las publicaciones correspondientes a una categoria.
  void _abrirCategoria(Map<String, dynamic> categoria) {
    final int? idCategoria = _obtenerIdCategoria(categoria);

    if (idCategoria == null || idCategoria <= 0) {
      _mostrarMensaje('La categoria no tiene un identificador valido.');
      return;
    }

    final String nombre = (categoria['nombre'] ?? '').toString().trim();

    if (nombre.isEmpty) {
      _mostrarMensaje('La categoria no tiene un nombre valido.');
      return;
    }

    // Abrir la pantalla de publicaciones de la categoria.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PublicacionesCategoriaView(
          idCategoria: idCategoria,
          nombreCategoria: nombre,
        ),
      ),
    );
  }

  // Construir la tarjeta de una categoria.
  Widget _crearTarjeta(Map<String, dynamic> categoria) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String nombre = (categoria['nombre'] ?? 'Sin nombre').toString();

    final String descripcion = (categoria['descripcion'] ?? '').toString();

    return Card(
      color: colores.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _abrirCategoria(categoria);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono representativo de la categoria.
              Icon(
                Icons.medical_information_outlined,
                size: 32,
                color: colores.onPrimaryContainer,
              ),

              const SizedBox(height: 8),

              // Nombre de la categoria.
              Text(
                nombre,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colores.onPrimaryContainer,
                ),
              ),

              // Descripcion cuando este disponible.
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 6),

                Text(
                  descripcion,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colores.onPrimaryContainer,
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Indicador de exploracion.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Explorar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colores.onPrimaryContainer,
                    ),
                  ),

                  const SizedBox(width: 5),

                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: colores.onPrimaryContainer,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir el listado de categorias.
  Widget _construirCategorias() {
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
              onPressed: _cargarCategorias,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_categorias.isEmpty) {
      return const Center(
        child: Text(
          'Todavia no hay categorias disponibles.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_filtradas.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron categorias '
          'con ese termino de busqueda.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 190,
      ),
      itemCount: _filtradas.length,
      itemBuilder: (context, indice) {
        return _crearTarjeta(_filtradas[indice]);
      },
    );
  }

  @override
  void dispose() {
    // Invalidar las solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar los recursos de la pantalla.
    _buscarController.removeListener(_filtrarCategorias);
    _buscarController.dispose();
    _apiService.cerrar();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de categorias.
      appBar: AppBar(
        title: const Text('Categorias'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar categorias',
            onPressed: _cargando ? null : _cargarCategorias,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la pantalla.
              Text(
                'Explora por categorias',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 8),

              // Descripcion de la seccion.
              Text(
                'Encuentra informacion medica '
                'organizada por temas.',
                style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 22),

              // Campo para buscar categorias.
              TextField(
                controller: _buscarController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar categoria...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Limpiar busqueda',
                    onPressed: () {
                      _buscarController.clear();
                    },
                    icon: const Icon(Icons.clear),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 22),

              // Encabezado de resultados.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Categorias disponibles',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),

                  if (!_cargando && _error == null)
                    Text(
                      '${_filtradas.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Listado de categorias.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarCategorias,
                  child:
                      _cargando ||
                          _error != null ||
                          _categorias.isEmpty ||
                          _filtradas.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 280,
                              child: _construirCategorias(),
                            ),
                          ],
                        )
                      : _construirCategorias(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pantalla para mostrar publicaciones de una categoria.
class _PublicacionesCategoriaView extends StatefulWidget {
  // Datos de la categoria seleccionada.
  final int idCategoria;
  final String nombreCategoria;

  const _PublicacionesCategoriaView({
    required this.idCategoria,
    required this.nombreCategoria,
  });

  @override
  State<_PublicacionesCategoriaView> createState() =>
      _PublicacionesCategoriaViewState();
}

class _PublicacionesCategoriaViewState
    extends State<_PublicacionesCategoriaView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Publicaciones asociadas a la categoria.
  List<Map<String, dynamic>> _publicaciones = [];

  // Variables de estado.
  bool _cargando = true;
  String? _error;

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar las publicaciones disponibles.
    _cargarPublicaciones();
  }

  // Normalizar nombres para comparar las categorias.
  String _normalizarNombre(String valor) {
    return valor.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  // Consultar y filtrar las publicaciones.
  Future<void> _cargarPublicaciones() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Consultar las publicaciones publicas con categoria.
      final dynamic respuesta = await _apiService.get('/publicaciones/');

      // El endpoint devuelve directamente una lista.
      if (respuesta is! List) {
        throw const ApiException(
          'El formato de las publicaciones no es valido.',
        );
      }

      final List<Map<String, dynamic>> publicaciones = [];

      for (final dynamic registro in respuesta) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una publicacion no valida.');
        }

        publicaciones.add(Map<String, dynamic>.from(registro));
      }

      // Comparar el nombre de categoria devuelto por FastAPI.
      final String nombreCategoria = _normalizarNombre(widget.nombreCategoria);

      final List<Map<String, dynamic>> filtradas = publicaciones.where((
        publicacion,
      ) {
        final String categoriaPublicacion = _normalizarNombre(
          (publicacion['categoria'] ?? '').toString(),
        );

        return categoriaPublicacion == nombreCategoria;
      }).toList();

      // Evitar sobrescribir una solicitud mas reciente.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = filtradas;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = [];
        _error = 'No fue posible consultar las publicaciones.';
        _cargando = false;
      });
    }
  }

  // Obtener el identificador de una publicacion.
  int? _obtenerIdPublicacion(Map<String, dynamic> publicacion) {
    final dynamic identificador = publicacion['id_blog'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Abrir el detalle de una publicacion.
  void _abrirPublicacion(Map<String, dynamic> publicacion) {
    final int? idBlog = _obtenerIdPublicacion(publicacion);

    if (idBlog == null || idBlog <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La publicacion no tiene un identificador valido.'),
        ),
      );

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  // Construir la tarjeta de una publicacion.
  Widget _crearPublicacion(Map<String, dynamic> publicacion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion = (publicacion['descripcion'] ?? '').toString();

    final String imagen = (publicacion['img'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _abrirPublicacion(publicacion);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen de la publicacion.
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imagen.trim().isNotEmpty
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

                    const SizedBox(height: 8),

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

                    const SizedBox(height: 8),

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
            ],
          ),
        ),
      ),
    );
  }

  // Construir un icono alternativo para la imagen.
  Widget _crearIconoImagen(ColorScheme colores) {
    return Container(
      width: 75,
      height: 85,
      alignment: Alignment.center,
      color: colores.primaryContainer,
      child: Icon(
        Icons.menu_book_outlined,
        size: 35,
        color: colores.onPrimaryContainer,
      ),
    );
  }

  // Construir el contenido de la pantalla.
  Widget _construirContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _construirEstado(
        icono: Icons.error_outline,
        mensaje: _error!,
        mostrarReintento: true,
      );
    }

    if (_publicaciones.isEmpty) {
      return _construirEstado(
        icono: Icons.menu_book_outlined,
        mensaje:
            'No se encontraron publicaciones '
            'de esta categoria en los resultados recibidos.',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: _publicaciones.length,
      itemBuilder: (context, indice) {
        return _crearPublicacion(_publicaciones[indice]);
      },
    );
  }

  // Construir los mensajes de estado.
  Widget _construirEstado({
    required IconData icono,
    required String mensaje,
    bool mostrarReintento = false,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: colores.primary),

            const SizedBox(height: 14),

            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: TextStyle(color: colores.onSurface),
            ),

            if (mostrarReintento) ...[
              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: _cargarPublicaciones,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Invalidar las solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar el servicio HTTP.
    _apiService.cerrar();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      appBar: AppBar(
        title: Text(widget.nombreCategoria),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar publicaciones',
            onPressed: _cargando ? null : _cargarPublicaciones,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la categoria.
              Text(
                'Publicaciones de ${widget.nombreCategoria}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Explora los articulos disponibles '
                'de esta categoria.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 20),

              // Resultados de publicaciones.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarPublicaciones,
                  child: _cargando || _error != null || _publicaciones.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: 300, child: _construirContenido()),
                          ],
                        )
                      : _construirContenido(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

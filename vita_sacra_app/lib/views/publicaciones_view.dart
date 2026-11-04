import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para consultar las publicaciones.
class PublicacionesView extends StatefulWidget {
  const PublicacionesView({super.key});

  @override
  State<PublicacionesView> createState() => _PublicacionesViewState();
}

class _PublicacionesViewState extends State<PublicacionesView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Controlador del campo de busqueda.
  final TextEditingController _buscarController = TextEditingController();

  // Lista de publicaciones recibidas.
  List<Map<String, dynamic>> _publicaciones = [];

  // Lista de publicaciones filtradas.
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
    _buscarController.addListener(_filtrarPublicaciones);

    // Consultar las publicaciones al iniciar.
    _cargarPublicaciones();
  }

  // Consultar publicaciones mediante FastAPI.
  Future<void> _cargarPublicaciones() async {
    if (!mounted) {
      return;
    }

    // Registrar la solicitud actual.
    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Ejecutar la solicitud HTTP GET.
      final dynamic respuesta = await _apiService.get('/posts');

      // Obtener los registros de la respuesta.
      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['publicaciones'] ??
            respuesta['posts'] ??
            respuesta['results'];
      }

      // Validar que los resultados sean una lista.
      if (registros is! List) {
        throw const ApiException(
          'El formato de las publicaciones no es valido.',
        );
      }

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> publicaciones = registros.map((
        registro,
      ) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una publicacion no valida.');
        }

        return Map<String, dynamic>.from(registro);
      }).toList();

      // Evitar actualizar una pantalla cerrada
      // o sobrescribir una solicitud mas reciente.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = publicaciones;
        _cargando = false;
      });

      // Aplicar nuevamente el filtro de busqueda.
      _filtrarPublicaciones();
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = [];
        _filtradas = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _publicaciones = [];
        _filtradas = [];
        _error = 'No fue posible cargar las publicaciones.';
        _cargando = false;
      });
    }
  }

  // Filtrar las publicaciones por titulo o descripcion.
  void _filtrarPublicaciones() {
    if (!mounted) {
      return;
    }

    final String busqueda = _buscarController.text.trim().toLowerCase();

    final List<Map<String, dynamic>> resultados = _publicaciones.where((
      publicacion,
    ) {
      final String titulo = (publicacion['titulo'] ?? '')
          .toString()
          .toLowerCase();

      final String descripcion =
          (publicacion['descripcion'] ?? publicacion['desc'] ?? '')
              .toString()
              .toLowerCase();

      return titulo.contains(busqueda) || descripcion.contains(busqueda);
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

  // Obtener el identificador de una publicacion.
  int? _obtenerIdPublicacion(Map<String, dynamic> publicacion) {
    final dynamic identificador = publicacion['id_blog'] ?? publicacion['id'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Abrir el detalle de una publicacion.
  void _abrirPublicacion(Map<String, dynamic> publicacion) {
    // Obtener el identificador del articulo.
    final int? idBlog = _obtenerIdPublicacion(publicacion);

    // Validar el identificador antes de navegar.
    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La publicacion no tiene un identificador valido.');
      return;
    }

    // Abrir el detalle del articulo seleccionado.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  // Construir la tarjeta de una publicacion.
  Widget _crearTarjeta(Map<String, dynamic> publicacion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener la informacion disponible.
    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion =
        (publicacion['descripcion'] ?? publicacion['desc'] ?? '').toString();

    final String? imagen = publicacion['img']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _abrirPublicacion(publicacion);
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mostrar la imagen cuando exista.
              if (imagen != null && imagen.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imagen,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,

                      // Mostrar un icono si falla la imagen.
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 180,
                          alignment: Alignment.center,
                          color: colores.primaryContainer,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 45,
                            color: colores.onPrimaryContainer,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Titulo del articulo.
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              const SizedBox(height: 10),

              // Descripcion del articulo.
              Text(
                descripcion.isNotEmpty
                    ? descripcion
                    : 'Sin descripcion disponible.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 14),

              // Indicador de acceso al articulo.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Leer mas',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colores.primary,
                    ),
                  ),

                  const SizedBox(width: 5),

                  Icon(Icons.arrow_forward, size: 18, color: colores.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir los resultados de las publicaciones.
  Widget _construirResultados() {
    // Mostrar indicador de carga.
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar errores de consulta.
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
              onPressed: _cargarPublicaciones,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    // Mostrar un mensaje si no hay publicaciones.
    if (_publicaciones.isEmpty) {
      return const Center(
        child: Text(
          'Todavia no hay publicaciones disponibles.',
          textAlign: TextAlign.center,
        ),
      );
    }

    // Mostrar un mensaje si no hay coincidencias.
    if (_filtradas.isEmpty) {
      return const Center(
        child: Text(
          'No se encontraron publicaciones '
          'con ese termino de busqueda.',
          textAlign: TextAlign.center,
        ),
      );
    }

    // Mostrar las publicaciones encontradas.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
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

    // Eliminar el listener del buscador.
    _buscarController.removeListener(_filtrarPublicaciones);

    // Liberar los recursos de la pantalla.
    _buscarController.dispose();
    _apiService.cerrar();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de publicaciones.
      appBar: AppBar(
        title: const Text('Publicaciones'),
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la pantalla.
              Text(
                'Explora nuestro contenido',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 8),

              // Descripcion de la seccion.
              Text(
                'Consulta articulos e informacion '
                'medica de nuestra comunidad.',
                style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 22),

              // Campo para buscar publicaciones.
              TextField(
                controller: _buscarController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar publicaciones...',
                  prefixIcon: const Icon(Icons.search),

                  // Mostrar la opcion de limpiar cuando hay texto.
                  suffixIcon: _buscarController.text.isEmpty
                      ? null
                      : IconButton(
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
                  Expanded(
                    child: Text(
                      'Articulos disponibles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                  ),

                  // Cantidad de publicaciones filtradas.
                  if (!_cargando && _error == null)
                    Text(
                      '${_filtradas.length} resultados',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Listado de publicaciones.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarPublicaciones,
                  child:
                      _cargando ||
                          _error != null ||
                          _publicaciones.isEmpty ||
                          _filtradas.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 280,
                              child: _construirResultados(),
                            ),
                          ],
                        )
                      : _construirResultados(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

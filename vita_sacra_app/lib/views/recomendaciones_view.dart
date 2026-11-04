import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para consultar publicaciones recomendadas.
class RecomendacionesView extends StatefulWidget {
  const RecomendacionesView({super.key});

  @override
  State<RecomendacionesView> createState() => _RecomendacionesViewState();
}

class _RecomendacionesViewState extends State<RecomendacionesView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Publicaciones recomendadas por FastAPI.
  List<Map<String, dynamic>> _recomendaciones = [];

  // Variables de estado.
  bool _cargando = true;
  bool _requiereSesion = false;
  String? _error;

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar las recomendaciones al iniciar.
    _cargarRecomendaciones();
  }

  // Consultar recomendaciones personalizadas.
  Future<void> _cargarRecomendaciones() async {
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
      // Obtener el token del usuario.
      final String? token = await _authService.obtenerToken();

      // Evitar actualizar una pantalla cerrada
      // o procesar una solicitud desactualizada.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Verificar que exista una sesion iniciada.
      if (token == null || token.trim().isEmpty) {
        setState(() {
          _recomendaciones = [];
          _requiereSesion = true;
          _cargando = false;
        });

        return;
      }

      // Consultar el endpoint real de personalizacion.
      final dynamic respuesta = await _apiService.get(
        '/personalizacion/recomendaciones',
        token: token,
      );

      // Obtener los registros de la respuesta.
      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['recomendaciones'] ??
            respuesta['publicaciones'] ??
            respuesta['results'];
      }

      // Comprobar que se recibio una lista.
      if (registros is! List) {
        throw const ApiException(
          'El formato de las recomendaciones no es valido.',
        );
      }

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> recomendaciones = registros.map((
        registro,
      ) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una recomendacion no valida.');
        }

        // Convertir cada publicacion recibida desde FastAPI.
        return Map<String, dynamic>.from(registro);
      }).toList();

      // Evitar sobrescribir resultados mas recientes.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _recomendaciones = recomendaciones;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Identificar los errores de autenticacion.
      final bool sesionInvalida = error.codigoEstado == 401;

      setState(() {
        _recomendaciones = [];
        _requiereSesion = sesionInvalida;
        _error = sesionInvalida ? null : error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _recomendaciones = [];
        _error = 'No fue posible cargar las recomendaciones.';
        _cargando = false;
      });
    }
  }

  // Obtener el identificador de una publicacion.
  int? _obtenerId(Map<String, dynamic> publicacion) {
    final dynamic identificador = publicacion['id_blog'];

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

  // Abrir el detalle de una publicacion.
  void _abrirPublicacion(Map<String, dynamic> publicacion) {
    // Obtener el identificador del articulo.
    final int? idBlog = _obtenerId(publicacion);

    // Validar el identificador antes de navegar.
    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La publicacion no tiene un identificador valido.');
      return;
    }

    // Navegar hacia la publicacion seleccionada.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  // Construir una tarjeta de recomendacion.
  Widget _crearRecomendacion(Map<String, dynamic> publicacion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los datos disponibles.
    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion = (publicacion['descripcion'] ?? '').toString();

    final String? imagen = publicacion['img']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
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
              // Mostrar la imagen cuando este disponible.
              if (imagen != null && imagen.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imagen,
                      width: double.infinity,
                      height: 170,
                      fit: BoxFit.cover,

                      // Mostrar un icono si falla la imagen.
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 130,
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

              // Indicador visual de recomendacion.
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: colores.primary,
                  ),

                  const SizedBox(width: 6),

                  Text(
                    'Recomendado para ti',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colores.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Titulo de la publicacion.
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              const SizedBox(height: 10),

              // Descripcion de la publicacion.
              Text(
                descripcion.isNotEmpty
                    ? descripcion
                    : 'Sin descripcion disponible.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 14),

              // Indicador para abrir el articulo.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Ver articulo',
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

  // Construir un mensaje de estado.
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
                onPressed: _cargarRecomendaciones,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir el listado de recomendaciones.
  Widget _construirRecomendaciones() {
    // Mostrar el indicador de carga.
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Solicitar una sesion iniciada.
    if (_requiereSesion) {
      return _construirEstado(
        icono: Icons.lock_outline,
        titulo: 'Inicia sesion',
        descripcion:
            'Necesitas iniciar sesion o renovar tu sesion '
            'para consultar tus recomendaciones personalizadas.',
        mostrarReintento: true,
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

    // Mostrar un mensaje si no hay recomendaciones.
    if (_recomendaciones.isEmpty) {
      return _construirEstado(
        icono: Icons.auto_awesome_outlined,
        titulo: 'Sin recomendaciones',
        descripcion:
            'Todavia no hay publicaciones recomendadas '
            'para tu perfil.',
      );
    }

    // Mostrar las publicaciones recomendadas.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: _recomendaciones.length,
      itemBuilder: (context, indice) {
        return _crearRecomendacion(_recomendaciones[indice]);
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

      // Barra superior de recomendaciones.
      appBar: AppBar(
        title: const Text('Recomendaciones'),
        centerTitle: true,

        actions: [
          IconButton(
            tooltip: 'Actualizar recomendaciones',
            onPressed: _cargando ? null : _cargarRecomendaciones,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
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
                          'Contenido para ti',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Descubre articulos recomendados '
                          'segun tus intereses.',
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

              const SizedBox(height: 20),

              // Informacion sobre las recomendaciones.
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
                        'Las recomendaciones se obtienen '
                        'del sistema de personalizacion '
                        'de Vita Sacra.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colores.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Encabezado de los resultados.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Articulos recomendados',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                  ),

                  if (!_cargando && !_requiereSesion && _error == null)
                    Text(
                      '${_recomendaciones.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Listado de recomendaciones.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarRecomendaciones,
                  child:
                      _cargando ||
                          _requiereSesion ||
                          _error != null ||
                          _recomendaciones.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 280,
                              child: _construirRecomendaciones(),
                            ),
                          ],
                        )
                      : _construirRecomendaciones(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

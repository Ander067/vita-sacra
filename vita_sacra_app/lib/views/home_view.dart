import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'anatomia_3d_view.dart';
import 'buscar_view.dart';
import 'categorias_view.dart';
import 'detalle_publicacion_view.dart';
import 'guardados_view.dart';
import 'login_view.dart';
import 'perfil_view.dart';
import 'recomendaciones_view.dart';

// Pantalla principal de Vita Sacra.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Controlador del buscador.
  final TextEditingController _buscarController = TextEditingController();

  // Estado de las publicaciones.
  List<Map<String, dynamic>> _publicaciones = [];
  bool _cargando = true;
  bool _cerrandoSesion = false;
  String? _error;

  // Identificador de la ultima consulta de publicaciones.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar las publicaciones al abrir la pantalla.
    _cargarPublicaciones();
  }

  // Consultar las publicaciones desde FastAPI.
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
      // Consultar el endpoint publico de publicaciones.
      final dynamic respuesta = await _apiService.get('/posts');

      // Aceptar una lista JSON o una respuesta paginada.
      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['publicaciones'] ??
            respuesta['posts'] ??
            respuesta['results'];
      }

      // Validar el formato de la respuesta.
      if (registros is! List) {
        throw const ApiException(
          'El formato de las publicaciones no es valido.',
        );
      }

      // Convertir los registros recibidos a mapas.
      final List<Map<String, dynamic>> publicaciones = registros.map((
        registro,
      ) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una publicacion no valida.');
        }

        return Map<String, dynamic>.from(registro);
      }).toList();

      // Evitar actualizar una pantalla cerrada
      // o sobrescribir una consulta mas reciente.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Actualizar la lista de publicaciones.
      setState(() {
        _publicaciones = publicaciones;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Mostrar el error devuelto por el servicio.
      setState(() {
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Mostrar un mensaje para errores inesperados.
      setState(() {
        _error = 'No fue posible cargar las publicaciones.';
        _cargando = false;
      });
    }
  }

  // Mostrar un mensaje informativo.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir una pantalla de la aplicacion.
  Future<void> _abrirPantalla(Widget pantalla) async {
    if (!mounted || _cerrandoSesion) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => pantalla),
    );
  }

  // Preparar la busqueda de publicaciones.
  void _buscarPublicaciones() {
    final String texto = _buscarController.text.trim();

    if (texto.isEmpty) {
      _mostrarMensaje('Ingresa un termino de busqueda.');
      return;
    }

    if (texto.length < 2) {
      _mostrarMensaje('Escribe al menos 2 caracteres.');
      return;
    }

    // Ocultar el teclado antes de abrir la busqueda.
    FocusScope.of(context).unfocus();

    // Enviar el termino al modulo de busqueda.
    _abrirPantalla(BuscarView(terminoInicial: texto));
  }

  // Abrir el perfil del usuario.
  void _abrirPerfil() {
    _abrirPantalla(const PerfilView());
  }

  // Abrir el modulo de categorias.
  void _abrirCategorias() {
    _abrirPantalla(const CategoriasView());
  }

  // Abrir las recomendaciones personalizadas.
  void _abrirRecomendaciones() {
    _abrirPantalla(const RecomendacionesView());
  }

  // Abrir las publicaciones guardadas.
  void _abrirGuardados() {
    _abrirPantalla(const GuardadosView());
  }

  // Abrir el modulo de anatomia tridimensional.
  void _abrirAnatomia3D() {
    _abrirPantalla(const Anatomia3DView());
  }

  // Obtener el identificador de una publicacion.
  int? _obtenerId(Map<String, dynamic> publicacion) {
    final dynamic identificador = publicacion['id_blog'] ?? publicacion['id'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Abrir el detalle de una publicacion.
  void _abrirDetalle(Map<String, dynamic> publicacion) {
    // Obtener el identificador del articulo.
    final int? idBlog = _obtenerId(publicacion);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('Esta publicacion no tiene un identificador valido.');
      return;
    }

    // Navegar hacia el detalle del articulo.
    _abrirPantalla(DetallePublicacionView(idBlog: idBlog));
  }

  // Cerrar la sesion del usuario.
  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) {
      return;
    }

    setState(() {
      _cerrandoSesion = true;
    });

    try {
      // Eliminar el token almacenado.
      await _authService.cerrarSesion();

      if (!mounted) {
        return;
      }

      // Regresar al inicio de sesion.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginView()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible cerrar la sesion.');
    } finally {
      if (mounted) {
        setState(() {
          _cerrandoSesion = false;
        });
      }
    }
  }

  // Construir una tarjeta de acceso rapido.
  Widget _crearAcceso({
    required IconData icono,
    required String titulo,
    required VoidCallback accion,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      color: colores.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: accion,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 35, color: colores.onPrimaryContainer),

              const SizedBox(height: 10),

              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colores.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir una tarjeta de publicacion.
  Widget _crearPublicacion(Map<String, dynamic> publicacion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los campos disponibles de la API.
    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion =
        (publicacion['descripcion'] ?? publicacion['desc'] ?? '').toString();

    final String? imagen = publicacion['img']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _abrirDetalle(publicacion);
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen de la publicacion.
              if (imagen != null && imagen.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imagen,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 100,
                          alignment: Alignment.center,
                          color: colores.primaryContainer,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colores.onPrimaryContainer,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Titulo de la publicacion.
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              // Descripcion de la publicacion.
              if (descripcion.isNotEmpty) ...[
                const SizedBox(height: 8),

                Text(
                  descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colores.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Construir la seccion de publicaciones.
  Widget _construirPublicaciones() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(30.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return Column(
        children: [
          Text(_error!, textAlign: TextAlign.center),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _cargarPublicaciones,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }

    // Mostrar un mensaje si no existen publicaciones.
    if (_publicaciones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(
          child: Text(
            'Todavia no hay publicaciones disponibles.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Mostrar las publicaciones obtenidas desde FastAPI.
    return Column(
      children: _publicaciones.map((publicacion) {
        return _crearPublicacion(publicacion);
      }).toList(),
    );
  }

  // Controlar las opciones de navegacion inferior.
  void _seleccionarDestino(int indice) {
    switch (indice) {
      case 0:
        // Permanecer en la pantalla principal.
        return;

      case 1:
        _abrirPantalla(const BuscarView());
        break;

      case 2:
        _abrirGuardados();
        break;

      case 3:
        _abrirPerfil();
        break;
    }
  }

  @override
  void dispose() {
    // Invalidar las solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar los recursos de la pantalla.
    _buscarController.dispose();
    _apiService.cerrar();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de la aplicacion.
      appBar: AppBar(
        title: const Text('Vita Sacra'),
        centerTitle: false,
        actions: [
          // Acceso al perfil del usuario.
          IconButton(
            tooltip: 'Perfil',
            onPressed: _abrirPerfil,
            icon: const Icon(Icons.account_circle_outlined),
          ),

          // Opcion para cerrar sesion.
          PopupMenuButton<String>(
            enabled: !_cerrandoSesion,
            onSelected: (opcion) {
              if (opcion == 'salir') {
                _cerrarSesion();
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(value: 'salir', child: Text('Cerrar sesion')),
              ];
            },
          ),
        ],
      ),

      // Contenido principal.
      body: RefreshIndicator(
        onRefresh: _cargarPublicaciones,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Encabezado de bienvenida.
            Text(
              'Bienvenido a Vita Sacra',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: colores.primary,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Explora informacion y recursos medicos.',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),

            const SizedBox(height: 24),

            // Campo de busqueda.
            TextField(
              controller: _buscarController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _buscarPublicaciones();
              },
              decoration: InputDecoration(
                hintText: 'Buscar publicaciones...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: _buscarPublicaciones,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 28),

            // Titulo de accesos rapidos.
            Text(
              'Explorar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colores.onSurface,
              ),
            ),

            const SizedBox(height: 14),

            // Accesos a los modulos principales.
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _crearAcceso(
                  icono: Icons.category_outlined,
                  titulo: 'Categorias',
                  accion: _abrirCategorias,
                ),

                _crearAcceso(
                  icono: Icons.auto_awesome_outlined,
                  titulo: 'Recomendaciones',
                  accion: _abrirRecomendaciones,
                ),

                _crearAcceso(
                  icono: Icons.bookmark_outline,
                  titulo: 'Guardados',
                  accion: _abrirGuardados,
                ),

                _crearAcceso(
                  icono: Icons.view_in_ar_outlined,
                  titulo: 'Anatomia 3D',
                  accion: _abrirAnatomia3D,
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Encabezado de publicaciones recientes.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Publicaciones recientes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),
                ),

                IconButton(
                  tooltip: 'Actualizar publicaciones',
                  onPressed: _cargando ? null : _cargarPublicaciones,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Resultados obtenidos desde FastAPI.
            _construirPublicaciones(),
          ],
        ),
      ),

      // Navegacion inferior de la pantalla principal.
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: _seleccionarDestino,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Guardados',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

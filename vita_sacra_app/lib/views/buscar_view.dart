import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para buscar publicaciones del blog.
class BuscarView extends StatefulWidget {
  // Permitir recibir un termino desde otra pantalla.
  final String terminoInicial;

  const BuscarView({super.key, this.terminoInicial = ''});

  @override
  State<BuscarView> createState() => _BuscarViewState();
}

class _BuscarViewState extends State<BuscarView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Controlador del campo de busqueda.
  final TextEditingController _buscarController = TextEditingController();

  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Publicaciones encontradas.
  List<Map<String, dynamic>> _resultados = [];

  // Variables de estado.
  bool _buscando = false;
  bool _busquedaRealizada = false;
  String? _error;
  String _terminoBuscado = '';

  // Identificador de la ultima solicitud.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Obtener el termino enviado desde otra pantalla.
    _establecerTerminoInicial(widget.terminoInicial);
  }

  @override
  void didUpdateWidget(covariant BuscarView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Actualizar la busqueda si cambia el termino recibido.
    if (oldWidget.terminoInicial != widget.terminoInicial) {
      _numeroSolicitud++;

      _buscarController.clear();

      setState(() {
        _resultados = [];
        _buscando = false;
        _busquedaRealizada = false;
        _terminoBuscado = '';
        _error = null;
      });

      _establecerTerminoInicial(widget.terminoInicial);
    }
  }

  // Establecer el termino recibido desde otra pantalla.
  void _establecerTerminoInicial(String valor) {
    final String termino = valor.trim();

    if (termino.isEmpty) {
      return;
    }

    _buscarController.text = termino;

    // Ejecutar la busqueda despues de construir la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _buscarController.text.trim() != termino) {
        return;
      }

      _buscarPublicaciones();
    });
  }

  // Validar el termino de busqueda.
  String? _validarBusqueda(String? valor) {
    final String termino = valor?.trim() ?? '';

    if (termino.isEmpty) {
      return 'Escribe una palabra para buscar.';
    }

    if (termino.length < 2) {
      return 'Escribe al menos 2 caracteres.';
    }

    return null;
  }

  // Normalizar los textos para realizar busquedas sin acentos.
  String _normalizarTexto(String texto) {
    String resultado = texto.trim().toLowerCase();

    const Map<String, String> reemplazos = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
    };

    reemplazos.forEach((caracter, reemplazo) {
      resultado = resultado.replaceAll(caracter, reemplazo);
    });

    // Unificar espacios consecutivos.
    return resultado.replaceAll(RegExp(r'\s+'), ' ');
  }

  // Comprobar si una publicacion coincide con la busqueda.
  bool _coincideBusqueda(Map<String, dynamic> publicacion, String termino) {
    // Consultar los campos que realmente devuelve GET /posts.
    final String titulo = _normalizarTexto(
      (publicacion['titulo'] ?? '').toString(),
    );

    final String descripcion = _normalizarTexto(
      (publicacion['descripcion'] ?? '').toString(),
    );

    // Buscar el termino completo en titulo o descripcion.
    return titulo.contains(termino) || descripcion.contains(termino);
  }

  // Buscar publicaciones mediante FastAPI.
  Future<void> _buscarPublicaciones() async {
    // Validar que la pantalla continue activa.
    if (!mounted) {
      return;
    }

    // Validar el formulario.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Obtener el termino de busqueda.
    final String termino = _buscarController.text.trim();

    // Normalizar el termino para comparar los resultados.
    final String terminoNormalizado = _normalizarTexto(termino);

    // Ocultar el teclado al realizar la consulta.
    FocusScope.of(context).unfocus();

    // Registrar la solicitud actual.
    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _buscando = true;
      _busquedaRealizada = true;
      _terminoBuscado = termino;
      _resultados = [];
      _error = null;
    });

    try {
      // Consultar las publicaciones publicas.
      // El endpoint GET /posts no admite el parametro buscar.
      final dynamic respuesta = await _apiService.get('/posts');

      // FastAPI devuelve directamente una lista.
      if (respuesta is! List) {
        throw FormatException('El formato de los resultados no es valido.');
      }

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> publicaciones = [];

      for (final dynamic registro in respuesta) {
        if (registro is! Map) {
          throw FormatException('Se recibio una publicacion no valida.');
        }

        publicaciones.add(Map<String, dynamic>.from(registro));
      }

      // Filtrar localmente por titulo y descripcion.
      final List<Map<String, dynamic>> resultados = publicaciones.where((
        publicacion,
      ) {
        return _coincideBusqueda(publicacion, terminoNormalizado);
      }).toList();

      // Evitar actualizar una pantalla cerrada
      // o sobrescribir una busqueda mas reciente.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _resultados = resultados;
        _buscando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _error = error.mensaje;
        _buscando = false;
      });
    } on FormatException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _error = error.message;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _error = 'No fue posible realizar la busqueda.';
        _buscando = false;
      });
    }
  }

  // Limpiar los resultados de la busqueda.
  void _limpiarBusqueda() {
    // Invalidar cualquier solicitud pendiente.
    _numeroSolicitud++;

    // Limpiar el campo de texto.
    _buscarController.clear();

    // Limpiar los errores de validacion.
    _formKey.currentState?.reset();

    setState(() {
      _resultados = [];
      _busquedaRealizada = false;
      _buscando = false;
      _terminoBuscado = '';
      _error = null;
    });
  }

  // Obtener el identificador de una publicacion.
  int? _obtenerId(Map<String, dynamic> publicacion) {
    final dynamic identificador = publicacion['id_blog'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Mostrar un mensaje informativo.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Abrir el detalle de la publicacion.
  void _abrirPublicacion(Map<String, dynamic> publicacion) {
    // Obtener el identificador del articulo.
    final int? idBlog = _obtenerId(publicacion);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La publicacion no tiene un identificador valido.');
      return;
    }

    // Navegar hacia el detalle del articulo.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  // Construir la tarjeta de un resultado.
  Widget _crearResultado(Map<String, dynamic> publicacion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Obtener los campos disponibles.
    final String titulo = (publicacion['titulo'] ?? 'Sin titulo').toString();

    final String descripcion = (publicacion['descripcion'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,

      child: InkWell(
        onTap: () {
          _abrirPublicacion(publicacion);
        },

        child: Padding(
          padding: const EdgeInsets.all(12),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icono representativo del articulo.
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 32,
                  color: colores.onPrimaryContainer,
                ),
              ),

              const SizedBox(width: 12),

              // Informacion del articulo.
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

                    const SizedBox(height: 6),

                    Text(
                      descripcion.isNotEmpty
                          ? descripcion
                          : 'Sin descripcion disponible.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Ver publicacion',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colores.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 5),

              Icon(Icons.chevron_right, color: colores.primary),
            ],
          ),
        ),
      ),
    );
  }

  // Construir el contenido de los resultados.
  Widget _construirResultados() {
    // Mostrar el estado inicial.
    if (!_busquedaRealizada) {
      return _construirEstado(
        icono: Icons.search,
        titulo: 'Comienza una busqueda',
        descripcion:
            'Escribe una palabra clave para encontrar '
            'publicaciones del blog medico.',
      );
    }

    // Mostrar el indicador de carga.
    if (_buscando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),

            const SizedBox(height: 12),

            Text(_error!, textAlign: TextAlign.center),

            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: _buscarPublicaciones,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    // Mostrar un mensaje si no existen resultados.
    if (_resultados.isEmpty) {
      return _construirEstado(
        icono: Icons.search_off,
        titulo: 'Sin resultados',
        descripcion:
            'No se encontraron publicaciones '
            'para "$_terminoBuscado".',
      );
    }

    // Mostrar el listado de publicaciones.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _resultados.length,
      itemBuilder: (context, indice) {
        return _crearResultado(_resultados[indice]);
      },
    );
  }

  // Construir los mensajes de estado.
  Widget _construirEstado({
    required IconData icono,
    required String titulo,
    required String descripcion,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, restricciones) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: restricciones.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 45, color: colores.primary),

                    const SizedBox(height: 12),

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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Invalidar las solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar los recursos utilizados.
    _buscarController.dispose();
    _apiService.cerrar();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior del buscador.
      appBar: AppBar(
        title: const Text('Buscar publicaciones'),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la pantalla.
              Text(
                '¿Que deseas aprender?',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Encuentra articulos medicos '
                'y contenido de salud.',
                style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 22),

              // Formulario de busqueda.
              Form(
                key: _formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Campo para ingresar palabras clave.
                    TextFormField(
                      controller: _buscarController,
                      textInputAction: TextInputAction.search,
                      enabled: !_buscando,
                      onFieldSubmitted: (_) {
                        _buscarPublicaciones();
                      },
                      decoration: InputDecoration(
                        hintText: 'Buscar por palabra clave...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Limpiar busqueda',
                          onPressed: _limpiarBusqueda,
                          icon: const Icon(Icons.clear),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validarBusqueda,
                    ),

                    const SizedBox(height: 12),

                    // Boton para ejecutar la busqueda.
                    SizedBox(
                      height: 48,

                      child: ElevatedButton.icon(
                        onPressed: _buscando ? null : _buscarPublicaciones,
                        icon: const Icon(Icons.search),
                        label: const Text('Buscar'),
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
                  Text(
                    'Resultados de busqueda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),

                  if (_busquedaRealizada && !_buscando && _error == null)
                    Text(
                      '${_resultados.length}',
                      style: TextStyle(color: colores.onSurfaceVariant),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Resultados obtenidos desde FastAPI.
              Expanded(child: _construirResultados()),
            ],
          ),
        ),
      ),
    );
  }
}

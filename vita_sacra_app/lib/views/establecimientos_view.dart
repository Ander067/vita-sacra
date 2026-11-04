import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

// Pantalla para consultar establecimientos de salud.
class EstablecimientosView extends StatefulWidget {
  const EstablecimientosView({super.key});

  @override
  State<EstablecimientosView> createState() => _EstablecimientosViewState();
}

class _EstablecimientosViewState extends State<EstablecimientosView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Controlador del buscador.
  final TextEditingController _buscarController = TextEditingController();

  // Listas de establecimientos.
  List<Map<String, dynamic>> _establecimientos = [];
  List<Map<String, dynamic>> _filtrados = [];

  // Tipos de establecimientos disponibles.
  final List<String> _tipos = [
    'Todos',
    'Hospital',
    'Clinica',
    'Consultorio',
    'Farmacia',
    'Laboratorio',
    'Otro',
  ];

  // Tipo seleccionado.
  String _tipoSeleccionado = 'Todos';

  // Variables de estado.
  bool _cargando = true;
  String? _error;

  // Control de solicitudes.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar establecimientos al iniciar.
    _cargarEstablecimientos();
  }

  // Obtener un texto de los campos disponibles.
  String _obtenerTexto(
    Map<String, dynamic> establecimiento,
    List<String> campos, {
    String defecto = '',
  }) {
    for (final String campo in campos) {
      final dynamic valor = establecimiento[campo];

      if (valor != null) {
        final String texto = valor.toString().trim();

        if (texto.isNotEmpty) {
          return texto;
        }
      }
    }

    return defecto;
  }

  // Normalizar textos para realizar comparaciones.
  String _normalizarTexto(String texto) {
    return texto
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  // Consultar los establecimientos aprobados desde FastAPI.
  Future<void> _cargarEstablecimientos() async {
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
      // Consultar el endpoint publico de establecimientos.
      final dynamic respuesta = await _apiService.get('/establecimientos/');

      // Identificar la lista recibida.
      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['establecimientos'] ??
            respuesta['results'];
      }

      // Validar el formato de la respuesta.
      if (registros is! List) {
        throw const ApiException(
          'El formato de los establecimientos no es valido.',
        );
      }

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> establecimientos = registros.map((
        registro,
      ) {
        if (registro is! Map) {
          throw const ApiException('Se recibio un establecimiento no valido.');
        }

        return Map<String, dynamic>.from(registro);
      }).toList();

      // Evitar procesar respuestas antiguas.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Aplicar los filtros actuales.
      final List<Map<String, dynamic>> filtrados =
          _obtenerEstablecimientosFiltrados(establecimientos);

      // Guardar los resultados.
      setState(() {
        _establecimientos = establecimientos;
        _filtrados = filtrados;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _establecimientos = [];
        _filtrados = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _establecimientos = [];
        _filtrados = [];
        _error = 'No fue posible cargar los establecimientos.';
        _cargando = false;
      });
    }
  }

  // Obtener los establecimientos que coinciden con los filtros.
  List<Map<String, dynamic>> _obtenerEstablecimientosFiltrados(
    List<Map<String, dynamic>> establecimientos,
  ) {
    final String busqueda = _normalizarTexto(_buscarController.text);

    final String tipo = _normalizarTexto(_tipoSeleccionado);

    return establecimientos.where((establecimiento) {
      // Obtener los campos reales del backend.
      final String nombre = _normalizarTexto(
        _obtenerTexto(establecimiento, ['nombre']),
      );

      final String direccion = _normalizarTexto(
        _obtenerTexto(establecimiento, ['direccion']),
      );

      final String categoria = _normalizarTexto(
        _obtenerTexto(establecimiento, ['tipo']),
      );

      final String descripcion = _normalizarTexto(
        _obtenerTexto(establecimiento, ['descripcion']),
      );

      // Comprobar la coincidencia de texto.
      final bool coincideBusqueda =
          nombre.contains(busqueda) ||
          direccion.contains(busqueda) ||
          categoria.contains(busqueda) ||
          descripcion.contains(busqueda);

      // Comprobar el tipo seleccionado.
      final bool coincideTipo =
          _tipoSeleccionado == 'Todos' ||
          categoria == tipo ||
          (tipo == 'otro' &&
              ![
                'hospital',
                'clinica',
                'consultorio',
                'farmacia',
                'laboratorio',
              ].contains(categoria));

      return coincideBusqueda && coincideTipo;
    }).toList();
  }

  // Filtrar por nombre, direccion, descripcion y tipo.
  void _filtrarEstablecimientos() {
    if (!mounted) {
      return;
    }

    final List<Map<String, dynamic>> resultados =
        _obtenerEstablecimientosFiltrados(_establecimientos);

    // Actualizar los resultados visibles.
    setState(() {
      _filtrados = resultados;
    });
  }

  // Cambiar el tipo seleccionado.
  void _cambiarTipo(String tipo) {
    if (!mounted) {
      return;
    }

    setState(() {
      _tipoSeleccionado = tipo;
    });

    _filtrarEstablecimientos();
  }

  // Limpiar el texto de busqueda.
  void _limpiarBusqueda() {
    _buscarController.clear();

    _filtrarEstablecimientos();
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Copiar la direccion del establecimiento.
  Future<void> _copiarDireccion(Map<String, dynamic> establecimiento) async {
    // Obtener la direccion real del backend.
    final String direccion = _obtenerTexto(establecimiento, ['direccion']);

    if (direccion.isEmpty) {
      _mostrarMensaje(
        'Este establecimiento no tiene una direccion registrada.',
      );

      return;
    }

    try {
      // Copiar la direccion al portapapeles.
      await Clipboard.setData(ClipboardData(text: direccion));

      if (!mounted) {
        return;
      }

      _mostrarMensaje('Direccion copiada al portapapeles.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible copiar la direccion.');
    }
  }

  // Copiar el sitio web del establecimiento.
  Future<void> _copiarSitioWeb(Map<String, dynamic> establecimiento) async {
    final String sitioWeb = _obtenerTexto(establecimiento, ['sitio_web']);

    if (sitioWeb.isEmpty) {
      _mostrarMensaje('Este establecimiento no tiene un sitio web registrado.');

      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: sitioWeb));

      if (!mounted) {
        return;
      }

      _mostrarMensaje('Sitio web copiado al portapapeles.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible copiar el sitio web.');
    }
  }

  // Obtener un icono segun el tipo.
  IconData _obtenerIcono(String tipo) {
    switch (_normalizarTexto(tipo)) {
      case 'hospital':
        return Icons.local_hospital_outlined;

      case 'clinica':
        return Icons.health_and_safety_outlined;

      case 'consultorio':
        return Icons.medical_services_outlined;

      case 'farmacia':
        return Icons.local_pharmacy_outlined;

      case 'laboratorio':
        return Icons.science_outlined;

      default:
        return Icons.business_outlined;
    }
  }

  // Construir un campo de informacion.
  Widget _crearDato({
    required IconData icono,
    required String titulo,
    required String contenido,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Omitir campos sin informacion.
    if (contenido.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 22, color: colores.primary),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12,
                    color: colores.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  contenido,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colores.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mostrar la informacion de un establecimiento.
  void _mostrarDetalle(Map<String, dynamic> establecimiento) {
    final String nombre = _obtenerTexto(establecimiento, [
      'nombre',
    ], defecto: 'Establecimiento');

    final String tipo = _obtenerTexto(establecimiento, [
      'tipo',
    ], defecto: 'No especificado');

    final String direccion = _obtenerTexto(establecimiento, ['direccion']);

    final String telefono = _obtenerTexto(establecimiento, ['telefono']);

    final String sitioWeb = _obtenerTexto(establecimiento, ['sitio_web']);

    final String descripcion = _obtenerTexto(establecimiento, ['descripcion']);

    final String latitud = _obtenerTexto(establecimiento, ['latitud']);

    final String longitud = _obtenerTexto(establecimiento, ['longitud']);

    // Mostrar una ficha informativa.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final ColorScheme colores = Theme.of(context).colorScheme;

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Encabezado del establecimiento.
                Row(
                  children: [
                    Icon(_obtenerIcono(tipo), size: 36, color: colores.primary),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        nombre,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colores.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Tipo de establecimiento.
                _crearDato(
                  icono: Icons.category_outlined,
                  titulo: 'Tipo',
                  contenido: tipo,
                ),

                // Direccion registrada.
                _crearDato(
                  icono: Icons.location_on_outlined,
                  titulo: 'Direccion',
                  contenido: direccion,
                ),

                // Telefono de contacto.
                _crearDato(
                  icono: Icons.phone_outlined,
                  titulo: 'Telefono',
                  contenido: telefono,
                ),

                // Sitio web registrado.
                _crearDato(
                  icono: Icons.language_outlined,
                  titulo: 'Sitio web',
                  contenido: sitioWeb,
                ),

                // Descripcion de los servicios.
                _crearDato(
                  icono: Icons.info_outline,
                  titulo: 'Informacion adicional',
                  contenido: descripcion,
                ),

                // Coordenadas registradas.
                if (latitud.isNotEmpty && longitud.isNotEmpty)
                  _crearDato(
                    icono: Icons.place_outlined,
                    titulo: 'Coordenadas',
                    contenido: '$latitud, $longitud',
                  ),

                // Copiar la direccion registrada.
                if (direccion.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      _copiarDireccion(establecimiento);
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copiar direccion'),
                  ),

                if (direccion.isNotEmpty) const SizedBox(height: 10),

                // Copiar el sitio web registrado.
                if (sitioWeb.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      _copiarSitioWeb(establecimiento);
                    },
                    icon: const Icon(Icons.link_outlined),
                    label: const Text('Copiar sitio web'),
                  ),

                const SizedBox(height: 14),

                // Advertencia informativa.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colores.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Verifica los horarios, servicios '
                    'y datos de contacto directamente '
                    'con el establecimiento antes de acudir.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colores.onPrimaryContainer,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Cerrar el detalle.
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Construir una tarjeta de establecimiento.
  Widget _crearEstablecimiento(Map<String, dynamic> establecimiento) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String nombre = _obtenerTexto(establecimiento, [
      'nombre',
    ], defecto: 'Establecimiento sin nombre');

    final String tipo = _obtenerTexto(establecimiento, [
      'tipo',
    ], defecto: 'No especificado');

    final String direccion = _obtenerTexto(establecimiento, [
      'direccion',
    ], defecto: 'Direccion no disponible');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _mostrarDetalle(establecimiento);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Informacion principal.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 65,
                    height: 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _obtenerIcono(tipo),
                      size: 32,
                      color: colores.onPrimaryContainer,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
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
                          tipo,
                          style: TextStyle(
                            fontSize: 13,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: colores.onSurfaceVariant,
                            ),

                            const SizedBox(width: 4),

                            Expanded(
                              child: Text(
                                direccion,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colores.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Acciones disponibles.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      _mostrarDetalle(establecimiento);
                    },
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Ver informacion'),
                  ),

                  IconButton(
                    tooltip: 'Copiar direccion',
                    onPressed: () {
                      _copiarDireccion(establecimiento);
                    },
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir los filtros por tipo.
  Widget _construirFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tipos.map((tipo) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tipo),
              selected: _tipoSeleccionado == tipo,
              onSelected: (_) {
                _cambiarTipo(tipo);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // Construir mensajes de estado.
  Widget _construirEstado({
    required IconData icono,
    required String titulo,
    required String descripcion,
    bool mostrarReintento = false,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
                onPressed: _cargarEstablecimientos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir los resultados del directorio.
  Widget _construirResultados() {
    // Mostrar indicador de carga.
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return _construirEstado(
        icono: Icons.error_outline,
        titulo: 'Error al cargar el directorio',
        descripcion: _error!,
        mostrarReintento: true,
      );
    }

    // Mostrar mensaje cuando no existan registros.
    if (_establecimientos.isEmpty) {
      return _construirEstado(
        icono: Icons.local_hospital_outlined,
        titulo: 'Sin establecimientos',
        descripcion:
            'Todavia no existen establecimientos '
            'disponibles en el directorio.',
      );
    }

    // Mostrar mensaje si no hay coincidencias.
    if (_filtrados.isEmpty) {
      return _construirEstado(
        icono: Icons.search_off,
        titulo: 'Sin resultados',
        descripcion:
            'No se encontraron establecimientos '
            'con los filtros seleccionados.',
      );
    }

    // Mostrar los establecimientos encontrados.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: _filtrados.length,
      itemBuilder: (context, indice) {
        return _crearEstablecimiento(_filtrados[indice]);
      },
    );
  }

  @override
  void dispose() {
    // Invalidar solicitudes pendientes.
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

      // Barra superior del directorio.
      appBar: AppBar(
        title: const Text('Establecimientos'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar directorio',
            onPressed: _cargando ? null : _cargarEstablecimientos,
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
              // Encabezado del modulo.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_hospital_outlined,
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
                          'Directorio de salud',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Consulta establecimientos '
                          'y sus datos de contacto.',
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

              const SizedBox(height: 22),

              // Campo de busqueda.
              TextField(
                controller: _buscarController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar establecimiento...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscarController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Limpiar',
                          onPressed: _limpiarBusqueda,
                          icon: const Icon(Icons.close),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _filtrarEstablecimientos();
                },
              ),

              const SizedBox(height: 16),

              // Filtros por tipo de establecimiento.
              _construirFiltros(),

              const SizedBox(height: 22),

              // Encabezado de resultados.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Establecimientos disponibles',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                  ),

                  if (!_cargando && _error == null)
                    Text(
                      '${_filtrados.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Listado de establecimientos.
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargarEstablecimientos,
                  child: _cargando || _error != null || _filtrados.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 300,
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

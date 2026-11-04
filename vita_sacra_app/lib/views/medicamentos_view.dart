import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'detalle_publicacion_view.dart';

// Pantalla para consultar informacion de medicamentos.
class MedicamentosView extends StatefulWidget {
  const MedicamentosView({super.key});

  @override
  State<MedicamentosView> createState() => _MedicamentosViewState();
}

class _MedicamentosViewState extends State<MedicamentosView> {
  // Servicio de comunicacion con FastAPI.
  final ApiService _apiService = ApiService();

  // Controlador del buscador.
  final TextEditingController _buscarController = TextEditingController();

  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Fichas de medicamentos recibidas del backend.
  List<Map<String, dynamic>> _medicamentos = [];

  // Variables de estado.
  bool _buscando = false;
  bool _busquedaRealizada = false;
  String? _error;
  String _terminoBuscado = '';

  // Identificador para evitar resultados antiguos.
  int _numeroSolicitud = 0;

  // Obtener un texto de los campos disponibles.
  String _obtenerTexto(
    Map<String, dynamic> medicamento,
    List<String> campos, {
    String defecto = '',
  }) {
    for (final String campo in campos) {
      final dynamic valor = medicamento[campo];

      if (valor != null) {
        final String texto = valor.toString().trim();

        if (texto.isNotEmpty) {
          return texto;
        }
      }
    }

    return defecto;
  }

  // Obtener el identificador de una ficha.
  int? _obtenerId(Map<String, dynamic> medicamento) {
    final dynamic identificador = medicamento['id_blog'];

    if (identificador is int) {
      return identificador;
    }

    return int.tryParse(identificador?.toString() ?? '');
  }

  // Validar el termino introducido.
  String? _validarBusqueda(String? valor) {
    final String texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return 'Escribe el nombre de un medicamento.';
    }

    if (texto.length < 2) {
      return 'Escribe al menos 2 caracteres.';
    }

    if (texto.length > 100) {
      return 'No puedes superar 100 caracteres.';
    }

    return null;
  }

  // Consultar fichas de medicamentos desde FastAPI.
  Future<void> _buscarMedicamentos() async {
    if (!mounted || _buscando) {
      return;
    }

    // Validar el formulario antes de consultar.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final String busqueda = _buscarController.text.trim();

    // Registrar la solicitud mas reciente.
    final int solicitud = ++_numeroSolicitud;

    // Cerrar el teclado.
    FocusScope.of(context).unfocus();

    setState(() {
      _buscando = true;
      _busquedaRealizada = true;
      _terminoBuscado = busqueda;
      _medicamentos = [];
      _error = null;
    });

    try {
      // Consultar las publicaciones publicas de FastAPI.
      final dynamic respuesta = await _apiService.get('/posts');

      // Identificar la lista recibida.
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

      // Convertir los registros en mapas.
      final List<Map<String, dynamic>> publicaciones = registros.map((
        registro,
      ) {
        if (registro is! Map) {
          throw const ApiException('Se recibio una publicacion no valida.');
        }

        return Map<String, dynamic>.from(registro);
      }).toList();

      // Normalizar el termino para buscar coincidencias.
      final String termino = busqueda.toLowerCase();

      // Seleccionar solamente las fichas de medicamentos.
      final List<Map<String, dynamic>> medicamentos = publicaciones.where((
        publicacion,
      ) {
        final String tipo = (publicacion['tipo'] ?? '')
            .toString()
            .toLowerCase();

        // Ignorar articulos y fichas de otros productos.
        if (tipo != 'ficha_medicamento') {
          return false;
        }

        final String titulo = _obtenerTexto(publicacion, [
          'titulo',
        ]).toLowerCase();

        final String descripcion = _obtenerTexto(publicacion, [
          'descripcion',
          'desc',
        ]).toLowerCase();

        // Buscar por titulo o descripcion.
        return titulo.contains(termino) || descripcion.contains(termino);
      }).toList();

      // Evitar procesar respuestas de solicitudes antiguas.
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      // Guardar los resultados encontrados.
      setState(() {
        _medicamentos = medicamentos;
        _buscando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _medicamentos = [];
        _error = error.mensaje;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _medicamentos = [];
        _error = 'No fue posible consultar los medicamentos.';
        _buscando = false;
      });
    }
  }

  // Limpiar los resultados y el buscador.
  void _limpiarBusqueda() {
    if (!mounted) {
      return;
    }

    // Invalidar cualquier solicitud anterior.
    _numeroSolicitud++;

    // Limpiar el texto introducido.
    _buscarController.clear();

    // Limpiar los resultados y mensajes.
    setState(() {
      _medicamentos = [];
      _buscando = false;
      _busquedaRealizada = false;
      _terminoBuscado = '';
      _error = null;
    });

    // Restablecer la validacion del formulario.
    _formKey.currentState?.reset();
  }

  // Abrir el articulo completo de una ficha.
  void _abrirPublicacion(Map<String, dynamic> medicamento) {
    final int? idBlog = _obtenerId(medicamento);

    if (idBlog == null || idBlog <= 0) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La ficha no tiene un identificador valido.'),
        ),
      );

      return;
    }

    // Navegar hacia el detalle real de la publicacion.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  // Mostrar informacion detallada de un medicamento.
  void _mostrarDetalle(Map<String, dynamic> medicamento) {
    final String nombre = _obtenerTexto(medicamento, [
      'titulo',
    ], defecto: 'Medicamento');

    final String descripcion = _obtenerTexto(medicamento, [
      'descripcion',
      'desc',
    ]);

    final String tipo = _obtenerTexto(medicamento, ['tipo']);

    final String autor = _obtenerTexto(medicamento, ['autor']);

    final int? idBlog = _obtenerId(medicamento);

    // Abrir una hoja con la informacion disponible.
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
                // Encabezado del medicamento.
                Row(
                  children: [
                    Icon(
                      Icons.medication_outlined,
                      size: 32,
                      color: colores.primary,
                    ),

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

                // Mostrar la informacion disponible.
                _crearApartadoDetalle(
                  titulo: 'Descripcion',
                  contenido: descripcion,
                ),

                _crearApartadoDetalle(
                  titulo: 'Tipo de contenido',
                  contenido: tipo == 'ficha_medicamento'
                      ? 'Ficha informativa de medicamento'
                      : tipo,
                ),

                _crearApartadoDetalle(titulo: 'Autor', contenido: autor),

                // Informar cuando no exista una descripcion.
                if (descripcion.isEmpty)
                  _crearApartadoDetalle(
                    titulo: 'Informacion disponible',
                    contenido:
                        'Esta ficha no cuenta con una descripcion '
                        'en los resultados de la consulta. '
                        'Puedes revisar su publicacion completa.',
                  ),

                const SizedBox(height: 12),

                // Advertencia de seguridad medica.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colores.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.health_and_safety_outlined,
                        color: colores.onPrimaryContainer,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          'Esta informacion es educativa. '
                          'Consulta a un profesional de la '
                          'salud antes de iniciar, cambiar '
                          'o suspender un medicamento.',
                          style: TextStyle(
                            fontSize: 13,
                            color: colores.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Consultar el contenido completo de la ficha.
                if (idBlog != null && idBlog > 0) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _abrirPublicacion(medicamento);
                    },
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Ver ficha completa'),
                  ),

                  const SizedBox(height: 10),
                ],

                // Cerrar la ventana de detalle.
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

  // Construir un apartado de informacion detallada.
  Widget _crearApartadoDetalle({
    required String titulo,
    required String contenido,
  }) {
    // Omitir los apartados sin informacion.
    if (contenido.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(contenido, style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  // Construir una tarjeta de medicamento.
  Widget _crearMedicamento(Map<String, dynamic> medicamento) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String nombre = _obtenerTexto(medicamento, [
      'titulo',
    ], defecto: 'Medicamento sin nombre');

    final String descripcion = _obtenerTexto(medicamento, [
      'descripcion',
      'desc',
    ], defecto: 'Sin descripcion disponible.');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _mostrarDetalle(medicamento);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icono representativo.
              Container(
                width: 65,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.medication_outlined,
                  size: 32,
                  color: colores.onPrimaryContainer,
                ),
              ),

              const SizedBox(width: 12),

              // Informacion del medicamento.
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

                    const SizedBox(height: 7),

                    Text(
                      descripcion,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Consultar informacion',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colores.primary,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(Icons.chevron_right, color: colores.primary),
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
                onPressed: _buscarMedicamentos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Construir el contenido de los resultados.
  Widget _construirResultados() {
    // Mostrar indicador de carga.
    if (_buscando) {
      return const Center(child: CircularProgressIndicator());
    }

    // Mostrar el estado inicial.
    if (!_busquedaRealizada) {
      return _construirEstado(
        icono: Icons.search,
        titulo: 'Busca un medicamento',
        descripcion:
            'Escribe su nombre para consultar '
            'la informacion disponible.',
      );
    }

    // Mostrar errores de consulta.
    if (_error != null) {
      return _construirEstado(
        icono: Icons.error_outline,
        titulo: 'Error en la consulta',
        descripcion: _error!,
        mostrarReintento: true,
      );
    }

    // Mostrar mensaje si no hay coincidencias.
    if (_medicamentos.isEmpty) {
      return _construirEstado(
        icono: Icons.medication_outlined,
        titulo: 'Sin resultados',
        descripcion:
            'No se encontraron fichas de medicamentos '
            'para "$_terminoBuscado".',
      );
    }

    // Mostrar los medicamentos encontrados.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _medicamentos.length,
      itemBuilder: (context, indice) {
        return _crearMedicamento(_medicamentos[indice]);
      },
    );
  }

  @override
  void dispose() {
    // Invalidar solicitudes pendientes.
    _numeroSolicitud++;

    // Liberar el controlador y el servicio.
    _buscarController.dispose();
    _apiService.cerrar();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de medicamentos.
      appBar: AppBar(title: const Text('Medicamentos'), centerTitle: true),

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
                      Icons.medication_outlined,
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
                          'Consulta de medicamentos',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Informacion general y educativa.',
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

              const SizedBox(height: 18),

              // Advertencia de seguridad.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.health_and_safety_outlined,
                      color: colores.onPrimaryContainer,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'La informacion es orientativa '
                        'y no sustituye una consulta '
                        'medica. Evita automedicarte.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colores.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Formulario de busqueda.
              Form(
                key: _formKey,
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _buscarController,
                        enabled: !_buscando,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar medicamento...',
                          prefixIcon: const Icon(Icons.search),

                          // Mostrar la opcion de limpiar.
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
                          setState(() {});
                        },

                        onFieldSubmitted: (_) {
                          if (!_buscando) {
                            _buscarMedicamentos();
                          }
                        },

                        validator: _validarBusqueda,
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Boton para ejecutar la consulta.
                    IconButton.filled(
                      tooltip: 'Buscar',
                      onPressed: _buscando ? null : _buscarMedicamentos,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Encabezado de resultados.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resultados de busqueda',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                  ),

                  if (_busquedaRealizada && !_buscando && _error == null)
                    Text(
                      '${_medicamentos.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Resultados de la consulta.
              Expanded(child: _construirResultados()),
            ],
          ),
        ),
      ),
    );
  }
}

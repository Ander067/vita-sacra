import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import 'detalle_publicacion_view.dart';

class _DetalleFichaSalud {
  final Map<String, dynamic> publicacion;
  final List<Map<String, dynamic>> fuentes;
  final String? errorFuentes;

  const _DetalleFichaSalud({
    required this.publicacion,
    required this.fuentes,
    this.errorFuentes,
  });
}

// Consulta educativa de medicamentos y productos de salud.
class MedicamentosView extends StatefulWidget {
  const MedicamentosView({super.key});

  @override
  State<MedicamentosView> createState() => _MedicamentosViewState();
}

class _MedicamentosViewState extends State<MedicamentosView> {
  final ApiService _apiService = ApiService();
  final TextEditingController _buscarController = TextEditingController();

  List<Map<String, dynamic>> _fichas = [];
  List<String> _categorias = [];

  bool _cargando = true;
  String? _error;
  String _categoriaSeleccionada = '';

  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();
    _cargarFichas();
  }

  String _obtenerTexto(
    Map<String, dynamic> datos,
    List<String> campos, {
    String defecto = '',
  }) {
    for (final String campo in campos) {
      final dynamic valor = datos[campo];

      if (valor != null) {
        final String texto = valor.toString().trim();

        if (texto.isNotEmpty) {
          return texto;
        }
      }
    }

    return defecto;
  }

  int? _obtenerId(Map<String, dynamic> publicacion) {
    final dynamic valor =
        publicacion['id_blog'] ?? publicacion['blog_id'] ?? publicacion['id'];

    if (valor is int) {
      return valor;
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  Future<void> _cargarFichas() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Este endpoint consulta blog_publico: solo contiene publicaciones
      // publicadas y apunta a la version publica vigente.
      final dynamic respuesta = await _apiService.get('/publicaciones/');

      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ??
            respuesta['publicaciones'] ??
            respuesta['results'];
      }

      if (registros is! List) {
        throw const ApiException(
          'El formato de las fichas recibidas no es valido.',
        );
      }

      final List<Map<String, dynamic>> fichas = [];

      for (final dynamic registro in registros) {
        if (registro is! Map) {
          throw const ApiException(
            'Se recibio una ficha con formato no valido.',
          );
        }

        final Map<String, dynamic> ficha = Map<String, dynamic>.from(registro);

        final String tipo = _obtenerTexto(ficha, ['tipo']).toLowerCase();

        if (tipo == 'ficha_medicamento' || tipo == 'ficha_producto') {
          fichas.add(ficha);
        }
      }

      final List<String> categorias =
          fichas
              .map((ficha) => _obtenerTexto(ficha, ['categoria']))
              .where((categoria) => categoria.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _fichas = fichas;
        _categorias = categorias;

        if (_categoriaSeleccionada.isNotEmpty &&
            !_categorias.contains(_categoriaSeleccionada)) {
          _categoriaSeleccionada = '';
        }

        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _fichas = [];
        _categorias = [];
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _fichas = [];
        _categorias = [];
        _error = 'No fue posible cargar las fichas de salud.';
        _cargando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _fichasFiltradas {
    final String busqueda = _buscarController.text.trim().toLowerCase();

    return _fichas.where((ficha) {
      final String titulo = _obtenerTexto(ficha, ['titulo']).toLowerCase();
      final String categoria = _obtenerTexto(ficha, [
        'categoria',
      ]).toLowerCase();

      final bool coincideBusqueda =
          busqueda.isEmpty ||
          titulo.contains(busqueda) ||
          categoria.contains(busqueda);

      final bool coincideCategoria =
          _categoriaSeleccionada.isEmpty ||
          _obtenerTexto(ficha, ['categoria']) == _categoriaSeleccionada;

      return coincideBusqueda && coincideCategoria;
    }).toList();
  }

  Future<_DetalleFichaSalud> _cargarDetalle(int idBlog) async {
    final dynamic respuesta = await _apiService.get('/publicaciones/$idBlog');

    if (respuesta is! Map) {
      throw const ApiException(
        'El detalle de la ficha tiene un formato no valido.',
      );
    }

    final Map<String, dynamic> publicacion = Map<String, dynamic>.from(
      respuesta,
    );

    List<Map<String, dynamic>> fuentes = [];
    String? errorFuentes;

    try {
      final dynamic respuestaFuentes = await _apiService.get(
        '/recursos/publicaciones/$idBlog/fuentes',
      );

      dynamic registros = respuestaFuentes;

      if (respuestaFuentes is Map) {
        registros =
            respuestaFuentes['items'] ??
            respuestaFuentes['fuentes'] ??
            respuestaFuentes['results'];
      }

      if (registros is! List) {
        throw const ApiException('El formato de las referencias no es valido.');
      }

      fuentes = registros.map((registro) {
        if (registro is! Map) {
          throw const ApiException(
            'Se recibio una referencia con formato no valido.',
          );
        }

        return Map<String, dynamic>.from(registro);
      }).toList();
    } on ApiException catch (error) {
      errorFuentes = error.mensaje;
    } catch (error) {
      errorFuentes = 'No fue posible consultar las referencias.';
    }

    return _DetalleFichaSalud(
      publicacion: publicacion,
      fuentes: fuentes,
      errorFuentes: errorFuentes,
    );
  }

  void _mostrarDetalle(Map<String, dynamic> ficha) {
    final int? idBlog = _obtenerId(ficha);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La ficha no tiene un identificador valido.');
      return;
    }

    final Future<_DetalleFichaSalud> detalle = _cargarDetalle(idBlog);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: FutureBuilder<_DetalleFichaSalud>(
              future: detalle,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final Object? error = snapshot.error;
                  final String mensaje = error is ApiException
                      ? error.mensaje
                      : 'No fue posible cargar el detalle de la ficha.';

                  return _construirErrorDetalle(mensaje);
                }

                final _DetalleFichaSalud? datos = snapshot.data;

                if (datos == null) {
                  return _construirErrorDetalle(
                    'No se recibieron datos de la ficha.',
                  );
                }

                return _construirDetalle(datos);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _construirErrorDetalle(String mensaje) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(
          height: 260,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: colores.error),
                const SizedBox(height: 12),
                Text(mensaje, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirDetalle(_DetalleFichaSalud datos) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final Map<String, dynamic> publicacion = datos.publicacion;

    final String titulo = _obtenerTexto(publicacion, [
      'titulo',
    ], defecto: 'Ficha de salud');

    final String descripcion = _obtenerTexto(publicacion, [
      'descripcion',
      'desc',
    ], defecto: 'No hay descripcion disponible.');

    final String categoria = _obtenerTexto(publicacion, [
      'categoria',
    ], defecto: 'No especificada');

    final String tipo = _obtenerTexto(publicacion, ['tipo']);
    final String nombreTipo = tipo == 'ficha_producto'
        ? 'Producto de salud'
        : 'Medicamento';

    final String advertencia = _obtenerTexto(publicacion, ['advertencia']);
    final String fechaRevision = _formatearFecha(publicacion['fecha_revision']);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.medication_outlined, size: 32, color: colores.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
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

        _crearSeccion(titulo: 'Descripcion general', contenido: descripcion),

        _crearSeccion(titulo: 'Categoria', contenido: categoria),

        _crearSeccion(titulo: 'Tipo de ficha', contenido: nombreTipo),

        _crearSeccion(
          titulo: 'Fecha de revision editorial',
          contenido: fechaRevision,
        ),

        _crearSeccion(
          titulo: 'Advertencia de la ficha',
          contenido: advertencia.isEmpty
              ? 'No se registro una advertencia especifica para esta ficha.'
              : advertencia,
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 20),
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
                  'Contenido educativo: no sustituye la consulta con '
                  'un profesional de la salud. Vita Sacra no ofrece '
                  'diagnosticos, prescripciones, dosis personalizadas '
                  'ni compras de medicamentos.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colores.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),

        Text(
          'Fuentes y referencias',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 10),

        if (datos.errorFuentes != null)
          _construirAviso(datos.errorFuentes!, esError: true)
        else if (datos.fuentes.isEmpty)
          _construirAviso(
            'Esta ficha no tiene referencias bibliograficas registradas.',
          )
        else
          ...datos.fuentes.map(_crearFuente),

        const SizedBox(height: 16),

        if (_obtenerId(publicacion) != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _abrirPublicacion(publicacion);
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Ver publicacion completa'),
          ),

        const SizedBox(height: 8),

        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _crearFuente(Map<String, dynamic> fuente) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String titulo = _obtenerTexto(fuente, [
      'titulo',
    ], defecto: 'Referencia sin titulo');

    final String autor = _obtenerTexto(fuente, ['autor']);
    final String anio = _obtenerTexto(fuente, ['anio']);
    final String url = _obtenerTexto(fuente, ['url']);
    final bool urlSegura = _esUrlHttpsSegura(url);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),

            if (autor.isNotEmpty || anio.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (autor.isNotEmpty) autor,
                  if (anio.isNotEmpty) anio,
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 8),

            if (urlSegura)
              TextButton.icon(
                onPressed: () {
                  _abrirFuente(url);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir referencia'),
              )
            else
              Text(
                url.isEmpty ? 'Esta referencia no tiene un enlace registrado.' : 'Enlace no disponible: solo se abren enlaces HTTPS seguros.',
                style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _crearSeccion({required String titulo, required String contenido}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          Text(contenido, style: const TextStyle(fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }

  Widget _construirAviso(String mensaje, {bool esError = false}) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esError ? colores.errorContainer : colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        mensaje,
        style: TextStyle(
          color: esError ? colores.onErrorContainer : colores.onSurfaceVariant,
        ),
      ),
    );
  }

  String _formatearFecha(dynamic valor) {
    if (valor == null) {
      return 'No disponible';
    }

    final String texto = valor.toString().trim();

    if (texto.isEmpty) {
      return 'No disponible';
    }

    final DateTime? fecha = DateTime.tryParse(texto);

    if (fecha == null) {
      return texto;
    }

    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  bool _esUrlHttpsSegura(String url) {
    final Uri? uri = Uri.tryParse(url.trim());

    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Future<void> _abrirFuente(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());

    if (uri == null || !_esUrlHttpsSegura(url)) {
      _mostrarMensaje('El enlace de la referencia no es valido o seguro.');
      return;
    }

    try {
      final bool abierto = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) {
        return;
      }

      if (!abierto) {
        _mostrarMensaje('No fue posible abrir la referencia.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('Ocurrio un error al abrir la referencia.');
    }
  }

  void _abrirPublicacion(Map<String, dynamic> publicacion) {
    final int? idBlog = _obtenerId(publicacion);

    if (idBlog == null || idBlog <= 0) {
      _mostrarMensaje('La ficha no tiene un identificador valido.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetallePublicacionView(idBlog: idBlog),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Widget _crearFicha(Map<String, dynamic> ficha) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final String titulo = _obtenerTexto(ficha, [
      'titulo',
    ], defecto: 'Ficha sin titulo');

    final String descripcion = _obtenerTexto(ficha, [
      'descripcion',
      'desc',
    ], defecto: 'Sin descripcion disponible.');

    final String categoria = _obtenerTexto(ficha, [
      'categoria',
    ], defecto: 'Categoria no especificada');

    final String tipo = _obtenerTexto(ficha, ['tipo']);
    final String etiqueta = tipo == 'ficha_producto'
        ? 'Producto de salud'
        : 'Medicamento';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _mostrarDetalle(ficha);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colores.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
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
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$etiqueta · $categoria',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colores.primary),
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
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: colores.primary),
            ],
          ),
        ),
      ),
    );
  }

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
            Icon(icono, size: 48, color: colores.primary),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
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
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _cargarFichas,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _construirLista() {
    if (_cargando) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 280,
            child: _construirEstado(
              icono: Icons.error_outline,
              titulo: 'No se pudieron cargar las fichas',
              descripcion: _error!,
              mostrarReintento: true,
            ),
          ),
        ],
      );
    }

    if (_fichas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 280,
            child: _construirEstado(
              icono: Icons.medication_outlined,
              titulo: 'No hay fichas disponibles',
              descripcion:
                  'Todavia no hay fichas de medicamentos o productos '
                  'de salud publicadas y aprobadas.',
            ),
          ),
        ],
      );
    }

    final List<Map<String, dynamic>> filtradas = _fichasFiltradas;

    if (filtradas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 280,
            child: _construirEstado(
              icono: Icons.search_off_outlined,
              titulo: 'Sin resultados',
              descripcion:
                  'No se encontraron fichas para los filtros seleccionados.',
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: filtradas.length,
      itemBuilder: (context, indice) => _crearFicha(filtradas[indice]),
    );
  }

  @override
  void dispose() {
    _numeroSolicitud++;
    _buscarController.dispose();
    _apiService.cerrar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Medicamentos y salud'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar fichas',
            onPressed: _cargando ? null : _cargarFichas,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consulta educativa',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: colores.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Busca por nombre o categoria. Solo se muestran '
                    'fichas publicadas.',
                    style: TextStyle(color: colores.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _buscarController,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar medicamento o categoria...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _buscarController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar busqueda',
                              onPressed: () {
                                _buscarController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _categoriaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por categoria',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Todas las categorias'),
                      ),
                      ..._categorias.map(
                        (categoria) => DropdownMenuItem<String>(
                          value: categoria,
                          child: Text(
                            categoria,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (valor) {
                      setState(() {
                        _categoriaSeleccionada = valor ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'La informacion es educativa y no sustituye la '
                      'valoracion de un profesional de la salud. '
                      'No te automediques.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colores.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargarFichas,
                child: _construirLista(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

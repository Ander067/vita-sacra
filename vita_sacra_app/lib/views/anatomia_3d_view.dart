import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../widgets/visor_modelo_3d.dart';
import 'detalle_publicacion_view.dart';

class ModeloAnatomico {
  final int idRecurso;
  final int idBlog;
  final String titulo;
  final String url;
  final String tituloPublicacion;
  final String categoria;
  final String? mime;
  final String? licencia;
  final String? procedencia;

  const ModeloAnatomico({
    required this.idRecurso,
    required this.idBlog,
    required this.titulo,
    required this.url,
    required this.tituloPublicacion,
    required this.categoria,
    this.mime,
    this.licencia,
    this.procedencia,
  });

  factory ModeloAnatomico.fromJson(Map<String, dynamic> json) {
    return ModeloAnatomico(
      idRecurso: int.tryParse('${json['id_recurso']}') ?? 0,
      idBlog: int.tryParse('${json['id_blog']}') ?? 0,
      titulo: (json['titulo'] ?? '').toString().trim(),
      url: (json['url'] ?? '').toString().trim(),
      tituloPublicacion: (json['titulo_publicacion'] ?? '').toString().trim(),
      categoria: (json['categoria'] ?? '').toString().trim(),
      mime: json['mime']?.toString(),
      licencia: json['licencia']?.toString(),
      procedencia: json['procedencia']?.toString(),
    );
  }
}

class Anatomia3DView extends StatefulWidget {
  final int? idBlog;

  const Anatomia3DView({super.key, this.idBlog});

  @override
  State<Anatomia3DView> createState() => _Anatomia3DViewState();
}

class _Anatomia3DViewState extends State<Anatomia3DView> {
  final ApiService _apiService = ApiService();
  final TextEditingController _buscarController = TextEditingController();

  List<ModeloAnatomico> _modelos = [];
  List<String> _categorias = [];
  ModeloAnatomico? _modeloSeleccionado;

  String _categoriaSeleccionada = '';
  bool _cargando = true;
  String? _error;
  int _numeroSolicitud = 0;

  bool get _esBiblioteca => widget.idBlog == null;

  @override
  void initState() {
    super.initState();
    _cargarModelos();
  }

  @override
  void didUpdateWidget(covariant Anatomia3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.idBlog != widget.idBlog) {
      _numeroSolicitud++;
      _modelos = [];
      _categorias = [];
      _modeloSeleccionado = null;
      _categoriaSeleccionada = '';
      _buscarController.clear();
      _cargarModelos();
    }
  }

  String _claveModelo(ModeloAnatomico modelo) {
    return '${modelo.idBlog}:${modelo.idRecurso}';
  }

  Future<void> _cargarModelos() async {
    if (!mounted) {
      return;
    }

    if (widget.idBlog != null && widget.idBlog! <= 0) {
      setState(() {
        _modelos = [];
        _categorias = [];
        _modeloSeleccionado = null;
        _error = 'El identificador de la publicacion no es valido.';
        _cargando = false;
      });
      return;
    }

    final int solicitud = ++_numeroSolicitud;
    final String? seleccionAnterior = _modeloSeleccionado == null
        ? null
        : _claveModelo(_modeloSeleccionado!);

    final String endpoint = widget.idBlog == null
        ? '/recursos/modelos-3d/publicos'
        : '/recursos/modelos-3d/publicos?blog_id=${widget.idBlog}';

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final dynamic respuesta = await _apiService.get(endpoint);

      dynamic registros = respuesta;

      if (respuesta is Map) {
        registros =
            respuesta['items'] ?? respuesta['modelos'] ?? respuesta['results'];
      }

      if (registros is! List) {
        throw const ApiException(
          'El formato de la biblioteca de modelos no es valido.',
        );
      }

      final Map<String, ModeloAnatomico> modelosUnicos = {};

      for (final dynamic registro in registros) {
        if (registro is! Map) {
          throw const ApiException(
            'Se recibio un modelo con formato no valido.',
          );
        }

        final ModeloAnatomico modelo = ModeloAnatomico.fromJson(
          Map<String, dynamic>.from(registro),
        );

        if (modelo.idRecurso <= 0 || modelo.idBlog <= 0) {
          throw const ApiException(
            'Un modelo no contiene identificadores validos.',
          );
        }

        modelosUnicos.putIfAbsent(_claveModelo(modelo), () => modelo);
      }

      final List<ModeloAnatomico> modelos = modelosUnicos.values.toList();

      final List<String> categorias =
          modelos
              .map((modelo) => modelo.categoria)
              .where((categoria) => categoria.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      ModeloAnatomico? seleccionado;

      if (seleccionAnterior != null) {
        for (final ModeloAnatomico modelo in modelos) {
          if (_claveModelo(modelo) == seleccionAnterior) {
            seleccionado = modelo;
            break;
          }
        }
      }

      seleccionado ??= modelos.isEmpty ? null : modelos.first;

      setState(() {
        _modelos = modelos;
        _categorias = categorias;
        _modeloSeleccionado = seleccionado;
        _cargando = false;
        _error = null;

        if (!_categorias.contains(_categoriaSeleccionada)) {
          _categoriaSeleccionada = '';
        }
      });

      _ajustarSeleccionAFiltros();
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _modelos = [];
        _categorias = [];
        _modeloSeleccionado = null;
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _modelos = [];
        _categorias = [];
        _modeloSeleccionado = null;
        _error = 'No fue posible consultar los modelos anatomicos.';
        _cargando = false;
      });
    }
  }

  List<ModeloAnatomico> get _modelosFiltrados {
    final String busqueda = _buscarController.text.trim().toLowerCase();

    return _modelos.where((modelo) {
      final bool coincideBusqueda =
          busqueda.isEmpty ||
          modelo.titulo.toLowerCase().contains(busqueda) ||
          modelo.tituloPublicacion.toLowerCase().contains(busqueda) ||
          modelo.categoria.toLowerCase().contains(busqueda);

      final bool coincideCategoria =
          _categoriaSeleccionada.isEmpty ||
          modelo.categoria == _categoriaSeleccionada;

      return coincideBusqueda && coincideCategoria;
    }).toList();
  }

  void _ajustarSeleccionAFiltros() {
    if (!mounted) {
      return;
    }

    setState(() {
      final List<ModeloAnatomico> filtrados = _modelosFiltrados;
      final ModeloAnatomico? actual = _modeloSeleccionado;

      if (filtrados.isEmpty) {
        _modeloSeleccionado = null;
      } else if (actual == null ||
          !filtrados.any(
            (modelo) => _claveModelo(modelo) == _claveModelo(actual),
          )) {
        _modeloSeleccionado = filtrados.first;
      }
    });
  }

  void _actualizarBusqueda(String valor) {
    _ajustarSeleccionAFiltros();
  }

  void _actualizarCategoria(String? categoria) {
    _categoriaSeleccionada = categoria ?? '';
    _ajustarSeleccionAFiltros();
  }

  void _seleccionarModelo(ModeloAnatomico modelo) {
    setState(() {
      _modeloSeleccionado = modelo;
    });
  }

  Future<void> _copiarEnlace() async {
    final ModeloAnatomico? modelo = _modeloSeleccionado;

    if (modelo == null) {
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: modelo.url));

      if (!mounted) {
        return;
      }

      _mostrarMensaje('Enlace del modelo copiado.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible copiar el enlace.');
    }
  }

  void _abrirPublicacion(int idBlog) {
    if (idBlog <= 0) {
      _mostrarMensaje('La publicacion asociada no es valida.');
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

  Widget _construirEncabezado(ColorScheme colores) {
    final String titulo = _esBiblioteca
        ? 'Biblioteca de anatomia 3D'
        : 'Modelos de la publicacion';

    final String descripcion = _esBiblioteca
        ? 'Explora modelos GLB aprobados asociados a publicaciones educativas.'
        : 'Modelos GLB aprobados asociados a este contenido educativo.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colores.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.accessibility_new_outlined,
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
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                descripcion,
                style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirFiltros(ColorScheme colores) {
    if (!_esBiblioteca) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        TextField(
          controller: _buscarController,
          onChanged: _actualizarBusqueda,
          decoration: InputDecoration(
            hintText: 'Buscar modelo, publicacion o categoria...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buscarController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar busqueda',
                    onPressed: () {
                      _buscarController.clear();
                      _actualizarBusqueda('');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_categorias.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _categoriaSeleccionada,
            decoration: const InputDecoration(
              labelText: 'Filtrar por categoria',
              prefixIcon: Icon(Icons.category_outlined),
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Todas las categorias'),
              ),
              ..._categorias.map(
                (categoria) => DropdownMenuItem<String>(
                  value: categoria,
                  child: Text(categoria, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: _actualizarCategoria,
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _construirMensaje({
    required ColorScheme colores,
    required IconData icono,
    required String titulo,
    required String descripcion,
    bool reintentar = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colores.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icono, size: 46, color: colores.primary),
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
          if (reintentar) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _cargarModelos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirVisor(ColorScheme colores) {
    final ModeloAnatomico? modelo = _modeloSeleccionado;

    if (modelo == null) {
      return _construirMensaje(
        colores: colores,
        icono: Icons.view_in_ar_outlined,
        titulo: 'Selecciona un modelo',
        descripcion: 'Elige un modelo de la lista para visualizarlo.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisorModelo3D(
          key: ValueKey<String>(_claveModelo(modelo)),
          urlModelo: modelo.url,
          titulo: modelo.titulo,
          mime: modelo.mime,
          altura: 340,
        ),
        const SizedBox(height: 10),
        Text(
          'Arrastra para girar y usa dos dedos para acercar o alejar. '
          'Toca el icono AR del visor para abrir Scene Viewer.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _construirListaModelos(ColorScheme colores) {
    final List<ModeloAnatomico> modelos = _modelosFiltrados;

    if (modelos.isEmpty) {
      return _construirMensaje(
        colores: colores,
        icono: Icons.search_off_outlined,
        titulo: 'Sin resultados',
        descripcion: 'No hay modelos que coincidan con los filtros.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modelos disponibles (${modelos.length})',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        ...modelos.map((modelo) {
          final bool seleccionado =
              _modeloSeleccionado != null &&
              _claveModelo(_modeloSeleccionado!) == _claveModelo(modelo);

          final String titulo = modelo.titulo.isEmpty
              ? 'Modelo ${modelo.idRecurso}'
              : modelo.titulo;

          return Card(
            color: seleccionado
                ? colores.primaryContainer
                : colores.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              leading: Icon(
                Icons.view_in_ar_outlined,
                color: seleccionado
                    ? colores.onPrimaryContainer
                    : colores.primary,
              ),
              title: Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (modelo.tituloPublicacion.isNotEmpty)
                    modelo.tituloPublicacion,
                  if (modelo.categoria.isNotEmpty) modelo.categoria,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                seleccionado ? Icons.check_circle : Icons.chevron_right,
                color: seleccionado
                    ? colores.primary
                    : colores.onSurfaceVariant,
              ),
              onTap: () => _seleccionarModelo(modelo),
            ),
          );
        }),
      ],
    );
  }

  Widget _construirInformacion(ColorScheme colores) {
    final ModeloAnatomico? modelo = _modeloSeleccionado;

    if (modelo == null) {
      return const SizedBox.shrink();
    }

    final String licencia = modelo.licencia?.trim() ?? '';
    final String procedencia = modelo.procedencia?.trim() ?? '';
    final String mime = modelo.mime?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informacion y atribucion',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            modelo.titulo.isEmpty
                ? 'Modelo ${modelo.idRecurso}'
                : modelo.titulo,
          ),
          if (modelo.tituloPublicacion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Publicacion: ${modelo.tituloPublicacion}',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
          ],
          if (modelo.categoria.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Categoria: ${modelo.categoria}',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
          ],
          if (mime.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Formato: $mime',
              style: TextStyle(color: colores.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Licencia: ${licencia.isEmpty ? "No especificada" : licencia}',
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            'Procedencia: '
            '${procedencia.isEmpty ? "No especificada" : procedencia}',
            style: TextStyle(color: colores.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _copiarEnlace,
                icon: const Icon(Icons.link_outlined),
                label: const Text('Copiar enlace'),
              ),
              OutlinedButton.icon(
                onPressed: () => _abrirPublicacion(modelo.idBlog),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Ver publicacion'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirAdvertencia(ColorScheme colores) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Los modelos tienen fines educativos. No sustituyen la valoracion '
        'de un profesional de la salud ni materiales clinicos especializados.',
        style: TextStyle(fontSize: 12, color: colores.onPrimaryContainer),
      ),
    );
  }

  Widget _construirContenido(ColorScheme colores) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _construirMensaje(
        colores: colores,
        icono: Icons.error_outline,
        titulo: 'No se pudieron cargar los modelos',
        descripcion: _error!,
        reintentar: true,
      );
    }

    if (_modelos.isEmpty) {
      return _construirMensaje(
        colores: colores,
        icono: Icons.inventory_2_outlined,
        titulo: 'No hay modelos disponibles',
        descripcion: _esBiblioteca
            ? 'Aun no hay modelos GLB aprobados asociados a publicaciones '
                  'publicas. Cuando se agreguen desde la web, apareceran aqui.'
            : 'Esta publicacion no tiene modelos GLB aprobados y disponibles.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _construirVisor(colores),
        const SizedBox(height: 20),
        _construirListaModelos(colores),
        const SizedBox(height: 18),
        _construirInformacion(colores),
        const SizedBox(height: 18),
        _construirAdvertencia(colores),
      ],
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
        title: Text(_esBiblioteca ? 'Biblioteca 3D' : 'Modelos anatomicos'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar modelos',
            onPressed: _cargando ? null : _cargarModelos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargarModelos,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _construirEncabezado(colores),
              const SizedBox(height: 18),
              if (_esBiblioteca && _modelos.isNotEmpty)
                _construirFiltros(colores),
              _construirContenido(colores),
            ],
          ),
        ),
      ),
    );
  }
}

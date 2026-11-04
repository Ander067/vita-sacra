import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../widgets/visor_modelo_3d.dart';

// Modelo de datos para un recurso anatomico publico y aprobado.
class ModeloAnatomico {
  final int idRecurso;
  final String titulo;
  final String url;
  final String? mime;
  final String? licencia;
  final String? procedencia;

  const ModeloAnatomico({
    required this.idRecurso,
    required this.titulo,
    required this.url,
    this.mime,
    this.licencia,
    this.procedencia,
  });

  // Construir el modelo con la respuesta publica de FastAPI.
  factory ModeloAnatomico.fromJson(Map<String, dynamic> json) {
    return ModeloAnatomico(
      idRecurso: int.tryParse('${json['id_recurso']}') ?? 0,
      titulo: (json['titulo'] ?? '').toString().trim(),
      url: (json['url'] ?? '').toString().trim(),
      mime: json['mime']?.toString(),
      licencia: json['licencia']?.toString(),
      procedencia: json['procedencia']?.toString(),
    );
  }
}

// Pantalla para consultar modelos anatomicos asociados a publicaciones.
class Anatomia3DView extends StatefulWidget {
  // Identificador opcional de la publicacion.
  final int? idBlog;

  const Anatomia3DView({super.key, this.idBlog});

  @override
  State<Anatomia3DView> createState() => _Anatomia3DViewState();
}

class _Anatomia3DViewState extends State<Anatomia3DView> {
  // Servicio para consumir las APIs de Vita Sacra.
  final ApiService _apiService = ApiService();

  // Recursos tridimensionales de la publicacion.
  List<ModeloAnatomico> _modelos = [];
  ModeloAnatomico? _modeloSeleccionado;

  // Estado de consulta.
  bool _cargando = false;
  String? _error;

  // Identificador para descartar respuestas anteriores.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();
    _cargarModelos();
  }

  @override
  void didUpdateWidget(covariant Anatomia3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Consultar nuevamente cuando cambie la publicacion.
    if (oldWidget.idBlog != widget.idBlog) {
      // Descartar los modelos de la publicacion anterior.
      _numeroSolicitud++;
      _modelos = [];
      _modeloSeleccionado = null;
      _cargarModelos();
    }
  }

  // Convertir los identificadores recibidos desde FastAPI.
  int? _convertirEntero(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    return int.tryParse(valor?.toString() ?? '');
  }

  // Verificar que la direccion no contenga credenciales y utilice HTTPS.
  bool _esUrlSegura(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  // Comprobar que el recurso corresponda a un archivo GLB.
  // El tipo MIME puede variar entre proveedores de archivos 3D.
  bool _esArchivoGlb(ModeloAnatomico modelo) {
    final Uri? uri = Uri.tryParse(modelo.url);
    if (uri == null) {
      return false;
    }

    final String ruta = uri.path.toLowerCase();
    final String mime = (modelo.mime ?? '').trim().toLowerCase();
    // La extension .glb identifica el formato requerido.
    // Si la URL es opaca, se admite el MIME especifico de GLB.
    return ruta.endsWith('.glb') || mime == 'model/gltf-binary';
  }

  // Consultar los modelos tridimensionales de una publicacion.
  Future<void> _cargarModelos() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;
    final int? idBlog = widget.idBlog;
    final int? seleccionAnterior = _modeloSeleccionado?.idRecurso;

    if (idBlog == null || idBlog <= 0) {
      setState(() {
        _modelos = [];
        _modeloSeleccionado = null;
        _cargando = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Recuperar los bloques de la version publicada.
      final dynamic respuesta = await _apiService.get(
        '/recursos/publicaciones/$idBlog/bloques',
      );

      if (respuesta is! List) {
        throw const ApiException('La respuesta de los bloques no es valida.');
      }

      // Evitar consultar dos veces un mismo recurso.
      final Set<int> identificadores = {};

      for (final dynamic elemento in respuesta) {
        if (elemento is! Map) {
          continue;
        }

        final Map<String, dynamic> bloque = Map<String, dynamic>.from(elemento);

        if (bloque['tipo'] != 'modelo_3d') {
          continue;
        }

        final int? idRecurso = _convertirEntero(bloque['recurso_id']);
        if (idRecurso != null && idRecurso > 0) {
          identificadores.add(idRecurso);
        }
      }

      final List<ModeloAnatomico> modelos = [];

      // Verificar cada recurso en el endpoint publico de FastAPI.
      for (final int idRecurso in identificadores) {
        if (!mounted || solicitud != _numeroSolicitud) {
          return;
        }

        try {
          final dynamic datos = await _apiService.get(
            '/recursos/publicos/$idRecurso',
          );

          if (datos is! Map) {
            continue;
          }

          final Map<String, dynamic> recurso = Map<String, dynamic>.from(datos);

          // El endpoint publico solamente debe entregar aprobados.
          if (recurso['tipo'] != 'modelo_3d') {
            continue;
          }

          final ModeloAnatomico modelo = ModeloAnatomico.fromJson(recurso);

          // Comprobar identidad, URL y formato del archivo.
          if (modelo.idRecurso != idRecurso ||
              !_esUrlSegura(modelo.url) ||
              !_esArchivoGlb(modelo)) {
            continue;
          }

          modelos.add(modelo);
        } on ApiException catch (error) {
          // Un recurso no disponible no impide consultar los demas.
          if (error.codigoEstado != 403 && error.codigoEstado != 404) {
            rethrow;
          }
        }
      }

      if (!mounted ||
          solicitud != _numeroSolicitud ||
          idBlog != widget.idBlog) {
        return;
      }

      ModeloAnatomico? seleccionado;
      for (final ModeloAnatomico modelo in modelos) {
        if (modelo.idRecurso == seleccionAnterior) {
          seleccionado = modelo;
          break;
        }
      }

      if (seleccionado == null && modelos.isNotEmpty) {
        seleccionado = modelos.first;
      }

      setState(() {
        _modelos = modelos;
        _modeloSeleccionado = seleccionado;
        _cargando = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }
      setState(() {
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }
      setState(() {
        _error = 'No fue posible consultar los modelos anatomicos.';
        _cargando = false;
      });
    }
  }

  // Seleccionar un modelo de la publicacion.
  void _seleccionarModelo(ModeloAnatomico modelo) {
    setState(() {
      _modeloSeleccionado = modelo;
    });
  }

  // Copiar la direccion del recurso autorizado.
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace del recurso copiado correctamente.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible copiar el enlace.')),
      );
    }
  }

  // Construir el encabezado principal.
  Widget _construirEncabezado() {
    final ColorScheme colores = Theme.of(context).colorScheme;

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
                'Anatomia tridimensional',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Consulta recursos anatomicos '
                'asociados a publicaciones educativas.',
                style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Construir el area de visualizacion interactiva del modelo GLB.
  Widget _construirVisor() {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ModeloAnatomico? modelo = _modeloSeleccionado;

    // Mantener un mensaje informativo mientras no exista un modelo seleccionado.
    if (modelo == null) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 250),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colores.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colores.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 70, color: colores.primary),
            const SizedBox(height: 16),
            Text(
              'Visualizador anatomico 3D',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colores.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Selecciona un modelo anatomico disponible para visualizarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Mostrar el archivo autorizado con rotacion y zoom mediante el widget 3D.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisorModelo3D(
          key: ValueKey<int>(modelo.idRecurso),
          urlModelo: modelo.url,
          titulo: modelo.titulo,
          mime: modelo.mime,
          altura: 300,
        ),
        const SizedBox(height: 10),
        Text(
          modelo.titulo.isNotEmpty
              ? modelo.titulo
              : 'Modelo ${modelo.idRecurso}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Gira el modelo y utiliza los gestos de acercamiento para explorarlo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Center(
          child: OutlinedButton.icon(
            onPressed: _copiarEnlace,
            icon: const Icon(Icons.link_outlined),
            label: const Text('Copiar enlace del modelo'),
          ),
        ),
      ],
    );
  }

  // Construir un mensaje cuando no se selecciono una publicacion.
  Widget _construirSinPublicacion() {
    return _construirMensaje(
      Icons.article_outlined,
      'Selecciona una publicacion',
      'Los modelos anatomicos se consultan desde los articulos '
          'educativos publicados. Abre una publicacion que contenga '
          'recursos tridimensionales.',
    );
  }

  // Construir un mensaje cuando no hay modelos disponibles.
  Widget _construirSinModelos() {
    return _construirMensaje(
      Icons.inventory_2_outlined,
      'No hay modelos disponibles',
      'Esta publicacion no tiene archivos GLB publicos, '
          'aprobados y disponibles.',
    );
  }

  // Construir los mensajes de estado de la pantalla.
  Widget _construirMensaje(IconData icono, String titulo, String descripcion) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icono, size: 42, color: colores.primary),
          const SizedBox(height: 12),
          Text(
            titulo,
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
            style: TextStyle(fontSize: 13, color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Construir la lista de modelos asociados al articulo.
  Widget _construirModelos() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modelos disponibles',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        ..._modelos.map((modelo) {
          final bool seleccionado =
              _modeloSeleccionado?.idRecurso == modelo.idRecurso;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: seleccionado
                  ? colores.primaryContainer
                  : colores.surfaceContainerLow,
              child: ListTile(
                leading: Icon(
                  Icons.view_in_ar_outlined,
                  color: seleccionado
                      ? colores.onPrimaryContainer
                      : colores.primary,
                ),
                title: Text(
                  modelo.titulo.isNotEmpty
                      ? modelo.titulo
                      : 'Modelo ${modelo.idRecurso}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Recurso ${modelo.idRecurso}'),
                trailing: Icon(
                  seleccionado ? Icons.check_circle : Icons.chevron_right,
                  color: seleccionado
                      ? colores.primary
                      : colores.onSurfaceVariant,
                ),
                onTap: () => _seleccionarModelo(modelo),
              ),
            ),
          );
        }),
      ],
    );
  }

  // Construir los datos del modelo seleccionado.
  Widget _construirInformacion() {
    final ModeloAnatomico? modelo = _modeloSeleccionado;
    if (modelo == null) {
      return const SizedBox.shrink();
    }

    final ColorScheme colores = Theme.of(context).colorScheme;
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
            'Informacion del recurso',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Nombre:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
            modelo.titulo.isNotEmpty
                ? modelo.titulo
                : 'Modelo ${modelo.idRecurso}',
          ),
          if (mime.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Tipo de archivo:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(mime),
          ],
          const SizedBox(height: 14),
          const Text(
            'Licencia:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            licencia.isNotEmpty ? licencia : 'No especificada en el recurso.',
          ),
          const SizedBox(height: 14),
          const Text(
            'Procedencia:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            procedencia.isNotEmpty
                ? procedencia
                : 'No especificada en el recurso.',
          ),
        ],
      ),
    );
  }

  // Construir la advertencia educativa.
  Widget _construirAdvertencia() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
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
              'Este modulo tiene fines educativos. '
              'Los modelos anatomicos no sustituyen '
              'la valoracion de un profesional de la salud '
              'ni los materiales clinicos especializados.',
              style: TextStyle(fontSize: 12, color: colores.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _numeroSolicitud++;
    _apiService.cerrar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(title: const Text('Anatomia humana'), centerTitle: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargarModelos,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _construirEncabezado(),
                const SizedBox(height: 22),
                _construirVisor(),
                const SizedBox(height: 26),
                if (_cargando)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colores.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colores.onErrorContainer),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _cargarModelos,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ),
                ],
                if (!_cargando && _error == null) ...[
                  if (widget.idBlog == null || widget.idBlog! <= 0)
                    _construirSinPublicacion()
                  else if (_modelos.isEmpty)
                    _construirSinModelos()
                  else ...[
                    _construirModelos(),
                    const SizedBox(height: 22),
                    _construirInformacion(),
                  ],
                ],
                const SizedBox(height: 24),
                _construirAdvertencia(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

// Tipos de contenido que pueden reportarse.
enum TipoContenidoReportado { publicacion, comentario }

// Pantalla para reportar contenido del blog.
class ReportarContenidoView extends StatefulWidget {
  // Identificador de la publicacion.
  final int? idBlog;

  // Identificador del comentario.
  final int? idComentario;

  const ReportarContenidoView({super.key, this.idBlog, this.idComentario})
    : assert(
        (idBlog != null && idComentario == null) ||
            (idBlog == null && idComentario != null),
        'Debes proporcionar un solo identificador.',
      );

  @override
  State<ReportarContenidoView> createState() => _ReportarContenidoViewState();
}

class _ReportarContenidoViewState extends State<ReportarContenidoView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controlador de la descripcion del reporte.
  final TextEditingController _descripcionController = TextEditingController();

  // Motivos disponibles para reportar contenido.
  final Map<String, String> _motivos = {
    'informacion_incorrecta': 'Informacion medica incorrecta',
    'contenido_inapropiado': 'Contenido inapropiado',
    'publicidad_enganosa': 'Publicidad enganosa',
    'spam': 'Contenido repetitivo o spam',
    'derechos_autor': 'Posible infraccion de derechos de autor',
    'otro': 'Otro motivo',
  };

  // Motivo seleccionado.
  String? _motivoSeleccionado;

  // Variables de estado.
  bool _enviando = false;
  bool _confirmando = false;
  String? _error;

  // Identificar el tipo de contenido reportado.
  TipoContenidoReportado get _tipoContenido {
    if (widget.idComentario != null) {
      return TipoContenidoReportado.comentario;
    }

    return TipoContenidoReportado.publicacion;
  }

  // Obtener el nombre del tipo de contenido.
  String get _nombreTipo {
    if (_tipoContenido == TipoContenidoReportado.comentario) {
      return 'Comentario';
    }

    return 'Publicacion';
  }

  // Obtener el identificador del contenido.
  int? get _identificador {
    if (_tipoContenido == TipoContenidoReportado.comentario) {
      return widget.idComentario;
    }

    return widget.idBlog;
  }

  // Obtener el texto del motivo seleccionado.
  String _obtenerNombreMotivo() {
    if (_motivoSeleccionado == null) {
      return '';
    }

    return _motivos[_motivoSeleccionado] ?? '';
  }

  // Preparar el motivo completo para FastAPI.
  String _prepararMotivo() {
    final String motivo = _obtenerNombreMotivo();
    final String descripcion = _descripcionController.text.trim();

    // El backend solo acepta el campo motivo.
    // Se incluye la categoria y la explicacion del usuario.
    return '$motivo: $descripcion';
  }

  // Validar el motivo del reporte.
  String? _validarMotivo(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Selecciona un motivo.';
    }

    if (!_motivos.containsKey(valor)) {
      return 'Selecciona un motivo valido.';
    }

    return null;
  }

  // Validar la descripcion del reporte.
  String? _validarDescripcion(String? valor) {
    final String descripcion = valor?.trim() ?? '';

    if (descripcion.isEmpty) {
      return 'Describe el problema encontrado.';
    }

    if (descripcion.length < 10) {
      return 'Escribe al menos 10 caracteres.';
    }

    // Verificar el limite real del modelo ReporteRegistro.
    final String motivo = _obtenerNombreMotivo();

    if (motivo.isNotEmpty) {
      final String motivoCompleto = '$motivo: $descripcion';

      if (motivoCompleto.length > 255) {
        return 'El motivo y la descripcion no pueden '
            'superar 255 caracteres en total.';
      }
    }

    return null;
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Confirmar el envio del reporte.
  Future<void> _confirmarReporte() async {
    // Evitar envios simultaneos.
    if (!mounted || _enviando || _confirmando) {
      return;
    }

    // Validar los campos del formulario.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Verificar el identificador del contenido.
    final int? identificador = _identificador;

    if (identificador == null || identificador <= 0) {
      _mostrarMensaje('No se encontro un identificador valido.');

      return;
    }

    // Bloquear la apertura simultanea de varios dialogos.
    setState(() {
      _confirmando = true;
      _error = null;
    });

    // Solicitar confirmacion al usuario.
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar reporte'),
          content: Text(
            '¿Deseas enviar este reporte sobre '
            '${_nombreTipo.toLowerCase()}?\n\n'
            'El contenido sera evaluado mediante '
            'el sistema de moderacion.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _confirmando = false;
    });

    if (confirmar != true) {
      return;
    }

    // Validar nuevamente antes de enviar.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Enviar el reporte a FastAPI.
    await _enviarReporte();
  }

  // Registrar el reporte mediante FastAPI.
  Future<void> _enviarReporte() async {
    if (!mounted || _enviando) {
      return;
    }

    final int? identificador = _identificador;
    final TipoContenidoReportado tipoContenido = _tipoContenido;

    if (identificador == null || identificador <= 0) {
      _mostrarMensaje('No se encontro un identificador valido.');

      return;
    }

    // Construir el motivo aceptado por FastAPI.
    final String motivo = _prepararMotivo();

    if (motivo.length < 5 || motivo.length > 255) {
      setState(() {
        _error =
            'El motivo debe contener entre '
            '5 y 255 caracteres.';
      });

      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      // Obtener el token del usuario.
      final String? token = await _authService.obtenerToken();

      if (!mounted ||
          _identificador != identificador ||
          _tipoContenido != tipoContenido) {
        return;
      }

      // Verificar que exista una sesion.
      if (token == null || token.trim().isEmpty) {
        setState(() {
          _error = 'Debes iniciar sesion para enviar un reporte.';
        });

        return;
      }

      // Preparar los datos conforme a ReporteRegistro.
      final Map<String, dynamic> datos = {'motivo': motivo};

      // Solo se envia uno de los identificadores.
      if (tipoContenido == TipoContenidoReportado.publicacion) {
        datos['blog_id'] = identificador;
      } else {
        datos['com_id'] = identificador;
      }

      // Enviar el reporte al endpoint real de moderacion.
      final dynamic respuesta = await _apiService.post(
        '/moderacion/reportar',
        datos: datos,
        token: token,
      );

      if (!mounted ||
          _identificador != identificador ||
          _tipoContenido != tipoContenido) {
        return;
      }

      // Mostrar confirmacion despues de la respuesta exitosa.
      String mensaje = 'El reporte se envio correctamente.';

      if (respuesta is Map && respuesta['mensaje'] != null) {
        mensaje = respuesta['mensaje'].toString();
      }

      _mostrarMensaje(mensaje);

      // Regresar a la pantalla anterior indicando el resultado.
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (error.codigoEstado == 401) {
          _error =
              'Tu sesion no es valida o ha expirado. '
              'Inicia sesion nuevamente.';
        } else if (error.codigoEstado == 404) {
          _error =
              'El contenido que deseas reportar '
              'no existe o no esta disponible.';
        } else if (error.codigoEstado == 409) {
          _error =
              'No fue posible registrar el reporte. '
              'Verifica la informacion e intenta nuevamente.';
        } else if (error.codigoEstado == 422) {
          _error =
              'Los datos del reporte no cumplen '
              'con las validaciones del servidor.';
        } else {
          _error = error.mensaje;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'No fue posible enviar el reporte. '
            'Intenta nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  // Construir el apartado informativo.
  Widget _construirInformacion() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
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
              'Los reportes permiten identificar '
              'contenido que requiere revision. '
              'Enviar un reporte no elimina '
              'automaticamente la publicacion '
              'o el comentario.',
              style: TextStyle(fontSize: 13, color: colores.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // Construir el campo del tipo de contenido.
  Widget _construirTipoContenido() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Tipo de contenido',
        prefixIcon: Icon(Icons.article_outlined),
        border: OutlineInputBorder(),
      ),
      child: Text(
        '$_nombreTipo #${_identificador ?? "-"}',
        style: TextStyle(fontWeight: FontWeight.w600, color: colores.onSurface),
      ),
    );
  }

  // Construir el formulario de reporte.
  Widget _construirFormulario() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identificar el contenido reportado.
          _construirTipoContenido(),

          const SizedBox(height: 20),

          // Seleccionar el motivo del reporte.
          DropdownButtonFormField<String>(
            value: _motivoSeleccionado,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Motivo del reporte',
              prefixIcon: Icon(Icons.flag_outlined),
              border: OutlineInputBorder(),
            ),
            items: _motivos.entries.map((motivo) {
              return DropdownMenuItem<String>(
                value: motivo.key,
                child: Text(motivo.value, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: _enviando
                ? null
                : (valor) {
                    setState(() {
                      _motivoSeleccionado = valor;
                    });

                    // Actualizar la validacion de la descripcion.
                    _formKey.currentState?.validate();
                  },
            validator: _validarMotivo,
          ),

          const SizedBox(height: 20),

          // Describir el problema encontrado.
          TextFormField(
            controller: _descripcionController,
            enabled: !_enviando,
            minLines: 4,
            maxLines: 7,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripcion del problema',
              hintText:
                  'Explica por que deseas '
                  'reportar este contenido...',
              alignLabelWithHint: true,
              helperText:
                  'El motivo y la descripcion deben '
                  'sumar un maximo de 255 caracteres.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            validator: _validarDescripcion,
          ),

          const SizedBox(height: 12),

          // Mostrar errores del envio.
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colores.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colores.onErrorContainer),
              ),
            ),

            const SizedBox(height: 14),
          ],

          // Boton para enviar el reporte.
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _enviando || _confirmando ? null : _confirmarReporte,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_enviando ? 'Enviando reporte...' : 'Enviar reporte'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Liberar los recursos utilizados.
    _descripcionController.dispose();
    _apiService.cerrar();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de reportes.
      appBar: AppBar(
        title: const Text('Reportar contenido'),
        centerTitle: true,
      ),

      // Contenido principal de la pantalla.
      body: SafeArea(
        child: SingleChildScrollView(
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
                      Icons.shield_outlined,
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
                          'Ayudanos a mejorar',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: colores.primary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Reporta contenido que pueda '
                          'incumplir nuestras normas.',
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

              // Informacion sobre la moderacion.
              _construirInformacion(),

              const SizedBox(height: 24),

              // Titulo del formulario.
              Text(
                'Informacion del reporte',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colores.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              // Formulario para enviar el reporte.
              _construirFormulario(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

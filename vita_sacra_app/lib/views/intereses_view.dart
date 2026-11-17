import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'recomendaciones_view.dart';

class InteresesView extends StatefulWidget {
  const InteresesView({super.key});

  @override
  State<InteresesView> createState() => _InteresesViewState();
}

class _InteresesViewState extends State<InteresesView> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _categorias = [];
  Set<int> _interesesSeleccionados = {};
  final Set<int> _categoriasActualizando = {};

  String? _token;
  String? _error;
  bool _cargando = true;
  bool _requiereSesion = false;
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  int? _convertirId(dynamic valor) {
    if (valor is int) {
      return valor > 0 ? valor : null;
    }

    if (valor is num) {
      if (!valor.isFinite || valor != valor.truncateToDouble()) {
        return null;
      }

      final int numero = valor.toInt();
      return numero > 0 ? numero : null;
    }

    final int? numero = int.tryParse(valor?.toString().trim() ?? '');
    return numero != null && numero > 0 ? numero : null;
  }

  Future<void> _cargarDatos() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _cargando = true;
      _requiereSesion = false;
      _error = null;
      _token = null;
    });

    try {
      final String? token = await _authService.obtenerToken();

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      if (token == null || token.trim().isEmpty) {
        setState(() {
          _categorias = [];
          _interesesSeleccionados = {};
          _requiereSesion = true;
          _cargando = false;
        });
        return;
      }

      final List<dynamic> respuestas = await Future.wait<dynamic>([
        _apiService.get('/personalizacion/categorias'),
        _apiService.get('/personalizacion/mis-intereses', token: token),
      ]);

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      final dynamic respuestaCategorias = respuestas[0];
      final dynamic respuestaIntereses = respuestas[1];

      if (respuestaCategorias is! List || respuestaIntereses is! List) {
        throw const ApiException(
          'El servidor devolvió un formato de intereses no válido.',
        );
      }

      final List<Map<String, dynamic>> categorias = [];
      for (final dynamic registro in respuestaCategorias) {
        if (registro is! Map) {
          throw const ApiException('Se recibió una categoría no válida.');
        }

        final Map<String, dynamic> categoria = Map<String, dynamic>.from(
          registro,
        );

        if (_convertirId(categoria['id_categoria']) == null) {
          throw const ApiException(
            'Una categoría no tiene un identificador válido.',
          );
        }

        categorias.add(categoria);
      }

      final Set<int> intereses = {};
      for (final dynamic registro in respuestaIntereses) {
        if (registro is! Map) {
          throw const ApiException('Se recibió un interés no válido.');
        }

        final int? idCategoria = _convertirId(registro['categoria_id']);
        if (idCategoria == null) {
          throw const ApiException(
            'Un interés no tiene un identificador válido.',
          );
        }

        intereses.add(idCategoria);
      }

      setState(() {
        _token = token;
        _categorias = categorias;
        _interesesSeleccionados = intereses;
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _requiereSesion = error.codigoEstado == 401;
        _error = error.codigoEstado == 401 ? null : error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _error = 'No fue posible cargar tus intereses.';
        _cargando = false;
      });
    }
  }

  Future<void> _cambiarInteres(int categoriaId, bool seleccionado) async {
    if (_categoriasActualizando.contains(categoriaId)) {
      return;
    }

    final String? token = _token;
    if (token == null || token.trim().isEmpty) {
      _mostrarMensaje('Inicia sesión para modificar tus intereses.');
      return;
    }

    final bool yaSeleccionado = _interesesSeleccionados.contains(categoriaId);

    if (yaSeleccionado == seleccionado) {
      return;
    }

    setState(() {
      _categoriasActualizando.add(categoriaId);
    });

    try {
      if (seleccionado) {
        await _apiService.post(
          '/personalizacion/intereses',
          datos: {'categoria_id': categoriaId},
          token: token,
        );
      } else {
        await _apiService.delete(
          '/personalizacion/intereses/$categoriaId',
          token: token,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        if (seleccionado) {
          _interesesSeleccionados.add(categoriaId);
        } else {
          _interesesSeleccionados.remove(categoriaId);
        }
      });

      _mostrarMensaje(
        seleccionado
            ? 'Interés agregado. Actualizamos tus recomendaciones.'
            : 'Interés eliminado. Actualizamos tus recomendaciones.',
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.codigoEstado == 401) {
        setState(() {
          _requiereSesion = true;
          _token = null;
        });
      }

      _mostrarMensaje(error.mensaje);
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('No fue posible guardar el cambio.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _categoriasActualizando.remove(categoriaId);
        });
      }
    }
  }

  void _abrirRecomendaciones() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const RecomendacionesView(),
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

  Widget _construirContenido() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Personaliza tus recomendaciones',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: colores.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Selecciona los temas que te interesan. Puedes cambiarlos cuando '
          'quieras; Vita Sacra los usará para recomendarte publicaciones.',
          style: TextStyle(color: colores.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _cargarDatos,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ] else if (_categorias.isEmpty) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Todavía no hay categorías disponibles.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ] else ...[
          Text(
            'Categorías disponibles',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colores.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ..._categorias.map((Map<String, dynamic> categoria) {
            final int idCategoria = _convertirId(categoria['id_categoria'])!;
            final String nombre = categoria['nombre']?.toString().trim() ?? '';
            final String descripcion =
                categoria['descripcion']?.toString().trim() ?? '';
            final bool seleccionado = _interesesSeleccionados.contains(
              idCategoria,
            );
            final bool actualizando = _categoriasActualizando.contains(
              idCategoria,
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                value: seleccionado,
                onChanged: actualizando
                    ? null
                    : (bool? valor) {
                        _cambiarInteres(idCategoria, valor ?? false);
                      },
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  nombre.isEmpty ? 'Categoría' : nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: descripcion.isEmpty ? null : Text(descripcion),
                secondary: actualizando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _abrirRecomendaciones,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Ver mis recomendaciones'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _numeroSolicitud++;
    _apiService.cerrar();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis intereses'),
        actions: [
          IconButton(
            tooltip: 'Actualizar intereses',
            onPressed: _cargando ? null : _cargarDatos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _requiereSesion
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 44),
                      const SizedBox(height: 12),
                      const Text(
                        'Inicia sesión para administrar tus intereses.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _cargarDatos,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : _construirContenido(),
      ),
    );
  }
}

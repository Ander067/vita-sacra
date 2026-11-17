import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class SolicitudRolView extends StatefulWidget {
  const SolicitudRolView({super.key});

  @override
  State<SolicitudRolView> createState() => _SolicitudRolViewState();
}

class _SolicitudRolViewState extends State<SolicitudRolView> {
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _motivoController = TextEditingController();

  List<Map<String, dynamic>> _rolesDisponibles = [];
  List<Map<String, dynamic>> _solicitudes = [];
  int? _rolSeleccionado;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  int? _leerId(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final List<Map<String, dynamic>> catalogo = await _authService
          .obtenerCatalogoRoles();
      final Map<String, dynamic> misRoles = await _authService
          .obtenerMisRoles();
      final List<Map<String, dynamic>> solicitudes = await _authService
          .obtenerMisSolicitudesRol();

      final Set<int> rolesYaAsignados = {};

      final dynamic principal = misRoles['rol_principal'];
      if (principal is Map) {
        final int? idPrincipal = _leerId(principal['id_rol']);
        if (idPrincipal != null) rolesYaAsignados.add(idPrincipal);
      }

      final dynamic adicionales = misRoles['roles_adicionales'];
      if (adicionales is List) {
        for (final dynamic elemento in adicionales) {
          if (elemento is Map) {
            final int? id = _leerId(elemento['id_rol']);
            if (id != null) rolesYaAsignados.add(id);
          }
        }
      }

      final Set<int> rolesPendientes = solicitudes
          .where(
            (solicitud) =>
                (solicitud['estatus']?.toString().toLowerCase() ?? '') ==
                'pendiente',
          )
          .map((solicitud) => _leerId(solicitud['rol_id']))
          .whereType<int>()
          .toSet();

      final List<Map<String, dynamic>> disponibles = catalogo.where((rol) {
        final String nombre = (rol['nombre'] ?? '').toString().toLowerCase();
        final int? id = _leerId(rol['id_rol']);

        return id != null &&
            (nombre == 'autor' || nombre == 'anunciante') &&
            !rolesYaAsignados.contains(id) &&
            !rolesPendientes.contains(id);
      }).toList();

      if (!mounted) return;
      setState(() {
        _rolesDisponibles = disponibles;
        _solicitudes = solicitudes;
        _rolSeleccionado = disponibles.isEmpty
            ? null
            : _leerId(disponibles.first['id_rol']);
        _cargando = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.mensaje;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No fue posible cargar las solicitudes de rol.';
        _cargando = false;
      });
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_enviando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final int? rolId = _rolSeleccionado;
    if (rolId == null) {
      _mostrarMensaje('No hay un rol disponible para solicitar.');
      return;
    }

    setState(() {
      _enviando = true;
    });

    try {
      final Map<String, dynamic> respuesta = await _authService
          .solicitarRolAdicional(rolId: rolId, motivo: _motivoController.text);

      if (!mounted) return;

      _motivoController.clear();
      _mostrarMensaje(
        respuesta['mensaje']?.toString() ??
            'Solicitud de rol enviada para revisión.',
      );
      await _cargarDatos();
    } on ApiException catch (error) {
      if (mounted) _mostrarMensaje(error.mensaje);
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('No fue posible enviar la solicitud.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) return texto;
    return '${texto[0].toUpperCase()}${texto.substring(1)}';
  }

  Widget _construirSolicitud() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    if (_rolesDisponibles.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No tienes roles adicionales disponibles para solicitar. '
            'Solo se pueden solicitar Autor o Anunciante, y no puedes '
            'solicitar un rol que ya tienes o cuya solicitud está pendiente.',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _rolSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Rol adicional',
                  border: OutlineInputBorder(),
                ),
                items: _rolesDisponibles.map((rol) {
                  final int id = _leerId(rol['id_rol'])!;
                  final String nombre = _capitalizar(rol['nombre'].toString());
                  return DropdownMenuItem<int>(value: id, child: Text(nombre));
                }).toList(),
                onChanged: _enviando
                    ? null
                    : (int? valor) {
                        setState(() {
                          _rolSeleccionado = valor;
                        });
                      },
                validator: (valor) =>
                    valor == null ? 'Selecciona un rol.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _motivoController,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la solicitud',
                  helperText: 'Escribe al menos 10 caracteres.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  if ((valor?.trim().length ?? 0) < 10) {
                    return 'El motivo debe tener al menos 10 caracteres.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'La solicitud requiere aprobación administrativa. '
                'Se agrega como rol adicional; no reemplaza tu rol principal.',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _enviando ? null : _enviarSolicitud,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirHistorial() {
    if (_solicitudes.isEmpty) {
      return const Text('Aún no tienes solicitudes de rol.');
    }

    return Column(
      children: _solicitudes.map((solicitud) {
        final String rol = _capitalizar(solicitud['rol']?.toString() ?? 'Rol');
        final String estado = _capitalizar(
          solicitud['estatus']?.toString() ?? 'desconocido',
        );
        final String motivo = solicitud['motivo']?.toString() ?? '';
        final String? observacion = solicitud['observacion']?.toString();

        return Card(
          child: ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: Text('$rol — $estado'),
            subtitle: Text(
              [
                if (motivo.isNotEmpty) 'Motivo: $motivo',
                if (observacion != null && observacion.trim().isNotEmpty)
                  'Respuesta: $observacion',
                if (solicitud['fecha'] != null) 'Fecha: ${solicitud['fecha']}',
              ].join('\n'),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _motivoController.dispose();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitud de rol adicional')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Solicitar un rol adicional',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: colores.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes solicitar Autor o Anunciante. '
                    'La administración revisará tu solicitud.',
                  ),
                  const SizedBox(height: 16),
                  _construirSolicitud(),
                  const SizedBox(height: 24),
                  Text(
                    'Mis solicitudes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colores.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _construirHistorial(),
                ],
              ),
      ),
    );
  }
}

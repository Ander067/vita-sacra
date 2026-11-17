import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class InformacionCuentaView extends StatefulWidget {
  const InformacionCuentaView({super.key});

  @override
  State<InformacionCuentaView> createState() => _InformacionCuentaViewState();
}

class _InformacionCuentaViewState extends State<InformacionCuentaView> {
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();

  Usuario? _usuario;
  bool _cargando = true;
  bool _editando = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final Usuario usuario = await _authService.obtenerPerfil();
      if (!mounted) return;

      _nombreController.text = usuario.nomUsr;
      _direccionController.text = usuario.dirUsr ?? '';

      setState(() {
        _usuario = usuario;
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
        _error = 'No fue posible cargar la información de la cuenta.';
        _cargando = false;
      });
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false) || _guardando) {
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final Usuario actualizado = await _authService.actualizarPerfil(
        nombre: _nombreController.text,
        direccion: _direccionController.text,
      );

      if (!mounted) return;

      setState(() {
        _usuario = actualizado;
        _editando = false;
      });

      _mostrarMensaje('Información de la cuenta actualizada.');
    } on ApiException catch (error) {
      if (mounted) _mostrarMensaje(error.mensaje);
    } catch (error) {
      if (mounted) {
        _mostrarMensaje('No fue posible actualizar la cuenta.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  void _cancelarEdicion() {
    final Usuario? usuario = _usuario;
    if (usuario == null) return;

    _nombreController.text = usuario.nomUsr;
    _direccionController.text = usuario.dirUsr ?? '';

    setState(() {
      _editando = false;
    });
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Widget _crearCampoSoloLectura({
    required String etiqueta,
    required String valor,
    required IconData icono,
  }) {
    return ListTile(
      leading: Icon(icono),
      title: Text(etiqueta),
      subtitle: Text(valor),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _direccionController.dispose();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final Usuario? usuario = _usuario;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Información de la cuenta'),
        actions: [
          if (usuario != null && !_editando)
            IconButton(
              tooltip: 'Editar nombre y dirección',
              onPressed: () {
                setState(() {
                  _editando = true;
                });
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
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
                        onPressed: _cargarPerfil,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : usuario == null
            ? const Center(child: Text('Información de cuenta no disponible.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _editando
                          ? Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _nombreController,
                                    maxLength: 100,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (valor) {
                                      final String nombre = valor?.trim() ?? '';
                                      if (nombre.length < 3) {
                                        return 'Escribe al menos 3 caracteres.';
                                      }
                                      if (nombre.length > 100) {
                                        return 'Máximo 100 caracteres.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _direccionController,
                                    maxLength: 255,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Domicilio (opcional)',
                                      helperText: 'No es necesario para usar la aplicación.',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (valor) {
                                      if ((valor?.trim().length ?? 0) > 255) {
                                        return 'Máximo 255 caracteres.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  _crearCampoSoloLectura(
                                    etiqueta: 'Correo electrónico',
                                    valor: usuario.mail,
                                    icono: Icons.email_outlined,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _guardando
                                              ? null
                                              : _cancelarEdicion,
                                          child: const Text('Cancelar'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _guardando
                                              ? null
                                              : _guardar,
                                          icon: _guardando
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.save_outlined),
                                          label: const Text('Guardar'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                _crearCampoSoloLectura(
                                  etiqueta: 'Nombre',
                                  valor: usuario.nomUsr,
                                  icono: Icons.person_outline,
                                ),
                                const Divider(),
                                _crearCampoSoloLectura(
                                  etiqueta: 'Correo electrónico',
                                  valor: usuario.mail,
                                  icono: Icons.email_outlined,
                                ),
                                const Divider(),
                                _crearCampoSoloLectura(
                                  etiqueta: 'Domicilio',
                                  valor:
                                      (usuario.dirUsr == null ||
                                          usuario.dirUsr!.trim().isEmpty)
                                      ? 'No registrado'
                                      : usuario.dirUsr!,
                                  icono: Icons.location_on_outlined,
                                ),
                                const Divider(),
                                _crearCampoSoloLectura(
                                  etiqueta: 'Rol principal',
                                  valor: usuario.nombreRol,
                                  icono: Icons.badge_outlined,
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (!_editando) ...[
                    const SizedBox(height: 12),
                    Text(
                      'El correo se muestra como solo lectura. '
                      'El domicilio es opcional.',
                      style: TextStyle(color: colores.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

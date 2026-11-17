import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_view.dart';

class CambiarContrasenaView extends StatefulWidget {
  const CambiarContrasenaView({super.key});

  @override
  State<CambiarContrasenaView> createState() => _CambiarContrasenaViewState();
}

class _CambiarContrasenaViewState extends State<CambiarContrasenaView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _actualController = TextEditingController();
  final TextEditingController _nuevaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _cargando = false;
  bool _mostrarActual = false;
  bool _mostrarNueva = false;

  String? _validarActual(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa tu contraseña actual.';
    }

    return null;
  }

  String? _validarNueva(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa una contraseña nueva.';
    }

    if (valor.length < 8 || valor.length > 128) {
      return 'Utiliza entre 8 y 128 caracteres.';
    }

    if (valor == _actualController.text) {
      return 'Debe ser diferente a tu contraseña actual.';
    }

    return null;
  }

  String? _validarConfirmacion(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Confirma tu contraseña nueva.';
    }

    if (valor != _nuevaController.text) {
      return 'Las contraseñas no coinciden.';
    }

    return null;
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _cambiarContrasena() async {
    if (_cargando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      final String mensaje = await _authService.cambiarContrasena(
        contrasenaActual: _actualController.text,
        contrasenaNueva: _nuevaController.text,
      );

      if (!mounted) {
        return;
      }

      _actualController.clear();
      _nuevaController.clear();
      _confirmarController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );

      Navigator.pushAndRemoveUntil<void>(
        context,
        MaterialPageRoute<void>(builder: (context) => const LoginView()),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (mounted) {
        _mostrarMensaje(error.mensaje);
      }
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('Ocurrió un error al cambiar la contraseña.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Cambiar contraseña'),
        centerTitle: true,
        backgroundColor: colores.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.lock_reset_outlined,
                      size: 72,
                      color: colores.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Actualiza tu contraseña',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Por seguridad, confirma tu contraseña actual. '
                      'Después tendrás que iniciar sesión nuevamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 26),
                    TextFormField(
                      controller: _actualController,
                      enabled: !_cargando,
                      obscureText: !_mostrarActual,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Contraseña actual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  setState(() {
                                    _mostrarActual = !_mostrarActual;
                                  });
                                },
                          icon: Icon(
                            _mostrarActual
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: _validarActual,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nuevaController,
                      enabled: !_cargando,
                      obscureText: !_mostrarNueva,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Contraseña nueva',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  setState(() {
                                    _mostrarNueva = !_mostrarNueva;
                                  });
                                },
                          icon: Icon(
                            _mostrarNueva
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: _validarNueva,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _confirmarController,
                      enabled: !_cargando,
                      obscureText: !_mostrarNueva,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) {
                        if (!_cargando) {
                          _cambiarContrasena();
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Confirmar contraseña nueva',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarConfirmacion,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _cambiarContrasena,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colores.primary,
                          foregroundColor: colores.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Guardar contraseña',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class RecuperacionContrasenaView extends StatefulWidget {
  final String correoInicial;

  const RecuperacionContrasenaView({super.key, required this.correoInicial});

  @override
  State<RecuperacionContrasenaView> createState() =>
      _RecuperacionContrasenaViewState();
}

class _RecuperacionContrasenaViewState
    extends State<RecuperacionContrasenaView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _codigoSolicitado = false;
  bool _cargando = false;
  bool _mostrarContrasenas = false;

  @override
  void initState() {
    super.initState();
    _correoController.text = widget.correoInicial.trim();
  }

  String? _validarCorreo(String? valor) {
    final String correo = valor?.trim() ?? '';

    if (correo.isEmpty) {
      return 'Ingresa tu correo electrónico.';
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo)) {
      return 'Ingresa un correo electrónico válido.';
    }

    return null;
  }

  String? _validarCodigo(String? valor) {
    final String codigo = valor?.trim() ?? '';

    if (codigo.isEmpty) {
      return 'Ingresa el código que recibiste por correo.';
    }

    if (codigo.length < 30 || codigo.length > 256) {
      return 'El código no parece válido. Revisa el correo recibido.';
    }

    return null;
  }

  String? _validarContrasena(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa una contraseña nueva.';
    }

    if (valor.length < 8 || valor.length > 128) {
      return 'Utiliza entre 8 y 128 caracteres.';
    }

    return null;
  }

  String? _validarConfirmacion(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Confirma la contraseña nueva.';
    }

    if (valor != _contrasenaController.text) {
      return 'Las contraseñas no coinciden.';
    }

    return null;
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _solicitarCodigo() async {
    if (_cargando) {
      return;
    }

    final String? errorCorreo = _validarCorreo(_correoController.text);

    if (errorCorreo != null) {
      _mostrarMensaje(errorCorreo);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      final String mensaje = await _authService.solicitarRecuperacion(
        correo: _correoController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _codigoSolicitado = true;
      });

      _mostrarMensaje(mensaje);
    } on ApiException catch (error) {
      if (mounted) {
        _mostrarMensaje(error.mensaje);
      }
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('Ocurrió un error al solicitar la recuperación.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Future<void> _restablecerContrasena() async {
    if (_cargando || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      final String mensaje = await _authService.restablecerContrasena(
        token: _codigoController.text,
        contrasenaNueva: _contrasenaController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop<String>(context, mensaje);
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
    _correoController.dispose();
    _codigoController.dispose();
    _contrasenaController.dispose();
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
        title: const Text('Recuperar contraseña'),
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
                      size: 78,
                      color: colores.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Recupera tu cuenta',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _codigoSolicitado
                          ? 'Si existe una cuenta activa con ese correo, '
                                'recibirás un código. Ingresa el código y '
                                'elige una contraseña nueva.'
                          : 'Ingresa el correo asociado a tu cuenta. '
                                'Te enviaremos instrucciones si existe una '
                                'cuenta activa con ese correo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 26),
                    TextFormField(
                      controller: _correoController,
                      enabled: !_cargando,
                      readOnly: _codigoSolicitado,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: _codigoSolicitado
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      onFieldSubmitted: (_) {
                        if (!_codigoSolicitado && !_cargando) {
                          _solicitarCodigo();
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        hintText: 'correo@ejemplo.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarCorreo,
                    ),
                    if (!_codigoSolicitado) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _cargando ? null : _solicitarCodigo,
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
                                  'Enviar código',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                    if (_codigoSolicitado) ...[
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _codigoController,
                        enabled: !_cargando,
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        maxLength: 256,
                        decoration: const InputDecoration(
                          labelText: 'Código de recuperación',
                          hintText: 'Pega aquí el código recibido',
                          prefixIcon: Icon(Icons.key_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _validarCodigo,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _contrasenaController,
                        enabled: !_cargando,
                        obscureText: !_mostrarContrasenas,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Contraseña nueva',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _cargando
                                ? null
                                : () {
                                    setState(() {
                                      _mostrarContrasenas =
                                          !_mostrarContrasenas;
                                    });
                                  },
                            icon: Icon(
                              _mostrarContrasenas
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: _validarContrasena,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _confirmarController,
                        enabled: !_cargando,
                        obscureText: !_mostrarContrasenas,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onFieldSubmitted: (_) {
                          if (!_cargando) {
                            _restablecerContrasena();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña nueva',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _validarConfirmacion,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _cargando ? null : _restablecerContrasena,
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
                                  'Cambiar contraseña',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _cargando ? null : _solicitarCodigo,
                        child: const Text('Solicitar otro código'),
                      ),
                    ],
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

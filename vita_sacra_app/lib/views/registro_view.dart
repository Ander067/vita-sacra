import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'verificar_correo_view.dart';

class RegistroView extends StatefulWidget {
  const RegistroView({super.key});

  @override
  State<RegistroView> createState() => _RegistroViewState();
}

class _RegistroViewState extends State<RegistroView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _mostrarContrasena = false;
  bool _mostrarConfirmacion = false;
  bool _cargando = false;
  bool _registroCompletado = false;

  final List<String> _mensajesRegistro = [
    'El conocimiento es el primer paso hacia el bienestar.',
    'Cuidar la salud tambien comienza con aprender.',
    'Cada persona tiene algo que aportar al conocimiento.',
    'La informacion confiable puede marcar la diferencia.',
    'Compartir experiencias tambien nos ayuda a aprender.',
    'La prevencion comienza con una buena informacion.',
    'Aprender sobre salud es invertir en nuestro bienestar.',
    'Una comunidad informada puede construir un futuro mejor.',
    'El conocimiento crece cuando se comparte.',
    'Bienvenido a un espacio para aprender y cuidar.',
  ];

  int _indiceMensaje = 0;
  Timer? _temporizadorMensajes;

  void _iniciarMensajes() {
    _temporizadorMensajes = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _indiceMensaje = (_indiceMensaje + 1) % _mensajesRegistro.length;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _iniciarMensajes();
  }

  String? _validarNombre(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu nombre completo.';
    }

    if (valor.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }

    return null;
  }

  String? _validarCorreo(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu correo electronico.';
    }

    final RegExp expresion = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!expresion.hasMatch(valor.trim())) {
      return 'Ingresa un correo electronico valido.';
    }

    return null;
  }

  String? _validarContrasena(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa una contrasena.';
    }

    if (valor.length < 8) {
      return 'Utiliza al menos 8 caracteres.';
    }

    return null;
  }

  String? _validarConfirmacion(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Confirma tu contrasena.';
    }

    if (valor != _contrasenaController.text) {
      return 'Las contrasenas no coinciden.';
    }

    return null;
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _abrirVerificacion() async {
    final String? mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (context) =>
            VerificarCorreoView(correo: _correoController.text.trim()),
      ),
    );

    if (!mounted) {
      return;
    }

    if (mensaje != null && mensaje.isNotEmpty) {
      Navigator.pop<String>(context, mensaje);
    }
  }

  Future<void> _registrarUsuario() async {
    if (_cargando || _registroCompletado) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      await _authService.registrar(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      if (!mounted) {
        return;
      }

      _temporizadorMensajes?.cancel();
      _contrasenaController.clear();
      _confirmarController.clear();

      setState(() {
        _registroCompletado = true;
      });

      await _abrirVerificacion();
    } on ApiException catch (error) {
      if (mounted) {
        _mostrarMensaje(error.mensaje);
      }
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('Ocurrio un error al registrar la cuenta.');
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
    _temporizadorMensajes?.cancel();

    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarController.dispose();
    _authService.cerrarServicio();

    super.dispose();
  }

  Widget _construirRegistroPendiente(ColorScheme colores) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 78,
                color: colores.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Cuenta creada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Debes verificar el correo antes de iniciar sesión.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colores.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                _correoController.text.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _cargando ? null : _abrirVerificacion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colores.primary,
                    foregroundColor: colores.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continuar verificación',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cargando
                    ? null
                    : () {
                        Navigator.pop<String>(
                          context,
                          'La cuenta quedó pendiente de verificación. '
                          'Revisa el correo antes de iniciar sesión.',
                        );
                      },
                child: const Text('Volver a iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Registro'),
        centerTitle: true,
        backgroundColor: colores.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: _registroCompletado
            ? _construirRegistroPendiente(colores)
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Crear una cuenta',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                              color: colores.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 45,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 700),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              child: Center(
                                key: ValueKey(_indiceMensaje),
                                child: Text(
                                  _mensajesRegistro[_indiceMensaje],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: colores.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Image.asset(
                              'assets/images/vita_sacra_logo.png',
                              width: 290,
                              height: 145,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '1.0.0 - Arca',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colores.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 25),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colores.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colores.outlineVariant,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _nombreController,
                                  enabled: !_cargando,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre completo',
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: _validarNombre,
                                ),
                                const SizedBox(height: 18),
                                TextFormField(
                                  controller: _correoController,
                                  enabled: !_cargando,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Correo electronico',
                                    hintText: 'correo@ejemplo.com',
                                    prefixIcon: Icon(Icons.email_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: _validarCorreo,
                                ),
                                const SizedBox(height: 18),
                                TextFormField(
                                  controller: _contrasenaController,
                                  enabled: !_cargando,
                                  obscureText: !_mostrarContrasena,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'Contrasena',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      onPressed: _cargando
                                          ? null
                                          : () {
                                              setState(() {
                                                _mostrarContrasena =
                                                    !_mostrarContrasena;
                                              });
                                            },
                                      icon: Icon(
                                        _mostrarContrasena
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
                                  obscureText: !_mostrarConfirmacion,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  onFieldSubmitted: (_) {
                                    if (!_cargando) {
                                      _registrarUsuario();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Confirmar contrasena',
                                    prefixIcon: const Icon(
                                      Icons.verified_user_outlined,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      onPressed: _cargando
                                          ? null
                                          : () {
                                              setState(() {
                                                _mostrarConfirmacion =
                                                    !_mostrarConfirmacion;
                                              });
                                            },
                                      icon: Icon(
                                        _mostrarConfirmacion
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                    ),
                                  ),
                                  validator: _validarConfirmacion,
                                ),
                                const SizedBox(height: 25),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _cargando
                                        ? null
                                        : _registrarUsuario,
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
                                            'Crear cuenta',
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
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  '¿Ya tienes una cuenta?',
                                  style: TextStyle(
                                    color: colores.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _cargando
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                      },
                                child: const Text('Inicia sesion'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
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

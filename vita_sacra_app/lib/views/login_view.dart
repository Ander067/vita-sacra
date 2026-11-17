import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/biometric_service.dart';
import 'home_view.dart';
import 'recuperacion_contrasena_view.dart';
import 'registro_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final FocusNode _contrasenaFocusNode = FocusNode();

  final AuthService _authService = AuthService();

  bool _mostrarContrasena = false;
  bool _cargando = false;
  bool _biometriaDisponible = false;
  bool _permitirContrasena = false;
  bool _mostrandoOpciones = false;

  String? _mensajeErrorGeneral;
  Timer? _timerErrorGeneral;

  final List<String> _frasesPool = [
    'Un espacio para cultivar la sabiduría y el orden.',
    'Nos alegra verte otra vez por aquí.',
    'Conecta de nuevo con tu comunidad y tus recursos.',
    'La constancia es el cimiento de todo gran proyecto.',
  ];

  late final String _fraseBienvenida =
      _frasesPool[Random().nextInt(_frasesPool.length)];

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final String? correoGuardado = await SecureStorageService.obtenerCorreo();
      final bool biometriaActiva =
          await SecureStorageService.esBiometriaHabilitada();
      final bool soportaBiometria = await BiometricService.puedeAutenticarse();
      final String? credencial =
          await SecureStorageService.obtenerCredencialBiometrica();

      if (!mounted) return;

      if (correoGuardado != null && correoGuardado.isNotEmpty) {
        _correoController.text = correoGuardado;
      }

      debugPrint('Correo guardado: $correoGuardado');
      debugPrint('Biometria activa: $biometriaActiva');
      debugPrint('Soporta biometria: $soportaBiometria');
      debugPrint('Credencial: ${credencial != null && credencial.isNotEmpty}');

      setState(() {
        _biometriaDisponible =
            biometriaActiva &&
            soportaBiometria &&
            credencial != null &&
            credencial.isNotEmpty;
      });

      debugPrint('Biometria activada: $biometriaActiva');
      debugPrint('Biometria disponible: $soportaBiometria');
      debugPrint('Credencial biometrica disponible: ${credencial != null}');
    } catch (error) {
      debugPrint('Error al cargar datos iniciales: $error');
    }
  }

  String? _validarCorreoTexto(String correo) {
    if (correo.trim().isEmpty) {
      return 'El campo de correo electrónico no puede estar vacío.';
    }

    if (!correo.contains('@')) {
      return 'El correo electrónico está incompleto (falta el símbolo "@").';
    }

    final List<String> partes = correo.trim().split('@');

    if (partes.length > 2 || partes[0].isEmpty) {
      return 'El nombre de usuario antes del "@" no es válido.';
    }

    if (partes[1].isEmpty || !partes[1].contains('.')) {
      return 'El dominio del correo está incompleto o le falta un punto (ej. .com).';
    }

    final RegExp expresion = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!expresion.hasMatch(correo.trim())) {
      return 'El correo electrónico contiene caracteres no permitidos.';
    }

    return null;
  }

  String? _validarContrasenaTexto(String contrasena) {
    if (contrasena.isEmpty) {
      return 'La contraseña no puede estar vacía.';
    }

    if (contrasena.length < 6) {
      return 'La contraseña es muy corta (mínimo 6 caracteres).';
    }

    return null;
  }

  void _mostrarErrorGeneral(String mensaje) {
    if (!mounted) return;

    _timerErrorGeneral?.cancel();

    setState(() {
      _mensajeErrorGeneral = mensaje;
    });

    _timerErrorGeneral = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _mensajeErrorGeneral = null;
        });
      }
    });
  }

  Future<void> _ofrecerActivarBiometria() async {
    final bool yaActivada = await SecureStorageService.esBiometriaHabilitada();
    final String? credencialGuardada =
        await SecureStorageService.obtenerCredencialBiometrica();

    if (!mounted) return;

    if (yaActivada &&
        credencialGuardada != null &&
        credencialGuardada.isNotEmpty) {
      return;
    }

    if (yaActivada &&
        (credencialGuardada == null || credencialGuardada.isEmpty)) {
      await SecureStorageService.guardarBiometriaHabilitada(false);
      if (!mounted) return;
    }

    final bool? activar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Activar acceso biometrico'),
          content: const Text(
            '¿Deseas utilizar tu huella digital para ingresar '
            'a Vita Sacra en tus proximos accesos?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Ahora no'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Activar'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (activar != true) {
      await SecureStorageService.guardarBiometriaHabilitada(false);
      return;
    }

    try {
      final bool soportaBiometria = await BiometricService.puedeAutenticarse();

      if (!mounted) return;

      if (!soportaBiometria) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se detecto una huella registrada. '
              'Configura la biometria en tu dispositivo.',
            ),
          ),
        );
        return;
      }

      final bool autenticado = await BiometricService.autenticarUsuario(
        mensaje: 'Confirma tu identidad para activar la biometria',
      );

      if (!mounted) return;

      if (!autenticado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo activar el acceso biometrico.'),
          ),
        );
        return;
      }

      final String idDispositivo =
          await SecureStorageService.obtenerIdDispositivo();

      debugPrint('Registrando dispositivo biometrico...');

      final String credencial = await _authService.registrarBiometria(
        idDispositivo: idDispositivo,
      );

      debugPrint('Credencial recibida correctamente.');

      await SecureStorageService.guardarCredencialBiometrica(credencial);

      final String? credencialVerificada =
          await SecureStorageService.obtenerCredencialBiometrica();

      if (credencialVerificada == null || credencialVerificada.isEmpty) {
        throw const ApiException(
          'No fue posible guardar la credencial biometrica.',
        );
      }

      await SecureStorageService.guardarBiometriaHabilitada(true);

      if (!mounted) return;

      setState(() {
        _biometriaDisponible = true;
      });

      debugPrint('Registro biometrico completado.');
      debugPrint('Biometria disponible: $_biometriaDisponible');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso biometrico habilitado correctamente.'),
        ),
      );
    } catch (error) {
      await SecureStorageService.guardarBiometriaHabilitada(false);

      debugPrint('Error al activar biometria: $error');

      if (!mounted) return;

      setState(() {
        _biometriaDisponible = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ocurrio un error al registrar la biometria: $error'),
        ),
      );
    }
  }

  Future<void> _iniciarSesion() async {
    if (_cargando) return;

    setState(() {
      _mensajeErrorGeneral = null;
    });

    final String correoText = _correoController.text;
    final String contrasenaText = _contrasenaController.text;

    final String? errorC = _validarCorreoTexto(correoText);

    if (errorC != null) {
      _mostrarErrorGeneral(errorC);
      return;
    }

    final String? errorP = _validarContrasenaTexto(contrasenaText);

    if (errorP != null) {
      _mostrarErrorGeneral(errorP);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      await _authService.iniciarSesion(
        correo: correoText.trim(),
        contrasena: contrasenaText,
      );

      final bool sesionValida = await _authService.sesionValida();

      if (!sesionValida) {
        throw const ApiException(
          'No fue posible verificar la sesión activa en el servidor.',
        );
      }

      await SecureStorageService.guardarCorreo(correoText.trim());

      if (!mounted) return;

      setState(() {
        _permitirContrasena = false;
      });

      await _ofrecerActivarBiometria();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeView()),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      final String msg = error.mensaje.toLowerCase();

      if (msg.contains('credenciales') ||
          msg.contains('incorrect') ||
          msg.contains('password') ||
          msg.contains('contraseña')) {
        _mostrarErrorGeneral('Correo o contraseña incorrectos.');
      } else {
        _mostrarErrorGeneral(error.mensaje);
      }
    } catch (error) {
      debugPrint('Error al iniciar sesion: $error');

      if (!mounted) return;

      _mostrarErrorGeneral(
        'El servidor no responde o no hay conexión con FastAPI.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Future<void> _intentarAccesoBiometrico() async {
    if (_cargando) return;

    final String? correoGuardado = await SecureStorageService.obtenerCorreo();

    if (!mounted) return;

    if (correoGuardado == null || correoGuardado.isEmpty) {
      _mostrarErrorGeneral('Inicia sesión con tu contraseña para continuar.');
      return;
    }

    setState(() {
      _cargando = true;
      _mensajeErrorGeneral = null;
    });

    try {
      final bool autenticado = await BiometricService.autenticarUsuario(
        mensaje: 'Usa tu huella para acceder a Vita Sacra',
      );

      if (!autenticado) {
        if (!mounted) return;

        setState(() {
          _permitirContrasena = true;
        });

        _mostrarErrorGeneral(
          'Autenticación cancelada. Puedes escribir tu contraseña.',
        );
        return;
      }

      final String? credencial =
          await SecureStorageService.obtenerCredencialBiometrica();
      final String idDispositivo =
          await SecureStorageService.obtenerIdDispositivo();

      if (credencial == null || credencial.isEmpty) {
        throw const ApiException(
          'No se encontro una credencial biometrica registrada.',
        );
      }

      await _authService.iniciarSesionBiometrica(
        correo: correoGuardado,
        idDispositivo: idDispositivo,
        credencial: credencial,
      );

      final bool sesionValida = await _authService.sesionValida();

      if (!sesionValida) {
        throw const ApiException(
          'El servidor no pudo validar la nueva sesion.',
        );
      }

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeView()),
        (route) => false,
      );
    } on ApiException catch (error) {
      debugPrint('Error de autenticacion biometrica: ${error.mensaje}');

      if (!mounted) return;

      setState(() {
        _permitirContrasena = true;
      });

      _mostrarErrorGeneral(
        'No fue posible validar la huella. '
        'Inicia sesión con tu contraseña.',
      );
    } catch (error) {
      debugPrint('Error en acceso biometrico: $error');

      if (!mounted) return;

      setState(() {
        _permitirContrasena = true;
      });

      _mostrarErrorGeneral(
        'No fue posible validar el acceso. '
        'Inicia sesión con tu contraseña.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  void _mostrarOpcionesAcceso() {
    if (_mostrandoOpciones || _cargando) return;

    _mostrandoOpciones = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Opciones de acceso',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Selecciona como deseas ingresar a Vita Sacra.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              if (_biometriaDisponible)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F0FE),
                    child: Icon(Icons.fingerprint, color: Colors.blue),
                  ),
                  title: const Text(
                    'Ingresar con huella digital',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Utilizar el sensor biometrico del dispositivo.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _intentarAccesoBiometrico();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF1F3F4),
                  child: Icon(Icons.keyboard, color: Colors.black87),
                ),
                title: const Text(
                  'Ingresar con contraseña',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Escribir tu contraseña habitual.'),
                onTap: () {
                  Navigator.pop(context);

                  setState(() {
                    _permitirContrasena = true;
                  });

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(_contrasenaFocusNode);
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    ).whenComplete(() {
      _mostrandoOpciones = false;
    });
  }

  Future<void> _abrirRecuperacion() async {
    if (_cargando) return;

    final String? mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (context) => RecuperacionContrasenaView(
          correoInicial: _correoController.text.trim(),
        ),
      ),
    );

    if (!mounted) return;

    if (mensaje != null && mensaje.isNotEmpty) {
      _contrasenaController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _abrirRegistro() async {
    if (_cargando) return;

    final String? mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const RegistroView()),
    );

    if (!mounted) return;

    if (mensaje != null && mensaje.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  void dispose() {
    _timerErrorGeneral?.cancel();
    _correoController.dispose();
    _contrasenaController.dispose();
    _contrasenaFocusNode.dispose();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 20.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      'Iniciar sesión',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fraseBienvenida,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Image.asset(
                        'assets/images/vita_sacra_logo.png',
                        width: 330,
                        height: 165,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'v1.0.0 — Arca',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.1,
                        color: colores.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_mensajeErrorGeneral != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colores.error, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: colores.error.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colores.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _mensajeErrorGeneral!,
                                style: TextStyle(
                                  color: colores.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _correoController,
                      enabled: !_cargando,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.email,
                        AutofillHints.username,
                      ],
                      onChanged: (_) {
                        if (_mensajeErrorGeneral != null) {
                          setState(() {
                            _mensajeErrorGeneral = null;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        hintText: 'correo@ejemplo.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _contrasenaController,
                      focusNode: _contrasenaFocusNode,
                      enabled: !_cargando,
                      readOnly: _biometriaDisponible && !_permitirContrasena,
                      obscureText: !_mostrarContrasena,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onTap: () {
                        if (_biometriaDisponible &&
                            !_permitirContrasena &&
                            !_cargando) {
                          FocusScope.of(context).unfocus();
                          _mostrarOpcionesAcceso();
                        }
                      },
                      onChanged: (_) {
                        if (_mensajeErrorGeneral != null) {
                          setState(() {
                            _mensajeErrorGeneral = null;
                          });
                        }
                      },
                      onFieldSubmitted: (_) {
                        if (!_cargando) {
                          _iniciarSesion();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  setState(() {
                                    _mostrarContrasena = !_mostrarContrasena;
                                  });
                                },
                          icon: Icon(
                            _mostrarContrasena
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _cargando ? null : _abrirRecuperacion,
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _iniciarSesion,
                        child: _cargando
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Entrar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿No tienes una cuenta?',
                          style: TextStyle(
                            color: colores.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        TextButton(
                          onPressed: _cargando ? null : _abrirRegistro,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Regístrate',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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

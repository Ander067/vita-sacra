import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class VerificarCorreoView extends StatefulWidget {
  final String correo;

  const VerificarCorreoView({super.key, required this.correo});

  @override
  State<VerificarCorreoView> createState() => _VerificarCorreoViewState();
}

class _VerificarCorreoViewState extends State<VerificarCorreoView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codigoController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _cargandoVerificacion = false;
  bool _cargandoReenvio = false;

  bool get _cargando => _cargandoVerificacion || _cargandoReenvio;

  String? _validarCodigo(String? valor) {
    final String codigo = valor?.trim() ?? '';

    if (codigo.isEmpty) {
      return 'Ingresa el código que recibiste por correo.';
    }

    if (codigo.length < 30) {
      return 'El código no parece completo. Revisa el correo recibido.';
    }

    return null;
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _verificarCorreo() async {
    if (_cargandoVerificacion ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _cargandoVerificacion = true;
    });

    try {
      final String mensaje = await _authService.verificarCorreo(
        token: _codigoController.text,
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
        _mostrarMensaje('Ocurrió un error al verificar el correo.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargandoVerificacion = false;
        });
      }
    }
  }

  Future<void> _reenviarCodigo() async {
    if (_cargando) {
      return;
    }

    setState(() {
      _cargandoReenvio = true;
    });

    try {
      final String mensaje = await _authService.reenviarVerificacion(
        correo: widget.correo,
      );

      if (mounted) {
        _mostrarMensaje(mensaje);
      }
    } on ApiException catch (error) {
      if (mounted) {
        _mostrarMensaje(error.mensaje);
      }
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('Ocurrió un error al solicitar otro código.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargandoReenvio = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _authService.cerrarServicio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,
      appBar: AppBar(
        title: const Text('Verificar correo'),
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
                      Icons.mark_email_read_outlined,
                      size: 78,
                      color: colores.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Confirma tu correo electrónico',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enviamos un código a:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colores.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.correo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Copia el código completo del correo y pégalo aquí. '
                      'Si no lo encuentras, revisa la carpeta de correo no deseado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: colores.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 26),
                    TextFormField(
                      controller: _codigoController,
                      enabled: !_cargando,
                      keyboardType: TextInputType.visiblePassword,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      maxLength: 256,
                      onFieldSubmitted: (_) {
                        if (!_cargando) {
                          _verificarCorreo();
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Código de verificación',
                        hintText: 'Pega aquí el código recibido',
                        prefixIcon: Icon(Icons.key_outlined),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: _validarCodigo,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _verificarCorreo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colores.primary,
                          foregroundColor: colores.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _cargandoVerificacion
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Verificar correo',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _cargando ? null : _reenviarCodigo,
                      child: _cargandoReenvio
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Solicitar otro código'),
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

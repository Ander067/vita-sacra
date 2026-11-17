import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class CompartirPublicacionButton extends StatefulWidget {
  final String titulo;
  final String descripcion;

  const CompartirPublicacionButton({
    super.key,
    required this.titulo,
    required this.descripcion,
  });

  @override
  State<CompartirPublicacionButton> createState() =>
      _CompartirPublicacionButtonState();
}

class _CompartirPublicacionButtonState
    extends State<CompartirPublicacionButton> {
  bool _compartiendo = false;

  Future<void> _compartir() async {
    if (_compartiendo) {
      return;
    }

    final String titulo = widget.titulo.trim().isEmpty
        ? 'Publicación de Vita Sacra'
        : widget.titulo.trim();

    final String descripcion = widget.descripcion.trim();

    final String contenido = descripcion.isEmpty
        ? '$titulo\n\nCompartido desde Vita Sacra.'
        : '$titulo\n\n$descripcion\n\nCompartido desde Vita Sacra.';

    setState(() {
      _compartiendo = true;
    });

    try {
      await SharePlus.instance.share(
        ShareParams(text: contenido, title: titulo, subject: titulo),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible abrir las opciones para compartir.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _compartiendo = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Compartir publicación',
      onPressed: _compartiendo ? null : _compartir,
      icon: _compartiendo
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.share_outlined),
    );
  }
}

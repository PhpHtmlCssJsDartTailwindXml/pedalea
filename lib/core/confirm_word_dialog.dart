import 'package:flutter/material.dart';

/// Diálogo de confirmación que exige escribir una palabra exacta (p.ej.
/// "SALIR" o "CANCELAR") antes de habilitar el botón — una fricción extra
/// para acciones que no se pueden deshacer fácilmente.
Future<bool> confirmWithWord(
  BuildContext context, {
  required String title,
  required String message,
  required String requiredWord,
  String confirmLabel = 'Confirmar',
  Color confirmColor = Colors.redAccent,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final matches = controller.text.trim().toUpperCase() == requiredWord.toUpperCase();
        return Dialog(
          backgroundColor: const Color(0xFF0E0E18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white60, fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 14),
                Text(
                  'Escribe "$requiredWord" para confirmar',
                  style: TextStyle(fontFamily: 'Poppins', color: confirmColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
                  decoration: InputDecoration(
                    hintText: requiredWord,
                    hintStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Volver', style: TextStyle(fontFamily: 'Poppins', color: Colors.white38)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: confirmColor.withOpacity(0.25),
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return result ?? false;
}

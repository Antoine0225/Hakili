import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Demande « Espèces ou Mobile Money ? » quand de l'argent est reçu ou versé (règlement d'une dette).
/// Renvoie le mode choisi, ou null si la personne annule.
Future<String?> choisirModePaiement(BuildContext context,
    {required String titre, required String message, String question = 'Comment cet argent a-t-il été payé ?'}) {
  final p = Palette.de(context);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      title: Text(titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message, style: TextStyle(fontSize: 13, color: p.txtPrinc)),
          const SizedBox(height: 10),
          Text(question, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'Espèces'),
                  style: FilledButton.styleFrom(backgroundColor: p.succes),
                  child: const Text('💵 Espèces', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'Mobile Money'),
                  style: FilledButton.styleFrom(backgroundColor: p.cuivre),
                  child: const Text('📱 Mobile Money', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))],
    ),
  );
}

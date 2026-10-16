import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Les fenêtres de message du logiciel (messagebox.showerror / showwarning / askyesno de Python),
/// habillées aux couleurs de Hakili.
class Dialogues {
  Dialogues._();

  static Future<void> _simple(BuildContext context, String titre, String message, IconData icone, Color couleur) {
    final p = Palette.de(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        title: Row(children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 10),
          Flexible(child: Text(titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc))),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(message, style: TextStyle(fontSize: 13, color: p.txtPrinc)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  static Future<void> erreur(BuildContext c, String titre, String message) =>
      _simple(c, titre, message, Icons.error_outline, Palette.de(c).danger);

  static Future<void> avertissement(BuildContext c, String titre, String message) =>
      _simple(c, titre, message, Icons.warning_amber_rounded, Palette.de(c).alerte);

  static Future<void> info(BuildContext c, String titre, String message) =>
      _simple(c, titre, message, Icons.info_outline, Palette.de(c).succes);

  /// Question Oui / Non : renvoie true si l'utilisateur confirme.
  static Future<bool> confirmer(BuildContext context, String titre, String message,
      {String oui = 'Oui', String non = 'Non'}) async {
    final p = Palette.de(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        title: Text(titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(message, style: TextStyle(fontSize: 13, color: p.txtPrinc)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(non)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(oui)),
        ],
      ),
    );
    return r ?? false;
  }
}

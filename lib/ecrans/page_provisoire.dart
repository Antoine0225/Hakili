import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Page d'attente d'un module en cours de reconstruction. Chaque module la remplacera
/// par son vrai écran, sans toucher au cadre principal.
class PageProvisoire extends StatelessWidget {
  final String titre;
  final String message;
  final List<(String, VoidCallback)> actions;
  const PageProvisoire({super.key, required this.titre, required this.message, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titre,
                  style: TextStyle(fontFamily: policeTitre, fontSize: 28, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              const SizedBox(height: 8),
              Text(message, style: TextStyle(fontSize: 13, color: p.txtDoux)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final (texte, action) in actions)
                      FilledButton(onPressed: action, child: Text(texte)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

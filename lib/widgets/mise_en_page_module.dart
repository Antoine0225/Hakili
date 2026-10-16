import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// La mise en page commune des modules : colonne de gauche de 420 px (formulaires, listes)
/// et grand panneau à droite (résultats, tableaux, factures).
class MiseEnPageModule extends StatelessWidget {
  final Widget gauche;
  final Widget droite;
  final bool droitePapier;

  /// Le panneau de droite EST lui-même la feuille « papier » (module Stocks, Crédits…).
  final bool papierDirect;
  const MiseEnPageModule(
      {super.key, required this.gauche, required this.droite, this.droitePapier = false, this.papierDirect = false});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 420, child: gauche),
      const SizedBox(width: 20),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: papierDirect ? const Color(0xFFFDFAF3) : p.panneau,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: papierDirect ? (sombre ? const Color(0xFF2A3A30) : const Color(0xFFE8E2D7)) : p.bordure),
          ),
          child: papierDirect
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Theme(data: construireTheme(Palette.papier, Brightness.light), child: droite),
                )
              : droitePapier
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(25, 20, 25, 20),
                  child: Theme(
                    data: construireTheme(Palette.papier, Brightness.light),
                    child: Builder(
                      builder: (context) => Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDFAF3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sombre ? const Color(0xFF2A3A30) : const Color(0xFFE8E2D7)),
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(20), child: droite),
                      ),
                    ),
                  ),
                )
              : droite,
        ),
      ),
      const SizedBox(width: 0),
    ]);
  }
}

import 'package:flutter/material.dart';

import '../services/mise_a_jour.dart';
import '../theme/palette.dart';
import 'dialogues.dart';

/// La pastille « Mise à jour » en haut à droite. Invisible tant qu'il n'y a rien de nouveau.
/// Le client peut cliquer « Télécharger » puis continuer son travail : le téléchargement se fait en arrière-plan.
class PastilleMiseAJour extends StatelessWidget {
  const PastilleMiseAJour({super.key});

  Future<void> _installer(BuildContext context, String version) async {
    final oui = await Dialogues.confirmer(
      context,
      'Installer la mise à jour',
      'Hakili va se fermer, installer la version $version, puis se rouvrir tout seul.\n'
      'Vos données ne sont pas touchées.\n\n'
      'Terminez ce que vous êtes en train de faire avant de continuer.',
      oui: 'Installer maintenant',
      non: 'Plus tard',
    );
    if (oui) await MiseAJour.installer();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return ValueListenableBuilder<EtatMaj>(
      valueListenable: MiseAJour.etat,
      builder: (context, e, _) {
        if (e.phase == PhaseMaj.aucune) return const SizedBox.shrink();
        late Color fond;
        late String texte, bouton;
        VoidCallback? action;
        switch (e.phase) {
          case PhaseMaj.disponible:
            fond = p.cuivre;
            texte = '🔔 Mise à jour ${e.version} disponible';
            bouton = 'Télécharger';
            action = MiseAJour.telecharger;
          case PhaseMaj.telechargement:
            fond = p.accent;
            texte = '⬇️ Téléchargement ${(e.progression * 100).round()} %';
            bouton = '';
          case PhaseMaj.prete:
            fond = p.succes;
            texte = '✅ Mise à jour ${e.version} prête';
            bouton = 'Installer maintenant';
            action = () => _installer(context, e.version);
          case PhaseMaj.erreur:
            fond = p.danger;
            texte = '⚠️ ${e.message}';
            bouton = 'Réessayer';
            action = () async {
              await MiseAJour.verifier();
              if (MiseAJour.etat.value.phase == PhaseMaj.disponible) await MiseAJour.telecharger();
            };
          case PhaseMaj.aucune:
            return const SizedBox.shrink();
        }
        return Tooltip(
          message: e.phase == PhaseMaj.telechargement
              ? 'Vous pouvez continuer à travailler : le téléchargement se fait en arrière-plan.'
              : 'Une nouvelle version de Hakili est proposée.',
          child: Container(
            height: 28,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(texte, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              if (e.phase == PhaseMaj.telechargement) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: LinearProgressIndicator(
                    value: e.progression > 0 ? e.progression : null,
                    minHeight: 5,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (bouton.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 22,
                  child: TextButton(
                    onPressed: action,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: fond,
                      padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    child: Text(bouton, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

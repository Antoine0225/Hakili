import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../session.dart';
import '../theme/palette.dart';

/// La pastille « Cloud » en haut à droite : voyant vert = synchronisé, gris = en attente.
/// Survol : explication complète. Clic (Patron seulement) : détails techniques.
class IndicateurCloud extends StatelessWidget {
  const IndicateurCloud({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return ListenableBuilder(
      listenable: Listenable.merge([ServiceCloud.etat, ServiceCloud.enAttente]),
      builder: (context, _) {
        final etat = ServiceCloud.etat.value;
        final attente = ServiceCloud.enAttente.value;
        String court, long;
        var synchro = false;
        if (etat == EtatCloud.ok && attente == 0) {
          court = 'Synchronisé';
          long = '☁️ Synchronisé avec le Cloud — ${ServiceCloud.derniereHeure}';
          synchro = true;
        } else if (etat == EtatCloud.ok) {
          court = 'En attente · $attente';
          long = '☁️ Envoi en cours — $attente ligne(s) à transmettre';
        } else if (etat == EtatCloud.horsLigne) {
          court = 'Hors-ligne';
          long = '📴 Travail hors-ligne — vos données restent enregistrées sur ce PC';
        } else if (etat == EtatCloud.local || etat == EtatCloud.erreur) {
          court = 'En attente';
          final suffixe = Session.estPatron ? '  •  ℹ️ Détails (clic, Patron)' : '';
          long = '☁️ Sauvegarde en ligne différée — vos données sont en sécurité sur ce PC$suffixe';
        } else {
          court = 'Connexion…';
          long = '☁️ Connexion au Cloud…';
        }

        return Tooltip(
          message: long,
          waitDuration: const Duration(milliseconds: 350),
          child: Material(
            color: p.panneau,
            shape: StadiumBorder(side: BorderSide(color: p.bordure)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: Session.estPatron ? () => ouvrirDetailsCloud(context) : null,
              child: SizedBox(
                height: 30,
                child: Padding(
                  padding: const EdgeInsets.only(left: 13, right: 15),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: synchro ? p.succes : p.voyantAttente, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(court, style: TextStyle(fontSize: 12, color: p.txtPrinc)),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fenêtre « Détails de la synchronisation Cloud » (réservée au Patron).
Future<void> ouvrirDetailsCloud(BuildContext context) async {
  if (!Session.estPatron) return;
  final p = Palette.de(context);
  final etat = ServiceCloud.etat.value;
  final attente = ServiceCloud.enAttente.value;
  final erreur = ServiceCloud.derniereErreur.trim();
  final lisible = switch (etat) {
    EtatCloud.ok => 'Envoi en cours',
    EtatCloud.horsLigne => "Pas d'accès Internet actuellement",
    EtatCloud.local || EtatCloud.erreur => 'Envoi non abouti',
    EtatCloud.demarrage => 'Connexion en cours',
  };
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text('☁️ SYNCHRONISATION CLOUD — DÉTAILS TECHNIQUES',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              ),
              const SizedBox(height: 10),
              Text(
                  "Vos données ne sont jamais en danger : elles sont toujours enregistrées d'abord sur ce PC. "
                  "Ce qui suit concerne uniquement l'envoi vers le Cloud (sauvegarde et partage entre vos PC).",
                  style: TextStyle(fontSize: 11, color: p.txtDoux)),
              const SizedBox(height: 12),
              Text('État actuel : $lisible',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
              const SizedBox(height: 2),
              Text("Lignes en attente d'envoi : $attente", style: TextStyle(fontSize: 11, color: p.txtDoux)),
              if (erreur.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 90),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: p.carte, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.bordure)),
                  child: SingleChildScrollView(
                    child: SelectableText(erreur,
                        style: TextStyle(fontFamily: 'Consolas', fontSize: 10, color: p.txtPrinc)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    'Ce message complet est aussi enregistré dans le fichier donnies_antoine_erreurs_cloud.log '
                    '— à transmettre au support si besoin.',
                    style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: p.txtGris)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                      backgroundColor: p.panneau2, foregroundColor: p.txtPrinc, minimumSize: const Size(0, 32)),
                  child: const Text('Fermer', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

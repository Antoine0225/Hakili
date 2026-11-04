import 'package:flutter/material.dart';

import '../cloud/file_attente.dart';
import '../cloud/service_cloud.dart';
import '../data/journal_repo.dart';
import '../session.dart';
import '../theme/palette.dart';
import 'dialogues.dart';
import 'toast.dart';

/// Fenêtre « Opérations bloquées » (réservée au Patron).
/// Une opération est bloquée quand le serveur l'a refusée 5 fois : elle n'est plus renvoyée toute seule.
/// Ici le Patron voit la raison du refus, puis choisit : réessayer (une dernière tentative) ou abandonner.
Future<void> ouvrirOperationsBloquees(BuildContext context, {VoidCallback? onDetails}) async {
  if (!Session.estPatron) return;
  final p = Palette.de(context);
  List<OperationBloquee> liste = await FileAttente.bloquees();
  if (!context.mounted) return;
  var occupe = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
      Future<void> recharger() async {
        final nouvelle = await FileAttente.bloquees();
        if (!ctx.mounted) return;
        setL(() {
          liste = nouvelle;
          occupe = false;
        });
        if (nouvelle.isEmpty && ctx.mounted) Navigator.pop(ctx);
      }

      Future<void> reessayer({List<int>? ids}) async {
        if (occupe) return;
        setL(() => occupe = true);
        final concernees = ids?.length ?? liste.length;
        try {
          await ServiceCloud.reprendreBloquees(ids: ids);
        } catch (_) {}
        await recharger();
        if (!context.mounted) return;
        final reste = ServiceCloud.bloquees.value;
        // parmi les lignes qu'on vient de retenter, combien sont encore refusées ?
        final encoreRefusees = ids == null ? liste.length : liste.where((o) => ids.contains(o.id)).length;
        final repartis = concernees - encoreRefusees;
        JournalRepo.noter('Cloud', 'REPRISE',
            'Reprise des opérations bloquées : $repartis envoyée(s), $encoreRefusees encore refusée(s)');
        Toast.afficher(
            context,
            reste == 0
                ? '✅ Tout est parti vers le Cloud'
                : (repartis > 0 ? '✅ $repartis envoyée(s) — $reste encore refusée(s)' : '⚠️ Le serveur refuse toujours'),
            couleur: reste == 0 || repartis > 0 ? p.succes : p.alerte,
            dureeMs: 2600);
      }

      Future<void> abandonner(List<OperationBloquee> choisies) async {
        if (occupe || choisies.isEmpty) return;
        final ok = await Dialogues.confirmer(
          ctx,
          'Abandonner ${choisies.length == 1 ? 'cette opération' : 'ces ${choisies.length} opérations'} ?',
          "Elle(s) ne sera(ont) plus jamais envoyée(s) au Cloud.\n\n"
          "Les données restent sur ce PC, mais l'autre PC ne les recevra pas, et le Cloud pourra même "
          "remplacer la version de ce PC par la sienne lors d'une prochaine synchronisation.\n\n"
          "Cette action est définitive.",
          oui: 'Abandonner',
          non: 'Garder',
        );
        if (!ok || !ctx.mounted) return;
        setL(() => occupe = true);
        await ServiceCloud.abandonnerBloquees(choisies.map((o) => o.id).toList());
        JournalRepo.noter('Cloud', 'ABANDON',
            '${choisies.length} opération(s) bloquée(s) abandonnée(s) : ${choisies.take(3).map((o) => '${o.nature} ${o.resume}').join(' ; ')}');
        await recharger();
      }

      return Dialog(
        backgroundColor: p.panneau,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('⚠️', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('OPÉRATIONS BLOQUÉES (${liste.length})',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                    "Vos données sont en sécurité sur ce PC. Ces lignes-là n'ont pas pu partir vers le Cloud : "
                    "le logiciel les a déjà retentées tout seul pendant plusieurs jours, et le serveur les refuse toujours. "
                    "« Réessayer » donne une dernière chance à la ligne ; "
                    "si le serveur la refuse encore, elle revient ici avec la nouvelle raison.",
                    style: TextStyle(fontSize: 11, color: p.txtDoux)),
                const SizedBox(height: 12),
                Flexible(
                  child: liste.isEmpty
                      ? Center(child: Text('Aucune opération bloquée.', style: TextStyle(color: p.txtGris)))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: liste.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final o = liste[i];
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: p.carte,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: p.bordure)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${o.action} · ${o.nature}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                                const SizedBox(height: 2),
                                Text(o.resume, style: TextStyle(fontSize: 11, color: p.txtPrinc)),
                                if (o.creeLe.isNotEmpty)
                                  Text('Saisi le ${o.creeLe}', style: TextStyle(fontSize: 10, color: p.txtGris)),
                                const SizedBox(height: 6),
                                Text(o.explication,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                                if (o.erreur.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: SelectableText(o.erreur,
                                        maxLines: 3,
                                        style: TextStyle(fontFamily: 'Consolas', fontSize: 9, color: p.txtGris)),
                                  ),
                                const SizedBox(height: 6),
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  TextButton(
                                    onPressed: occupe ? null : () => abandonner([o]),
                                    style: TextButton.styleFrom(foregroundColor: p.danger),
                                    child: const Text('Abandonner', style: TextStyle(fontSize: 11)),
                                  ),
                                  const SizedBox(width: 4),
                                  FilledButton(
                                    onPressed: occupe ? null : () => reessayer(ids: [o.id]),
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 30)),
                                    child: const Text('Réessayer', style: TextStyle(fontSize: 11)),
                                  ),
                                ]),
                              ]),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                if (occupe)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                Row(children: [
                  if (onDetails != null)
                    TextButton(
                      onPressed: occupe ? null : onDetails,
                      child: const Text('Détails techniques', style: TextStyle(fontSize: 11)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: occupe ? null : () => Navigator.pop(ctx),
                    child: const Text('Fermer', style: TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: occupe || liste.isEmpty ? null : () => reessayer(),
                    child: const Text('Tout réessayer', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
    }),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../data/parametres.dart';
import '../session.dart';
import 'application_tirage.dart';
import 'file_attente.dart';
import 'moteur_cloud.dart';
import 'payloads.dart';

enum EtatCloud { demarrage, ok, horsLigne, erreur, local }

/// Le chef d'orchestre de la synchronisation. Principe :
///  • l'écran lit et écrit TOUJOURS dans SQLite (rapide, marche sans Internet) ;
///  • chaque écriture est aussi placée dans la file d'attente ;
///  • ce service envoie la file au Cloud, puis rapatrie ce que l'autre PC a saisi.
/// Les écrans écoutent [etat], [enAttente] et [versionDonnees] pour se rafraîchir tout seuls.
class ServiceCloud {
  ServiceCloud._();

  static final ValueNotifier<EtatCloud> etat = ValueNotifier(EtatCloud.demarrage);
  static final ValueNotifier<int> enAttente = ValueNotifier(0);
  /// Augmente chaque fois que des données de l'autre PC ont été intégrées.
  static final ValueNotifier<int> versionDonnees = ValueNotifier(0);
  /// Augmente quand le nom de la ferme change à cause d'un autre PC : le menu se rafraîchit seul.
  static final ValueNotifier<int> versionNomFerme = ValueNotifier(0);
  static String derniereErreur = '';
  static String derniereHeure = '';

  static Timer? _horloge;
  static MoteurCloud? _moteur;
  static String _licence = '';
  static bool _occupe = false;
  static DateTime _dernierCycle = DateTime.fromMillisecondsSinceEpoch(0);

  // ------------------------------------------------------------------ démarrage / arrêt
  static Future<void> demarrer(String licence) async {
    arreter();
    _licence = licence.trim().toLowerCase();
    if (_licence.isEmpty) {
      etat.value = EtatCloud.local;
      return;
    }
    await _preparerDonnees();
    _moteur = MoteurCloud(_licence);
    FileAttente.urgent = true;
    etat.value = EtatCloud.demarrage;
    enAttente.value = await FileAttente.compter();
    _horloge = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  static void arreter() {
    _horloge?.cancel();
    _horloge = null;
    _moteur = null;
  }

  static Future<void> _tick() async {
    if (_horloge == null || _occupe) return;
    final ecoule = DateTime.now().difference(_dernierCycle).inSeconds;
    if (ecoule >= cloudIntervalleSec || (FileAttente.urgent && ecoule >= 2)) {
      await _cycle();
    }
  }

  /// Envoie tout ce qui attend, en bloquant (au plus ~20 s). Renvoie (tout est parti ?, lignes restantes).
  static Future<(bool, int)> viderFile() async {
    if (_moteur == null) return (true, 0);
    for (var i = 0; i < 4; i++) {
      while (_occupe) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await _cycle();
      final reste = await FileAttente.compter();
      if (reste == 0) return (true, 0);
      if (etat.value == EtatCloud.horsLigne || etat.value == EtatCloud.local) break;
    }
    final reste = await FileAttente.compter();
    return (reste == 0, reste);
  }

  /// Force un cycle tout de suite (ex. bouton « Synchroniser maintenant »).
  static void synchroniserMaintenant() => FileAttente.urgent = true;

  // ------------------------------------------------------------------ un cycle
  static Future<void> _cycle() async {
    final moteur = _moteur;
    if (moteur == null) return;
    _occupe = true;
    _dernierCycle = DateTime.now();
    FileAttente.urgent = false;
    try {
      final ops = await FileAttente.lire(_licence);
      final curseurs = await ApplicationTirage.lireCurseurs(cloudTablesIncrementales);
      final res = await moteur.executerCycle(ops, curseurs);
      await _appliquerResultat(res);
      if (res.config && res.reseau) await _synchroNomFerme(moteur);
    } catch (e) {
      _journaliser('cycle_interrompu', '$e');
    } finally {
      _occupe = false;
    }
  }

  /// Le client vient de renommer sa ferme : on le note, l'envoi part au prochain cycle.
  static Future<void> nomFermeModifie() async {
    await Parametres.ecrire('nom_ferme_modifie_le', DateTime.now().toUtc().toIso8601String());
    await Parametres.ecrire('nom_ferme_a_envoyer', '1');
    synchroniserMaintenant();
  }

  /// Le nom de la ferme suit sur tous les PC : le plus récent gagne. Sans Internet, rien n'est perdu :
  /// l'envoi est simplement repris plus tard. Tout échec est silencieux (le nom local reste valable).
  static Future<void> _synchroNomFerme(MoteurCloud moteur) async {
    try {
      final localNom = (await Parametres.lire('nom_ferme')).trim();
      final localQuand = DateTime.tryParse(await Parametres.lire('nom_ferme_modifie_le'));
      final aEnvoyer = await Parametres.lire('nom_ferme_a_envoyer') == '1';
      final (distNom, distQuand) = await moteur.lireReglage('nom_ferme');
      final distant = (distNom ?? '').trim();

      if (aEnvoyer && localNom.isNotEmpty) {
        await moteur.ecrireReglage('nom_ferme', localNom, localQuand ?? DateTime.now());
        await Parametres.ecrire('nom_ferme_a_envoyer', '0');
      } else if (distant.isEmpty) {
        if (localNom.isNotEmpty) {
          // première fois : on dépose le nom actuel dans le cloud pour les autres PC
          final q = localQuand ?? DateTime.now();
          await moteur.ecrireReglage('nom_ferme', localNom, q);
          await Parametres.ecrire('nom_ferme_modifie_le', q.toUtc().toIso8601String());
        }
      } else if (distant != localNom && (localQuand == null || (distQuand != null && distQuand.isAfter(localQuand)))) {
        await Parametres.ecrire('nom_ferme', distant);
        await Parametres.ecrire('nom_ferme_modifie_le', (distQuand ?? DateTime.now()).toUtc().toIso8601String());
        Session.nomFerme = distant;
        versionNomFerme.value++;
      }
    } catch (_) {
      // réseau coupé ou table absente côté serveur : on réessaiera au prochain cycle
    }
  }

  static Future<void> _appliquerResultat(ResultatCycle res) async {
    await FileAttente.retirer(res.idsOk);
    await FileAttente.compterUnEchec(res.echecs.keys);
    final attente = await FileAttente.compter();
    enAttente.value = attente;

    if (!res.config) {
      etat.value = EtatCloud.local;
    } else if (!res.reseau) {
      etat.value = EtatCloud.horsLigne;
    } else if (res.echecs.isNotEmpty || res.erreur.isNotEmpty) {
      etat.value = EtatCloud.erreur;
    } else {
      etat.value = EtatCloud.ok;
      final n = DateTime.now();
      derniereHeure = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    }
    derniereErreur = res.erreur.isNotEmpty
        ? res.erreur
        : (res.echecs.isNotEmpty ? res.echecs.values.first : '');
    if ((etat.value == EtatCloud.erreur || etat.value == EtatCloud.local) && derniereErreur.isNotEmpty) {
      _journaliser(etat.value.name, derniereErreur, echecs: res.echecs);
    }

    // il reste des lignes et le réseau marche : on enchaîne tout de suite
    if (attente > 0 && res.reseau && res.config && res.idsOk.isNotEmpty) FileAttente.urgent = true;

    if (res.tirage != null && res.reseau && res.config) {
      try {
        final resume = await ApplicationTirage.appliquer(res.tirage!,
            journaliser: (e, d) => _journaliser(e, d));
        if (resume.quelqueChoseAChange) versionDonnees.value++;
      } catch (e) {
        _journaliser('rapatriement_annule_rollback', '$e'); // la transaction a tout annulé
      }
    }
  }

  // ------------------------------------------------------------------ journal des erreurs
  static void _journaliser(String etatTexte, String erreur, {Map<int, String>? echecs}) {
    try {
      final f = File(p.join(BaseLocale.dossierUtilisateur(), 'donnies_antoine_erreurs_cloud.log'));
      final b = StringBuffer('[${DateTime.now().toIso8601String()}] état=$etatTexte — $erreur\n');
      echecs?.forEach((id, detail) => b.writeln('    · ligne en file #$id rejetée : $detail'));
      f.writeAsStringSync(b.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ rattachement + migration unique
  /// Rattache la base à la licence et prépare l'envoi UNIQUE des données déjà présentes sur ce PC.
  static Future<void> _preparerDonnees() async {
    try {
      final proprietaire = await Parametres.lire('cloud_proprietaire');
      if (proprietaire.isNotEmpty && proprietaire != _licence) {
        // Changement d'adresse : on ne supprime JAMAIS rien, on le note seulement.
        _journaliser('changement_licence_detecte_AUCUNE_SUPPRESSION',
            'ancienne licence = "$proprietaire" — nouvelle = "$_licence" — données conservées intactes.');
      }
      if (proprietaire != _licence) await Parametres.ecrire('cloud_proprietaire', _licence);

      if (await Parametres.lire('cloud_migration_faite') != '1') {
        await BaseLocale.db.transaction((txn) async {
          await _enfilerMigration(txn);
          await txn.rawInsert("INSERT OR REPLACE INTO parametres (cle, valeur) VALUES ('cloud_migration_faite', '1')");
        });
      }
    } catch (e) {
      _journaliser('preparation_donnees', '$e');
    }
  }

  static Future<void> _enfilerMigration(DatabaseExecutor txn) async {
    Future<List<Map<String, Object?>>> lire(String sql) async =>
        (await txn.rawQuery(sql)).map((l) => Map<String, Object?>.from(l)).toList();

    for (final r in await lire('SELECT nom, unite FROM catalogue_produits ORDER BY id ASC')) {
      await FileAttente.enfiler(txn, _licence, 'catalogue_produits', 'upsert',
          {'licence': _licence, 'nom': r['nom'], 'unite': r['unite']});
    }
    for (final r in await lire('SELECT nom, quantite_disponible, cout_achat_unitaire FROM stock_produits')) {
      await FileAttente.enfiler(txn, _licence, 'stock_produits', 'stock_init', {
        'p_licence': _licence,
        'p_nom': r['nom'],
        'p_qte': (r['quantite_disponible'] as num?)?.toDouble() ?? 0.0,
        'p_cout': (r['cout_achat_unitaire'] as num?)?.toDouble() ?? 0.0,
      });
    }
    for (final r in await lire('SELECT * FROM ventes ORDER BY id ASC')) {
      if ('${r['uid'] ?? ''}'.isEmpty) continue;
      await FileAttente.enfiler(txn, _licence, 'ventes', 'upsert',
          PayloadsCloud.vente(r, '${r['uid']}', _licence));
    }
    for (final r in await lire('SELECT * FROM stocks_arrivages ORDER BY id ASC')) {
      if ('${r['uid'] ?? ''}'.isEmpty) continue;
      await FileAttente.enfiler(txn, _licence, 'stocks_arrivages', 'upsert', PayloadsCloud.arrivage(r, _licence));
    }
    for (final r in await lire('SELECT * FROM bandes_elevage')) {
      await FileAttente.enfiler(txn, _licence, 'bandes_elevage', 'upsert',
          PayloadsCloud.bande(r, _licence, supprime: r['supprime'] == 1));
    }
    for (final r in await lire('SELECT * FROM rappels_veterinaires')) {
      await FileAttente.enfiler(txn, _licence, 'rappels_veterinaires', 'upsert', PayloadsCloud.rappel(r, _licence));
    }
    for (final r in await lire('SELECT * FROM journal_bande_evenements')) {
      await FileAttente.enfiler(txn, _licence, 'journal_bande_evenements', 'upsert',
          PayloadsCloud.journalBande(r, _licence));
    }
  }
}

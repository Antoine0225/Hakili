import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/base_locale.dart';
import 'diagnostic.dart';

/// Sauvegarde automatique de la base de données : une copie par jour, les 7 dernières sont gardées.
/// Les copies sont rangées dans le dossier « hakili_sauvegardes » (dossier utilisateur).
/// Pour revenir en arrière : fermer Hakili, puis remplacer le fichier de la base par une de ces copies.
class Sauvegarde {
  Sauvegarde._();

  static const int nombreAGarder = 7;
  static Timer? _minuteur;
  static bool _occupe = false;

  static String get dossier => p.join(BaseLocale.dossierUtilisateur(), 'hakili_sauvegardes');

  static String _jour(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _prefixe() => p.basenameWithoutExtension(BaseLocale.nomFichierActif);

  static String _cheminDuJour() => p.join(dossier, '${_prefixe()}_${_jour(DateTime.now())}.db');

  /// Lance la sauvegarde du jour peu après l'ouverture, puis vérifie toutes les 6 heures
  /// (utile si le logiciel reste ouvert plusieurs jours de suite).
  static void demarrer() {
    arreter();
    Future.delayed(const Duration(seconds: 20), () => faire());
    _minuteur = Timer.periodic(const Duration(hours: 6), (_) => faire());
  }

  static void arreter() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  /// Fait la copie du jour. Si [ecraser] est vrai, une copie déjà faite aujourd'hui est remplacée
  /// (à la fermeture : la copie contient alors tout le travail de la journée).
  /// Ne plante jamais : en cas de souci, l'erreur est notée dans le journal de diagnostic.
  static Future<bool> faire({bool ecraser = false}) async {
    if (_occupe) return false;
    _occupe = true;
    try {
      await Directory(dossier).create(recursive: true);
      final cible = File(_cheminDuJour());
      if (await cible.exists() && !ecraser) return true; // déjà fait aujourd'hui

      final temporaire = File('${cible.path}.tmp');
      if (await temporaire.exists()) await temporaire.delete();

      try {
        // Méthode 1 : SQLite fabrique lui-même une copie propre et cohérente.
        await BaseLocale.db.execute('VACUUM INTO ?', [temporaire.path]);
      } catch (e) {
        // Méthode 2 (si la version de SQLite est trop ancienne) : on vide le journal en attente puis on copie le fichier.
        Diagnostic.erreur('sauvegarde (méthode 1)', e);
        if (await temporaire.exists()) await temporaire.delete();
        await BaseLocale.db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        await File(BaseLocale.cheminDe(BaseLocale.nomFichierActif)).copy(temporaire.path);
      }

      if (await cible.exists()) await cible.delete();
      await temporaire.rename(cible.path);
      await _ranger();
      Diagnostic.ecrire('Sauvegarde automatique faite : ${p.basename(cible.path)}');
      return true;
    } catch (e) {
      Diagnostic.erreur('sauvegarde automatique', e);
      return false;
    } finally {
      _occupe = false;
    }
  }

  /// Garde seulement les 7 copies les plus récentes.
  static Future<void> _ranger() async {
    try {
      final prefixe = '${_prefixe()}_';
      final copies = <File>[];
      await for (final f in Directory(dossier).list()) {
        final nom = p.basename(f.path);
        if (f is File && nom.startsWith(prefixe) && nom.endsWith('.db')) copies.add(f);
      }
      copies.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path))); // les plus récentes d'abord
      for (final ancienne in copies.skip(nombreAGarder)) {
        await ancienne.delete();
      }
    } catch (e) {
      Diagnostic.erreur('rangement des sauvegardes', e);
    }
  }
}

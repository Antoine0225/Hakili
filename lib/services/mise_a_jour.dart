import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../securite/jeton_cloud.dart';
import 'diagnostic.dart';

enum PhaseMaj { aucune, disponible, telechargement, prete, erreur }

/// Ce que la pastille « Mise à jour » doit afficher.
class EtatMaj {
  final PhaseMaj phase;
  final String version, message;
  final double progression; // 0 → 1
  const EtatMaj(this.phase, {this.version = '', this.progression = 0, this.message = ''});
}

enum ResultatRecherche { aJour, disponible, impossible }

/// Mise à jour du logiciel :
///  1. toutes les 3 heures, Hakili regarde sur Supabase s'il existe une version plus récente ;
///  2. si oui, une pastille apparaît : le client clique « Télécharger » et continue son travail pendant ce temps ;
///  3. quand c'est prêt, « Installer maintenant » : Hakili se ferme, l'installateur remplace les fichiers
///     (les données ne sont jamais touchées : elles sont dans le dossier de l'utilisateur) et Hakili se rouvre.
class MiseAJour {
  MiseAJour._();

  static final etat = ValueNotifier<EtatMaj>(const EtatMaj(PhaseMaj.aucune));

  static String _version = '', _url = '', _sha = '';
  static Timer? _minuteur;
  static bool _occupe = false;

  static String get _dossier => p.join(BaseLocale.dossierUtilisateur(), 'hakili_mises_a_jour');
  static String get _chemin => p.join(_dossier, 'Hakili_Installation_$_version.exe');

  // ------------------------------------------------------------------ démarrage
  static void demarrer() {
    if (!Platform.isWindows || _minuteur != null) return;
    Future.delayed(const Duration(seconds: 6), verifier);
    _minuteur = Timer.periodic(const Duration(hours: majIntervalleHeures), (_) => verifier());
  }

  static void arreter() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  // ------------------------------------------------------------------ comparaison de versions
  static List<int> _morceaux(String v) {
    final net = v.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    return [for (final m in net.split(RegExp(r'[.\-+]'))) int.tryParse(m) ?? 0];
  }

  /// Vrai si [distante] est strictement plus récente que [locale] (1.0.1 > 1.0, 1.10 > 1.9).
  static bool estPlusRecente(String distante, String locale) {
    final a = _morceaux(distante), b = _morceaux(locale);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  // ------------------------------------------------------------------ recherche
  static Future<ResultatRecherche> verifier() async {
    if (!Platform.isWindows) return ResultatRecherche.aJour;
    final phase = etat.value.phase;
    if (_occupe || phase == PhaseMaj.telechargement) {
      return phase == PhaseMaj.aucune ? ResultatRecherche.aJour : ResultatRecherche.disponible;
    }
    _occupe = true;
    try {
      final email = BaseLocale.emailEnMemoire ?? '';
      final jeton = JetonCloud.lire(email);
      final rep = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/configuration_systeme?select=*'),
        headers: {'apikey': supabaseCle, 'Authorization': 'Bearer ${jeton.isEmpty ? supabaseCle : jeton}'},
      ).timeout(const Duration(seconds: 12));
      if (rep.statusCode != 200) throw 'le serveur a répondu ${rep.statusCode}';
      final lignes = jsonDecode(utf8.decode(rep.bodyBytes));
      if (lignes is! List) throw 'réponse inattendue';
      Map<String, dynamic>? ligne(String cle) {
        for (final l in lignes) {
          if (l is Map && '${l['cle']}'.trim() == cle) return Map<String, dynamic>.from(l);
        }
        return null;
      }

      final version = '${ligne(majCleVersion)?['valeur'] ?? ''}'.trim();
      final ligneUrl = ligne(majCleUrl);
      final url = '${ligneUrl?['valeur'] ?? ''}'.trim();
      final sha = '${ligneUrl?['sha256_exe'] ?? ''}'.trim().toLowerCase();
      if (version.isEmpty || !estPlusRecente(version, versionLogiciel)) {
        if (etat.value.phase != PhaseMaj.prete) etat.value = const EtatMaj(PhaseMaj.aucune);
        _nettoyerAnciens();
        return ResultatRecherche.aJour;
      }
      if (!url.toLowerCase().startsWith('https://')) throw 'lien de téléchargement absent ou non sécurisé';
      _version = version;
      _url = url;
      _sha = sha;
      etat.value = await _dejaTelechargee()
          ? EtatMaj(PhaseMaj.prete, version: version)
          : EtatMaj(PhaseMaj.disponible, version: version);
      return ResultatRecherche.disponible;
    } catch (e) {
      Diagnostic.ecrire('Recherche de mise à jour impossible : $e');
      return ResultatRecherche.impossible;
    } finally {
      _occupe = false;
    }
  }

  // ------------------------------------------------------------------ fichiers
  static Future<String> _empreinte(File f) async {
    final h = await Sha256().hash(await f.readAsBytes());
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<bool> _dejaTelechargee() async {
    try {
      final f = File(_chemin);
      if (!await f.exists() || !await File('$_chemin.ok').exists()) return false;
      if (_sha.isNotEmpty && await _empreinte(f) != _sha) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Quand le logiciel est à jour, on efface les anciens installateurs téléchargés.
  static void _nettoyerAnciens() {
    try {
      final d = Directory(_dossier);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ téléchargement (en arrière-plan)
  static Future<void> telecharger() async {
    final phase = etat.value.phase;
    if (phase == PhaseMaj.telechargement || _url.isEmpty || _version.isEmpty) return;
    final version = _version;
    etat.value = EtatMaj(PhaseMaj.telechargement, version: version);
    final client = http.Client();
    try {
      await Directory(_dossier).create(recursive: true);
      final fichier = File(_chemin);
      final part = File('$_chemin.part');
      final rep = await client.send(http.Request('GET', Uri.parse(_url))).timeout(const Duration(seconds: 30));
      if (rep.statusCode != 200) throw 'le serveur a répondu ${rep.statusCode}';
      final total = rep.contentLength ?? 0;
      var recu = 0, dernierPourcent = -1;
      final sortie = part.openWrite();
      try {
        await for (final morceau in rep.stream.timeout(const Duration(seconds: 60))) {
          sortie.add(morceau);
          recu += morceau.length;
          if (total > 0) {
            final pct = (recu * 100 / total).floor();
            if (pct != dernierPourcent) {
              dernierPourcent = pct;
              etat.value = EtatMaj(PhaseMaj.telechargement, version: version, progression: recu / total);
            }
          }
        }
      } finally {
        await sortie.close();
      }
      if (total > 0 && recu != total) throw 'téléchargement incomplet';
      // un vrai programme Windows commence par « MZ » (sinon on a reçu une page web d'erreur)
      final debut = await part.openRead(0, 2).expand((x) => x).toList();
      if (debut.length < 2 || debut[0] != 0x4D || debut[1] != 0x5A) throw "le fichier reçu n'est pas un programme Windows";
      if (_sha.isNotEmpty && await _empreinte(part) != _sha) {
        await part.delete();
        throw 'le fichier reçu ne correspond pas à celui attendu (empreinte différente)';
      }
      if (await fichier.exists()) await fichier.delete();
      await part.rename(_chemin);
      await File('$_chemin.ok').writeAsString(version);
      etat.value = EtatMaj(PhaseMaj.prete, version: version);
    } catch (e) {
      Diagnostic.ecrire('Téléchargement de la mise à jour échoué : $e');
      etat.value = EtatMaj(PhaseMaj.erreur, version: version, message: 'Le téléchargement a été interrompu.');
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------------ installation
  /// Lance l'installateur puis ferme Hakili. Renvoie false si l'installateur n'a pas pu démarrer.
  static Future<bool> installer() async {
    if (etat.value.phase != PhaseMaj.prete) return false;
    try {
      // « cmd /c start » : Windows peut ainsi demander l'autorisation habituelle (écran bleu/jaune) à l'utilisateur.
      await Process.start(
        'cmd',
        ['/c', 'start', '', _chemin, '/SILENT', '/CLOSEAPPLICATIONS', '/NOCANCEL'],
        mode: ProcessStartMode.detached,
      );
      try {
        await BaseLocale.db.close().timeout(const Duration(seconds: 3));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
      exit(0);
    } catch (e) {
      Diagnostic.ecrire("Lancement de l'installateur impossible : $e");
      etat.value = EtatMaj(PhaseMaj.erreur, version: _version, message: "L'installation n'a pas pu démarrer.");
      return false;
    }
  }
}

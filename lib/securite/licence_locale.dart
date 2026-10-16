import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../config/constantes.dart';
import '../data/base_locale.dart';
import '../data/parametres.dart';
import 'licence_serveur.dart';

enum Issue { autorise, refuse, verrouille }

class ResultatControle {
  final Issue issue;
  final String message;
  const ResultatControle(this.issue, [this.message = '']);
}

/// Tout ce qui touche à la licence ET qui vit sur ce PC : e-mail du client, cache signé
/// (anti-triche), mode hors ligne limité à 5 jours, verrou de sécurité.
/// Mêmes tables, mêmes réglages et même signature que securite.py : une base existante est reconnue.
class Licence {
  Licence._();

  static String messageHorsLigne = '';
  static String expiration = '';

  // ------------------------------------------------------------------ outils
  static String _hex(List<int> o) => o.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _depuisHex(String h) =>
      [for (var i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

  static String _texteJour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static DateTime _aujourdhui() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime? _valide(int a, int m, int j) {
    final d = DateTime(a, m, j);
    return (d.year == a && d.month == m && d.day == j) ? d : null;
  }

  /// Lecture tolérante : « JJ/MM/AAAA », « JJ-MM-AAAA » ou « AAAA-MM-JJ ».
  static DateTime? lireDate(String? texte) {
    if (texte == null) return null;
    final s = texte.trim();
    var m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(s);
    if (m != null) return _valide(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m != null) return _valide(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return null;
  }

  // ------------------------------------------------------------------ identité du client
  static Future<String> lireEmail() async {
    final memo = BaseLocale.emailEnMemoire;
    if (memo != null) return memo;
    try {
      final l = await BaseLocale.db.rawQuery('SELECT email FROM identite_utilisateur WHERE id = 1');
      if (l.isEmpty) return '';
      return ('${l.first['email'] ?? ''}').trim().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static Future<void> enregistrerEmail(String email) async {
    await BaseLocale.db.rawInsert(
        'INSERT OR REPLACE INTO identite_utilisateur (id, email) VALUES (1, ?)',
        [email.trim().toLowerCase()]);
    BaseLocale.emailEnMemoire = email.trim().toLowerCase();
  }

  /// Identifiant de ce PC (une place de licence = un PC).
  static String? _pcIdCache;

  /// Adresse MAC de la carte réseau, convertie en nombre (comme uuid.getnode() de Python), pour retrouver
  /// le MÊME identifiant que l'ancien logiciel. Renvoie null si Windows n'en fournit pas de vraie.
  static Future<String?> _identifiantMac() async {
    try {
      if (!Platform.isWindows) return null;
      final r = await Process.run('getmac', ['/fo', 'csv', '/nh']);
      for (final m in RegExp(r'([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}').allMatches('${r.stdout}')) {
        final noeud = int.parse(m.group(0)!.replaceAll(RegExp(r'[-:]'), ''), radix: 16);
        if (noeud != 0 && ((noeud >> 40) & 1) == 0) return '$noeud'; // bit « adresse fabriquée » absent → vraie MAC
      }
    } catch (_) {}
    return null;
  }

  static Future<String> pcId() async {
    if (_pcIdCache != null) return _pcIdCache!;
    var secours = await Parametres.lire('pc_id_local');
    if (secours.isEmpty) {
      final r = Random.secure();
      secours = 'LOC-${_hex(List<int>.generate(6, (_) => r.nextInt(256)))}';
      await Parametres.ecrire('pc_id_local', secours);
    }
    return _pcIdCache = (await _identifiantMac()) ?? secours;
  }

  /// Adresse e-mail à laquelle appartient la base locale ouverte ('' = base vierge ou inconnue).
  static Future<String> lireProprietaireFerme() async {
    for (final cle in ['proprietaire_licence', 'cloud_proprietaire']) {
      final v = (await Parametres.lire(cle)).trim().toLowerCase();
      if (v.isNotEmpty) return v;
    }
    return lireEmail();
  }

  static Future<bool> baseContientDesDonnees() async {
    if (await Parametres.lire('configuration_terminee', defaut: '0') == '1') return true;
    try {
      for (final t in ['ventes', 'stocks_arrivages', 'bandes_elevage']) {
        final l = await BaseLocale.db.rawQuery('SELECT COUNT(*) AS n FROM $t');
        if (((l.first['n'] as int?) ?? 0) > 0) return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> sessionOuverte() async =>
      await Parametres.lire('licence_session_ouverte', defaut: '1') == '1';

  static Future<void> marquerSession(bool ouverte) =>
      Parametres.ecrire('licence_session_ouverte', ouverte ? '1' : '0');

  // ------------------------------------------------------------------ cache signé (anti-triche)
  // La date d'expiration et la date du dernier contrôle en ligne sont scellées par une signature
  // HMAC-SHA256 dont la clé est propre à ce PC. Modifier la base à la main brise la signature.
  static Future<List<int>> _cleSignature() async {
    var h = await Parametres.lire('cle_signature_licence_locale');
    if (h.isEmpty) {
      final r = Random.secure();
      h = _hex(List<int>.generate(32, (_) => r.nextInt(256)));
      await Parametres.ecrire('cle_signature_licence_locale', h);
    }
    return _depuisHex(h);
  }

  static Future<String> _signer(String exp, String verif) async {
    final mac = await Hmac.sha256()
        .calculateMac(utf8.encode('$exp|$verif'), secretKey: SecretKey(await _cleSignature()));
    return _hex(mac.bytes);
  }

  static bool _egal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<(String?, String?, String?)> _lireCache() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT expiration, derniere_verif, signature FROM cache_licence_securise WHERE id = 1');
      if (l.isEmpty) return (null, null, null);
      final r = l.first;
      return (r['expiration'] as String?, r['derniere_verif'] as String?, r['signature'] as String?);
    } catch (_) {
      return (null, null, null);
    }
  }

  /// Scelle la date de fin et le jour du dernier contrôle en ligne réussi.
  static Future<void> enregistrerCache(String expirationTxt) async {
    final verif = _texteJour(_aujourdhui());
    final signature = await _signer(expirationTxt, verif);
    await BaseLocale.db.rawInsert(
        'INSERT OR REPLACE INTO cache_licence_securise (id, expiration, derniere_verif, signature) '
        'VALUES (1, ?, ?, ?)',
        [expirationTxt, verif, signature]);
  }

  /// Après une déconnexion : ce PC ne doit plus s'ouvrir hors ligne sur d'anciens droits.
  static Future<void> effacerCache() async {
    try {
      await BaseLocale.db.rawDelete('DELETE FROM cache_licence_securise');
    } catch (_) {}
  }

  // ------------------------------------------------------------------ verrou de sécurité (coffre-fort)
  // Si la licence est révoquée, on ne détruit JAMAIS la base : on pose seulement ce petit fichier
  // masqué, relu en priorité à chaque démarrage, même sans Internet.
  static String _cheminVerrou() =>
      p.join(BaseLocale.dossierUtilisateur(), '.antoine_syscache.dat');

  /// Renvoie (verrouillé ?, message). Un fichier illisible = verrouillé, par prudence.
  static Future<(bool, String)> lireVerrou() async {
    final f = File(_cheminVerrou());
    if (!await f.exists()) return (false, '');
    try {
      final data = jsonDecode(await f.readAsString());
      if (data is Map && data['verrouille'] == true) return (true, '${data['message'] ?? ''}');
      return (false, '');
    } catch (_) {
      return (true,
          '🚨 SÉCURITÉ : Accès gelé (fichier de contrôle local illisible). Contactez le support.');
    }
  }

  static Future<void> activerVerrou(String email, String message, {String code = ''}) async {
    try {
      final chemin = _cheminVerrou();
      await File(chemin).writeAsString(jsonEncode({
        'verrouille': true,
        'email': email.trim().toLowerCase(),
        'code': code,
        'message': message,
        'date': DateTime.now().toIso8601String(),
      }));
      if (Platform.isWindows) await Process.run('attrib', ['+h', chemin]); // fichier masqué
    } catch (_) {}
  }

  /// Appelée UNIQUEMENT après une activation validée par le serveur. Ne touche jamais à la base.
  static Future<void> leverVerrou() async {
    final chemin = _cheminVerrou();
    final f = File(chemin);
    if (!await f.exists()) return;
    try {
      if (Platform.isWindows) await Process.run('attrib', ['-h', chemin]);
      await f.delete();
    } catch (_) {}
  }

  // ------------------------------------------------------------------ contrôle hors ligne (4 verrous)
  static Future<ResultatControle> verifierHorsLigne() async {
    final (expTxt, verifTxt, signature) = await _lireCache();
    final dateFin = lireDate(expTxt);
    final dateVerif = lireDate(verifTxt);
    final aujourdhui = _aujourdhui();

    if (dateFin == null || dateVerif == null) {
      return const ResultatControle(
          Issue.refuse,
          'Première activation impossible sans Internet.\n'
          'Connectez le PC au réseau (ou en partage de connexion) une seule fois.');
    }

    // Verrou 0 : la signature ne correspond plus → quelqu'un a modifié la base à la main.
    if (signature != null && signature.isNotEmpty) {
      final attendue = await _signer(expTxt!, verifTxt!);
      if (!_egal(attendue, signature)) {
        const msg = '🚨 FALSIFICATION DÉTECTÉE : les données de licence stockées localement '
            'ont été modifiées en dehors du logiciel.\nAccès définitivement gelé.';
        await activerVerrou(await lireEmail(), msg, code: 'falsification_signature');
        return const ResultatControle(Issue.verrouille, msg);
      }
    }

    // Verrou 3 : l'horloge du PC a été reculée.
    if (aujourdhui.isBefore(dateVerif)) {
      return ResultatControle(
          Issue.refuse,
          '⛔ Falsification de l\'horloge système détectée.\n'
          'La date du PC est antérieure au dernier contrôle officiel ($verifTxt).\n'
          'Remettez la date correcte pour continuer.');
    }

    // Verrou 1 : abonnement terminé.
    if (aujourdhui.isAfter(dateFin)) {
      return ResultatControle(Issue.refuse,
          '⛔ Votre licence a expiré le $expTxt.\nContactez votre fournisseur pour la renouveler.');
    }

    // Verrou 2 : plus de 5 jours sans connexion.
    final joursSansReseau = aujourdhui.difference(dateVerif).inDays;
    if (joursSansReseau > licenceJoursMaxHorsLigne) {
      return ResultatControle(
          Issue.refuse,
          '⛔ $joursSansReseau jours sans vérification en ligne '
          '(maximum autorisé : $licenceJoursMaxHorsLigne).\n'
          'Activez le partage de connexion de votre téléphone une minute pour rafraîchir vos droits.');
    }

    final restants = licenceJoursMaxHorsLigne - joursSansReseau;
    messageHorsLigne =
        '📡 Mode Compagne Hors-Ligne actif — $restants jour(s) avant obligation de connexion.';
    expiration = expTxt ?? '';
    return const ResultatControle(Issue.autorise);
  }

  // ------------------------------------------------------------------ point d'entrée du démarrage
  static Future<ResultatControle> controlerDroits() async {
    messageHorsLigne = '';
    final email = await lireEmail();
    if (email.isEmpty) return const ResultatControle(Issue.refuse, ''); // → écran d'activation

    final res = await LicenceServeur.transaction(email, await pcId());

    if (res.reseau && res.autorise) {
      await enregistrerCache(res.expiration ?? ''); // on scelle les droits frais
      expiration = res.expiration ?? '';
      return const ResultatControle(Issue.autorise);
    }

    if (res.reseau && !res.autorise) {
      final message = res.message.isNotEmpty
          ? res.message
          : '⛔ L\'adresse $email n\'est plus autorisée sur le serveur.';
      // Seule une fiche supprimée côté serveur (« inconnu ») est une vraie révocation.
      // « pleine » ou « conflit » sont récupérables : jamais de verrou définitif pour ça.
      if (res.code == 'inconnu') {
        await activerVerrou(email, message, code: res.code);
        return ResultatControle(Issue.verrouille, message);
      }
      return ResultatControle(Issue.refuse, message);
    }

    return verifierHorsLigne(); // pas de réseau
  }
}

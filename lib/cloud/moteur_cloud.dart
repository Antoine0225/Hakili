import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/constantes.dart';
import '../securite/jeton_cloud.dart';
import 'file_attente.dart';

/// Résultat d'un cycle : ce qui est parti, ce qui est revenu, et l'état du réseau.
class ResultatCycle {
  bool config = true; // false : configuration impossible (pas de licence, URL invalide)
  bool reseau = true; // false : pas d'Internet / badge absent → on réessaiera, rien n'est perdu
  String erreur = '';
  final List<int> idsOk = [];
  final Map<int, String> echecs = {};
  Tirage? tirage;
}

class Tirage {
  final Map<String, List<Map<String, dynamic>>> tables = {
    'ventes': [],
    'stocks_arrivages': [],
    'catalogue_produits': [],
    'stock_produits': [],
    'bandes_elevage': [],
    'rappels_veterinaires': [],
  };
  final Map<String, int> curseurs;
  Tirage(this.curseurs);
}

class _ErreurHttp implements Exception {
  final int statut; // 0 = coupure réseau
  final String corps;
  _ErreurHttp(this.statut, this.corps);

  /// Coupure réseau, ou badge expiré/refusé : on attend (jamais d'abandon de la file pour ça).
  bool get reseau =>
      statut == 0 || corps.contains('JWT') || corps.contains('PGRST301') || corps.contains('PGRST303');

  @override
  String toString() => statut == 0 ? corps : 'HTTP $statut : $corps';
}

/// Parle à Supabase en REST. Chaque requête porte :
///  • apikey          : la clé publique du projet
///  • Authorization   : le badge signé de la licence
///  • x-licence       : l'e-mail du client → la base (RLS) refuse toute ligne d'une autre ferme
class MoteurCloud {
  final String licence;
  MoteurCloud(String licence) : licence = licence.trim().toLowerCase();

  bool get _urlValide {
    final u = Uri.tryParse(supabaseUrl);
    final h = (u?.host ?? '').toLowerCase();
    return supabaseUrl.toLowerCase().startsWith('https://') &&
        h.contains('.') &&
        !['supabase.co', 'www.supabase.co', 'supabase.com', 'www.supabase.com'].contains(h);
  }

  Map<String, String> _entetes(String jeton, {String? prefer}) => {
        'apikey': supabaseCle,
        'Authorization': 'Bearer $jeton',
        'x-licence': licence,
        'Content-Type': 'application/json',
        if (prefer != null) 'Prefer': prefer,
      };

  Future<Object?> _requete(String methode, String chemin, String jeton,
      {Map<String, String>? requete, Object? corps, String? prefer}) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/$chemin').replace(queryParameters: requete);
    try {
      final entetes = _entetes(jeton, prefer: prefer);
      final delai = const Duration(seconds: cloudDelaiSec);
      late http.Response r;
      switch (methode) {
        case 'GET':
          r = await http.get(uri, headers: entetes).timeout(delai);
        case 'DELETE':
          r = await http.delete(uri, headers: entetes).timeout(delai);
        default:
          r = await http.post(uri, headers: entetes, body: jsonEncode(corps)).timeout(delai);
      }
      final texte = utf8.decode(r.bodyBytes);
      if (r.statusCode >= 300) throw _ErreurHttp(r.statusCode, texte);
      if (texte.trim().isEmpty) return null;
      return jsonDecode(texte);
    } on _ErreurHttp {
      rethrow;
    } catch (e) {
      // SocketException, TimeoutException, ClientException, erreur TLS... : coupure réseau
      throw _ErreurHttp(0, '$e');
    }
  }

  // ------------------------------------------------------------------ ENVOI
  Future<void> _envoyerLotUpsert(String jeton, String table, List<OperationCloud> lot) async {
    final cles = cloudConflits[table]!.split(',');
    final uniques = <String, Map<String, dynamic>>{};
    for (final op in lot) {
      // un même identifiant deux fois dans un lot serait refusé : la dernière version gagne
      uniques[cles.map((c) => '${op.payload[c]}').join('|')] = op.payload;
    }
    final ignorer = table == 'catalogue_produits'; // un produit déjà présent n'est jamais réécrit
    await _requete('POST', table, jeton,
        requete: {'on_conflict': cloudConflits[table]!},
        corps: uniques.values.toList(),
        prefer: '${ignorer ? 'resolution=ignore-duplicates' : 'resolution=merge-duplicates'},return=minimal');
  }

  /// Envoie la file dans l'ordre. Renvoie false dès que le réseau lâche.
  Future<bool> _pousser(String jeton, List<OperationCloud> ops, ResultatCycle res) async {
    var i = 0;
    while (i < ops.length) {
      final op = ops[i];
      if (op.operation == 'upsert') {
        var j = i;
        final lot = <OperationCloud>[];
        while (j < ops.length &&
            ops[j].operation == 'upsert' &&
            ops[j].table == op.table &&
            lot.length < cloudTailleLot) {
          lot.add(ops[j]);
          j++;
        }
        try {
          await _envoyerLotUpsert(jeton, op.table, lot);
          res.idsOk.addAll(lot.map((o) => o.id));
        } on _ErreurHttp catch (e) {
          if (e.reseau) {
            res.reseau = false;
            res.erreur = '$e';
            return false;
          }
          for (final o in lot) {
            // rejet du serveur : on isole la ligne fautive
            try {
              await _envoyerLotUpsert(jeton, o.table, [o]);
              res.idsOk.add(o.id);
            } on _ErreurHttp catch (e2) {
              if (e2.reseau) {
                res.reseau = false;
                res.erreur = '$e2';
                return false;
              }
              res.echecs[o.id] = '$e2';
            }
          }
        }
        i = j;
      } else if (op.operation == 'delete') {
        try {
          final filtre = <String, String>{};
          for (final cle in (cloudConflits[op.table] ?? '').split(',')) {
            if (cle.isNotEmpty) filtre[cle] = 'eq.${op.payload[cle]}';
          }
          await _requete('DELETE', op.table, jeton, requete: filtre);
          res.idsOk.add(op.id);
        } on _ErreurHttp catch (e) {
          if (e.reseau) {
            res.reseau = false;
            res.erreur = '$e';
            return false;
          }
          res.echecs[op.id] = '$e';
        }
        i++;
      } else {
        try {
          final fonction = cloudRpc[op.operation];
          if (fonction == null) throw _ErreurHttp(400, 'opération inconnue : ${op.operation}');
          await _requete('POST', 'rpc/$fonction', jeton, corps: op.payload);
          res.idsOk.add(op.id);
        } on _ErreurHttp catch (e) {
          if (e.reseau) {
            res.reseau = false;
            res.erreur = '$e';
            return false;
          }
          res.echecs[op.id] = '$e';
        }
        i++;
      }
    }
    return true;
  }

  // ------------------------------------------------------------------ TIRAGE
  Future<List<Map<String, dynamic>>> _lireTout(String jeton, String table,
      {int? depart, bool trier = true}) async {
    final lignes = <Map<String, dynamic>>[];
    var decalage = 0;
    while (true) {
      final rep = await _requete('GET', table, jeton, requete: {
        'select': '*',
        'licence': 'eq.$licence',
        if (depart != null) 'seq': 'gte.$depart',
        if (trier) 'order': 'seq.asc',
        'limit': '$cloudTaillePage',
        'offset': '$decalage',
      });
      final page = (rep is List ? rep : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      lignes.addAll(page);
      if (page.length < cloudTaillePage) break;
      decalage += cloudTaillePage;
    }
    return lignes;
  }

  Future<Tirage> _tirer(String jeton, Map<String, int> curseurs) async {
    final t = Tirage(Map<String, int>.from(curseurs));
    for (final table in cloudTablesIncrementales) {
      final depart = max(0, (curseurs[table] ?? 0) - cloudChevauchement);
      final lignes = await _lireTout(jeton, table, depart: depart);
      t.tables[table] = lignes;
      if (lignes.isNotEmpty) {
        final maxSeq = lignes.map((l) => int.tryParse('${l['seq'] ?? 0}') ?? 0).reduce((a, b) => a > b ? a : b);
        final ancien = curseurs[table] ?? 0;
        t.curseurs[table] = maxSeq > ancien ? maxSeq : ancien;
      }
    }
    t.tables['catalogue_produits'] = await _lireTout(jeton, 'catalogue_produits');
    t.tables['stock_produits'] = await _lireTout(jeton, 'stock_produits', trier: false);
    return t;
  }

  // ------------------------------------------------------------------ RÉGLAGES DE LA FERME (nom...)
  String? _porteurOuNull() {
    if (!_urlValide || licence.isEmpty) return null;
    final jeton = JetonCloud.lire(licence);
    if (jeton.isEmpty && jetonObligatoire) return null;
    return jeton.isEmpty ? supabaseCle : jeton;
  }

  /// Lit un réglage partagé : (valeur, modifié le) ; (null, null) s'il n'existe pas encore.
  /// Lance une erreur si le réseau ou le serveur ne répond pas.
  Future<(String?, DateTime?)> lireReglage(String cle) async {
    final porteur = _porteurOuNull();
    if (porteur == null) throw _ErreurHttp(0, 'cloud non configuré');
    final rep = await _requete('GET', 'reglages_ferme', porteur,
        requete: {'select': 'valeur,modifie_le', 'licence': 'eq.$licence', 'cle': 'eq.$cle', 'limit': '1'});
    final l = (rep is List ? rep : const []).whereType<Map>().toList();
    if (l.isEmpty) return (null, null);
    return ('${l.first['valeur'] ?? ''}', DateTime.tryParse('${l.first['modifie_le'] ?? ''}'));
  }

  /// Enregistre (ou remplace) un réglage partagé.
  Future<void> ecrireReglage(String cle, String valeur, DateTime quand) async {
    final porteur = _porteurOuNull();
    if (porteur == null) throw _ErreurHttp(0, 'cloud non configuré');
    await _requete('POST', 'reglages_ferme', porteur,
        requete: {'on_conflict': 'licence,cle'},
        corps: [
          {'licence': licence, 'cle': cle, 'valeur': valeur, 'modifie_le': quand.toUtc().toIso8601String()}
        ],
        prefer: 'resolution=merge-duplicates,return=minimal');
  }

  /// Un cycle complet : 1) envoi de la file d'attente  2) rapatriement des nouveautés des autres PC.
  Future<ResultatCycle> executerCycle(List<OperationCloud> ops, Map<String, int> curseurs,
      {bool tirer = true}) async {
    final res = ResultatCycle();
    if (!_urlValide) {
      res.config = false;
      res.erreur = 'URL Supabase invalide (attendu : https://votre-projet.supabase.co)';
      return res;
    }
    if (licence.isEmpty) {
      // 🚨 Aucune requête ne part sans en-tête x-licence (la sécurité RLS en dépend).
      res.config = false;
      res.erreur = 'Aucune licence active : connexion Cloud refusée.';
      return res;
    }
    final jeton = JetonCloud.lire(licence);
    if (jeton.isEmpty && jetonObligatoire) {
      res.reseau = false;
      res.erreur = 'badge de licence indisponible : synchronisation en attente';
      return res;
    }
    final porteur = jeton.isEmpty ? supabaseCle : jeton;
    try {
      if (!await _pousser(porteur, ops, res)) return res;
      if (tirer) res.tirage = await _tirer(porteur, curseurs);
    } on _ErreurHttp catch (e) {
      if (e.reseau) res.reseau = false;
      res.erreur = '$e';
    } catch (e) {
      res.erreur = '$e';
    }
    return res;
  }
}

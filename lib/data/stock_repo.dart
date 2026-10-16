import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../cloud/file_attente.dart';
import '../securite/licence_locale.dart';
import 'base_locale.dart';

/// Génère un identifiant unique de 32 caractères (équivalent de uuid4().hex de Python).
String nouvelUid() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class Produit {
  final String nom, unite;
  const Produit(this.nom, this.unite);
}

class StockRepo {
  StockRepo._();

  /// Renvoie [(nom, unité), ...] dans l'ordre de création.
  static Future<List<Produit>> catalogue() async {
    try {
      final l = await BaseLocale.db.rawQuery('SELECT nom, unite FROM catalogue_produits ORDER BY id ASC');
      return l.map((r) => Produit('${r['nom']}', '${r['unite'] ?? 'piece'}')).toList();
    } catch (_) {
      return [];
    }
  }

  /// nom -> (quantité disponible, coût d'achat unitaire)
  static Future<Map<String, (double, double)>> tousLesStocks() async {
    try {
      final l = await BaseLocale.db
          .rawQuery('SELECT nom, quantite_disponible, cout_achat_unitaire FROM stock_produits');
      return {
        for (final r in l)
          '${r['nom']}': (((r['quantite_disponible'] as num?) ?? 0).toDouble(), ((r['cout_achat_unitaire'] as num?) ?? 0).toDouble())
      };
    } catch (_) {
      return {};
    }
  }

  static Future<(double, double)> stockProduit(String nom) async =>
      (await tousLesStocks())[nom] ?? (0.0, 0.0);

  static Future<String> unite(String nom) async {
    for (final p in await catalogue()) {
      if (p.nom == nom) return p.unite;
    }
    return 'piece';
  }

  static String libelleUnite(String unite) => (unite == 'kilo' || unite == 'sac') ? 'kg' : 'pièce(s)';

  /// Ajoute ou retire du stock. Écrit en local ET place l'opération dans la file d'envoi (même transaction).
  static Future<void> mettreAJour(DatabaseExecutor ex, String nom, double delta, {double? nouveauCout}) async {
    try {
      final l = await ex.rawQuery(
          'SELECT quantite_disponible, cout_achat_unitaire FROM stock_produits WHERE nom = ?', [nom]);
      final qte = l.isEmpty ? 0.0 : ((l.first['quantite_disponible'] as num?) ?? 0).toDouble();
      final cout = l.isEmpty ? 0.0 : ((l.first['cout_achat_unitaire'] as num?) ?? 0).toDouble();
      final nouvelle = max(0.0, qte + delta);
      await ex.rawInsert(
          'INSERT INTO stock_produits (nom, quantite_disponible, cout_achat_unitaire) VALUES (?, ?, ?) '
          'ON CONFLICT(nom) DO UPDATE SET quantite_disponible = excluded.quantite_disponible, '
          'cout_achat_unitaire = excluded.cout_achat_unitaire',
          [nom, nouvelle, nouveauCout ?? cout]);
      final licence = await Licence.lireEmail();
      await FileAttente.enfiler(ex, licence, 'stock_produits', 'stock_delta', {
        'p_op': nouvelUid(),
        'p_licence': licence,
        'p_nom': nom,
        'p_delta': delta,
        'p_cout': nouveauCout,
      });
    } catch (_) {}
  }

  /// Ajoute un produit au catalogue. false si le nom existe déjà ou est vide.
  static Future<bool> ajouterProduit(String nom, String unite) async {
    nom = nom.trim();
    if (nom.isEmpty) return false;
    try {
      return await BaseLocale.db.transaction((txn) async {
        final e = await txn.rawQuery('SELECT 1 FROM catalogue_produits WHERE nom = ?', [nom]);
        if (e.isNotEmpty) return false;
        await txn.rawInsert('INSERT INTO catalogue_produits (nom, unite) VALUES (?, ?)', [nom, unite]);
        await txn.rawInsert(
            'INSERT OR IGNORE INTO stock_produits (nom, quantite_disponible, cout_achat_unitaire) VALUES (?, 0, 0)', [nom]);
        final licence = await Licence.lireEmail();
        await FileAttente.enfiler(txn, licence, 'catalogue_produits', 'upsert',
            {'licence': licence, 'nom': nom, 'unite': unite});
        await FileAttente.enfiler(txn, licence, 'stock_produits', 'stock_init',
            {'p_licence': licence, 'p_nom': nom, 'p_qte': 0.0, 'p_cout': 0.0});
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  /// Ajoute un produit au catalogue à l'intérieur d'une transaction déjà ouverte.
  static Future<void> ajouterDansTransaction(DatabaseExecutor txn, String nom, String unite) async {
    await txn.rawInsert('INSERT INTO catalogue_produits (nom, unite) VALUES (?, ?)', [nom, unite]);
    await txn.rawInsert('INSERT OR IGNORE INTO stock_produits (nom, quantite_disponible, cout_achat_unitaire) VALUES (?, 0, 0)', [nom]);
    final licence = await Licence.lireEmail();
    await FileAttente.enfiler(txn, licence, 'catalogue_produits', 'upsert', {'licence': licence, 'nom': nom, 'unite': unite});
    await FileAttente.enfiler(txn, licence, 'stock_produits', 'stock_init',
        {'p_licence': licence, 'p_nom': nom, 'p_qte': 0.0, 'p_cout': 0.0});
  }

  static Future<bool> supprimerProduit(String nom) async {
    nom = nom.trim();
    if (nom.isEmpty) return false;
    try {
      await BaseLocale.db.transaction((txn) async {
        await txn.rawDelete('DELETE FROM catalogue_produits WHERE nom = ?', [nom]);
        await txn.rawDelete('DELETE FROM stock_produits WHERE nom = ?', [nom]);
        final licence = await Licence.lireEmail();
        await FileAttente.enfiler(txn, licence, 'catalogue_produits', 'delete', {'licence': licence, 'nom': nom});
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/constantes.dart';

/// La base de données locale (SQLite). Mêmes tables et mêmes noms de colonnes que le logiciel
/// Python : une base existante sera donc reconnue sans rien perdre.
class BaseLocale {
  BaseLocale._();

  static Database? _db;
  static String _nomFichierActif = nomBaseEssai;
  static Database get db => _db!;

  /// L'e-mail du client est gardé en mémoire : il est demandé à l'intérieur de beaucoup d'écritures,
  /// et relire la base à ce moment-là bloquerait tout (le logiciel resterait figé sur un écran blanc).
  static String? emailEnMemoire;

  static String dossierUtilisateur() =>
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

  static String cheminDe(String nomFichier) => p.join(dossierUtilisateur(), nomFichier);

  /// Ouvre la base (la crée si elle n'existe pas) et s'assure que toutes les tables sont là.
  static Future<void> ouvrir({String nomFichier = nomBaseEssai}) async {
    _nomFichierActif = nomFichier;
    emailEnMemoire = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _db = await databaseFactory.openDatabase(
      cheminDe(nomFichier),
      options: OpenDatabaseOptions(onConfigure: (d) async {
        await d.rawQuery('PRAGMA journal_mode=WAL'); // écritures rapides et sûres
        await d.execute('PRAGMA synchronous=NORMAL');
      }),
    );
    await _creerTables(_db!);
    try {
      await _creerJournal(_db!);
    } catch (_) {
      // le journal est un « plus » : s'il ne peut pas être créé, le logiciel fonctionne quand même
    }
    try {
      await _creerCompteurs(_db!);
    } catch (_) {
      // sans compteur, la lecture des ventes se fait simplement à chaque fois (plus lent, mais juste)
    }
    try {
      final l = await _db!.rawQuery('SELECT email FROM identite_utilisateur WHERE id = 1');
      emailEnMemoire = l.isEmpty ? '' : ('${l.first['email'] ?? ''}').trim().toLowerCase();
    } catch (_) {
      emailEnMemoire = '';
    }
  }

  // ------------------------------------------------------------------ plusieurs fermes sur un même PC
  static String dossierFermes() => p.join(dossierUtilisateur(), 'antoine_fermes');

  /// Fichier où la ferme d'une adresse e-mail est mise de côté (jamais supprimée).
  static Future<String> fichierFermeArchivee(String email) async {
    final h = await Sha256().hash(utf8.encode(email.trim().toLowerCase()));
    final hex = h.bytes.map((o) => o.toRadixString(16).padLeft(2, '0')).join().substring(0, 12);
    return p.join(dossierFermes(), 'ferme_$hex.db');
  }

  /// Nom de la ferme enregistrée dans un fichier de base (lecture seule), '' si illisible.
  static Future<String> nomFermeDans(String fichier) async {
    try {
      final d = await databaseFactory.openDatabase(fichier, options: OpenDatabaseOptions(readOnly: true));
      try {
        final l = await d.rawQuery("SELECT valeur FROM parametres WHERE cle = 'nom_ferme'");
        return l.isEmpty ? '' : ('${l.first['valeur'] ?? ''}').trim();
      } finally {
        await d.close();
      }
    } catch (_) {
      return '';
    }
  }

  static Future<void> _deplacer(String source, String cible) async {
    for (final suffixe in ['', '-wal', '-shm']) {
      final f = File(source + suffixe);
      if (await f.exists()) await f.rename(cible + suffixe);
    }
  }

  /// Met la ferme actuelle de côté (sans rien supprimer), puis ouvre une base vierge — ou celle déjà archivée
  /// pour [nouvelEmail] si [retrouver]. Renvoie true si la nouvelle base est ouverte.
  static Future<bool> basculerFerme(String? ancienProprietaire, String nouvelEmail, {required bool retrouver}) async {
    await Directory(dossierFermes()).create(recursive: true);
    try {
      await _db?.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await fermer();
    final actif = cheminDe(_nomFichierActif);
    final archiveAncien = await fichierFermeArchivee((ancienProprietaire ?? '').isEmpty ? 'inconnu' : ancienProprietaire!);
    final archiveNouveau = await fichierFermeArchivee(nouvelEmail);
    try {
      if (await File(archiveAncien).exists()) {
        final n = DateTime.now();
        String d(int v) => v.toString().padLeft(2, '0');
        await _deplacer(archiveAncien,
            '${archiveAncien.substring(0, archiveAncien.length - 3)}_${n.year}${d(n.month)}${d(n.day)}_${d(n.hour)}${d(n.minute)}${d(n.second)}.db');
      }
      await _deplacer(actif, archiveAncien);
      if (retrouver && await File(archiveNouveau).exists()) await _deplacer(archiveNouveau, actif);
    } catch (_) {}
    try {
      await ouvrir(nomFichier: _nomFichierActif);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fermes déjà utilisées sur ce PC et mises de côté : (chemin du fichier, nom de la ferme, date de dernière modification).
  /// Les bases vides (sans nom de ferme) sont ignorées.
  static Future<List<(String, String, DateTime)>> fermesDejaSurCePc() async {
    final out = <(String, String, DateTime)>[];
    try {
      final dossier = Directory(dossierFermes());
      if (!await dossier.exists()) return out;
      await for (final f in dossier.list()) {
        if (f is! File || !f.path.toLowerCase().endsWith('.db')) continue;
        final nom = await nomFermeDans(f.path);
        if (nom.isEmpty) continue;
        out.add((f.path, nom, await f.lastModified()));
      }
      out.sort((a, b) => b.$3.compareTo(a.$3));
    } catch (_) {}
    return out;
  }

  /// Reprend une ferme mise de côté : la base actuelle (vierge) est rangée sans rien supprimer,
  /// puis la ferme choisie devient la base active. Renvoie true si elle est ouverte.
  static Future<bool> reprendreFerme(String fichierArchive) async {
    await Directory(dossierFermes()).create(recursive: true);
    try {
      await _db?.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await fermer();
    final actif = cheminDe(_nomFichierActif);
    try {
      final n = DateTime.now();
      String d(int v) => v.toString().padLeft(2, '0');
      final rangee = p.join(dossierFermes(), 'base_vierge_${n.year}${d(n.month)}${d(n.day)}_${d(n.hour)}${d(n.minute)}${d(n.second)}.db');
      await _deplacer(actif, rangee);
      await _deplacer(fichierArchive, actif);
    } catch (_) {}
    try {
      await ouvrir(nomFichier: _nomFichierActif);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> fermer() async {
    await _db?.close();
    _db = null;
  }

  static Future<List<String>> listerTables() async {
    final lignes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
    return lignes.map((l) => l['name'] as String).toList();
  }

  static Future<void> _creerTables(Database d) async {
    final batch = d.batch();
    for (final requete in _requetes) {
      batch.execute(requete);
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------- journal des modifications
  // SQLite lui-même note chaque ajout / modification / suppression importante (ventes, arrivages, produits, bandes),
  // quel que soit l'écran qui l'a provoquée : impossible à oublier. La session (Patron / Ouvrier) vient du réglage
  // « ctx_session » ; un changement reçu de l'autre PC est noté « Autre PC ».
  static const _qui = "CASE WHEN IFNULL((SELECT valeur FROM parametres WHERE cle='ctx_ecriture'),'')='pull_cloud' "
      "THEN 'Autre PC' ELSE IFNULL((SELECT valeur FROM parametres WHERE cle='ctx_session'),'') END";
  static const _pasRecu = "IFNULL((SELECT valeur FROM parametres WHERE cle='ctx_ecriture'),'')!='pull_cloud'";

  static String _fmtVente(String x) =>
      "$x.date||' | qté '||printf('%g',$x.qte)||' × '||printf('%.0f',$x.pu)||' F = '||printf('%.0f',$x.total)||' F | '"
      "||IFNULL($x.reglement,'')"
      "||CASE WHEN IFNULL($x.client,'')!='' THEN ' ('||$x.client||')' ELSE '' END"
      "||CASE WHEN IFNULL($x.montant_regle,0)>0 THEN ' | réglé '||printf('%.0f',$x.montant_regle)||' F' ELSE '' END"
      "||CASE WHEN $x.statut='Clôturé' THEN ' | figée' ELSE '' END";

  static String _fmtArrivage(String x) =>
      "$x.date||' | '||printf('%g',IFNULL($x.quantite_ajoutee,0))||' ajoutés | total '||printf('%.0f',IFNULL($x.prix_achat_total,0))||' F'"
      "||CASE WHEN IFNULL($x.fournisseur,'')!='' THEN ' | '||$x.fournisseur ELSE '' END"
      "||' | '||IFNULL($x.reglement,'')"
      "||CASE WHEN IFNULL($x.montant_regle,0)>0 THEN ' | réglé '||printf('%.0f',$x.montant_regle)||' F' ELSE '' END";

  static String _ecrit(String categorie, String action, String objet, String ancien, String nouveau) =>
      "INSERT INTO journal_modifications (quand, session, categorie, action, objet, ancien, nouveau) "
      "VALUES (datetime('now','localtime'), $_qui, '$categorie', '$action', $objet, $ancien, $nouveau)";

  /// Un compteur qui augmente à CHAQUE changement du tableau des ventes (ajout, modification, suppression,
  /// y compris ceux qui viennent de l'autre PC). Il permet de ne relire toutes les ventes que si quelque chose a changé.
  static Future<void> _creerCompteurs(Database d) async {
    final b = d.batch();
    b.execute('CREATE TABLE IF NOT EXISTS compteurs_changements (nom TEXT PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0)');
    b.execute("INSERT OR IGNORE INTO compteurs_changements (nom, n) VALUES ('ventes', 0)");
    for (final (suffixe, evenement) in [('i', 'INSERT'), ('u', 'UPDATE'), ('d', 'DELETE')]) {
      b.execute("CREATE TRIGGER IF NOT EXISTS trg_cpt_ventes_$suffixe AFTER $evenement ON ventes BEGIN "
          "UPDATE compteurs_changements SET n = n + 1 WHERE nom = 'ventes'; END");
    }
    await b.commit(noResult: true);
  }

  static Future<void> _creerJournal(Database d) async {
    final b = d.batch();
    b.execute('''CREATE TABLE IF NOT EXISTS journal_modifications (
         id INTEGER PRIMARY KEY AUTOINCREMENT, quand TEXT, session TEXT, categorie TEXT, action TEXT,
         objet TEXT, ancien TEXT, nouveau TEXT)''');
    b.execute('CREATE INDEX IF NOT EXISTS idx_journal_quand ON journal_modifications(quand)');

    // --- Ventes
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_ventes_ins AFTER INSERT ON ventes WHEN $_pasRecu BEGIN
         ${_ecrit('Ventes', 'AJOUT', 'NEW.type', "''", _fmtVente('NEW'))}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_ventes_maj AFTER UPDATE ON ventes
         WHEN OLD.date IS NOT NEW.date OR OLD.type IS NOT NEW.type OR OLD.qte IS NOT NEW.qte OR OLD.pu IS NOT NEW.pu
           OR OLD.total IS NOT NEW.total OR OLD.reglement IS NOT NEW.reglement OR OLD.client IS NOT NEW.client
           OR OLD.statut IS NOT NEW.statut OR OLD.montant_regle IS NOT NEW.montant_regle BEGIN
         ${_ecrit('Ventes', 'MODIFIÉ', 'NEW.type', _fmtVente('OLD'), _fmtVente('NEW'))}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_ventes_sup AFTER DELETE ON ventes BEGIN
         ${_ecrit('Ventes', 'SUPPRIMÉ', 'OLD.type', _fmtVente('OLD'), "''")}; END''');

    // --- Arrivages de stock
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_arriv_ins AFTER INSERT ON stocks_arrivages WHEN $_pasRecu BEGIN
         ${_ecrit('Arrivages', 'AJOUT', 'NEW.produit', "''", _fmtArrivage('NEW'))}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_arriv_maj AFTER UPDATE ON stocks_arrivages
         WHEN OLD.prix_achat_total IS NOT NEW.prix_achat_total OR OLD.montant_regle IS NOT NEW.montant_regle
           OR OLD.reglement IS NOT NEW.reglement OR OLD.statut IS NOT NEW.statut
           OR OLD.quantite_ajoutee IS NOT NEW.quantite_ajoutee OR OLD.fournisseur IS NOT NEW.fournisseur BEGIN
         ${_ecrit('Arrivages', 'MODIFIÉ', 'NEW.produit', _fmtArrivage('OLD'), _fmtArrivage('NEW'))}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_arriv_sup AFTER DELETE ON stocks_arrivages BEGIN
         ${_ecrit('Arrivages', 'SUPPRIMÉ', 'OLD.produit', _fmtArrivage('OLD'), "''")}; END''');

    // --- Catalogue de produits
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_cat_ins AFTER INSERT ON catalogue_produits WHEN $_pasRecu BEGIN
         ${_ecrit('Catalogue', 'AJOUT', 'NEW.nom', "''", "'Produit ajouté (unité : '||IFNULL(NEW.unite,'')||')'")}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_cat_sup AFTER DELETE ON catalogue_produits BEGIN
         ${_ecrit('Catalogue', 'SUPPRIMÉ', 'OLD.nom', "'Produit du catalogue'", "''")}; END''');

    // --- Bandes d'élevage (création et suppression seulement : les mises à jour quotidiennes feraient trop de bruit)
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_bande_ins AFTER INSERT ON bandes_elevage WHEN $_pasRecu BEGIN
         ${_ecrit('Bandes', 'AJOUT', 'NEW.nom', "''", "IFNULL(NEW.type_elevage,'')||' | '||IFNULL(NEW.effectif_initial,0)||' sujets'")}; END''');
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_bande_sup AFTER DELETE ON bandes_elevage BEGIN
         ${_ecrit('Bandes', 'SUPPRIMÉ', 'OLD.nom', "IFNULL(OLD.type_elevage,'')||' | '||IFNULL(OLD.effectif_actuel,0)||' sujets'", "''")}; END''');

    // --- Sécurité : changement de code PIN ou d'accès de l'Ouvrier (les valeurs ne sont jamais écrites)
    b.execute('''CREATE TRIGGER IF NOT EXISTS trg_jrn_param_ins AFTER INSERT ON parametres
         WHEN NEW.cle IN ('pin_patron','pin_ouvrier','acces_module3_ouvrier') BEGIN
         ${_ecrit('Sécurité', 'MODIFIÉ', "CASE NEW.cle WHEN 'pin_patron' THEN 'Code PIN du Patron' WHEN 'pin_ouvrier' THEN 'Code PIN de l''Ouvrier' ELSE 'Accès de l''Ouvrier à Élevage' END", "''", "CASE NEW.cle WHEN 'acces_module3_ouvrier' THEN CASE NEW.valeur WHEN '1' THEN 'autorisé' ELSE 'révoqué' END ELSE 'nouveau code enregistré' END")}; END''');

    // La session en cours n'est connue qu'après la saisie du PIN.
    b.execute("INSERT OR REPLACE INTO parametres (cle, valeur) VALUES ('ctx_session', '')");
    // On garde deux ans d'historique.
    b.execute("DELETE FROM journal_modifications WHERE quand < datetime('now','localtime','-730 days')");
    await b.commit(noResult: true);
  }

  // ---------------------------------------------------------------- les tables
  static const List<String> _requetes = [
    // Réglages (clé / valeur)
    '''CREATE TABLE IF NOT EXISTS parametres (cle TEXT PRIMARY KEY, valeur TEXT)''',

    // Ventes
    '''CREATE TABLE IF NOT EXISTS ventes (
         id INTEGER PRIMARY KEY AUTOINCREMENT, ligne INTEGER, date TEXT, type TEXT, qte REAL,
         pu REAL, total REAL, reglement TEXT, client TEXT, statut TEXT,
         montant_regle REAL DEFAULT 0, cout_achat REAL DEFAULT 0, uid TEXT)''',
    'CREATE INDEX IF NOT EXISTS idx_ventes_date ON ventes(date)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_ventes_uid ON ventes(uid)',

    // Catalogue et stock
    '''CREATE TABLE IF NOT EXISTS catalogue_produits (
         id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT UNIQUE, unite TEXT)''',
    '''CREATE TABLE IF NOT EXISTS stock_produits (
         nom TEXT PRIMARY KEY, quantite_disponible REAL DEFAULT 0, cout_achat_unitaire REAL DEFAULT 0)''',

    // Arrivages
    '''CREATE TABLE IF NOT EXISTS stocks_arrivages (
         id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, produit TEXT, unite TEXT,
         quantite_saisie REAL, poids_sac REAL, prix_achat_total REAL, cout_unitaire REAL,
         quantite_ajoutee REAL, reglement TEXT DEFAULT 'Espèces', fournisseur TEXT DEFAULT '',
         alveoles_bonus REAL DEFAULT 0, montant_regle REAL DEFAULT 0, statut TEXT DEFAULT 'Actif',
         uid TEXT)''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_stocks_arrivages_uid ON stocks_arrivages(uid)',

    // File d'attente d'envoi vers le cloud
    '''CREATE TABLE IF NOT EXISTS file_attente_cloud (
         id INTEGER PRIMARY KEY AUTOINCREMENT, licence TEXT, table_cible TEXT, operation TEXT,
         payload TEXT, cree_le TEXT, tentatives INTEGER DEFAULT 0)''',

    // Licence
    '''CREATE TABLE IF NOT EXISTS identite_utilisateur (
         id INTEGER PRIMARY KEY CHECK (id = 1), email TEXT)''',
    '''CREATE TABLE IF NOT EXISTS cache_licence_securise (
         id INTEGER PRIMARY KEY CHECK (id = 1), expiration TEXT, derniere_verif TEXT, signature TEXT)''',

    // Bilans « Marge & Bénéfice Boss »
    '''CREATE TABLE IF NOT EXISTS bilans_financiers_locaux (
         id INTEGER PRIMARY KEY AUTOINCREMENT, date_archivage TEXT, periode TEXT,
         chiffre_affaires REAL, charge_electricite REAL, charge_transport REAL,
         charge_salaires REAL, charge_divers REAL, total_charges REAL, net_poche_boss REAL,
         marge_nette_pct REAL, envoye_supabase INTEGER DEFAULT 0)''',

    // Élevage : bandes
    '''CREATE TABLE IF NOT EXISTS bandes_elevage (
         id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT UNIQUE, nom TEXT, batiment TEXT,
         type_elevage TEXT, stade_biologique TEXT DEFAULT '', bascule_effectuee INTEGER DEFAULT 0,
         date_creation TEXT, date_arrivee TEXT, effectif_initial INTEGER DEFAULT 0,
         effectif_actuel INTEGER DEFAULT 0, morts_cumulees INTEGER DEFAULT 0,
         oeufs_cumules INTEGER DEFAULT 0, alveoles_cumulees REAL DEFAULT 0,
         cout_investissement_initial REAL DEFAULT 0, cout_initial_poussins REAL DEFAULT 0,
         cout_direct_cumule REAL DEFAULT 0, cout_direct_cumule_ponte REAL DEFAULT 0,
         cout_aliment REAL DEFAULT 0, cout_sante_cumule REAL DEFAULT 0,
         statut TEXT DEFAULT 'En élevage', date_maturite_commerciale TEXT DEFAULT '',
         date_mise_en_vente TEXT DEFAULT '', date_epuisement TEXT DEFAULT '',
         cout_unitaire_fige REAL DEFAULT 0, produit_stock_nom TEXT DEFAULT '',
         date_derniere_imputation TEXT DEFAULT '', cout_amortissement_cumule REAL DEFAULT 0,
         frais_annexes_en_attente REAL DEFAULT 0, prix_kg_aliment REAL DEFAULT 0,
         conso_aliment_kg_cumulee REAL DEFAULT 0, date_reforme TEXT DEFAULT '',
         supprime INTEGER DEFAULT 0)''',
    '''CREATE TABLE IF NOT EXISTS journal_ponte_jour (
         id INTEGER PRIMARY KEY AUTOINCREMENT, bande_uid TEXT, jour TEXT, vivants INTEGER DEFAULT 0,
         saisi INTEGER DEFAULT 0, conso_kg REAL DEFAULT 0, prix_kg REAL DEFAULT 0,
         cout_aliment REAL DEFAULT 0, amortissement REAL DEFAULT 0, annexes REAL DEFAULT 0,
         alveoles REAL DEFAULT 0, UNIQUE (bande_uid, jour))''',
    '''CREATE TABLE IF NOT EXISTS rappels_veterinaires (
         id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT UNIQUE, bande_uid TEXT, date_prevue TEXT,
         tache TEXT, recurrent TEXT DEFAULT '', statut TEXT DEFAULT 'À faire',
         fait_le TEXT DEFAULT '', fait_par TEXT DEFAULT '')''',
    'CREATE INDEX IF NOT EXISTS idx_rappels_bande ON rappels_veterinaires(bande_uid)',
    'CREATE INDEX IF NOT EXISTS idx_rappels_date ON rappels_veterinaires(date_prevue)',
    '''CREATE TABLE IF NOT EXISTS journal_bande_evenements (
         id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT UNIQUE, bande_uid TEXT, date TEXT,
         morts INTEGER DEFAULT 0, oeufs INTEGER DEFAULT 0, alveoles REAL DEFAULT 0,
         taux_ponte REAL DEFAULT 0, note TEXT DEFAULT '')''',

    // Boîte noire des dettes fournisseurs (noté par SQLite lui-même, impossible à oublier)
    '''CREATE TABLE IF NOT EXISTS audit_arrivages (
         id INTEGER PRIMARY KEY AUTOINCREMENT, quand TEXT, uid TEXT, fournisseur TEXT,
         produit TEXT, evenement TEXT, ancien TEXT, nouveau TEXT, source TEXT)''',
    '''CREATE TRIGGER IF NOT EXISTS trg_audit_arrivages_maj
       AFTER UPDATE OF montant_regle, reglement, statut, prix_achat_total ON stocks_arrivages
       WHEN OLD.montant_regle IS NOT NEW.montant_regle OR OLD.reglement IS NOT NEW.reglement
            OR OLD.statut IS NOT NEW.statut OR OLD.prix_achat_total IS NOT NEW.prix_achat_total
       BEGIN
         INSERT INTO audit_arrivages (quand, uid, fournisseur, produit, evenement, ancien, nouveau, source)
         VALUES (datetime('now','localtime'), NEW.uid, NEW.fournisseur, NEW.produit, 'MODIFIÉ',
                 'réglé=' || IFNULL(OLD.montant_regle,'') || ' prix=' || IFNULL(OLD.prix_achat_total,'')
                   || ' mode=' || IFNULL(OLD.reglement,'') || ' statut=' || IFNULL(OLD.statut,''),
                 'réglé=' || IFNULL(NEW.montant_regle,'') || ' prix=' || IFNULL(NEW.prix_achat_total,'')
                   || ' mode=' || IFNULL(NEW.reglement,'') || ' statut=' || IFNULL(NEW.statut,''),
                 IFNULL((SELECT valeur FROM parametres WHERE cle = 'ctx_ecriture'), 'local'));
       END''',
    '''CREATE TRIGGER IF NOT EXISTS trg_audit_arrivages_sup
       AFTER DELETE ON stocks_arrivages
       BEGIN
         INSERT INTO audit_arrivages (quand, uid, fournisseur, produit, evenement, ancien, nouveau, source)
         VALUES (datetime('now','localtime'), OLD.uid, OLD.fournisseur, OLD.produit, 'SUPPRIMÉ',
                 'réglé=' || IFNULL(OLD.montant_regle,'') || ' prix=' || IFNULL(OLD.prix_achat_total,'')
                   || ' mode=' || IFNULL(OLD.reglement,''), '',
                 IFNULL((SELECT valeur FROM parametres WHERE cle = 'ctx_ecriture'), 'local'));
       END''',
  ];
}

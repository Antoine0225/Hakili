import '../session.dart';
import 'base_locale.dart';
import 'parametres.dart';

class EntreeJournal {
  final int id;
  final String quand, session, categorie, action, objet, ancien, nouveau;
  const EntreeJournal(this.id, this.quand, this.session, this.categorie, this.action, this.objet, this.ancien, this.nouveau);

  factory EntreeJournal.depuisLigne(Map<String, Object?> r) => EntreeJournal(
        (r['id'] as int?) ?? 0,
        '${r['quand'] ?? ''}',
        '${r['session'] ?? ''}',
        '${r['categorie'] ?? ''}',
        '${r['action'] ?? ''}',
        '${r['objet'] ?? ''}',
        '${r['ancien'] ?? ''}',
        '${r['nouveau'] ?? ''}',
      );

  /// « 2026-10-11 18:42:10 » → « 11/10/2026 18:42 ».
  String get quandAffiche {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})').firstMatch(quand);
    return m == null ? quand : '${m[3]}/${m[2]}/${m[1]} ${m[4]}:${m[5]}';
  }
}

class BilanJournal {
  final int ajouts, modifications, suppressions, autres;
  const BilanJournal(this.ajouts, this.modifications, this.suppressions, this.autres);
  int get total => ajouts + modifications + suppressions + autres;
}

/// Le journal des modifications. Les ajouts, modifications et suppressions des ventes, arrivages, produits et bandes
/// sont notés automatiquement par la base de données (voir BaseLocale). Ici : les événements notés par le logiciel
/// (connexions, codes PIN faux), la lecture et le suivi de ce que le Patron a déjà vu.
class JournalRepo {
  JournalRepo._();

  static const _cleVu = 'journal_dernier_vu';

  /// Note un événement qui n'est pas une écriture de table (connexion, mauvais code PIN, changement de session).
  static Future<void> noter(String categorie, String action, String objet, {String ancien = '', String nouveau = ''}) async {
    try {
      await BaseLocale.db.rawInsert(
          "INSERT INTO journal_modifications (quand, session, categorie, action, objet, ancien, nouveau) "
          "VALUES (datetime('now','localtime'), ?, ?, ?, ?, ?, ?)",
          [Session.role, categorie, action, objet, ancien, nouveau]);
    } catch (_) {
      // le journal ne doit jamais empêcher le logiciel de travailler
    }
  }

  static Future<List<EntreeJournal>> lire({DateTime? depuis, String? categorie, String? session, bool sansAjouts = false, int limite = 600}) async {
    try {
      final ou = <String>[];
      final args = <Object?>[];
      if (depuis != null) {
        ou.add('quand >= ?');
        args.add('${depuis.year.toString().padLeft(4, '0')}-${depuis.month.toString().padLeft(2, '0')}-${depuis.day.toString().padLeft(2, '0')} 00:00:00');
      }
      if (categorie != null) {
        ou.add('categorie = ?');
        args.add(categorie);
      }
      if (session != null) {
        ou.add('session = ?');
        args.add(session);
      }
      if (sansAjouts) ou.add("action != 'AJOUT'");
      final l = await BaseLocale.db.rawQuery(
          'SELECT * FROM journal_modifications ${ou.isEmpty ? '' : 'WHERE ${ou.join(' AND ')}'} ORDER BY id DESC LIMIT ?',
          [...args, limite]);
      return l.map(EntreeJournal.depuisLigne).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<BilanJournal> bilan({DateTime? depuis}) async {
    try {
      final args = <Object?>[];
      var ou = '';
      if (depuis != null) {
        ou = 'WHERE quand >= ?';
        args.add('${depuis.year.toString().padLeft(4, '0')}-${depuis.month.toString().padLeft(2, '0')}-${depuis.day.toString().padLeft(2, '0')} 00:00:00');
      }
      final l = await BaseLocale.db.rawQuery('SELECT action, COUNT(*) AS n FROM journal_modifications $ou GROUP BY action', args);
      var a = 0, m = 0, s = 0, o = 0;
      for (final r in l) {
        final n = (r['n'] as int?) ?? 0;
        switch ('${r['action']}') {
          case 'AJOUT':
            a += n;
          case 'MODIFIÉ':
            m += n;
          case 'SUPPRIMÉ':
            s += n;
          default:
            o += n;
        }
      }
      return BilanJournal(a, m, s, o);
    } catch (_) {
      return const BilanJournal(0, 0, 0, 0);
    }
  }

  static Future<int> dernierVu() async => int.tryParse(await Parametres.lire(_cleVu, defaut: '0')) ?? 0;

  /// Le Patron vient de consulter le journal : tout ce qui existe maintenant est « vu ».
  static Future<void> marquerVu() async {
    try {
      final l = await BaseLocale.db.rawQuery('SELECT MAX(id) AS m FROM journal_modifications');
      final m = (l.first['m'] as int?) ?? 0;
      await Parametres.ecrire(_cleVu, '$m');
    } catch (_) {}
  }

  /// Ce que le Patron n'a pas encore vu et qui mérite un coup d'œil : modifications, suppressions,
  /// codes PIN faux, faits par l'Ouvrier ou venant de l'autre PC.
  static Future<int> compterAVerifier() async {
    try {
      final vu = await dernierVu();
      final l = await BaseLocale.db.rawQuery(
          "SELECT COUNT(*) AS n FROM journal_modifications WHERE id > ? "
          "AND ((action IN ('MODIFIÉ','SUPPRIMÉ') AND session IN ('Ouvrier','Autre PC')) OR action IN ('ÉCHEC','ÉCART'))",
          [vu]);
      return (l.first['n'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

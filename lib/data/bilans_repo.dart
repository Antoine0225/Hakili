import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constantes.dart';
import '../securite/jeton_cloud.dart';
import '../securite/licence_locale.dart';
import '../utilitaires/formats.dart';
import 'base_locale.dart';

/// Le bilan « Marge & Bénéfice du Boss » calculé à l'écran.
class BilanMarge {
  final double ca, elec, transport, salaires, divers, totalCharges, netPoche, margePct;
  final String periode;
  final bool revenuModifie;
  final dynamic detailCaisse; // RevenuCaisse ou null si le revenu a été ajusté à la main
  const BilanMarge({
    required this.ca, required this.elec, required this.transport, required this.salaires, required this.divers,
    required this.totalCharges, required this.netPoche, required this.margePct, required this.periode,
    required this.revenuModifie, required this.detailCaisse,
  });
}

class BilanArchive {
  final String dateArchivage, periode;
  final double ca, totalCharges, net, margePct;
  final bool envoye;
  const BilanArchive(this.dateArchivage, this.periode, this.ca, this.totalCharges, this.net, this.margePct, this.envoye);
}

class BilansRepo {
  BilansRepo._();

  static Future<List<BilanArchive>> archives() async {
    try {
      final l = await BaseLocale.db.rawQuery(
          'SELECT date_archivage, periode, chiffre_affaires, total_charges, net_poche_boss, marge_nette_pct, envoye_supabase '
          'FROM bilans_financiers_locaux ORDER BY id DESC');
      double d(Object? v) => v is num ? v.toDouble() : 0.0;
      return [
        for (final r in l)
          BilanArchive('${r['date_archivage']}', '${r['periode']}', d(r['chiffre_affaires']), d(r['total_charges']),
              d(r['net_poche_boss']), d(r['marge_nette_pct']), r['envoye_supabase'] == 1)
      ];
    } catch (_) {
      return [];
    }
  }

  /// Enregistre le bilan sur ce PC, puis tente de l'envoyer au Cloud. Renvoie 'cloud', 'local' (envoi échoué)
  /// ou 'erreur:<détail>' si même l'écriture locale a échoué.
  static Future<String> archiver(BilanMarge b) async {
    final n = DateTime.now();
    final date = '${jourEnTexte(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    int idLocal;
    try {
      idLocal = await BaseLocale.db.rawInsert(
          'INSERT INTO bilans_financiers_locaux (date_archivage, periode, chiffre_affaires, charge_electricite, '
          'charge_transport, charge_salaires, charge_divers, total_charges, net_poche_boss, marge_nette_pct, envoye_supabase) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
          [date, b.periode, b.ca, b.elec, b.transport, b.salaires, b.divers, b.totalCharges, b.netPoche, b.margePct]);
    } catch (e) {
      return 'erreur:$e';
    }
    try {
      final email = await Licence.lireEmail();
      final jeton = JetonCloud.lire(email);
      final rep = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/bilans_financiers'),
            headers: {
              'apikey': supabaseCle,
              'Authorization': 'Bearer ${jeton.isEmpty ? supabaseCle : jeton}',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode({
              'licence': email, 'date_archivage': date, 'periode': b.periode, 'chiffre_affaires': b.ca,
              'charge_electricite': b.elec, 'charge_transport': b.transport, 'charge_salaires': b.salaires,
              'charge_divers': b.divers, 'total_charges': b.totalCharges, 'net_poche_boss': b.netPoche,
              'marge_nette_pct': b.margePct,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (rep.statusCode == 200 || rep.statusCode == 201 || rep.statusCode == 204) {
        await BaseLocale.db.rawUpdate('UPDATE bilans_financiers_locaux SET envoye_supabase = 1 WHERE id = ?', [idLocal]);
        return 'cloud';
      }
      return 'local';
    } catch (_) {
      return 'hors_ligne';
    }
  }
}

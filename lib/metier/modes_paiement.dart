import '../data/ventes_repo.dart';
import '../utilitaires/formats.dart';

/// Les deux façons d'encaisser que Hakili compare : les espèces (billets dans la caisse)
/// et l'argent mobile (Orange Money, Moov Money, Wave... : l'argent est sur le téléphone).
class ModesPaiement {
  ModesPaiement._();

  static const especes = 'Espèces';
  static const mobile = 'Mobile Money';
  static const credit = 'À Crédit';

  /// Les deux modes proposés quand de l'argent entre ou sort réellement.
  static const modesEncaissement = [especes, mobile];

  /// 'e' = espèces, 'm' = mobile, 'c' = crédit, 'a' = autre.
  static String famille(String reglement) {
    final r = reglement.toLowerCase().trim();
    if (r.isEmpty || r.contains('esp')) return 'e';
    if (r.contains('cr')) return 'c';
    if (r.contains('mobile') || r.contains('money') || r.contains('orange') || r.contains('moov') ||
        r.contains('wave') || r.contains('sama')) {
      return 'm';
    }
    return 'a';
  }

  /// Argent réellement entré / sorti entre deux dates (comprises).
  /// Une vente à crédit n'est PAS comptée ici : l'argent n'entre que le jour où le client règle sa dette
  /// (ce règlement est une ligne à part, avec son propre mode de paiement).
  static RepartitionModes calculer(List<Vente> ventes, DateTime debut, DateTime fin) {
    final r = RepartitionModes();
    for (final v in ventes) {
      final f = famille(v.reglement);
      if (f == 'c') continue;
      final txt = v.date.trim();
      final dt = lireJma(txt.length >= 10 ? txt.substring(0, 10) : txt);
      if (dt == null) continue;
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d.isBefore(debut) || d.isAfter(fin)) continue;
      if (v.total >= 0) {
        if (f == 'm') {
          r.entreesMobile += v.total;
        } else if (f == 'e') {
          r.entreesEspeces += v.total;
        } else {
          r.entreesAutres += v.total;
        }
        r.nb++;
      } else {
        if (f == 'm') {
          r.sortiesMobile += -v.total;
        } else {
          r.sortiesEspeces += -v.total;
        }
      }
    }
    return r;
  }
}

class RepartitionModes {
  double entreesEspeces = 0, entreesMobile = 0, entreesAutres = 0;
  double sortiesEspeces = 0, sortiesMobile = 0;
  int nb = 0;

  double get entrees => entreesEspeces + entreesMobile + entreesAutres;

  /// Part de l'argent mobile dans les encaissements (0 à 100).
  double get partMobile => entrees > 0.5 ? entreesMobile / entrees * 100 : 0.0;
  double get partEspeces => entrees > 0.5 ? entreesEspeces / entrees * 100 : 0.0;
}

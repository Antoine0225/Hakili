import '../data/parametres.dart';

/// Protège les codes PIN contre les essais en série : après 5 erreurs de suite, la saisie est bloquée
/// quelques instants, et le blocage s'allonge à chaque nouvelle série d'erreurs.
/// Le compteur est écrit dans la base : fermer puis rouvrir le logiciel ne le remet donc pas à zéro.
class LimiteEssaisPin {
  LimiteEssaisPin._();

  /// Nombre d'erreurs de suite autorisées avant le premier blocage.
  static const int erreursAutorisees = 5;

  /// Durées de blocage successives (en secondes) : 30 s, 1 min, 2 min, 5 min, puis 15 min à chaque fois.
  static const List<int> _durees = [30, 60, 120, 300, 900];

  static const _cleEchecs = 'pin_echecs_consecutifs';
  static const _cleBlocage = 'pin_bloque_jusqua';

  /// Secondes à attendre avant de pouvoir réessayer (0 = la saisie est libre).
  static Future<int> secondesRestantes() async {
    final fin = int.tryParse(await Parametres.lire(_cleBlocage)) ?? 0;
    final reste = fin - DateTime.now().millisecondsSinceEpoch;
    if (reste <= 0) return 0;
    // Garde-fou : si l'horloge du PC a été truquée, on ne bloque jamais plus de 15 minutes d'affilée.
    final secondes = (reste / 1000).ceil();
    return secondes > _durees.last ? _durees.last : secondes;
  }

  /// À appeler après un code incorrect. Renvoie le nombre de secondes de blocage décidé (0 = pas encore bloqué).
  static Future<int> enregistrerEchec() async {
    final n = (int.tryParse(await Parametres.lire(_cleEchecs)) ?? 0) + 1;
    await Parametres.ecrire(_cleEchecs, '$n');
    if (n < erreursAutorisees) return 0;
    final rang = n - erreursAutorisees; // 0 pour la 5e erreur, 1 pour la 6e...
    final duree = _durees[rang >= _durees.length ? _durees.length - 1 : rang];
    await Parametres.ecrire(
        _cleBlocage, '${DateTime.now().millisecondsSinceEpoch + duree * 1000}');
    return duree;
  }

  /// À appeler quand le code est bon : tout repart de zéro.
  static Future<void> reussite() async {
    await Parametres.ecrire(_cleEchecs, '0');
    await Parametres.ecrire(_cleBlocage, '0');
  }

  /// Phrase prête à afficher, par exemple « Trop d'essais. Réessayez dans 1 min 30 s. »
  static String message(int secondes) {
    final m = secondes ~/ 60, s = secondes % 60;
    final duree = m > 0 ? (s > 0 ? '$m min $s s' : '$m min') : '$s s';
    return "Trop d'essais. Réessayez dans $duree.";
  }
}

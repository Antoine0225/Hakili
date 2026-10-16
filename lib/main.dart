import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'cloud/service_cloud.dart';
import 'config/constantes.dart';
import 'data/base_locale.dart';
import 'data/journal_repo.dart';
import 'data/parametres.dart';
import 'ecrans/assistant_configuration.dart';
import 'ecrans/coque_principale.dart';
import 'ecrans/ecran_licence.dart';
import 'ecrans/ecran_pin.dart';
import 'ecrans/ecran_verrou.dart';
import 'metier/previsions.dart';
import 'securite/battement_licence.dart';
import 'securite/jeton_cloud.dart';
import 'securite/licence_locale.dart';
import 'securite/pin.dart';
import 'services/diagnostic.dart';
import 'services/meteo.dart';
import 'session.dart';
import 'theme/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Toute erreur inattendue est notée dans donnies_antoine_diagnostic.log (pour le support).
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    Diagnostic.ecrire('ERREUR ÉCRAN : ${d.exceptionAsString()}');
  };

  // Fenêtre : même taille et même titre que le logiciel actuel, fermeture contrôlée.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1366, 820), minimumSize: Size(1180, 720), center: true,
      title: 'Hakili — Système de Gestion Avicole',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await windowManager.setPreventClose(true);
  windowManager.addListener(_EcouteurFermeture());

  // Écran d'attente immédiat : la fenêtre n'est jamais blanche/vide pendant l'ouverture de la base.
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFF14110F),
      body: Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
      ),
    ),
  ));

  try {
    await BaseLocale.ouvrir(nomFichier: utiliserBaseReelle ? nomBaseReelle : nomBaseEssai);
  } catch (e) {
    Diagnostic.ecrire("BASE INACCESSIBLE : $e");
    runApp(_ErreurBase('$e'));
    return;
  }
  Diagnostic.ecrire('Ouverture du logiciel (base : ${utiliserBaseReelle ? nomBaseReelle : nomBaseEssai})');

  await _chargerReglagesDeSession();
  Meteo.demarrer(); // météo en direct, jamais bloquante
  final theme = await Parametres.lire('theme', defaut: 'Dark');

  runApp(HakiliApp(modeInitial: theme == 'Light' ? ThemeMode.light : ThemeMode.dark));
}

/// Relit dans la base le nom de la ferme et les réglages (aussi après un changement de ferme).
Future<void> _chargerReglagesDeSession() async {
  final nom = (await Parametres.lire('nom_ferme')).trim();
  Session.nomFerme = nom.isNotEmpty ? nom : 'ANTOINE SOFTWARE';
  Session.accesModule3Ouvrier = await Parametres.lire('acces_module3_ouvrier', defaut: '0') == '1';
  Session.sacsAlimentEnStock = int.tryParse(await Parametres.lire('stock_aliment_sacs', defaut: '5')) ?? 5;
}

/// Fermeture propre : réglages enregistrés, file d'envoi vidée si possible, base refermée.
class _EcouteurFermeture with WindowListener {
  bool _enCours = false;

  @override
  void onWindowClose() async {
    if (_enCours) return;
    _enCours = true;
    // La fenêtre disparaît tout de suite : le client voit « fermé » aussitôt, le rangement se termine en coulisses.
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await Previsions.sauvegarder();
      BattementLicence.arreter();
      await ServiceCloud.viderFile().timeout(const Duration(seconds: 6), onTimeout: () => (false, 0));
      ServiceCloud.arreter();
      await BaseLocale.fermer();
      Diagnostic.ecrire('Fermeture du logiciel');
    } catch (_) {}
    await windowManager.destroy();
  }
}

/// Affiché si la base de données ne peut pas être ouverte : on ne démarre jamais « à vide ».
class _ErreurBase extends StatelessWidget {
  final String detail;
  const _ErreurBase(this.detail);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🚨', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('Base de données inaccessible', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                      "Le logiciel n'arrive pas à ouvrir votre base de données.\n\nDétail : $detail\n\n"
                      "Vos données ne sont PAS effacées. Fermez toute autre fenêtre Antoine ouverte (Gestionnaire des tâches), "
                      "puis relancez. Si le message revient, envoyez le fichier donnies_antoine_diagnostic.log "
                      '(dossier utilisateur) au support.',
                      textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Les grandes étapes du démarrage : licence d'abord, code PIN ensuite.
enum Etape { controle, verrou, licence, configuration, pin, accueil }

class HakiliApp extends StatefulWidget {
  final ThemeMode modeInitial;
  const HakiliApp({super.key, required this.modeInitial});

  @override
  State<HakiliApp> createState() => _HakiliAppState();
}

class _HakiliAppState extends State<HakiliApp> {
  late ThemeMode _mode = widget.modeInitial;
  Etape _etape = Etape.controle;

  String _messageVerrou = '';
  String _emailLicence = '';
  String _infoLicence = '';

  // 🔒 Verrouillage automatique : après 45 minutes sans toucher au logiciel, le code PIN est redemandé.
  final _cleNavigation = GlobalKey<NavigatorState>();
  Timer? _veille;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_toucheAppuyee);
    _demarrer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_toucheAppuyee);
    _veille?.cancel();
    super.dispose();
  }

  bool _toucheAppuyee(KeyEvent e) {
    _activite();
    return false; // on regarde seulement : la touche continue son chemin normal
  }

  /// Appelé à chaque clic, défilement ou touche : la minuterie repart de zéro.
  void _activite() {
    if (_etape != Etape.accueil) return;
    _veille?.cancel();
    _veille = Timer(const Duration(minutes: verrouInactiviteMinutes), _verrouillerPourInactivite);
  }

  void _verrouillerPourInactivite() {
    if (!mounted || _etape != Etape.accueil) return;
    _cleNavigation.currentState?.popUntil((r) => r.isFirst); // ferme toute fenêtre restée ouverte
    JournalRepo.noter('Sécurité', 'VERROUILLAGE', 'Verrouillage automatique après $verrouInactiviteMinutes min sans activité');
    Session.fermer();
    _aller(Etape.pin);
  }

  void _aller(Etape e) {
    if (!mounted) return;
    setState(() => _etape = e);
    if (e == Etape.accueil) {
      _activite();
    } else {
      _veille?.cancel();
    }
  }

  void _versLicence({String email = '', String info = ''}) {
    _emailLicence = email;
    _infoLicence = info;
    _aller(Etape.licence);
  }

  void _versVerrou(String message) {
    _messageVerrou = message;
    _aller(Etape.verrou);
  }

  /// 1) verrou de sécurité  2) session de licence  3) contrôle (en ligne, sinon hors ligne)
  Future<void> _demarrer() async {
    final (verrouille, messageVerrou) = await Licence.lireVerrou();
    if (verrouille) return _versVerrou(messageVerrou);

    final email = await Licence.lireEmail();
    if (email.isNotEmpty && !await Licence.sessionOuverte()) {
      return _versLicence(
          email: email,
          info: '🔓 Session fermée. Validez votre e-mail pour reprendre votre travail.');
    }

    final r = await Licence.controlerDroits();
    switch (r.issue) {
      case Issue.autorise:
        return _apresLicence();
      case Issue.verrouille:
        return _versVerrou(r.message);
      case Issue.refuse:
        return _versLicence(email: email, info: r.message);
    }
  }

  Future<void> _apresLicence() async {
    await _chargerReglagesDeSession(); // la ferme a pu changer (choix de ferme à l'activation)
    await ServiceCloud.demarrer(await Licence.lireEmail()); // synchronisation en arrière-plan
    BattementLicence.demarrer( // 💓 le serveur reçoit des nouvelles toutes les 30 minutes
      onVerrou: _versVerrou,
      onDeconnexion: (message) => Licence.lireEmail().then((e) => _versLicence(email: e, info: message)),
    );
    final configure = await Pin.configurationTerminee();
    _aller(configure ? Etape.pin : Etape.configuration);
  }

  /// Déconnexion totale : la place du PC est déjà libérée côté serveur. On ferme la session locale
  /// sans toucher aux données, puis on revient à l'écran de licence (e-mail pré-rempli).
  Future<void> _deconnexionTotale() async {
    final email = await Licence.lireEmail();
    await Previsions.sauvegarder();
    BattementLicence.arreter();
    ServiceCloud.arreter();
    JetonCloud.oublier();
    await Licence.marquerSession(false);
    await Licence.effacerCache();
    Session.fermer();
    _versLicence(
        email: email,
        info: '✅ Déconnexion effectuée : la place de ce PC est libérée.\n'
            'Pour reprendre ici plus tard, validez simplement votre e-mail.');
  }

  void _basculerTheme() {
    setState(() => _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
    Parametres.ecrire('theme', _mode == ThemeMode.light ? 'Light' : 'Dark');
  }

  Widget _ecran() {
    switch (_etape) {
      case Etape.controle:
        return const _Chargement(key: ValueKey('controle'));
      case Etape.verrou:
        return EcranVerrou(
          key: const ValueKey('verrou'),
          message: _messageVerrou,
          onAutreAdresse: () => _versLicence(
              info: "🔑 Saisissez une adresse e-mail disposant d'une licence active."),
        );
      case Etape.licence:
        return EcranLicence(
          key: ValueKey('licence-$_emailLicence-$_infoLicence'),
          emailInitial: _emailLicence,
          messageInfo: _infoLicence,
          onActive: _apresLicence,
        );
      case Etape.configuration:
        return AssistantConfiguration(
            key: const ValueKey('config'),
            onTermine: () => _aller(Etape.pin),
            onFermeReprise: () {
              BattementLicence.arreter();
              _apresLicence(); // recharge le nom de la ferme, relance la synchro, puis demande le PIN
            });
      case Etape.pin:
        return EcranPin(key: const ValueKey('pin'), onOuvert: () => _aller(Etape.accueil));
      case Etape.accueil:
        return CoquePrincipale(
          key: const ValueKey('coque'),
          onBasculerTheme: _basculerTheme,
          onDeconnexionTotale: _deconnexionTotale,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hakili — Système de Gestion Avicole',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: construireTheme(Palette.clair, Brightness.light),
      darkTheme: construireTheme(Palette.sombre, Brightness.dark),
      themeMode: _mode,
      scrollBehavior: const _DefilementDoux(),
      navigatorKey: _cleNavigation,
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _activite(),
        onPointerMove: (_) => _activite(),
        onPointerSignal: (_) => _activite(),
        child: child ?? const SizedBox.shrink(),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        child: _ecran(),
      ),
    );
  }
}

/// Écran d'attente pendant la vérification de la licence (au plus quelques secondes).
class _Chargement extends StatelessWidget {
  const _Chargement({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hakili',
                style: TextStyle(fontFamily: policeTitre, fontSize: 40,
                    fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 22),
            SizedBox(
                width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: p.cuivre)),
            const SizedBox(height: 16),
            Text('Vérification de la licence…', style: TextStyle(fontSize: 12, color: p.txtGris)),
          ],
        ),
      ),
    );
  }
}

/// Défilement « iPhone » : léger rebond en fin de liste, et fonctionne aussi au doigt ou au pavé tactile.
class _DefilementDoux extends MaterialScrollBehavior {
  const _DefilementDoux();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

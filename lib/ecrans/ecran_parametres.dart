import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../config/constantes.dart';
import '../data/journal_repo.dart';
import '../data/parametres.dart';
import '../securite/licence_locale.dart';
import '../securite/licence_serveur.dart';
import '../securite/pin.dart';
import '../services/logo_pdf.dart';
import '../services/mise_a_jour.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../widgets/dialogues.dart';
import '../widgets/icones.dart';
import '../widgets/toast.dart';
import 'dialogue_journal.dart';

/// Page « Paramètres » : apparence, session de travail, accès de l'Ouvrier, compte & licence.
class EcranParametres extends StatefulWidget {
  final VoidCallback onBasculerTheme;
  final VoidCallback onRoleChange;
  final Future<void> Function() onDeconnexionTotale;
  const EcranParametres({
    super.key, required this.onBasculerTheme, required this.onRoleChange, required this.onDeconnexionTotale,
  });

  @override
  State<EcranParametres> createState() => _EcranParametresState();
}

class _EcranParametresState extends State<EcranParametres> {
  String _email = '—';
  bool _deconnexionEnCours = false;

  @override
  void initState() {
    super.initState();
    _lireLogo();
    Licence.lireEmail().then((e) {
      if (mounted) setState(() => _email = e.isEmpty ? '—' : e);
    });
  }

  Future<void> _chercherMaj() async {
    final r = await MiseAJour.verifier();
    if (!mounted) return;
    final p = Palette.de(context);
    switch (r) {
      case ResultatRecherche.aJour:
        Toast.afficher(context, '✅ Hakili est à jour.', couleur: p.succes);
      case ResultatRecherche.disponible:
        Toast.afficher(context, '🔔 Une mise à jour est disponible : voyez la pastille en haut à droite.', couleur: p.cuivre, dureeMs: 3200);
      case ResultatRecherche.impossible:
        Toast.afficher(context, '⚠️ Impossible de vérifier (pas de connexion ?).', couleur: p.danger, dureeMs: 3000);
    }
  }

  Widget _section(Palette p, String titre, String sous, String icone, List<Widget> corps) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14, right: 6),
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.bordure)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: p.iconeVert, borderRadius: BorderRadius.circular(10)),
              child: IconeFine(icone, couleur: sombre ? const Color(0xFF4FB37A) : const Color(0xFF3F6B4C), taille: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: TextStyle(fontFamily: policeTitre, fontSize: 17, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                Text(sous, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtDoux)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          ...corps,
        ]),
      ),
    );
  }

  Widget _bouton(String texte, Color fond, Color couleurTexte, VoidCallback? action, {Widget? icone, Color? bordure}) => SizedBox(
        width: 230, height: 40,
        child: FilledButton.icon(
          onPressed: action,
          icon: icone ?? const SizedBox.shrink(),
          label: Text(texte, style: const TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: fond, foregroundColor: couleurTexte,
            side: bordure == null ? null : BorderSide(color: bordure),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  // ------------------------------------------------------------------ logo des PDF
  bool _logoPresent = false;

  Future<void> _lireLogo() async {
    final v = await LogoPdf.existe();
    if (mounted) setState(() => _logoPresent = v);
  }

  Future<void> _choisirLogo() async {
    try {
      final fait = await LogoPdf.choisirEtEnregistrer();
      if (!fait || !mounted) return;
      setState(() => _logoPresent = true);
      Toast.afficher(context, '✅ Logo enregistré : il apparaîtra sur vos prochains PDF');
    } catch (_) {
      if (!mounted) return;
      Dialogues.erreur(context, 'Image illisible', "Ce fichier n'a pas pu être lu. Choisissez une image PNG ou JPG.");
    }
  }

  Future<void> _retirerLogo() async {
    await LogoPdf.retirer();
    if (!mounted) return;
    setState(() => _logoPresent = false);
    Toast.afficher(context, 'Logo retiré');
  }

  // ------------------------------------------------------------------ nom de la ferme
  Future<void> _changerNomFerme() async {
    if (!Session.estPatron) return;
    final nouveau = await showDialog<String>(
      context: context,
      builder: (_) => _DialogueNomFerme(actuel: Session.nomFerme),
    );
    if (nouveau == null || nouveau.isEmpty || nouveau == Session.nomFerme) return;
    final ancien = Session.nomFerme;
    await Parametres.ecrire('nom_ferme', nouveau);
    Session.nomFerme = nouveau;
    await ServiceCloud.nomFermeModifie(); // le nom suivra sur les autres PC
    await JournalRepo.noter('Sécurité', 'MODIFIÉ', 'Nom de la ferme', ancien: ancien, nouveau: nouveau);
    widget.onRoleChange(); // rafraîchit le menu et l'accueil
    if (!mounted) return;
    setState(() {});
    Toast.afficher(context, '✅ Nom de la ferme modifié : $nouveau');
  }

  // ------------------------------------------------------------------ changement de session
  Future<void> _changerSession() async {
    final p = Palette.de(context);
    final c = TextEditingController();
    var erreur = '';
    var enCours = false;
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setL) {
        Future<void> valider() async {
          if (enCours) return;
          setL(() => enCours = true);
          final r = await Pin.identifierRole(c.text.trim());
          if (r == null) {
            JournalRepo.noter('Sécurité', 'ÉCHEC', 'Code PIN incorrect (changement de session)');
            c.clear();
            setL(() {
              erreur = '⚠️  Code PIN non reconnu.';
              enCours = false;
            });
          } else if (ctx.mounted) {
            Navigator.pop(ctx, r);
          }
        }

        return Dialog(
          backgroundColor: p.panneau,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 22, 30, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🔁', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 4),
                Text('CHANGEMENT DE SESSION', style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                const SizedBox(height: 4),
                Text('Session active : ${Session.role}', style: TextStyle(fontSize: 12, color: p.txtDoux)),
                Text('Saisissez le code PIN de la session souhaitée', style: TextStyle(fontSize: 11, color: p.txtGris)),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: c, autofocus: true, obscureText: true, textAlign: TextAlign.center,
                    onSubmitted: (_) => valider(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity, height: 42,
                  child: FilledButton(onPressed: enCours ? null : valider, child: const Text('VALIDER LA SESSION', style: TextStyle(fontWeight: FontWeight.bold))),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), style: TextButton.styleFrom(foregroundColor: p.txtGris), child: const Text('Annuler')),
              ]),
            ),
          ),
        );
      }),
    );
    Future.delayed(const Duration(milliseconds: 600), c.dispose); // après la fermeture animée du dialogue
    if (role == null || !mounted) return;
    final ancienneSession = Session.role;
    Session.role = role;
    JournalRepo.noter('Sécurité', 'SESSION', 'Passage de la session $ancienneSession à la session $role');
    widget.onRoleChange();
    setState(() {});
    await Dialogues.info(context, 'Session modifiée', '✅ Vous travaillez désormais en session $role.');
  }

  // ------------------------------------------------------------------ accès de l'Ouvrier
  Future<void> _basculerAccesOuvrier() async {
    if (!Session.estPatron) return;
    Session.accesModule3Ouvrier = !Session.accesModule3Ouvrier;
    await Parametres.ecrire('acces_module3_ouvrier', Session.accesModule3Ouvrier ? '1' : '0');
    if (!mounted) return;
    Toast.afficher(context, '🐣 Accès Ouvrier à Élevage : ${Session.accesModule3Ouvrier ? 'AUTORISÉ' : 'RÉVOQUÉ'}',
        couleur: Palette.de(context).succes);
    widget.onRoleChange();
    setState(() {});
  }

  // ------------------------------------------------------------------ déconnexion totale
  Future<void> _deconnexion() async {
    final ok = await Dialogues.confirmer(
        context,
        'Déconnexion',
        '🚪 Voulez-vous vraiment vous déconnecter ?\n\n'
            '• La place de ce PC sera libérée sur le serveur : vous pourrez ouvrir le logiciel sur votre autre PC immédiatement.\n'
            '• Vos données (ventes, stocks, réglages) restent enregistrées sur ce PC.\n'
            '• Votre e-mail reste mémorisé : il suffira de le valider pour vous reconnecter.');
    if (!ok || !mounted) return;
    setState(() => _deconnexionEnCours = true);

    final (toutParti, restant) = await ServiceCloud.viderFile();
    if (!toutParti) {
      if (!mounted) return;
      setState(() => _deconnexionEnCours = false);
      final continuer = await Dialogues.confirmer(
          context,
          'Données non synchronisées',
          "📴 $restant ligne(s) de caisse/stock n'ont pas pu être envoyées au Cloud.\n\n"
              'Elles restent en sécurité sur ce PC et partiront dès le prochain démarrage avec Internet, '
              "mais votre autre PC ne les verra pas avant.\n\nSe déconnecter quand même ?");
      if (!continuer || !mounted) return;
      setState(() => _deconnexionEnCours = true);
    }
    final email = await Licence.lireEmail();
    final res = email.isEmpty
        ? const ReponseLicence(reseau: true, code: 'ok')
        : await LicenceServeur.transaction(email, await Licence.pcId(), mode: 'deconnexion');
    if (!res.reseau || res.code == 'conflit') {
      if (!mounted) return;
      setState(() => _deconnexionEnCours = false);
      Dialogues.erreur(
          context,
          'Déconnexion impossible',
          res.message.isNotEmpty
              ? res.message
              : "📡 Pas de connexion Internet : la place de ce PC n'a pas pu être libérée sur le serveur.\n\n"
                  'Activez le partage de connexion de votre téléphone puis réessayez.');
      return;
    }
    await widget.onDeconnexionTotale();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('RÉGLAGES DU LOGICIEL', style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('Paramètres', style: TextStyle(fontFamily: policeTitre, fontSize: 34, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ),
        _section(p, 'Apparence', "Choisissez l'ambiance : Ivoire & Forêt (clair) ou Émeraude & Or (sombre).", 'soleil', [
          _bouton(sombre ? 'Passer en mode clair' : 'Passer en mode sombre', p.cuivre, Colors.white, widget.onBasculerTheme,
              icone: IconeFine(sombre ? 'soleil' : 'lune', couleur: Colors.white, taille: 16)),
        ]),
        _section(p, 'Session de travail', 'Passez du profil Patron au profil Ouvrier avec le code PIN correspondant.', 'utilisateurs', [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Session active :  ${Session.role}', style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          ),
          _bouton('Changer de session', p.panneau2, p.txtPrinc, _changerSession,
              icone: IconeFine('session', couleur: p.txtPrinc, taille: 16), bordure: p.bordure),
        ]),
        if (Session.estPatron)
          _section(p, "Accès de l'Ouvrier", "Autoriser l'Ouvrier à ouvrir « Élevage & Suivi des Bandes ».", 'cadenas', [
            Row(children: [
              Switch(value: Session.accesModule3Ouvrier, activeColor: p.succes, onChanged: (_) => _basculerAccesOuvrier()),
              const SizedBox(width: 8),
              Text("Module Élevage accessible à l'Ouvrier", style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc)),
            ]),
          ]),
        if (Session.estPatron)
          _section(p, 'Nom de la ferme', 'Le nom affiché dans le menu, sur l\'accueil et sur les documents.', 'info', [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(Session.nomFerme, style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            _bouton('✏️ Changer le nom', p.panneau2, p.txtPrinc, _changerNomFerme, bordure: p.bordure),
          ]),
        if (Session.estPatron)
          _section(p, 'Logo pour les documents PDF', 'Votre logo apparaît en haut des PDF (rapports, reçus, dossier banque). Il n\'est affiché nulle part ailleurs.', 'info', [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_logoPresent ? '✅ Logo enregistré' : 'Aucun logo pour le moment',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _bouton(_logoPresent ? '🖼️ Changer le logo' : '🖼️ Choisir un logo', p.cuivre, Colors.white, _choisirLogo),
              if (_logoPresent) _bouton('Retirer le logo', p.panneau2, p.txtPrinc, _retirerLogo, bordure: p.bordure),
            ]),
          ]),
        if (Session.estPatron)
          _section(p, 'Journal des modifications', 'Qui a ajouté, modifié ou supprimé quoi, et quand (ventes, arrivages, produits, bandes).', 'info', [
            _bouton('🔍 Ouvrir le journal', p.cuivre, Colors.white, () => ouvrirJournal(context)),
          ]),
        _section(p, 'Compte & licence', 'Votre licence est liée à cette adresse e-mail.', 'info', [
          Text('E-mail de licence :  $_email', style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc)),
          if (Licence.expiration.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text("Valable jusqu'au :  ${Licence.expiration}", style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtDoux)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Text('Version du logiciel :  $versionLogiciel', style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtDoux)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _bouton('🔄 Rechercher une mise à jour', p.panneau2, p.txtPrinc, _chercherMaj, bordure: p.bordure),
          ),
          _bouton(_deconnexionEnCours ? '⏳ Déconnexion…' : 'Déconnexion', p.danger, Colors.white,
              _deconnexionEnCours ? null : _deconnexion, icone: const IconeFine('deconnexion', couleur: Colors.white, taille: 16)),
        ]),
      ]),
    );
  }
}

/// Petite fenêtre de saisie du nouveau nom (le champ est libéré proprement à la fermeture).
class _DialogueNomFerme extends StatefulWidget {
  final String actuel;
  const _DialogueNomFerme({required this.actuel});

  @override
  State<_DialogueNomFerme> createState() => _DialogueNomFermeState();
}

class _DialogueNomFermeState extends State<_DialogueNomFerme> {
  late final TextEditingController _nom = TextEditingController(text: widget.actuel);

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nom de la ferme'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: _nom, autofocus: true,
            decoration: const InputDecoration(labelText: 'Nouveau nom', hintText: 'Ex : Ferme Avicole de Moribabougou'),
            onSubmitted: (_) => Navigator.pop(context, _nom.text.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, _nom.text.trim()), child: const Text('Enregistrer')),
        ],
      );
}

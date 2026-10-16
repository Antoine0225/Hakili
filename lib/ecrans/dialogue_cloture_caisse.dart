import 'package:flutter/material.dart';

import '../data/journal_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/modes_paiement.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';

/// 🧮 Clôture de caisse : on compte l'argent, Hakili compare avec ce que les ventes devraient avoir rapporté.
/// Le résultat est noté dans le journal des modifications. L'Ouvrier ne voit pas les montants attendus
/// (pour qu'il ne puisse pas « ajuster » son comptage) : seul le Patron voit le détail.
Future<void> ouvrirClotureCaisse(BuildContext context, List<Vente> ventes, DateTime jour) =>
    showDialog<void>(context: context, builder: (_) => _DialogueCloture(ventes: ventes, jour: jour));

class _DialogueCloture extends StatefulWidget {
  final List<Vente> ventes;
  final DateTime jour;
  const _DialogueCloture({required this.ventes, required this.jour});

  @override
  State<_DialogueCloture> createState() => _DialogueClotureState();
}

class _DialogueClotureState extends State<_DialogueCloture> {
  final _fonds = TextEditingController();
  final _depenses = TextEditingController();
  final _compte = TextEditingController();
  final _telephone = TextEditingController();
  String _erreur = '';
  bool _fait = false;
  double _attenduEsp = 0, _ecartEsp = 0, _attenduMob = 0, _ecartMob = 0;

  @override
  void dispose() {
    _fonds.dispose();
    _depenses.dispose();
    _compte.dispose();
    _telephone.dispose();
    super.dispose();
  }

  double? _lire(TextEditingController c, {bool videEstZero = false}) {
    final t = c.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (t.isEmpty) return videEstZero ? 0.0 : null;
    final v = double.tryParse(t);
    return (v == null || v < 0) ? null : v;
  }

  String _signe(double v) => v > 0.5 ? '+${milliersAnglais(v)}' : (v < -0.5 ? '-${milliersAnglais(-v)}' : '0');

  Future<void> _verifier() async {
    final fonds = _lire(_fonds, videEstZero: true);
    final dep = _lire(_depenses, videEstZero: true);
    final compte = _lire(_compte);
    final tel = _lire(_telephone, videEstZero: true);
    if (fonds == null || dep == null || tel == null) {
      setState(() => _erreur = '⚠️ Un des montants est invalide.');
      return;
    }
    if (compte == null) {
      setState(() => _erreur = "⚠️ Indiquez l'argent compté dans la caisse (mettez 0 s'il n'y a rien).");
      return;
    }
    final r = ModesPaiement.calculer(widget.ventes, widget.jour, widget.jour);
    final attEsp = fonds + r.entreesEspeces + r.entreesAutres - r.sortiesEspeces - dep;
    final attMob = r.entreesMobile - r.sortiesMobile;
    final ecEsp = compte - attEsp;
    final ecMob = tel - attMob;
    final juste = ecEsp.abs() < 0.5 && ecMob.abs() < 0.5;
    await JournalRepo.noter(
      'Caisse', juste ? 'CONTRÔLE' : 'ÉCART', 'Clôture de caisse du ${jourEnTexte(widget.jour)}',
      ancien: 'Attendu : espèces ${milliersAnglais(attEsp)} F · mobile ${milliersAnglais(attMob)} F',
      nouveau: 'Compté : espèces ${milliersAnglais(compte)} F · mobile ${milliersAnglais(tel)} F'
          '  →  écart espèces ${_signe(ecEsp)} F, écart mobile ${_signe(ecMob)} F',
    );
    if (!mounted) return;
    setState(() {
      _erreur = '';
      _attenduEsp = attEsp;
      _attenduMob = attMob;
      _ecartEsp = ecEsp;
      _ecartMob = ecMob;
      _fait = true;
    });
  }

  Widget _champ(Palette p, String etiquette, TextEditingController c, {String aide = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiquette, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          if (aide.isNotEmpty) Text(aide, style: TextStyle(fontSize: 10, color: p.txtGris)),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: '0'),
            ),
          ),
        ]),
      );

  Widget _ligneResultat(Palette p, String titre, double attendu, double ecart) {
    final bon = ecart.abs() < 0.5;
    final couleur = bon ? p.succes : p.danger;
    final phrase = bon
        ? '✅ Juste'
        : (ecart < 0 ? '⚠️ Il MANQUE ${milliersAnglais(-ecart)} FCFA' : '⚠️ Il y a ${milliersAnglais(ecart)} FCFA EN TROP');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10), border: Border.all(color: couleur)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        const SizedBox(height: 2),
        Text('Attendu selon les ventes : ${milliersAnglais(attendu)} FCFA', style: TextStyle(fontSize: 11, color: p.txtDoux)),
        Text(phrase, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: couleur)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final patron = Session.estPatron;
    final r = ModesPaiement.calculer(widget.ventes, widget.jour, widget.jour);
    final juste = _ecartEsp.abs() < 0.5 && _ecartMob.abs() < 0.5;
    return Dialog(
      backgroundColor: p.panneau,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🧮  CLÔTURE DE CAISSE — ${jourEnTexte(widget.jour)}',
                style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 2),
            Text(
                'Comptez l\'argent, puis Hakili compare avec ce que les ventes de la journée devraient avoir rapporté.',
                style: TextStyle(fontSize: 11, color: p.txtGris)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: !_fait
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (patron)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
                            child: Text(
                                'Ventes du jour encaissées :  💵 Espèces ${milliersAnglais(r.entreesEspeces)} F   ·   📱 Mobile ${milliersAnglais(r.entreesMobile)} F',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                          ),
                        _champ(p, '💵 Espèces comptées dans la caisse (FCFA)', _compte,
                            aide: 'Tout l\'argent liquide qui est dans la caisse maintenant.'),
                        _champ(p, '🌅 Argent déjà dans la caisse ce matin (FCFA)', _fonds,
                            aide: 'Le fonds de départ. Laissez vide s\'il n\'y en avait pas.'),
                        _champ(p, '🧾 Dépenses payées en espèces aujourd\'hui (FCFA)', _depenses,
                            aide: 'Transport, réparations, achats payés avec l\'argent de la caisse.'),
                        _champ(p, '📱 Total reçu en argent mobile aujourd\'hui (FCFA)', _telephone,
                            aide: 'D\'après l\'historique de votre téléphone (Orange Money, Moov, Wave...).'),
                        if (_erreur.isNotEmpty)
                          Text(_erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (patron) ...[
                          _ligneResultat(p, '💵 ESPÈCES', _attenduEsp, _ecartEsp),
                          _ligneResultat(p, '📱 ARGENT MOBILE', _attenduMob, _ecartMob),
                        ] else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: p.succes.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.succes)),
                            child: Text('✅ Votre comptage est enregistré. Le Patron verra le résultat.',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                          ),
                        const SizedBox(height: 10),
                        Text(
                            patron
                                ? (juste
                                    ? 'Tout est juste. Le contrôle est noté dans le journal.'
                                    : 'L\'écart est noté dans le journal des modifications.')
                                : 'Le contrôle est noté dans le journal.',
                            style: TextStyle(fontSize: 11, color: p.txtGris)),
                      ]),
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(_fait ? 'Fermer' : 'Annuler')),
              if (!_fait) ...[
                const SizedBox(width: 8),
                FilledButton(onPressed: _verifier, child: const Text('Vérifier et enregistrer')),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

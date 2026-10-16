import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Ce que le Patron choisit avant de générer le dossier pour la banque.
class ChoixDossierBanque {
  final int nbMois;
  final String objet;
  final double montant;
  const ChoixDossierBanque(this.nbMois, this.objet, this.montant);
}

Future<ChoixDossierBanque?> choisirDossierBanque(BuildContext context) =>
    showDialog<ChoixDossierBanque>(context: context, builder: (_) => const _DialogueDossier());

class _DialogueDossier extends StatefulWidget {
  const _DialogueDossier();

  @override
  State<_DialogueDossier> createState() => _DialogueDossierState();
}

class _DialogueDossierState extends State<_DialogueDossier> {
  final _objet = TextEditingController();
  final _montant = TextEditingController();
  int _mois = 12;
  String _erreur = '';

  @override
  void dispose() {
    _objet.dispose();
    _montant.dispose();
    super.dispose();
  }

  void _valider() {
    final t = _montant.text.trim().replaceAll(' ', '').replaceAll(',', '.');
    var m = 0.0;
    if (t.isNotEmpty) {
      final v = double.tryParse(t);
      if (v == null || v < 0) {
        setState(() => _erreur = '⚠️ Le montant demandé est invalide.');
        return;
      }
      m = v;
    }
    Navigator.pop(context, ChoixDossierBanque(_mois, _objet.text.trim(), m));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    Widget puce(int n, String t) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            selected: _mois == n,
            onSelected: (_) => setState(() => _mois = n),
          ),
        );
    return Dialog(
      backgroundColor: p.panneau,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🏦  DOSSIER POUR LA BANQUE',
                style: TextStyle(fontFamily: policeTexte, fontSize: 15, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 4),
            Text(
                'Hakili prépare un PDF propre avec vos chiffres : ventes, bénéfice, dettes, créances et élevage. '
                'Vous pouvez l\'imprimer ou l\'envoyer à votre banque ou à votre institution de microfinance.',
                style: TextStyle(fontSize: 11, color: p.txtGris)),
            const SizedBox(height: 14),
            Text('Sur quelle durée ?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 6),
            Row(children: [puce(3, '3 mois'), puce(6, '6 mois'), puce(12, '12 mois')]),
            const SizedBox(height: 14),
            Text('Objet de la demande (facultatif)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 4),
            TextField(
              controller: _objet,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: 'Ex : achat de 1 000 poussins et d\'aliment'),
            ),
            const SizedBox(height: 12),
            Text('Montant souhaité en FCFA (facultatif)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 4),
            TextField(
              controller: _montant,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: 'Ex : 2000000'),
              onSubmitted: (_) => _valider(),
            ),
            if (_erreur.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_erreur, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.danger)),
              ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _valider, child: const Text('📄 Générer le PDF')),
            ]),
          ]),
        ),
      ),
    );
  }
}

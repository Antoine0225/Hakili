import 'package:flutter/material.dart';

import '../data/journal_repo.dart';
import '../services/pdf_journal.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';
import '../widgets/dialogues.dart';
import '../widgets/toast.dart';

/// Ouvre le journal des modifications (réservé au Patron). À la fermeture, tout ce qui a été affiché est marqué « vu ».
Future<void> ouvrirJournal(BuildContext context) async {
  final vu = await JournalRepo.dernierVu();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _DialogueJournal(dernierVu: vu),
  );
  await JournalRepo.marquerVu();
}

class _DialogueJournal extends StatefulWidget {
  final int dernierVu;
  const _DialogueJournal({required this.dernierVu});

  @override
  State<_DialogueJournal> createState() => _DialogueJournalState();
}

class _DialogueJournalState extends State<_DialogueJournal> {
  static const _periodes = {'Aujourd\'hui': 0, '7 derniers jours': 7, '30 derniers jours': 30, 'Tout l\'historique': -1};
  static const _categories = ['Toutes', 'Ventes', 'Arrivages', 'Catalogue', 'Bandes', 'Caisse', 'Sécurité'];
  static const _qui = ['Tous', 'Patron', 'Ouvrier', 'Autre PC'];

  String _periode = '7 derniers jours';
  String _categorie = 'Toutes';
  String _session = 'Tous';
  bool _sansAjouts = false;
  List<EntreeJournal> _entrees = [];
  BilanJournal _bilan = const BilanJournal(0, 0, 0, 0);
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  DateTime? get _depuis {
    final n = _periodes[_periode] ?? 7;
    if (n < 0) return null;
    final auj = aujourdhui();
    return n == 0 ? auj : auj.subtract(Duration(days: n));
  }

  Future<void> _recharger() async {
    final l = await JournalRepo.lire(
      depuis: _depuis,
      categorie: _categorie == 'Toutes' ? null : _categorie,
      session: _session == 'Tous' ? null : _session,
      sansAjouts: _sansAjouts,
    );
    final b = await JournalRepo.bilan(depuis: _depuis);
    if (!mounted) return;
    setState(() {
      _entrees = l;
      _bilan = b;
      _charge = true;
    });
  }

  /// Imprime ce que les filtres montrent à l'écran, mais sans la limite des 600 lignes (jusqu'à 5 000).
  Future<void> _exporterPdf() async {
    const limitePdf = 5000;
    try {
      final depuis = _depuis;
      final l = await JournalRepo.lire(
        depuis: depuis,
        categorie: _categorie == 'Toutes' ? null : _categorie,
        session: _session == 'Tous' ? null : _session,
        sansAjouts: _sansAjouts,
        limite: limitePdf,
      );
      final filtres = 'Periode : $_periode'
          '${depuis == null ? '' : ' (depuis le ${jourEnTexte(depuis)})'}  -  Sujet : $_categorie  -  Qui : $_session'
          '${_sansAjouts ? '  -  Ajouts masques' : ''}';
      // le résumé du PDF compte ce qui est réellement imprimé (donc il suit aussi les filtres Sujet / Qui)
      int nb(bool Function(EntreeJournal) f) => l.where(f).length;
      final ajouts = nb((e) => e.action == 'AJOUT'), modifs = nb((e) => e.action == 'MODIFIÉ'), supprs = nb((e) => e.action == 'SUPPRIMÉ');
      final bilan = BilanJournal(ajouts, modifs, supprs, l.length - ajouts - modifs - supprs);
      final ok = await PdfJournal.exporter(entrees: l, bilan: bilan, filtres: filtres, tronque: l.length >= limitePdf);
      if (ok && mounted) Toast.afficher(context, '📄 Journal exporté en PDF !', couleur: Palette.de(context).succes);
    } catch (e) {
      if (mounted) Dialogues.erreur(context, 'Erreur PDF', "Détails de l'exportation : $e");
    }
  }

  Color _couleurAction(Palette p, String a) => switch (a) {
        'AJOUT' => p.succes,
        'MODIFIÉ' => p.alerte,
        'SUPPRIMÉ' => p.danger,
        'ÉCHEC' => p.danger,
        'ÉCART' => p.danger,
        'CONTRÔLE' => p.succes,
        _ => p.txtDoux,
      };

  String _libelleAction(String a) => switch (a) {
        'AJOUT' => 'AJOUT',
        'MODIFIÉ' => 'MODIFIÉ',
        'SUPPRIMÉ' => 'SUPPRIMÉ',
        'ÉCHEC' => 'PIN FAUX',
        'ÉCART' => 'ÉCART DE CAISSE',
        'CONTRÔLE' => 'CAISSE JUSTE',
        'CONNEXION' => 'CONNEXION',
        'SESSION' => 'SESSION',
        _ => a,
      };

  Widget _filtre(String etiquette, String valeur, List<String> choix, ValueChanged<String> onChange) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiquette, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Palette.de(context).txtGris)),
          DropdownButton<String>(
            value: valeur,
            isDense: true,
            items: [for (final c in choix) DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))],
            onChanged: (v) {
              if (v == null) return;
              setState(() => onChange(v));
              _recharger();
            },
          ),
        ]),
      );

  Widget _ligne(Palette p, EntreeJournal e) {
    final couleur = _couleurAction(p, e.action);
    final nouveau = e.id > widget.dernierVu;
    final risque = ((e.action == 'SUPPRIMÉ' || e.action == 'ÉCHEC') && e.session != 'Patron') || e.action == 'ÉCART';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: risque ? p.danger.withValues(alpha: 0.07) : p.panneau2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: nouveau ? p.cuivre : p.bordure, width: nouveau ? 1.4 : 1),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 5,
            decoration: BoxDecoration(
                color: couleur, borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10))),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(e.quandAffiche, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtDoux)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(6)),
                    child: Text(_libelleAction(e.action),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Text(e.session.isEmpty ? '—' : e.session,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: e.session == 'Ouvrier' ? p.alerte : p.txtPrinc)),
                  const SizedBox(width: 10),
                  Text(e.categorie, style: TextStyle(fontSize: 11, color: p.txtGris)),
                  const Spacer(),
                  if (nouveau)
                    Text('NOUVEAU', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.cuivre)),
                ]),
                const SizedBox(height: 4),
                Text(e.objet, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                if (e.ancien.isNotEmpty && e.nouveau.isNotEmpty) ...[
                  Text('Avant :  ${e.ancien}', style: TextStyle(fontSize: 11, color: p.txtDoux)),
                  Text('Après :  ${e.nouveau}', style: TextStyle(fontSize: 11, color: p.txtPrinc)),
                ] else if (e.ancien.isNotEmpty)
                  Text(e.ancien, style: TextStyle(fontSize: 11, color: p.txtDoux))
                else if (e.nouveau.isNotEmpty)
                  Text(e.nouveau, style: TextStyle(fontSize: 11, color: p.txtDoux)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return Dialog(
      backgroundColor: p.panneau,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.bordure)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 940, maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🔍  JOURNAL DES MODIFICATIONS',
                style: TextStyle(fontFamily: policeTexte, fontSize: 16, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 2),
            Text(
                'Tout ce qui est ajouté, modifié ou supprimé (ventes, arrivages, produits, bandes), avec la session qui l\'a fait. '
                'Les lignes entourées en cuivre sont nouvelles depuis votre dernière visite.',
                style: TextStyle(fontSize: 11, color: p.txtGris)),
            const SizedBox(height: 10),
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
              _filtre('PÉRIODE', _periode, _periodes.keys.toList(), (v) => _periode = v),
              _filtre('SUJET', _categorie, _categories, (v) => _categorie = v),
              _filtre('QUI', _session, _qui, (v) => _session = v),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: _sansAjouts,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) {
                      setState(() => _sansAjouts = v ?? false);
                      _recharger();
                    },
                  ),
                  Text('Masquer les ajouts', style: TextStyle(fontSize: 12, color: p.txtPrinc)),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                '${_bilan.total} événement(s) sur la période :  ${_bilan.ajouts} ajout(s)  ·  ${_bilan.modifications} modification(s)  ·  '
                '${_bilan.suppressions} suppression(s)${_bilan.autres > 0 ? '  ·  ${_bilan.autres} connexion(s) / alerte(s)' : ''}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            const SizedBox(height: 10),
            Flexible(
              child: !_charge
                  ? const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                  : _entrees.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Text('Rien à afficher pour ces filtres.', style: TextStyle(fontSize: 13, color: p.txtDoux)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _entrees.length,
                          itemBuilder: (_, i) => _ligne(p, _entrees[i]),
                        ),
            ),
            if (_entrees.length >= 600)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Les 600 événements les plus récents sont affichés : réduisez la période pour voir plus précisément.',
                    style: TextStyle(fontSize: 10, color: p.txtGris)),
              ),
            const Divider(height: 18),
            Row(children: [
              Expanded(
                child: Text(
                    'Ce journal est propre à ce PC. Il garde 2 ans d\'historique et ne peut pas être effacé depuis le logiciel.',
                    style: TextStyle(fontSize: 10, color: p.txtGris)),
              ),
              OutlinedButton(onPressed: _exporterPdf, child: const Text('📄 Exporter en PDF')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
            ]),
          ]),
        ),
      ),
    );
  }
}

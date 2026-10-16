import 'package:flutter/material.dart';

import '../cloud/service_cloud.dart';
import '../config/constantes.dart';
import '../data/journal_repo.dart';
import '../data/ventes_repo.dart';
import '../metier/modes_paiement.dart';
import '../session.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';

enum _Voyant { vert, orange, rouge, neutre }

class _Ligne {
  final String titre, valeur, detail;
  final _Voyant voyant;
  const _Ligne(this.titre, this.valeur, this.detail, this.voyant);
}

/// 📋 « Patron absent » : une seule page, des voyants vert / orange / rouge, pour savoir en 30 secondes
/// si la ferme a bien tourné aujourd'hui. Réservée au Patron.
class EcranResumeJour extends StatefulWidget {
  const EcranResumeJour({super.key});

  @override
  State<EcranResumeJour> createState() => _EcranResumeJourState();
}

class _EcranResumeJourState extends State<EcranResumeJour> {
  bool _charge = false;
  List<_Ligne> _lignes = [];
  List<EntreeJournal> _recent = [];

  @override
  void initState() {
    super.initState();
    ServiceCloud.versionDonnees.addListener(_charger); // un autre PC a saisi quelque chose : la page se met à jour
    _charger();
  }

  @override
  void dispose() {
    ServiceCloud.versionDonnees.removeListener(_charger);
    super.dispose();
  }

  static String _jourIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _charger() async {
    final auj = aujourdhui();
    final hier = auj.subtract(const Duration(days: 1));
    final ventes = await VentesRepo.toutes();
    final caAuj = VentesRepo.totauxPeriode(ventes, auj, auj);
    final caHier = VentesRepo.totauxPeriode(ventes, hier, hier);
    final modes = ModesPaiement.calculer(ventes, auj, auj);
    final dettes = await VentesRepo.creancesOuvertes();
    final totalDettes = dettes.fold<double>(0, (s, v) => s + v.reste);
    final aVerifier = await JournalRepo.compterAVerifier();
    final clotures = await JournalRepo.lire(categorie: 'Caisse', limite: 1);
    final journalJour = await JournalRepo.lire(depuis: auj, sansAjouts: true, limite: 60);
    final importants = journalJour
        .where((e) => const ['MODIFIÉ', 'SUPPRIMÉ', 'ÉCHEC', 'ÉCART'].contains(e.action))
        .take(6)
        .toList();

    // Ventes : comparaison avec hier
    String detailVentes;
    var vVentes = _Voyant.neutre;
    if (caHier.ca > 0.5) {
      final ecart = (caAuj.ca - caHier.ca) / caHier.ca * 100;
      detailVentes = '${ecart >= 0 ? '+' : ''}${ecart.toStringAsFixed(0)} % par rapport à hier (${fmtF(caHier.ca)})';
      vVentes = caAuj.ca >= caHier.ca ? _Voyant.vert : _Voyant.orange;
    } else {
      detailVentes = 'Hier : aucune vente enregistrée';
    }

    // Caisse : dernière clôture
    String detailCaisse;
    var vCaisse = _Voyant.orange;
    if (clotures.isNotEmpty && clotures.first.quand.startsWith(_jourIso(auj))) {
      final c = clotures.first;
      if (c.action == 'ÉCART') {
        vCaisse = _Voyant.rouge;
        detailCaisse = '⚠️ Clôture faite avec un écart : ${c.nouveau}';
      } else {
        vCaisse = _Voyant.vert;
        detailCaisse = 'Caisse clôturée et juste (${c.quandAffiche})';
      }
    } else {
      detailCaisse = "La caisse n'a pas encore été clôturée aujourd'hui";
    }

    final sacs = Session.sacsAlimentEnStock;
    final lignes = <_Ligne>[
      _Ligne("Ventes d'aujourd'hui", fmtF(caAuj.ca), '${caAuj.nb} vente(s) · $detailVentes', vVentes),
      _Ligne('Argent encaissé', fmtF(modes.entrees),
          'Espèces ${fmtF(modes.entreesEspeces)} · Mobile Money ${fmtF(modes.entreesMobile)}', _Voyant.neutre),
      _Ligne('Caisse', juste(vCaisse), detailCaisse, vCaisse),
      _Ligne('Dettes clients', fmtF(totalDettes), '${dettes.length} client(s) à relancer',
          dettes.isEmpty ? _Voyant.vert : _Voyant.orange),
      _Ligne("Stock d'aliment", '$sacs sac(s)',
          sacs <= 0 ? 'Plus aucun sac : à racheter tout de suite' : (sacs <= 2 ? 'Stock bas : pensez à commander' : 'Stock correct'),
          sacs <= 0 ? _Voyant.rouge : (sacs <= 2 ? _Voyant.orange : _Voyant.vert)),
      _Ligne('À vérifier dans le journal', '$aVerifier',
          aVerifier == 0 ? 'Rien de suspect' : 'Modifications ou suppressions que vous n\'avez pas encore vues',
          aVerifier == 0 ? _Voyant.vert : (aVerifier > 5 ? _Voyant.rouge : _Voyant.orange)),
    ];
    if (!mounted) return;
    setState(() {
      _lignes = lignes;
      _recent = importants;
      _charge = true;
    });
  }

  static String juste(_Voyant v) => switch (v) {
        _Voyant.vert => 'Juste ✅',
        _Voyant.rouge => 'Écart ⚠️',
        _ => 'À faire',
      };

  Color _couleur(Palette p, _Voyant v) => switch (v) {
        _Voyant.vert => p.succes,
        _Voyant.orange => p.alerte,
        _Voyant.rouge => p.danger,
        _Voyant.neutre => p.txtGris,
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PATRON ABSENT', style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Résumé du jour', style: TextStyle(fontFamily: policeTitre, fontSize: 34, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text("L'essentiel de la journée en un coup d'œil.   🟢 normal   🟠 à surveiller   🔴 à traiter",
              style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtDoux)),
        ),
        if (!_charge)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else ...[
          for (final l in _lignes) _carte(p, l),
          const SizedBox(height: 8),
          _blocRecent(p),
        ],
      ]),
    );
  }

  Widget _carte(Palette p, _Ligne l) {
    final c = _couleur(p, l.voyant);
    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 6),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.bordure)),
      child: Row(children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.titre, style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
            const SizedBox(height: 2),
            Text(l.detail, style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtGris)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(l.valeur, style: TextStyle(fontFamily: policeTitre, fontSize: 20, fontWeight: FontWeight.bold, color: p.txtPrinc)),
      ]),
    );
  }

  Widget _blocRecent(Palette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14, right: 6),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.bordure)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Changements importants d'aujourd'hui",
            style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtDoux)),
        const SizedBox(height: 8),
        if (_recent.isEmpty)
          Text('Aucune modification ni suppression aujourd\'hui. ✅', style: TextStyle(fontSize: 12, color: p.txtGris))
        else
          for (final e in _recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${e.quandAffiche} · ${e.session} · ${e.action} · ${e.objet}',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 11, color: p.txtPrinc)),
            ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/ventes_repo.dart';
import '../metier/modes_paiement.dart';
import '../theme/palette.dart';
import '../utilitaires/formats.dart';

// ======================================================================== BILAN GLOBAL
/// 💰 Bilan financier global de la caisse (Patron) : argent encaissé, dettes, bénéfice, livre des dettes.
class VueBilanGlobal extends StatelessWidget {
  final List<Vente> ventes;
  const VueBilanGlobal({super.key, required this.ventes});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    var cash = 0.0, dehors = 0.0;
    final livre = <String, double>{};
    for (final v in ventes) {
      if (v.estCredit) {
        final reste = v.reste < 0 ? 0.0 : v.reste;
        dehors += reste;
        final nom = v.client.trim().isEmpty ? 'Débiteur' : v.client.trim();
        if (reste > 0.01) livre[nom] = (livre[nom] ?? 0) + reste;
      } else {
        cash += v.total;
      }
    }
    final (poche, attente) = VentesRepo.margesEnPocheEtAttente(ventes);
    const ligne = '  -----------------------------------------------------------\n';
    var txt = '💰 BILAN FINANCIER GLOBAL — CAISSE EN DIRECT ANTOINE\n\n'
        "  • Volume d'activités enregistrées  : ${ventes.length} opérations\n$ligne"
        '  💵 ARGENT ENCAISSÉ (Cash/Mobile)    : ${milliersAnglais(cash)} FCFA\n'
        '  ⚠️ CRÉDITS HORS EXPLOITATION (Dettes) : ${milliersAnglais(dehors)} FCFA\n'
        "  👉 CHIFFRE D'AFFAIRES BRUT TOTAL    : ${milliersAnglais(cash + dehors)} FCFA\n$ligne"
        '  📈 BÉNÉFICE EN POCHE (marge encaissée) : ${milliersAnglais(poche)} FCFA\n';
    if (attente > 0.5) txt += '  ⏳ Bénéfice en attente (sur crédits)   : ${milliersAnglais(attente)} FCFA\n';
    txt += '$ligne\n';
    if (livre.isNotEmpty) {
      txt += '👤 LIVRE ANALYTIQUE DES DETTES CLIENTS :\n';
      livre.forEach((cli, somme) => txt += '  • $cli vous doit  ➡️  ${milliersAnglais(somme)} FCFA\n');
    } else {
      txt += "🔥 Félicitations Antoine, aucun crédit n'est dehors !";
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(txt,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          const SizedBox(height: 18),
          CarteModesPaiement(ventes: ventes),
        ]),
      ),
    );
  }
}

// ======================================================================== ESPÈCES OU ARGENT MOBILE
/// 💵📱 Comparaison de la façon dont l'argent est entré : espèces (billets) ou argent mobile (téléphone).
class CarteModesPaiement extends StatelessWidget {
  final List<Vente> ventes;
  const CarteModesPaiement({super.key, required this.ventes});

  Widget _periode(Palette p, String titre, RepartitionModes r) {
    final total = r.entrees;
    final pe = total > 0.5 ? r.entreesEspeces / total : 0.0;
    final pm = total > 0.5 ? r.entreesMobile / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
        const SizedBox(height: 5),
        if (total < 0.5)
          Text('Aucun encaissement.', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtGris))
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                if (pe > 0) Expanded(flex: (pe * 1000).round().clamp(1, 1000).toInt(), child: Container(color: p.succes)),
                if (pm > 0) Expanded(flex: (pm * 1000).round().clamp(1, 1000).toInt(), child: Container(color: p.cuivre)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text(
              '💵 Espèces ${milliersAnglais(r.entreesEspeces)} F (${r.partEspeces.toStringAsFixed(0)} %)'
              '     📱 Mobile ${milliersAnglais(r.entreesMobile)} F (${r.partMobile.toStringAsFixed(0)} %)',
              style: TextStyle(fontSize: 10, color: p.txtDoux)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final auj = aujourdhui();
    final debutMois = DateTime(auj.year, auj.month, 1);
    final jour = ModesPaiement.calculer(ventes, auj, auj);
    final mois = ModesPaiement.calculer(ventes, debutMois, auj);
    final tout = ModesPaiement.calculer(ventes, DateTime(2000), auj);
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(color: p.panneau, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('💵 ESPÈCES  ou  📱 ARGENT MOBILE ?',
            style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.accent)),
        Text("L'argent réellement entré en caisse (les crédits ne comptent que le jour où le client paie).",
            style: TextStyle(fontSize: 10, color: p.txtGris)),
        _periode(p, "Aujourd'hui", jour),
        _periode(p, 'Ce mois-ci', mois),
        _periode(p, 'Depuis le début', tout),
        if (tout.entreesMobile < 0.5)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                'Astuce : choisissez « Mobile Money » comme mode de règlement quand un client paie avec son téléphone.',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: p.txtGris)),
          ),
      ]),
    );
  }
}

// ======================================================================== MARGES RÉELLES
/// 📊 Tableau de bord & marges réelles : CA global, cash réel, bénéfice net, bilan par produit.
class VueMarges extends StatelessWidget {
  final List<Vente> ventes;
  final VoidCallback onRetourStock;
  const VueMarges({super.key, required this.ventes, required this.onRetourStock});

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final produits = ventes.where((v) => !ligneEstHorsChiffreAffaires(v.type)).toList();
    final ca = produits.fold<double>(0, (s, v) => s + v.total);
    final cash = ventes.where((v) => !v.estCredit).fold<double>(0, (s, v) => s + v.total);
    var net = 0.0;
    final bilan = <String, List<double>>{}; // nom -> [qté, bénéfice]
    for (final v in produits) {
      final b = v.coutAchat > 0 ? (v.pu - v.coutAchat) * v.qte : 0.0;
      net += b;
      final nom = v.type.isEmpty ? 'Produit inconnu' : v.type;
      final l = bilan.putIfAbsent(nom, () => [0.0, 0.0]);
      l[0] += v.qte;
      l[1] += b;
    }
    final tries = bilan.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]));
    final entete = '📊 TABLEAU DE BORD & MARGES RÉELLES\n'
        '-----------------------------------------------------------\n\n'
        "  👉 CHIFFRE D'AFFAIRES GLOBAL      : ${milliersAnglais(ca)} FCFA\n\n"
        '  💵 FLUX DE TRÉSORERIE (CASH RÉEL)  : ${milliersAnglais(cash)} FCFA\n\n'
        '  📈 BÉNÉFICE NET PUR                : ${milliersAnglais(net)} FCFA\n'
        '-----------------------------------------------------------\n';

    return Column(children: [
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: p.carte, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.bordure)),
          child: ListView(padding: const EdgeInsets.fromLTRB(4, 15, 4, 15), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(entete,
                  style: TextStyle(fontFamily: 'Consolas', fontSize: 13, fontWeight: FontWeight.bold, color: p.txtPrinc)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 8),
              child: Text('🏆 BILAN PAR PRODUIT (quantité vendue & bénéfice)',
                  style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.accent)),
            ),
            if (tries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Aucune vente de produit enregistrée pour le moment.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)),
              ),
            for (final e in tries)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                    color: p.panneau, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bordure)),
                child: Row(children: [
                  Text(e.key,
                      style: TextStyle(fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                  const SizedBox(width: 10),
                  Text('Qté vendue : ${milliersAnglais(e.value[0], 1)}',
                      style: TextStyle(fontSize: 11, color: p.txtGris)),
                  const Spacer(),
                  Text('Bénéfice : ${milliersAnglais(e.value[1])} FCFA',
                      style: TextStyle(
                          fontFamily: policeTexte, fontSize: 12, fontWeight: FontWeight.bold,
                          color: e.value[1] >= 0 ? p.succes : p.danger)),
                ]),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: SizedBox(
          height: 32,
          child: FilledButton(
            onPressed: onRetourStock,
            style: FilledButton.styleFrom(
                backgroundColor: p.neutre, foregroundColor: p.txtPrinc,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
            child: const Text('↩️ Retour au Stock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    ]);
  }
}

// ======================================================================== ARCHIVES
/// 🗄️ Archives et traçabilité historique (Patron) : filtre par mois ou par jour, 60 lignes à la fois.
class VueArchives extends StatefulWidget {
  final List<Vente> ventes;
  final void Function(Vente) onOuvrir;
  final VoidCallback onFermer;
  const VueArchives({super.key, required this.ventes, required this.onOuvrir, required this.onFermer});

  @override
  State<VueArchives> createState() => _VueArchivesState();
}

class _VueArchivesState extends State<VueArchives> {
  static const _mois = [
    'Toutes les commandes', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
    'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];
  static const _taillePage = 60;
  String _choixMois = 'Toutes les commandes';
  DateTime? _jour;
  String _source = 'tous';
  int _pages = 1;

  List<Vente> _resultats() {
    final l = <Vente>[];
    for (var i = widget.ventes.length - 1; i >= 0; i--) {
      final v = widget.ventes[i];
      final d = v.date.trim().replaceAll('-', '/');
      final el = d.split('/');
      final m = el.length > 1 ? el[1] : '';
      var ok = false;
      if (_source == 'cal' && _jour != null && d == jourEnTexte(_jour!)) ok = true;
      if (_source == 'mois') {
        final num = _mois.indexOf(_choixMois);
        ok = num <= 0 || m == num.toString().padLeft(2, '0');
      }
      if (_source == 'tous') ok = true;
      if (ok) l.add(v);
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.de(context);
    final res = _resultats();
    final affiches = res.take(_taillePage * _pages).toList();
    final reste = res.length - affiches.length;

    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(15, 15, 15, 5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        width: double.infinity,
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10)),
        child: Text('🗄️ ARCHIVES ET TRAÇABILITÉ HISTORIQUE DU COMPTE',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: policeTexte, fontSize: 13, fontWeight: FontWeight.bold, color: p.accent)),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(15, 5, 15, 5),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: p.panneau2, borderRadius: BorderRadius.circular(10)),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          Text('📅 Mois :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          Container(
            width: 170, height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: p.panneau, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.bordure)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _choixMois, isExpanded: true, isDense: true, dropdownColor: p.panneau,
                style: TextStyle(fontFamily: policeTexte, fontSize: 12, color: p.txtPrinc),
                items: [for (final m in _mois) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() {
                  _choixMois = v ?? _choixMois;
                  _source = 'mois';
                  _pages = 1;
                }),
              ),
            ),
          ),
          Text('📆 Jour :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _jour ?? aujourdhui(), firstDate: DateTime(2000),
                  lastDate: DateTime(2100), locale: const Locale('fr'));
              if (d != null) {
                setState(() {
                  _jour = d;
                  _source = 'cal';
                  _pages = 1;
                });
              }
            },
            child: Container(
              width: 110, height: 28, alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: const Color(0xFF123229), borderRadius: BorderRadius.circular(4)),
              child: Text(jourEnTexte(_jour ?? aujourdhui()), style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ),
          SizedBox(
            height: 28,
            child: FilledButton(
              onPressed: () => setState(() {
                _choixMois = 'Toutes les commandes';
                _source = 'tous';
                _pages = 1;
              }),
              style: FilledButton.styleFrom(
                  backgroundColor: p.panneau2, foregroundColor: p.txtPrinc,
                  padding: const EdgeInsets.symmetric(horizontal: 12), side: BorderSide(color: p.bordure)),
              child: const Text('🔄 Tout', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          decoration: BoxDecoration(color: p.carte, borderRadius: BorderRadius.circular(10)),
          child: res.isEmpty
              ? Center(
                  child: Text(
                      _source == 'cal'
                          ? 'Aucune transaction trouvée pour le jour : ${jourEnTexte(_jour ?? aujourdhui())}.'
                          : 'Aucun flux enregistré en $_choixMois.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.txtGris)))
              : ListView(padding: const EdgeInsets.all(5), children: [
                  for (final v in affiches)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 5),
                      child: Material(
                        color: p.panneau2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          hoverColor: p.survol,
                          onTap: () => widget.onOuvrir(v),
                          child: Container(
                            height: 55, alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                                '📅 ${v.date.trim().replaceAll('-', '/')} — ${v.type}\n'
                                '📊 Qté: ${milliersAnglais(v.qte)} x ${milliersAnglais(v.pu)} F | Total: ${milliersAnglais(v.total)} FCFA | '
                                '${v.estCredit ? '⚠️ CRÉDIT (${v.client})' : '✅ ${v.reglement}'}',
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: policeTexte, fontSize: 11, fontWeight: FontWeight.bold, color: p.txtPrinc)),
                          ),
                        ),
                      ),
                    ),
                  if (reste > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
                      child: SizedBox(
                        height: 38,
                        child: FilledButton(
                          onPressed: () => setState(() => _pages++),
                          child: Text(
                              '⬇️  Afficher ${reste < _taillePage ? reste : _taillePage} transactions de plus ($reste restantes)',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
          height: 32,
          child: FilledButton(
            onPressed: widget.onFermer,
            style: FilledButton.styleFrom(backgroundColor: p.danger, padding: const EdgeInsets.symmetric(horizontal: 18)),
            child: const Text('↩️ Fermer et Voir le Bilan Global de la Ferme',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    ]);
  }
}

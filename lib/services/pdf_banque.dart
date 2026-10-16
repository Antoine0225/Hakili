import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/arrivages_repo.dart';
import '../data/bandes_repo.dart';
import '../data/base_locale.dart';
import '../data/bilans_repo.dart';
import '../data/ventes_repo.dart';
import '../ecrans/dialogue_dossier_banque.dart';
import '../metier/modes_paiement.dart';
import '../session.dart';
import '../utilitaires/formats.dart';

/// 🏦 Dossier de présentation pour une banque ou une institution de microfinance.
/// Tout vient des enregistrements de Hakili. Le document dit clairement qu'il n'est pas certifié.
class PdfBanque {
  PdfBanque._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _doux = PdfColor.fromHex('#4d5f56');
  static final _gris = PdfColor.fromHex('#6f7d75');
  static final _ligne = PdfColor.fromHex('#e8e2d7');
  static final _grille = PdfColor.fromHex('#d8d1c2');
  static final _creme = PdfColor.fromHex('#faf8f5');
  static final _succes = PdfColor.fromHex('#2f7d4f');
  static final _danger = PdfColor.fromHex('#b3372a');
  static const _moisNoms = [
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Aout', 'Septembre', 'Octobre', 'Novembre', 'Decembre'
  ];

  /// Le PDF utilise une police sans accents ni emojis : on nettoie tous les textes venant de la base.
  static String _a(String t) {
    const de = 'àâäçéèêëîïôöùûüÿñÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸÑ';
    const vers = 'aaaceeeeiioouuuynAAACEEEEIIOOUUUYN';
    final sb = StringBuffer();
    for (final r in t.runes) {
      final c = String.fromCharCode(r);
      final i = de.indexOf(c);
      if (i >= 0) {
        sb.write(vers[i]);
      } else if (r == 0x153) {
        sb.write('oe');
      } else if (r == 0x152) {
        sb.write('OE');
      } else if (r == 0x2019) {
        sb.write("'");
      } else if (r == 0x2013 || r == 0x2014) {
        sb.write('-');
      } else if (r == 0xA0 || r == 0x202F) {
        sb.write(' ');
      } else if (r >= 32 && r < 127) {
        sb.write(c);
      }
    }
    return sb.toString().trim();
  }

  static String _f(num v) => '${milliersAnglais(v)} FCFA';

  static pw.Widget _section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _vert)),
      );

  static pw.Widget _note(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: _gris)),
      );

  static pw.Widget _lignes(List<List<String>> d, {Set<int> gras = const {}}) => pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(330), 1: pw.FixedColumnWidth(200)},
        border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _ligne, width: 0.4), bottom: pw.BorderSide(color: _ligne, width: 0.4)),
        children: [
          for (var i = 0; i < d.length; i++)
            pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(d[i][0],
                      style: pw.TextStyle(fontSize: 10, fontWeight: gras.contains(i) ? pw.FontWeight.bold : pw.FontWeight.normal, color: _vert))),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(d[i][1],
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 10, fontWeight: gras.contains(i) ? pw.FontWeight.bold : pw.FontWeight.normal, color: _vert))),
            ]),
        ],
      );

  static pw.Widget _cell(String t, {bool gras = false, bool gauche = false, PdfColor? couleur}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: pw.Text(t,
            textAlign: gauche ? pw.TextAlign.left : pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
      );

  static double _n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);

  /// Renvoie true si le fichier a été enregistré, false si la personne a annulé.
  static Future<bool> exporter(ChoixDossierBanque choix) async {
    final ventes = await VentesRepo.toutes();
    final archives = await BilansRepo.archives();
    final bandes = await BandesRepo.toutes();
    final dettesF = await ArrivagesRepo.dettesActives();

    final auj = aujourdhui();
    final debut = DateTime(auj.year, auj.month - (choix.nbMois - 1), 1);
    final finJour = DateTime(auj.year, auj.month, auj.day, 23, 59, 59);
    final mois = [for (var i = 0; i < choix.nbMois; i++) DateTime(debut.year, debut.month + i, 1)];
    final nomFerme = _a(Session.nomFerme.trim().isEmpty ? 'Exploitation avicole' : Session.nomFerme.trim());

    // ---- mois par mois
    final lignesMois = <_LigneMois>[];
    for (final m in mois) {
      final fin = DateTime(m.year, m.month + 1, 0, 23, 59, 59);
      final r = VentesRepo.revenuPeriode(ventes, m, fin.isAfter(finJour) ? finJour : fin);
      final cle = '${m.month.toString().padLeft(2, '0')}/${m.year}';
      BilanArchive? arch;
      for (final a in archives) {
        if (a.periode == cle) {
          arch = a;
          break;
        }
      }
      lignesMois.add(_LigneMois(m, r, arch));
    }
    final global = VentesRepo.revenuPeriode(ventes, debut, finJour);
    final baseMarge = global.caBrut - global.caSansCout;
    final margePct = baseMarge > 0 ? global.beneficePur / baseMarge * 100 : 0.0;

    // ---- clients, jours d'activité
    final clients = <String>{};
    final jours = <String>{};
    for (final v in ventes) {
      if (ligneEstHorsChiffreAffaires(v.type)) continue;
      final dt = lireJma(v.date.trim());
      if (dt == null || dt.isBefore(debut) || dt.isAfter(finJour)) continue;
      jours.add('${dt.year}-${dt.month}-${dt.day}');
      final c = v.client.trim().toLowerCase();
      if (c.isNotEmpty && c != 'client comptant') clients.add(c);
    }

    // ---- charges saisies
    final avecCharges = lignesMois.where((l) => l.archive != null).toList();
    final totalCharges = avecCharges.fold<double>(0, (s, l) => s + l.archive!.totalCharges);
    final totalNet = avecCharges.fold<double>(0, (s, l) => s + l.archive!.net);
    final netMoyen = avecCharges.isEmpty ? 0.0 : totalNet / avecCharges.length;

    // ---- modes de paiement
    final modes = ModesPaiement.calculer(ventes, debut, auj);

    // ---- situation actuelle
    final creances = VentesRepo.dettesOuvertes(ventes);
    final totalCreances = creances.fold<double>(0, (s, v) => s + (v.reste < 0 ? 0 : v.reste));
    final nbDebiteurs = {for (final v in creances) v.client.trim().toLowerCase()}.length;
    final totalDettesF = dettesF?.fold<double>(0, (s, d) => s + d.resteDu);

    var valeurStock = 0.0;
    try {
      final l = await BaseLocale.db.rawQuery('SELECT SUM(quantite_disponible * cout_achat_unitaire) AS v FROM stock_produits');
      valeurStock = l.isEmpty ? 0.0 : _n(l.first['v']);
    } catch (_) {}
    var achats = 0.0;
    try {
      final l = await BaseLocale.db.rawQuery('SELECT date, prix_achat_total FROM stocks_arrivages');
      for (final r in l) {
        final dt = lireJma(r['date']);
        if (dt != null && !dt.isBefore(debut) && !dt.isAfter(finJour)) achats += _n(r['prix_achat_total']);
      }
    } catch (_) {}

    // ---- tendance : 3 derniers mois contre les 3 précédents (si on a au moins 6 mois)
    String? tendance;
    if (lignesMois.length >= 6) {
      final nm = lignesMois.length;
      final recent = lignesMois.sublist(nm - 3).fold<double>(0, (s, l) => s + l.rev.caBrut);
      final avant = lignesMois.sublist(nm - 6, nm - 3).fold<double>(0, (s, l) => s + l.rev.caBrut);
      if (avant > 0) {
        final ev = (recent - avant) / avant * 100;
        tendance = '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)} % (3 derniers mois contre les 3 precedents)';
      }
    }
    final actifs = lignesMois.where((l) => l.rev.caBrut > 0).toList();
    _LigneMois? meilleur, faible;
    for (final l in actifs) {
      if (meilleur == null || l.rev.caBrut > meilleur.rev.caBrut) meilleur = l;
      if (faible == null || l.rev.caBrut < faible.rev.caBrut) faible = l;
    }
    String nomMois(DateTime m) => '${_moisNoms[m.month - 1]} ${m.year}';

    final n = DateTime.now();
    final genere = '${jourEnTexte(n)} a ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    final periodeTxt = '${nomMois(mois.first)} a ${nomMois(mois.last)}';

    // ---------------------------------------------------------------- contenu
    final logo = await LogoPdf.widget(hauteur: 56);
    final c = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 10)],
      pw.Text('DOSSIER DE PRESENTATION', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gris)),
      pw.SizedBox(height: 3),
      pw.Text(nomFerme.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 6),
      pw.Text('Periode : $periodeTxt   -   Etabli le $genere', style: pw.TextStyle(fontSize: 10, color: _doux)),
    ];

    if (choix.objet.isNotEmpty || choix.montant > 0) {
      c.add(pw.SizedBox(height: 14));
      c.add(pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: _creme, border: pw.Border.all(color: _grille, width: 0.6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('OBJET DE LA DEMANDE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _gris)),
          pw.SizedBox(height: 4),
          if (choix.objet.isNotEmpty) pw.Text(_a(choix.objet), style: pw.TextStyle(fontSize: 11, color: _vert)),
          if (choix.montant > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text('Montant souhaite : ${_f(choix.montant)}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _vert)),
            ),
        ]),
      ));
    }

    // chiffres clés
    c.add(_section('1. Chiffres cles de la periode'));
    c.add(_lignes([
      ["Chiffre d'affaires (ventes enregistrees)", _f(global.caBrut)],
      ['Nombre de ventes', '${global.nbVentes}'],
      ['Vente moyenne', global.nbVentes > 0 ? _f(global.caBrut / global.nbVentes) : '-'],
      ['Marge sur les marchandises vendues (CA - prix d\'achat)', _f(global.beneficePur)],
      ['Taux de marge sur marchandises', baseMarge > 0 ? '${margePct.toStringAsFixed(1)} %' : '-'],
      ['Clients differents (clients nommes)', '${clients.length}'],
      ['Jours avec au moins une vente', '${jours.length}'],
      [
        'Part des paiements recus par argent mobile',
        modes.entrees > 0.5 ? '${modes.partMobile.toStringAsFixed(0)} %  (le reste en especes)' : '-'
      ],
    ], gras: {0, 3}));
    if (global.nbSansCout > 0) {
      c.add(_note("${global.nbSansCout} vente(s) sans prix d'achat connu (${_f(global.caSansCout)}) sont comptees dans le chiffre d'affaires "
          'mais pas dans la marge.'));
    }

    // mois par mois
    c.add(_section('2. Evolution mois par mois'));
    final tab = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _vert),
        repeat: true,
        children: [for (final t in ['Mois', 'Ventes', 'Chiffre d\'affaires', 'Marge marchandises', 'Charges saisies', 'Net apres charges']) _cell(t, gras: true, couleur: PdfColors.grey100)],
      ),
    ];
    for (var i = 0; i < lignesMois.length; i++) {
      final l = lignesMois[i];
      final a = l.archive;
      tab.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _creme),
        children: [
          _cell('${_moisNoms[l.mois.month - 1].substring(0, 3)} ${l.mois.year}', gras: true, gauche: true),
          _cell('${l.rev.nbVentes}'),
          _cell(milliersAnglais(l.rev.caBrut)),
          _cell(milliersAnglais(l.rev.beneficePur)),
          _cell(a == null ? 'non saisi' : milliersAnglais(a.totalCharges), couleur: a == null ? _gris : _vert),
          _cell(a == null ? '-' : milliersAnglais(a.net), gras: a != null, couleur: a == null ? _gris : (a.net >= 0 ? _succes : _danger)),
        ],
      ));
    }
    c.add(pw.Table(
      border: pw.TableBorder.all(color: _grille, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(70), 1: pw.FixedColumnWidth(45), 2: pw.FixedColumnWidth(105),
        3: pw.FixedColumnWidth(105), 4: pw.FixedColumnWidth(100), 5: pw.FixedColumnWidth(105),
      },
      children: tab,
    ));
    c.add(_note('Les montants sont en FCFA. Le mois en cours est partiel. Les charges (electricite, transport, salaires, divers) '
        "ne figurent que pour les mois ou l'exploitant les a saisies et archivees dans le logiciel."));

    // graphique
    final valeurs = [for (final l in lignesMois) l.rev.caBrut];
    final vmax = valeurs.fold<double>(0, (s, v) => v > s ? v : s);
    if (vmax > 0) {
      final (pas, nb) = echelleAgreable(vmax, 5);
      c.add(pw.SizedBox(height: 10));
      c.add(pw.Text("Chiffre d'affaires par mois (FCFA)", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _doux)));
      c.add(pw.SizedBox(
        height: 170,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis.fromStrings(
                [for (final l in lignesMois) '${l.mois.month.toString().padLeft(2, '0')}/${(l.mois.year % 100).toString().padLeft(2, '0')}'],
                marginStart: 18, marginEnd: 18),
            yAxis: pw.FixedAxis([for (var i = 0; i <= nb; i++) i * pas], format: (v) => formaterAxe(v.toDouble()), divisions: true),
          ),
          datasets: [
            pw.BarDataSet(
              color: _vert, width: choix.nbMois > 6 ? 14 : 24,
              data: [for (var i = 0; i < valeurs.length; i++) pw.PointChartValue(i.toDouble(), valeurs[i])],
            ),
          ],
        ),
      ));
    }

    // rentabilité
    c.add(_section('3. Rentabilite (sur les mois ou les charges sont saisies)'));
    if (avecCharges.isEmpty) {
      c.add(pw.Text(
          "Aucun mois n'a ses charges saisies et archivees dans le logiciel : le resultat apres charges n'est donc pas calcule. "
          "Seule la marge sur les marchandises ci-dessus est connue.",
          style: pw.TextStyle(fontSize: 10, color: _doux)));
    } else {
      c.add(_lignes([
        ['Mois avec charges saisies', '${avecCharges.length} sur ${lignesMois.length}'],
        ['Total des charges de ces mois', _f(totalCharges)],
        ['Resultat net cumule de ces mois', _f(totalNet)],
        ['Resultat net moyen par mois', _f(netMoyen)],
      ], gras: {3}));
    }
    if (tendance != null) {
      c.add(pw.SizedBox(height: 6));
      c.add(pw.Text("Evolution du chiffre d'affaires : $tendance", style: pw.TextStyle(fontSize: 10, color: _vert)));
    }
    if (meilleur != null && faible != null && meilleur != faible) {
      c.add(pw.SizedBox(height: 3));
      c.add(pw.Text(
          'Meilleur mois : ${nomMois(meilleur.mois)} (${_f(meilleur.rev.caBrut)})  -  Mois le plus faible : ${nomMois(faible.mois)} (${_f(faible.rev.caBrut)})',
          style: pw.TextStyle(fontSize: 10, color: _vert)));
    }

    // situation actuelle
    c.add(_section('4. Situation a ce jour'));
    c.add(_lignes([
      ['Credits clients encore a recouvrer ($nbDebiteurs client(s))', _f(totalCreances)],
      ['Dettes envers les fournisseurs', totalDettesF == null ? 'non disponible' : _f(totalDettesF)],
      ['Valeur du stock (au prix d\'achat)', _f(valeurStock)],
      ["Achats de marchandises et d'aliment sur la periode", _f(achats)],
    ]));

    // élevage
    c.add(_section('5. Elevage'));
    final actives = bandes.where((b) => b['statut'] != 'Épuisée').toList();
    final effectif = actives.fold<int>(0, (s, b) => s + _n(b['effectif_actuel']).toInt());
    c.add(pw.Text('Bandes en cours : ${actives.length}   -   Effectif actuel : $effectif sujets   -   Bandes enregistrees : ${bandes.length}',
        style: pw.TextStyle(fontSize: 10, color: _vert)));
    if (bandes.isNotEmpty) {
      c.add(pw.SizedBox(height: 6));
      final lb = <pw.TableRow>[
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _vert),
          repeat: true,
          children: [for (final t in ['Bande', 'Type', 'Statut', 'Effectif de depart', 'Effectif actuel', 'Mortalite']) _cell(t, gras: true, couleur: PdfColors.grey100)],
        ),
      ];
      final vues = bandes.take(10).toList();
      for (var i = 0; i < vues.length; i++) {
        final b = vues[i];
        final dep = _n(b['effectif_initial']);
        final morts = _n(b['morts_cumulees']);
        lb.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _creme),
          children: [
            _cell(_a('${b['nom'] ?? ''}'), gras: true, gauche: true),
            _cell(_a('${b['type_elevage'] ?? ''}')),
            _cell(_a('${b['statut'] ?? ''}')),
            _cell('${dep.toInt()}'),
            _cell('${_n(b['effectif_actuel']).toInt()}'),
            _cell(dep > 0 ? '${(morts / dep * 100).toStringAsFixed(1)} %' : '-'),
          ],
        ));
      }
      c.add(pw.Table(
        border: pw.TableBorder.all(color: _grille, width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(120), 1: pw.FixedColumnWidth(95), 2: pw.FixedColumnWidth(80),
          3: pw.FixedColumnWidth(85), 4: pw.FixedColumnWidth(80), 5: pw.FixedColumnWidth(70),
        },
        children: lb,
      ));
      if (bandes.length > 10) c.add(_note('Les 10 bandes les plus recentes sont affichees sur ${bandes.length}.'));
    }

    // signature + avertissement
    c.add(pw.SizedBox(height: 26));
    c.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Fait a ______________________, le ____ / ____ / ________', style: pw.TextStyle(fontSize: 10, color: _vert)),
      pw.Text("Nom et signature de l'exploitant :", style: pw.TextStyle(fontSize: 10, color: _vert)),
    ]));
    c.add(pw.SizedBox(height: 40));
    c.add(pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(color: _creme, border: pw.Border.all(color: _grille, width: 0.6), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Text(
          "Important : ce document est etabli par l'exploitant a partir des ventes, achats et stocks qu'il a enregistres dans le logiciel Hakili. "
          "Il n'a pas ete audite ni certifie par un comptable ou un organisme independant. Les chiffres ne valent que ce que valent les saisies.",
          style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: _doux)),
    ));

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => c,
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('$nomFerme - dossier genere par Hakili (Antoine Software)', style: pw.TextStyle(fontSize: 8, color: _gris)),
          pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: _gris)),
        ]),
      ),
    ));

    final suffixe = '${auj.month.toString().padLeft(2, '0')}-${auj.year}';
    final lieu = await getSaveLocation(
      suggestedName: 'Dossier_Banque_$suffixe.pdf',
      acceptedTypeGroups: const [XTypeGroup(label: 'Documents PDF', extensions: ['pdf'])],
      confirmButtonText: 'Enregistrer',
    );
    if (lieu == null) return false;
    var chemin = lieu.path;
    if (!chemin.toLowerCase().endsWith('.pdf')) chemin = '$chemin.pdf';
    await File(chemin).writeAsBytes(await doc.save());
    return true;
  }
}

class _LigneMois {
  final DateTime mois;
  final RevenuCaisse rev;
  final BilanArchive? archive;
  _LigneMois(this.mois, this.rev, this.archive);
}

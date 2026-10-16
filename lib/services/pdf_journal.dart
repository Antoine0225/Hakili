import 'dart:io';

import 'logo_pdf.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/journal_repo.dart';
import '../session.dart';
import '../utilitaires/formats.dart';
import '../utilitaires/texte_pdf.dart';

/// 📄 Le journal des modifications en PDF (avec les filtres choisis à l'écran).
class PdfJournal {
  PdfJournal._();

  static final _vert = PdfColor.fromHex('#123229');
  static final _cuivre = PdfColor.fromHex('#b8651f');
  static final _doux = PdfColor.fromHex('#4d5f56');
  static final _gris = PdfColor.fromHex('#6f7d75');
  static final _grille = PdfColor.fromHex('#d8d1c2');
  static final _creme = PdfColor.fromHex('#faf8f5');
  static final _succes = PdfColor.fromHex('#2f7d4f');
  static final _alerte = PdfColor.fromHex('#b98a1e');
  static final _danger = PdfColor.fromHex('#b3372a');
  static final _rouge = PdfColor.fromHex('#fbeceb');

  static PdfColor _couleur(String a) => switch (a) {
        'AJOUT' => _succes,
        'MODIFIÉ' => _alerte,
        'SUPPRIMÉ' || 'ÉCHEC' || 'ÉCART' => _danger,
        'CONTRÔLE' => _succes,
        _ => _doux,
      };

  static String _libelle(String a) => switch (a) {
        'AJOUT' => 'AJOUT',
        'MODIFIÉ' => 'MODIFIE',
        'SUPPRIMÉ' => 'SUPPRIME',
        'ÉCHEC' => 'PIN FAUX',
        'ÉCART' => 'ECART CAISSE',
        'CONTRÔLE' => 'CAISSE JUSTE',
        _ => sansAccents(a),
      };

  static pw.Widget _cell(String t, {bool gras = false, PdfColor? couleur, double taille = 8}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: taille, fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal, color: couleur ?? _vert)),
      );

  /// [entrees] : les événements à imprimer (du plus récent au plus ancien) ; [filtres] : phrase décrivant les filtres.
  /// Renvoie true si le fichier a été enregistré, false si la personne a annulé.
  static Future<bool> exporter({
    required List<EntreeJournal> entrees, required BilanJournal bilan, required String filtres, required bool tronque,
  }) async {
    final nomFerme = sansAccents(Session.nomFerme.trim().isEmpty ? 'Exploitation avicole' : Session.nomFerme.trim());
    final n = DateTime.now();
    final genere = '${jourEnTexte(n)} a ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';

    final lignes = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _vert),
        repeat: true,
        children: [for (final t in ['Date et heure', 'Session', 'Action', 'Sujet', 'Detail']) _cell(t, gras: true, couleur: PdfColors.grey100)],
      ),
    ];
    for (var i = 0; i < entrees.length; i++) {
      final e = entrees[i];
      final risque = ((e.action == 'SUPPRIMÉ' || e.action == 'ÉCHEC') && e.session != 'Patron') || e.action == 'ÉCART';
      final fond = risque ? _rouge : (i.isEven ? PdfColors.white : _creme);
      lignes.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: fond),
        children: [
          _cell(e.quandAffiche),
          _cell(e.session.isEmpty ? '-' : sansAccents(e.session), gras: e.session == 'Ouvrier'),
          _cell(_libelle(e.action), gras: true, couleur: _couleur(e.action)),
          _cell(sansAccents(e.categorie)),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(sansAccents(e.objet), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _vert)),
              if (e.ancien.isNotEmpty && e.nouveau.isNotEmpty) ...[
                pw.Text('Avant : ${sansAccents(e.ancien)}', style: pw.TextStyle(fontSize: 7.5, color: _doux)),
                pw.Text('Apres : ${sansAccents(e.nouveau)}', style: pw.TextStyle(fontSize: 7.5, color: _vert)),
              ] else if (e.ancien.isNotEmpty)
                pw.Text(sansAccents(e.ancien), style: pw.TextStyle(fontSize: 7.5, color: _doux))
              else if (e.nouveau.isNotEmpty)
                pw.Text(sansAccents(e.nouveau), style: pw.TextStyle(fontSize: 7.5, color: _doux)),
            ]),
          ),
        ],
      ));
    }

    final logo = await LogoPdf.widget();
    final contenu = <pw.Widget>[
      if (logo != null) ...[logo, pw.SizedBox(height: 8)],
      pw.Text('JOURNAL DES MODIFICATIONS - ${nomFerme.toUpperCase()}',
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _cuivre)),
      pw.SizedBox(height: 4),
      pw.Text('Etabli le $genere  -  ${sansAccents(filtres)}', style: pw.TextStyle(fontSize: 9, color: _doux)),
      pw.SizedBox(height: 4),
      pw.Text(
          '${bilan.total} evenement(s) : ${bilan.ajouts} ajout(s), ${bilan.modifications} modification(s), '
          '${bilan.suppressions} suppression(s)${bilan.autres > 0 ? ', ${bilan.autres} connexion(s) / alerte(s)' : ''}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _vert)),
      if (tronque)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text('Les ${entrees.length} evenements les plus recents sont imprimes : reduisez la periode pour voir le reste.',
              style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: _danger)),
        ),
      pw.SizedBox(height: 10),
      if (entrees.isEmpty)
        pw.Text('Rien a afficher pour ces filtres.', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: _gris))
      else
        pw.Table(
          border: pw.TableBorder.all(color: _grille, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(78), 1: pw.FixedColumnWidth(52), 2: pw.FixedColumnWidth(68), 3: pw.FixedColumnWidth(58),
            4: pw.FlexColumnWidth(),
          },
          children: lignes,
        ),
      pw.SizedBox(height: 10),
      pw.Text(
          "Les lignes sur fond rose sont les suppressions et alertes faites hors session Patron, ou un ecart de caisse. "
          "Ce journal est propre a ce PC : il est tenu automatiquement par le logiciel.",
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: _gris)),
    ];

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(30),
      build: (_) => contenu,
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('$nomFerme - journal genere par Hakili (Antoine Software)', style: pw.TextStyle(fontSize: 8, color: _gris)),
          pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8, color: _gris)),
        ]),
      ),
    ));

    final suffixe = '${n.day.toString().padLeft(2, '0')}-${n.month.toString().padLeft(2, '0')}-${n.year}';
    final lieu = await getSaveLocation(
      suggestedName: 'Journal_Modifications_$suffixe.pdf',
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

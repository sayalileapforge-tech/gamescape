// lib/services/invoice_pdf_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InvoicePdfService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Change this path to your actual asset path.
  // Make sure to add it under pubspec.yaml -> flutter -> assets:
  //   - assets/images/gamescape_logo.png
  static const String kLogoAssetPath = 'assets/images/gamescape_logo.png';

  Future<void> generateAndPrint({
    required String branchId,
    required String sessionId,
  }) async {
    // Load session + orders
    final sessionRef = _db
        .collection('branches')
        .doc(branchId)
        .collection('sessions')
        .doc(sessionId);

    final sessionSnap = await sessionRef.get();
    final s = sessionSnap.data() ?? {};

    final ordersSnap = await sessionRef.collection('orders').get();
    final orders = ordersSnap.docs.map((d) => d.data()).toList();

    // Try to load logo (safe fallback if missing)
    final pw.ImageProvider? logo = await _tryLoadLogo();

    // Build PDF
    final pdf = pw.Document();

    final fontTheme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.montserratRegular(),
      bold: await PdfGoogleFonts.montserratBold(),
      italic: await PdfGoogleFonts.montserratItalic(),
      boldItalic: await PdfGoogleFonts.montserratBoldItalic(),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
          textDirection: pw.TextDirection.ltr,
          theme: fontTheme,
        ),
        build: (ctx) => [
          _header(s, logo: logo),
          pw.SizedBox(height: 14),
          _metaRow(s, branchId),
          pw.SizedBox(height: 18),
          _segmentsTable(s),
          pw.SizedBox(height: 12),
          _ordersTable(orders),
          pw.SizedBox(height: 14),
          _totalsBlock(s),
          if (s['itemsOnly'] == true) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Items-only sale (no playtime charges).',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 24),
          _paymentsBlock(s),
          pw.SizedBox(height: 12),
          _footerNote(),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  Future<pw.ImageProvider?> _tryLoadLogo() async {
    try {
      final data = await rootBundle.load(kLogoAssetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;
      return pw.MemoryImage(bytes);
    } catch (_) {
      // Asset missing or not declared in pubspec -> fallback to default block.
      return null;
    }
  }

  // ---------- sections ----------
  pw.Widget _header(Map<String, dynamic> s, {pw.ImageProvider? logo}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // LOGO (if available) else old "G" block
          pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              color: logo == null ? PdfColor.fromInt(0xFF6C63FF) : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
              border: logo == null ? null : pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            alignment: pw.Alignment.center,
            child: logo != null
                ? pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Image(logo, fit: pw.BoxFit.cover),
                  )
                : pw.Text(
                    'G',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'GameScape',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
                ),
                pw.Text(
                  'Invoice',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.Text(
            '${s['invoiceNumber'] ?? '-'}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _metaRow(Map<String, dynamic> s, String branchId) {
    final startTs =
        (s['startTime'] is Timestamp) ? (s['startTime'] as Timestamp).toDate() : null;
    final closedTs =
        (s['closedAt'] is Timestamp) ? (s['closedAt'] as Timestamp).toDate() : null;
    final itemsOnly = s['itemsOnly'] == true;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _kv('Customer', (s['customerName'] ?? 'Walk-in').toString()),
              _kv('Phone', (s['customerPhone'] ?? '-').toString()),
              _kv('Players', '${s['pax'] ?? 1}'),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _kv('Branch', (s['branchName'] ?? branchId).toString()),
              _kv('Start', startTs != null ? startTs.toLocal().toString() : '-'),
              _kv('Closed', closedTs != null ? closedTs.toLocal().toString() : '-'),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _kv('Payment Type', (s['paymentType'] ?? 'postpaid').toString()),
              _kv('Payment Status', (s['paymentStatus'] ?? 'pending').toString()),
              _kv('Played Minutes', '${s['playedMinutes'] ?? 0}'),
              if (itemsOnly) _kv('Mode', 'Items-only'),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _segmentsTable(Map<String, dynamic> s) {
    final segs = (s['seatSegments'] as List?)?.cast<Map>() ?? const [];
    if (segs.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: _box(),
        child: pw.Text(
          'Seat Segments: None',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
      );
    }

    return pw.Container(
      decoration: _box(),
      child: pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(2),
          3: pw.FlexColumnWidth(2),
          4: pw.FlexColumnWidth(2),
        },
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
        ),
        children: [
          _th(['Seat', 'From', 'To', 'Billed (min)', 'Amount']),
          ...segs.map<pw.TableRow>((m) {
            final from = (m['from'] is Timestamp)
                ? (m['from'] as Timestamp).toDate().toLocal()
                : null;
            final to = (m['to'] is Timestamp)
                ? (m['to'] as Timestamp).toDate().toLocal()
                : null;
            final amt = _num(m['billedAmount']);
            return _tr([
              '${m['seatLabel'] ?? m['seatId'] ?? '-'}',
              from?.toString() ?? '-',
              to?.toString() ?? '-',
              '${m['billedMinutes'] ?? 0}',
              '₹${_money(amt)}',
            ]);
          }).toList(),
        ],
      ),
    );
  }

  pw.Widget _ordersTable(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: _box(),
        child: pw.Text(
          'Orders: None',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
      );
    }

    return pw.Container(
      decoration: _box(),
      child: pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(5),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(2),
        },
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
        ),
        children: [
          _th(['Item', 'Qty', 'Total']),
          ...orders.map<pw.TableRow>((o) => _tr([
                '${o['itemName'] ?? 'Item'}',
                '${o['qty'] ?? 1}',
                '₹${_money(_num(o['total']))}',
              ])),
        ],
      ),
    );
  }

  pw.Widget _totalsBlock(Map<String, dynamic> s) {
    final ordersSub = _num(s['ordersSubtotal']);
    final subtotal = _num(s['subtotal']);
    final taxPercent = _num(s['taxPercent']);
    final taxAmount = _num(s['taxAmount']);
    final discount = _num(s['discount']);
    final grand = _num(s['billAmount']);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: _box(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _kvR('Orders Subtotal', '₹${_money(ordersSub)}'),
          _kvR('Discount', '₹${_money(discount)}'),
          _kvR('Subtotal', '₹${_money(subtotal)}'),
          _kvR('Tax (${_money(taxPercent)}%)', '₹${_money(taxAmount)}'),
          pw.SizedBox(height: 6),
          pw.Container(
            color: PdfColors.grey100,
            padding: const pw.EdgeInsets.all(8),
            child: _kvRBold('Total Payable', '₹${_money(grand)}'),
          ),
        ],
      ),
    );
  }

  pw.Widget _paymentsBlock(Map<String, dynamic> s) {
    final payments = (s['payments'] as List?)?.cast<Map>() ?? const [];
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: _box(),
      child: payments.isEmpty
          ? pw.Text(
              'Payments: None',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: payments
                  .map((p) => pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${(p['mode'] ?? 'Mode').toString().toUpperCase()}'),
                          pw.Text(
                            '₹${_money(_num(p['amount']))}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ))
                  .toList(),
            ),
    );
  }

  pw.Widget _footerNote() {
    return pw.Center(
      child: pw.Text(
        'Thank you for playing at GameScape!',
        style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
      ),
    );
  }

  // ---------- tiny helpers ----------
  pw.BoxDecoration _box() => pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      );

  pw.TableRow _th(List<String> cols) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
      children: cols
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: pw.Text(
                  c,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ))
          .toList(),
    );
  }

  pw.TableRow _tr(List<String> cols) {
    return pw.TableRow(
      children: cols
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 10)),
              ))
          .toList(),
    );
  }

  pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Container(
            width: 90,
            child: pw.Text(
              k,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10))),
        ]),
      );

  pw.Widget _kvR(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text(k), pw.Text(v)],
        ),
      );

  pw.Widget _kvRBold(String k, String v) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      );

  num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  String _money(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

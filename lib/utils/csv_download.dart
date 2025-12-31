// lib/utils/csv_download.dart
import 'dart:convert';
import 'dart:html' as html;

/// Only works on Flutter Web.
/// For mobile/desktop, use share_plus or file saving.
void downloadCsvWeb(String csvContent, {String filename = 'report.csv'}) {
  final bytes = utf8.encode(csvContent);
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

// lib/data/models/booking_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BookingModel {
  final String id;
  final String customerName;
  final String? customerPhone;
  final String branchId;
  final String branchName;
  final String seatId;
  final String seatLabel;
  final DateTime startTime;
  final String status; // active, completed, moved, cancelled
  final String? notes;

  // Additive metadata for richer logic
  final String? seatType;
  final String? paymentType;          // prepaid | postpaid
  final int? durationMinutes;
  final String? createdBy;
  final String? createdByName;

  // ✅ Additive billing fields (optional, for reports/exports/UI)
  final int? pax;
  final bool? itemsOnly;
  final num? ordersSubtotal;
  final num? subtotal;
  final num? taxPercent;
  final num? taxAmount;
  final num? discount;
  final num? billAmount;
  final int? playedMinutes;
  final String? paymentStatus;        // pending | paid
  final String? invoiceNumber;

  BookingModel({
    required this.id,
    required this.customerName,
    this.customerPhone,
    required this.branchId,
    required this.branchName,
    required this.seatId,
    required this.seatLabel,
    required this.startTime,
    required this.status,
    this.notes,
    this.seatType,
    this.paymentType,
    this.durationMinutes,
    this.createdBy,
    this.createdByName,
    this.pax,
    this.itemsOnly,
    this.ordersSubtotal,
    this.subtotal,
    this.taxPercent,
    this.taxAmount,
    this.discount,
    this.billAmount,
    this.playedMinutes,
    this.paymentStatus,
    this.invoiceNumber,
  });

  factory BookingModel.fromMap(String id, Map<String, dynamic> data) {
    return BookingModel(
      id: id,
      customerName: data['customerName'] ?? '',
      customerPhone: data['customerPhone'],
      branchId: data['branchId'] ?? '',
      branchName: data['branchName'] ?? '',
      seatId: data['seatId'] ?? '',
      seatLabel: data['seatLabel'] ?? '',
      startTime: (data['startTime'] as Timestamp).toDate(),
      status: data['status'] ?? 'active',
      notes: data['notes'],
      seatType: data['seatType'],
      paymentType: data['paymentType'],
      durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
      createdBy: data['createdBy'],
      createdByName: data['createdByName'],

      // Optional billing fields (null-safe)
      pax: (data['pax'] as num?)?.toInt(),
      itemsOnly: data['itemsOnly'] == true,
      ordersSubtotal: _asNumOrNull(data['ordersSubtotal']),
      subtotal: _asNumOrNull(data['subtotal']),
      taxPercent: _asNumOrNull(data['taxPercent']),
      taxAmount: _asNumOrNull(data['taxAmount']),
      discount: _asNumOrNull(data['discount']),
      billAmount: _asNumOrNull(data['billAmount']),
      playedMinutes: (data['playedMinutes'] as num?)?.toInt(),
      paymentStatus: data['paymentStatus'],
      invoiceNumber: data['invoiceNumber'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'branchId': branchId,
      'branchName': branchName,
      'seatId': seatId,
      'seatLabel': seatLabel,
      'startTime': startTime,
      'status': status,
      'notes': notes,
      if (seatType != null) 'seatType': seatType,
      if (paymentType != null) 'paymentType': paymentType,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (createdBy != null) 'createdBy': createdBy,
      if (createdByName != null) 'createdByName': createdByName,

      // Optional billing fields (only write when present)
      if (pax != null) 'pax': pax,
      if (itemsOnly != null) 'itemsOnly': itemsOnly,
      if (ordersSubtotal != null) 'ordersSubtotal': ordersSubtotal,
      if (subtotal != null) 'subtotal': subtotal,
      if (taxPercent != null) 'taxPercent': taxPercent,
      if (taxAmount != null) 'taxAmount': taxAmount,
      if (discount != null) 'discount': discount,
      if (billAmount != null) 'billAmount': billAmount,
      if (playedMinutes != null) 'playedMinutes': playedMinutes,
      if (paymentStatus != null) 'paymentStatus': paymentStatus,
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
    };
  }
}

num? _asNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

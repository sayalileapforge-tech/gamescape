import 'dart:async';
import 'package:flutter/material.dart';

class BookingCountdown extends StatefulWidget {
  final DateTime endTime;
  const BookingCountdown({super.key, required this.endTime});

  @override
  State<BookingCountdown> createState() => _BookingCountdownState();
}

class _BookingCountdownState extends State<BookingCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.endTime.difference(DateTime.now());
    if (_remaining.isNegative) {
      _remaining = Duration.zero;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final diff = widget.endTime.difference(DateTime.now());
      if (!mounted) return;
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
      if (diff.isNegative) {
        t.cancel();
      }
    });
  }

  @override
  void didUpdateWidget(BookingCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endTime != widget.endTime) {
      _remaining = widget.endTime.difference(DateTime.now());
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return const Text(
        'Expired',
        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500),
      );
    }

    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);

    return Text(
      'Time left: ${_fmt(h)}:${_fmt(m)}:${_fmt(s)}',
      style: TextStyle(
        color: _remaining.inMinutes < 5 ? Colors.orangeAccent : Colors.greenAccent,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

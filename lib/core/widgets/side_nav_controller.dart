import 'package:flutter/foundation.dart';

class SideNavController extends ChangeNotifier {
  bool _isExpanded = false;
  bool _isReorderMode = false;

  bool get isExpanded => _isExpanded;
  bool get isReorderMode => _isReorderMode;

  void toggle() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void setExpanded(bool v) {
    _isExpanded = v;
    notifyListeners();
  }

  void toggleReorder() {
    _isReorderMode = !_isReorderMode;
    notifyListeners();
  }

  void setReorderMode(bool v) {
    _isReorderMode = v;
    notifyListeners();
  }
}

// global singleton
final sideNavController = SideNavController();

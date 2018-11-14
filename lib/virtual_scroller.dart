import 'dart:html';

import 'package:meta/meta.dart';
import 'package:virtual_scroller/layout.dart';

typedef Element CreateElement(int idx);
typedef Element UpdateElement(Element child, int idx);
typedef Element RecycleElement(Element child, int idx);

class VirtualScroller {
  final Layout1dBase layout;
  final Element container;
  final CreateElement createElement;
  final UpdateElement updateElement;
  final RecycleElement recycleElement;

  VirtualScroller({
    @required this.layout,
    @required this.container,
    @required this.createElement,
    @required this.updateElement,
    @required this.recycleElement,
  });
}

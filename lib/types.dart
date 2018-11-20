// TODO: rename to Offset
import 'package:meta/meta.dart';

class Coords {
  final num left;
  final num top;
  Coords({this.left, this.top});
  String toString() => "[left $left, top $top]";
}

class Size {
  num width;
  num height;
  Size({this.width, this.height});
}

class VSEvent {}

class ScrollSizeChangedEvent implements VSEvent {
  num height;
  num width;
  ScrollSizeChangedEvent({this.height, this.width});
}

class RangeChangedEvent implements VSEvent {
  final int first;
  final int last;
  final int num;
  bool stable;
  bool remeasure;
  RangeChangedEvent({
    this.first,
    this.last,
    this.num,
    this.stable = false,
    this.remeasure = false,
  });
}

class ItemPositionChangedEvent implements VSEvent {
  Map<num, Coords> indexToPos = {};
  ItemPositionChangedEvent(this.indexToPos);
}

class ToMeasure {
  List indices;
  List children;
  ToMeasure({
    @required this.indices,
    @required this.children,
  });
}

class Margin {
  num marginTop;
  num marginRight;
  num marginBottom;
  num marginLeft;
  Margin({
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
  });
  String toString() => "$marginTop $marginRight $marginBottom $marginLeft";
}

class ScrollEvent implements VSEvent {}

class Metrics {
  num height;
  num width;
  num marginTop;
  num marginBottom;
  num marginLeft;
  num marginRight;
  Metrics({
    this.height,
    this.width,
    this.marginTop,
    this.marginBottom,
    this.marginLeft,
    this.marginRight,
  });
}

// TODO: rename to Offset
class Coords {
  final int left;
  final int top;
  Coords({this.left, this.top});
}

class Size {
  int width;
  int height;
  Size({this.width, this.height});
}

class VSEvent {}

class ScrollSizeChangedEvent implements VSEvent {
  int height;
  int width;
  ScrollSizeChangedEvent({this.height, this.width});
}

class RangeChangedEvent implements VSEvent {
  final int first;
  final int last;
  final int num;
  final bool stable;
  final bool remeasure;
  RangeChangedEvent({
    this.first,
    this.last,
    this.num,
    this.stable = false,
    this.remeasure = false,
  });
}

class ItemPositionChangedEvent implements VSEvent {
  Map<int, Coords> indexToPos = {};
  ItemPositionChangedEvent(this.indexToPos);
}

class ToMeasure {
  List indices;
  List children;
  ToMeasure({this.indices, this.children});
}

class Margin {
  int marginTop;
  int marginRight;
  int marginBottom;
  int marginLeft;
  Margin({
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
  });
}

class ScrollEvent implements VSEvent {}

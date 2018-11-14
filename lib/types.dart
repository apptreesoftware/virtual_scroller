class Coords {
  final int left;
  final int top;
  Coords({this.left, this.top});
}

class Size {
  final int width;
  final int height;
  Size({this.width, this.height});
}

class VSEvent {

}

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
  RangeChangedEvent({this.first, this.last, this.num, this.stable = false});
}

class ItemPositionChangedEvent implements VSEvent {
  Map<int, int> indexToPos = {};
  ItemPositionChangedEvent(this.indexToPos);
}
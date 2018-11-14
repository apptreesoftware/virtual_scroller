class Layout extends Layout1dBase {
  Layout({
    String direction,
    int overhang,
  }) : super(direction: direction, overhang: overhang) {}
}

class Layout1dBase {
  final String direction;
  final int overhang;
  Layout1dBase({this.direction, this.overhang});
}

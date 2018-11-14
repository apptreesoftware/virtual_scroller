import 'dart:async';
import 'dart:math' as math;
import 'package:virtual_scroller/types.dart';

class Layout extends Layout1dBase {
  Layout({
    String direction,
    int overhang,
  }) : super(direction: direction, overhang: overhang) {}
}

class Layout1dBase {
  StreamController<VSEvent> _eventSink = StreamController<VSEvent>.broadcast();

  var _physicalMin = 0;
  var _physicalMax = 0;

  var _first = -1;
  var _last = -1;

  Coords _latestCoords = Coords(left: 0, top: 0);

  var _itemSize = Size(width: 100, height: 100);
  var _spacing = 0;

  var _sizeDim = 'height';
  var _secondarySizeDim = 'width';
  var _positionDim = 'top';
  var _secondaryPositionDim = 'left';
  var _direction = 'vertical';

  int _scrollPosition = 0;
  var _scrollError = 0;
  Size _viewportSize = Size(width: 0, height: 0);
  var _totalItems = 0;

  var _scrollSize = 1;

  int _overhang = 150;

  var _pendingReflow = false;

  var _scrollToIndex = -1;
  num _scrollToAnchor = 0;

  // todo: from layout-1d-grid
  bool _spacingChanged = false;

  // TODO: correct?
  Layout1dBase({direction, overhang});

  // public properties

  get totalItems {
    return this._totalItems;
  }

  set totalItems(num) {
    if (num != this._totalItems) {
      this._totalItems = num;
      this._scheduleReflow();
    }
  }

  get direction {
    return this._direction;
  }

  set direction(dir) {
    // Force it to be either horizontal or vertical.
    dir = (dir == 'horizontal') ? dir : 'vertical';
    if (dir != this._direction) {
      this._direction = dir;
      this._sizeDim = (dir == 'horizontal') ? 'width' : 'height';
      this._secondarySizeDim = (dir == 'horizontal') ? 'height' : 'width';
      this._positionDim = (dir == 'horizontal') ? 'left' : 'top';
      this._secondaryPositionDim = (dir == 'horizontal') ? 'top' : 'left';
      this._scheduleReflow();
    }
  }

  Size get itemSize {
    return this._itemSize;
  }

  set itemSize(Size dims) {
    var _itemDim1 = dims.width;
    var _itemDim2 = dims.height;
    this._itemSize = dims;
    if (_itemDim1 != this._itemDim1 || _itemDim2 != this._itemDim2) {
      if (_itemDim2 != this._itemDim2) {
        this._itemDim2Changed();
      } else {
        this._scheduleReflow();
      }
    }
  }

  get spacing {
    return this._spacing;
  }

  set spacing(px) {
    if (px != this._spacing) {
      this._spacing = px;
      this._scheduleReflow();
    }
  }

  Size get viewportSize {
    return this._viewportSize;
  }

  set viewportSize(Size dims) {
    var _viewDim1 = dims.width;
    var _viewDim2 = dims.height;
    this._viewportSize = dims;
    if (_viewDim2 != this._viewDim2) {
      this._viewDim2Changed();
    } else if (_viewDim1 != this._viewDim1) {
      this._checkThresholds();
    }
  }

  get viewportScroll {
    return this._latestCoords;
  }

  set viewportScroll(coords) {
    this._latestCoords = coords;
    var oldPos = this._scrollPosition;
    var topOrLeft = this._positionDim == 'top'
        ? this._latestCoords.top
        : this._latestCoords.left;
    this._scrollPosition = topOrLeft;
    if (oldPos != this._scrollPosition) {
      this._scrollPositionChanged(oldPos, this._scrollPosition);
    }
    this._checkThresholds();
  }

  // private properties

  get _delta {
    return this._itemDim1 + this._spacing;
  }

  get _itemDim1 {
    if (this._sizeDim == 'height') {
      return _itemSize.height;
    } else {
      return _itemSize.width;
    }
  }

  get _itemDim2 {
    if (this._secondarySizeDim == 'height') {
      return _itemSize.height;
    } else {
      return _itemSize.width;
    }
  }

  get _viewDim1 {
    if (this._sizeDim == 'height') {
      return this._viewportSize.height;
    } else {
      return this._viewportSize.width;
    }
  }

  get _viewDim2 {
    if (this._secondarySizeDim == 'height') {
      return _viewportSize.height;
    } else {
      return _viewportSize.width;
    }
  }

  get _num {
    if (this._first == -1 || this._last == -1) {
      return 0;
    }
    return this._last - this._first + 1;
  }

  // public methods

  reflowIfNeeded() {
    if (this._pendingReflow) {
      this._pendingReflow = false;
      this._reflow();
    }
  }

  scrollToIndex(num index, [position = 'start']) {
    index = math.min(this.totalItems, math.max(0, index));
    this._scrollToIndex = index;
    if (position == 'nearest') {
      position = index > this._first + this._num / 2 ? 'end' : 'start';
    }
    switch (position) {
      case 'start':
        this._scrollToAnchor = 0;
        break;
      case 'center':
        this._scrollToAnchor = 0.5;
        break;
      case 'end':
        this._scrollToAnchor = 1;
        break;
      default:
        throw 'position must be one of: start, center, end, nearest';
    }
    this._scheduleReflow();
    this.reflowIfNeeded();
  }

  ///

  _scheduleReflow() {
    this._pendingReflow = true;
  }

  _reflow() {
    var _first = this._first;
    var _last = this._last;
    var _scrollSize = this._scrollSize;

    this._updateScrollSize();
    this._getActiveItems();
    this._scrollIfNeeded();

    if (this._scrollSize != _scrollSize) {
      this._emitScrollSize();
    }

    if (this._first == -1 && this._last == -1) {
      this._emitRange(null); // todo ???
    } else if (this._first != _first ||
        this._last != _last ||
        this._spacingChanged) {
      this._emitRange(null); // todo ???
      this._emitChildPositions();
    }
    this._emitScrollError();
  }

  _updateScrollSize() {
    // Ensure we have at least 1px - this allows getting at least 1 item to be
    // rendered.
    this._scrollSize = math.max(1, this._totalItems * this._delta);
  }

  _checkThresholds() {
    if (this._viewDim1 == 0 && this._num > 0) {
      this._scheduleReflow();
    } else {
      var min = math.max(0, this._scrollPosition - this._overhang);
      var max = math.min(this._scrollSize,
          this._scrollPosition + this._viewDim1 + this._overhang);
      if (this._physicalMin > min || this._physicalMax < max) {
        this._scheduleReflow();
      }
    }
  }

  _scrollIfNeeded() {
    if (this._scrollToIndex == -1) {
      return;
    }
    var index = this._scrollToIndex;
    var anchor = this._scrollToAnchor;
    var pos = this._getItemPosition(index)[this._positionDim];
    var size = this._getItemSize(index)[this._sizeDim];

    var curAnchorPos = this._scrollPosition + this._viewDim1 * anchor;
    var newAnchorPos = pos + size * anchor;
    // Ensure scroll position is an integer within scroll bounds.
    var scrollPosition = (math.min(this._scrollSize - this._viewDim1,
            math.max(0, this._scrollPosition - curAnchorPos + newAnchorPos)))
        .floor();
    this._scrollError += this._scrollPosition - scrollPosition;
    this._scrollPosition = scrollPosition;
  }

  _emitRange(inProps) {
    this.dispatchEvent(new RangeChangedEvent(
        first: _first, last: _last, num: _num, stable: true));
  }

  _emitScrollSize() {
    if (this._sizeDim == 'height') {
      this.dispatchEvent(new ScrollSizeChangedEvent(height: this._scrollSize));
    } else {
      this.dispatchEvent(new ScrollSizeChangedEvent(width: this._scrollSize));
    }
  }

  _emitScrollError() {
//    if (this._scrollError != 0) {
//      const detail = {
//        [this._positionDim]: this._scrollError,
//        [this._secondaryPositionDim]: 0,
//      };
//      this.dispatchEvent(new CustomEvent('scrollerrorchange', {detail}));
//      this._scrollError = 0;
//    }
  }

  _emitChildPositions() {
    var detail = {};
    for (var idx = this._first; idx <= this._last; idx++) {
      detail[idx] = this._getItemPosition(idx);
    }
    this.dispatchEvent(ItemPositionChangedEvent(detail));
  }

  _itemDim2Changed() {
    // Override
  }

  _viewDim2Changed() {
    // Override
  }

  _scrollPositionChanged(oldPos, newPos) {
    // When both values are bigger than the max scroll position, keep the
    // current _scrollToIndex, otherwise invalidate it.
    var maxPos = this._scrollSize - this._viewDim1;
    if (oldPos < maxPos || newPos < maxPos) {
      this._scrollToIndex = -1;
    }
  }

  _getActiveItems() {
    // Override
  }

  _getItemPosition(idx) {
    // Override.
  }

  _getItemSize(idx) {
    // Override.
    return {
      [this._sizeDim]: this._itemDim1,
      [this._secondarySizeDim]: this._itemDim2,
    };
  }

  void dispatchEvent(VSEvent event) {
    _eventSink.add(event);
  }
}

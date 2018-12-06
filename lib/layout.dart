import 'dart:async';
import 'dart:math' as math;
import 'package:virtual_scroller/types.dart';

class Layout extends Layout1dBase {
  Map _physicalItems = new Map();
  Map _newPhysicalItems = new Map();

  Map _metrics = new Map();

  var _anchorIdx;
  var _anchorPos;
  var _stable = true;

  var _needsRemeasure = false;

  var _nMeasured = 0;
  var _tMeasured = 0;

  var _estimate = true;
  var _maxIdx;

  Layout({
    String direction,
    int overhang,
  }) : super(direction: direction, overhang: overhang) {}

  bool hasUpdateItemSizesFn = true;
  updateItemSizes(Map<int, Metrics> sizes) {
    sizes.keys.forEach((key) {
      var metrics = sizes[key],
          mi = this._getMetrics(key),
          prevSize = mi[this._sizeDim];

      // TODO(valdrin) Handle margin collapsing.
      // https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Box_Model/Mastering_margin_collapsing
      mi['width'] = metrics.width +
          (metrics.marginLeft ?? 0) +
          (metrics.marginRight ?? 0);
      mi['height'] = metrics.height +
          (metrics.marginTop ?? 0) +
          (metrics.marginBottom ?? 0);

      int size;
      if (this._sizeDim == "height") {
        size = mi['height'];
      } else {
        size = mi['width'];
      }
      var item = this._getPhysicalItem(key);
      if (item != null) {
        var delta;

        if (size != null) {
          item['size'] = size;
          if (prevSize == null) {
            delta = size;
            this._nMeasured++;
          } else {
            delta = size - prevSize;
          }
        }
        this._tMeasured = this._tMeasured + delta;
      }
    });
    if (this._nMeasured == null) {
    } else {
      this._updateItemSize();
      this._scheduleReflow();
    }
  }

  _updateItemSize() {
    // Keep integer values.
    if (this._sizeDim == "height") {
      this._itemSize.height = (this._tMeasured / this._nMeasured).round();
    } else {
      this._itemSize.width = (this._tMeasured / this._nMeasured).round();
    }
  }

  _getMetrics(idx) {
    return (this._metrics[idx] = this._metrics[idx] ?? {});
  }

  _getPhysicalItem(int idx) {
    return this._newPhysicalItems[idx] ?? this._physicalItems[idx];
  }

  _getSize(idx) {
    var item = this._getPhysicalItem(idx);
    return item != null ? item['size'] : null;
  }

  _getPosition(idx) {
    var item = this._physicalItems[idx];
    var result =
        item != null ? item['pos'] : (idx * (this._delta)) + this._spacing;
    return result;
  }

  _calculateAnchor(num lower, num upper) {
    if (lower == 0) {
      return 0;
    }
    if (upper > this._scrollSize - this._viewDim1) {
      return this._totalItems - 1;
    }
    return math.max(
        0,
        math.min(this._totalItems - 1,
            (((lower + upper) / 2) / this._delta).floor()));
  }

  _getAnchor(num lower, num upper) {
    if (this._physicalItems['size'] == 0) {
      return this._calculateAnchor(lower, upper);
    }
    if (this._first < 0) {
      return this._calculateAnchor(lower, upper);
    }
    if (this._last < 0) {
      return this._calculateAnchor(lower, upper);
    }

    var firstItem = this._getPhysicalItem(this._first),
        lastItem = this._getPhysicalItem(this._last),
        firstMin = firstItem['pos'],
        firstMax = firstMin + firstItem['size'],
        lastMin = lastItem['pos'],
        lastMax = lastMin + lastItem['size'];

    if (lastMax < lower) {
      // Window is entirely past physical items, calculate new anchor
      return this._calculateAnchor(lower, upper);
    }
    if (firstMin > upper) {
      // Window is entirely before physical items, calculate new anchor
      return this._calculateAnchor(lower, upper);
    }
    if (firstMin >= lower || firstMax >= lower) {
      // First physical item overlaps window, choose it
      return this._first;
    }
    if (lastMax <= upper || lastMin <= upper) {
      // Last physical overlaps window, choose it
      return this._last;
    }
    // Window contains a physical item, but not the first or last
    var maxIdx = this._last, minIdx = this._first;

    while (true) {
      var candidateIdx = ((maxIdx + minIdx) / 2).round(),
          candidate = this._physicalItems[candidateIdx],
          cMin = candidate.pos,
          cMax = cMin + candidate.size;

      if ((cMin >= lower && cMin <= upper) ||
          (cMax >= lower && cMax <= upper)) {
        return candidateIdx;
      } else if (cMax < lower) {
        minIdx = candidateIdx + 1;
      } else if (cMin > upper) {
        maxIdx = candidateIdx - 1;
      }
    }
  }

  _getActiveItems() {
    if (this._viewDim1 == 0 || this._totalItems == 0) {
      this._clearItems();
    } else {
      var upper = math.min(this._scrollSize,
              this._scrollPosition + this._viewDim1 + this._overhang),
          lower = math.max(0, upper - this._viewDim1 - (2 * this._overhang));

      this._getItems(lower, upper);
    }
  }

  _clearItems() {
    this._first = -1;
    this._last = -1;
    this._physicalMin = 0;
    this._physicalMax = 0;
    var items = this._newPhysicalItems;
    this._newPhysicalItems = this._physicalItems;
    this._newPhysicalItems.clear();
    this._physicalItems = items;
    this._stable = true;
  }

  _getItems(lower, upper) {
    var items = this._newPhysicalItems;

    // The anchorIdx is the anchor around which we reflow. It is designed to
    // allow jumping to any point of the scroll size. We choose it once and
    // stick with it until stable. first and last are deduced around it.
    if (this._anchorIdx == null || this._anchorPos == null) {
      this._anchorIdx = this._getAnchor(lower, upper);
      this._anchorPos = this._getPosition(this._anchorIdx);
    }

    var anchorSize = this._getSize(this._anchorIdx);
    if (anchorSize == null) {
      anchorSize = this._itemDim1;
    }

    // Anchor might be outside bounds, so prefer correcting the error and keep
    // that anchorIdx.
    var anchorErr = 0;

    if (this._anchorPos + anchorSize + this._spacing < lower) {
      anchorErr = lower - (this._anchorPos + anchorSize + this._spacing);
    }

    if (this._anchorPos > upper) {
      anchorErr = upper - this._anchorPos;
    }

    if (anchorErr != null) {
      this._scrollPosition -= anchorErr;
      lower -= anchorErr;
      upper -= anchorErr;
      this._scrollError += anchorErr;
    }

    // TODO use class?
    items[this._anchorIdx] = {'pos': this._anchorPos, 'size': anchorSize};

    this._first = (this._last = this._anchorIdx);
    this._physicalMin = (this._physicalMax = this._anchorPos);

    this._stable = true;

    while (this._physicalMin > lower && this._first > 0) {
      var size = this._getSize(--this._first);
      if (size == null) {
        this._stable = false;
        size = this._itemDim1;
      }
      var pos = (this._physicalMin -= size + this._spacing);
      // TODO: use class?
      items[this._first] = {'pos': pos, 'size': size};
      if (this._stable == false && this._estimate == false) {
        break;
      }
    }

    while (this._physicalMax < upper && this._last < this._totalItems) {
      var size = this._getSize(this._last);
      if (size == null) {
        this._stable = false;
        size = this._itemDim1;
      }
      items[this._last++] = {'pos': this._physicalMax, 'size': size};
      if (this._stable == false && this._estimate == false) {
        break;
      } else {
        this._physicalMax += size + this._spacing;
      }
    }

    this._last--;

    // This handles the cases where we were relying on estimated sizes.
    var extentErr = this._calculateError();
    if (extentErr != null) {
      this._physicalMin -= extentErr;
      this._physicalMax -= extentErr;
      this._anchorPos -= extentErr;
      this._scrollPosition -= extentErr;
      items.values.forEach((item) => item['pos'] -= extentErr);
      this._scrollError += extentErr;
    }

    if (this._stable) {
      this._newPhysicalItems = this._physicalItems;
      this._newPhysicalItems.clear();
      this._physicalItems = items;
    }
  }

  _calculateError() {
    if (this._first == 0) {
      return this._physicalMin;
    } else if (this._physicalMin <= 0) {
      return this._physicalMin - (this._first * this._delta);
    } else if (this._last == this._maxIdx) {
      return this._physicalMax - this._scrollSize;
    } else if (this._physicalMax >= this._scrollSize) {
      return ((this._physicalMax - this._scrollSize) +
          ((this._totalItems - 1 - this._last) * this._delta));
    }
    return 0;
  }

  _updateScrollSize() {
    // Reuse previously calculated physical max, as it might be higher than the
    // estimated size.
    super._updateScrollSize();
    this._scrollSize = math.max(this._physicalMax, this._scrollSize);
  }

  // TODO: Can this be made to inherit from base, with proper hooks?
  _reflow() {
    var _first, _last, _scrollSize;
    _first = this._first;
    _last = this._last;
    _scrollSize = this._scrollSize;

    this._updateScrollSize();
    this._getActiveItems();
    this._scrollIfNeeded();

    if (this._scrollSize != _scrollSize) {
      this._emitScrollSize();
    }

    this._emitRange(null);
    if (this._first == -1 && this._last == -1) {
      this._resetReflowState();
    } else if (this._first != _first ||
        this._last != _last ||
        this._needsRemeasure) {
      this._emitChildPositions();
      this._emitScrollError();
    } else {
      this._emitChildPositions();
      this._emitScrollError();
      this._resetReflowState();
    }
  }

  _resetReflowState() {
    this._anchorIdx = null;
    this._anchorPos = null;
    this._stable = true;
  }

  _getItemPosition(idx) {
    if (this._positionDim == 'left') {
      return Coords(left: this._getPosition(idx), top: 0);
    } else {
      return Coords(left: 0, top: this._getPosition(idx));
    }
  }

  _getItemSize(idx) {
    return {
      [this._sizeDim]: this._getSize(idx) || this._itemDim1,
      [this._secondarySizeDim]: this._itemDim2,
    };
  }

  _viewDim2Changed() {
    this._needsRemeasure = true;
    this._scheduleReflow();
  }

  _emitRange(_) {
    var remeasure = this._needsRemeasure;
    var stable = this._stable;
    this._needsRemeasure = false;
    super._emitRange({'remeasure': remeasure, 'stable': stable});
  }
}

class Layout1dBase {
  StreamController<VSEvent> _eventSink = StreamController<VSEvent>.broadcast();
  Stream<VSEvent> get onEvent => _eventSink.stream;

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
  var _direction = 'vertical';

  int _scrollPosition = 0;
  var _scrollError = 0;
  Size _viewportSize = Size(width: 0, height: 0);
  int _totalItems = 0;

  var _scrollSize = 1;

  int _overhang = 150;

  var _pendingReflow = false;

  var _scrollToIndex = -1;
  num _scrollToAnchor = 0;

  // todo: from layout-1d-grid
  bool _spacingChanged = false;

  // TODO: correct?
  Layout1dBase({direction, overhang}) {
    if (direction != null) {
      this.direction = direction;
    }
    if (overhang != null) {
      this._overhang = overhang;
    }
  }

  bool hasUpdateItemSizesFn = false;
  updateItemSizes(Map<int, Metrics> sizes) {}

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
    int pos;
    if (this._positionDim == "left") {
      pos = this._getItemPosition(index).left;
    } else {
      pos = this._getItemPosition(index).top;
    }
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
    var evt = new RangeChangedEvent(
        first: _first, last: _last, num: _num, stable: true);
    if (inProps != null) {
      if (inProps['stable'] != null) {
        evt.stable = inProps['stable'];
      }
      if (inProps['remeasure'] != null) {
        evt.remeasure = inProps['remeasure'];
      }
    }
    this.dispatchEvent(evt);
  }

  _emitScrollSize() {
    if (this._sizeDim == 'height') {
      this.dispatchEvent(new ScrollSizeChangedEvent(height: this._scrollSize));
    } else {
      this.dispatchEvent(new ScrollSizeChangedEvent(width: this._scrollSize));
    }
  }

  _emitScrollError() {
    // TODO
  }

  _emitChildPositions() {
    var detail = <int, Coords>{};
    for (var idx = this._first; idx <= this._last; idx++) {
      detail[idx] = this._getItemPosition(idx);
    }
    this.dispatchEvent(ItemPositionChangedEvent(detail));
  }

  _itemDim2Changed() {}

  _viewDim2Changed() {}

  _scrollPositionChanged(oldPos, newPos) {
    // When both values are bigger than the max scroll position, keep the
    // current _scrollToIndex, otherwise invalidate it.
    var maxPos = this._scrollSize - this._viewDim1;
    if (oldPos < maxPos || newPos < maxPos) {
      this._scrollToIndex = -1;
    }
  }

  _getActiveItems() {}

  Coords _getItemPosition(idx) {
    return null;
  }

  _getItemSize(idx) {
    return {
      [this._sizeDim]: this._itemDim1,
      [this._secondarySizeDim]: this._itemDim2,
    };
  }

  void dispatchEvent(VSEvent event) {
    _eventSink.add(event);
  }
}

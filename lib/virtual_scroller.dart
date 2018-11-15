import 'dart:async';
import 'dart:html';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:virtual_scroller/layout.dart';
import 'package:virtual_scroller/types.dart';

typedef Element CreateElement(int idx);
typedef Element UpdateElement(Element child, int idx);
typedef Element RecycleElement(Element child, int idx);

class _RepeatsAndScrolls extends _Repeats {
  StreamSubscription _layoutSubscription;
  ResizeObserver _childrenRO;
  bool _skipNextChildrenSizeChanged = false;
  bool _needsUpdateView;
  Layout1dBase _layout;
  Element _scrollTarget;
  var _sizer;
  var _scrollSize;
  var _scrollErr;
  Map<int, Coords> _childrenPos;
  Element _containerElement;
  var _containerInlineStyle;
  Size _containerSize;
  ResizeObserver _containerRO;

  _RepeatsAndScrolls({
    @required layout,
    @required container,
    @required createElement,
    @required updateElement,
    @required recycleElement,
  }) {
    _childrenRO = ResizeObserver((entries, _) => _childrenSizeChanged());
    _num = 0;
    _first = -1;
    _last = -1;
    _prevFirst = -1;
    _prevLast = -1;

    _needsUpdateView = false;
    _layout = null;
    _scrollTarget = null;
    // A sentinel element that sizes the container when it is a scrolling
    // element.
    _sizer = null;
    _scrollSize = null;
    _scrollErr = null;

    _childrenPos = null;
    _containerElement = null;

    // Keep track of original inline style of the container, so it can be
    // restored when container is changed.
    _containerInlineStyle = null;
    _containerSize = null;
    _containerRO = ResizeObserver((entries, _) {
      var rect = entries[0].contentRect;
      _containerSizeChanged(Size(width: rect.width, height: rect.height));
    });

    this.container = container;
    this.createElement = createElement;
    this.updateElement = updateElement;
    this.recycleElement = recycleElement;
    this.layout = layout;
  }

  get container {
    return super.container;
  }

  set container(container) {
    super.container = container;

    var oldEl = this._containerElement;
    // Consider document fragments as shadowRoots.
    var newEl =
        (container != null && container.nodeType == Node.DOCUMENT_FRAGMENT_NODE)
            ? container.host
            : container;
    if (oldEl == newEl) {
      return;
    }

    this._containerRO.disconnect();
    this._containerSize = null;

    if (oldEl != null) {
      if (this._containerInlineStyle) {
        oldEl.setAttribute('style', this._containerInlineStyle);
      } else {
        oldEl.setAttribute('style', null);
      }
      this._containerInlineStyle = null;
      if (oldEl == this._scrollTarget) {
        oldEl.removeEventListener('scroll', this.handleScrollEvent);
        this._sizer && this._sizer.remove();
      }
    } else {
      // First time container was setup, add listeners only now.
      document.addEventListener('scroll', this.handleScrollEvent);
    }

    this._containerElement = newEl;

    if (newEl != null) {
      this._containerInlineStyle = newEl.getAttribute('style');
      if (newEl == this._scrollTarget) {
        this._sizer = this._sizer || this._createContainerSizer();
        this._container.prepend(this._sizer);
      }
      this._scheduleUpdateView();
      this._containerRO.observe(newEl);
    }
  }

  get layout {
    return this._layout;
  }

  set layout(layout) {
    if (layout == this._layout) {
      return;
    }

    if (this._layout != null) {
      this._measureCallback = null;

      // TODO: Layout can't extend EventTarget
      _layoutSubscription?.cancel();
//      this._layout.removeEventListener('scrollsizechange', this);
//      this._layout.removeEventListener('scrollerrorchange', this);
//      this._layout.removeEventListener('itempositionchange', this);
//      this._layout.removeEventListener('rangechange', this);
      // Reset container size so layout can get correct viewport size.
      if (this._containerElement != null) {
        this._sizeContainer(null);
      }
    }

    this._layout = layout;

    if (this._layout != null) {
      // TODO: layout.updateItemSizes
      if (this._layout.hasUpdateItemSizesFn) {
        this._measureCallback = this._layout.updateItemSizes;
        this.requestRemeasure();
      }
      // TODO: Layout can't extend EventTarget
      _layoutSubscription = _layout.onEvent.listen(handleEvent);
//      this._layout.addEventListener('scrollsizechange', this);
//      this._layout.addEventListener('scrollerrorchange', this);
//      this._layout.addEventListener('itempositionchange', this);
//      this._layout.addEventListener('rangechange', this);
      this._scheduleUpdateView();
    }
  }

  /**
   * The element that generates scroll events and defines the container
   * viewport. The value `null` (default) corresponds to `window` as scroll
   * target.
   * @type {Element|null}
   */
  get scrollTarget {
    return this._scrollTarget;
  }

  /**
   * @param {Element|null} target
   */
  set scrollTarget(target) {
    // Consider window as null.
    if (target == window) {
      target = null;
    }
    if (this._scrollTarget == target) {
      return;
    }
    if (this._scrollTarget != null) {
      this._scrollTarget.removeEventListener('scroll', this.handleScrollEvent);
      if (this._sizer && this._scrollTarget == this._containerElement) {
        this._sizer.remove();
      }
    }

    this._scrollTarget = target;

    if (target != null) {
      target.addEventListener('scroll', this.handleScrollEvent);
      if (target == this._containerElement) {
        this._sizer = this._sizer || this._createContainerSizer();
        this._container.prepend(this._sizer);
      }
    }
  }

  /**
   * @protected
   */
  _render() {
    this._childrenRO.disconnect();

    // Update layout properties before rendering to have correct first, num,
    // scroll size, children positions.
    this._layout.totalItems = this.totalItems;
    if (this._needsUpdateView) {
      this._needsUpdateView = false;
      this._updateView();
    }
    this._layout.reflowIfNeeded();
    // Keep rendering until there is no more scheduled renders.
    while (true) {
      if (this._pendingRender != null) {
        window.cancelAnimationFrame(this._pendingRender);
        this._pendingRender = null;
      }
      // Update scroll size and correct scroll error before rendering.
      this._sizeContainer(this._scrollSize);
      if (this._scrollErr) {
        // This triggers a 'scroll' event (async) which triggers another
        // _updateView().
        this._correctScrollError(this._scrollErr);
        this._scrollErr = null;
      }
      // Position children (_didRender()), and provide their measures to layout.
      super._render();
      this._layout.reflowIfNeeded();
      // If layout reflow did not provoke another render, we're done.
      if (this._pendingRender == null) {
        break;
      }
    }
    // We want to skip the first ResizeObserver callback call as we already
    // measured the children.
    this._skipNextChildrenSizeChanged = true;
    this._kids.forEach((child) => this._childrenRO.observe(child));
  }

  /**
   * Position children before they get measured. Measuring will force relayout,
   * so by positioning them first, we reduce computations.
   * @protected
   */
  _didRender() {
    if (this._childrenPos != null) {
      this._positionChildren(this._childrenPos);
      this._childrenPos = null;
    }
  }

  handleScrollEvent(event) {
            if (this._scrollTarget == null || event.target == this._scrollTarget) {
          this._scheduleUpdateView();
        }
  }

  /**
   * @param {!Event} event
   * @private
   */
  handleEvent(VSEvent event) {
    switch (event.runtimeType) {
      // moved to handleScrollEvent
//      case ScrollEvent:
//        if (this._scrollTarget == null || event.target == this._scrollTarget) {
//          this._scheduleUpdateView();
//        }
//        break;
      case ScrollSizeChangedEvent:
        var evt = (event as ScrollSizeChangedEvent);
        this._scrollSize = Size(width: evt.width, height: evt.height);
        this._scheduleRender();
        break;
//      case ScrollErr:
//        this._scrollErr = event.detail;
//        this._scheduleRender();
//        break;
      case ItemPositionChangedEvent:
        this._childrenPos = (event as ItemPositionChangedEvent).indexToPos;
        this._scheduleRender();
        break;
      case RangeChangedEvent:
        this._adjustRange((event as RangeChangedEvent));
        break;
      default:
        print('event not handled $event');
    }
  }

  /**
   * @return {!Element}
   * @private
   */
  _createContainerSizer() {
    var sizer = document.createElement('div');
    // When the scrollHeight is large, the height of this element might be
    // ignored. Setting content and font-size ensures the element has a size.
    sizer.style
      ..position = 'absolute'
      ..margin = '-2px 0 0 0'
      ..padding = '0'
      ..visibility = 'hidden'
      ..fontSize = '2px';
    sizer.setInnerHtml('&nbsp;');
    return sizer;
  }

  // TODO: Rename _ordered to _kids?
  /**
   * @protected
   */
  get _kids {
    return this._ordered;
  }

  /**
   * @private
   */
  _scheduleUpdateView() {
    this._needsUpdateView = true;
    this._scheduleRender();
  }

  /**
   * @private
   */
  _updateView() {
    var width, height, top, left;
    if (this._scrollTarget == this._containerElement) {
      width = this._containerSize.width;
      height = this._containerSize.height;
      left = this._containerElement.scrollLeft;
      top = this._containerElement.scrollTop;
    } else {
      var containerBounds = this._containerElement.getBoundingClientRect();
      var scrollBounds = this._scrollTarget != null
          ? this._scrollTarget.getBoundingClientRect()
          : Rectangle(0, 0, window.innerWidth, window.innerHeight);

      var scrollerWidth = scrollBounds.width;
      var scrollerHeight = scrollBounds.height;
      var xMin = math.max(
          0, math.min(scrollerWidth, containerBounds.left - scrollBounds.left));
      var yMin = math.max(
          0, math.min(scrollerHeight, containerBounds.top - scrollBounds.top));
      var xMax = this._layout.direction == 'vertical'
          ? math.max(
              0,
              math.min(
                  scrollerWidth, containerBounds.right - scrollBounds.left))
          : scrollerWidth;
      var yMax = this._layout.direction == 'vertical'
          ? scrollerHeight
          : math.max(
              0,
              math.min(
                  scrollerHeight, containerBounds.bottom - scrollBounds.top));
      width = xMax - xMin;
      height = yMax - yMin;
      left = math.max(0, -(containerBounds.left - scrollBounds.left));
      top = math.max(0, -(containerBounds.top - scrollBounds.top));
    }
    this._layout.viewportSize = Size(width: width, height: height);
    this._layout.viewportScroll = Coords(top: top, left: left);
  }

  /**
   * @private
   */
  _sizeContainer(size) {
    if (this._scrollTarget == this._containerElement) {
      var left = size != null && size.width ? size.width - 1 : 0;
      var top = size != null && size.height ? size.height - 1 : 0;
      this._sizer.style.transform = 'translate(${left}px, ${top}px)';
    } else {
      var style = this._containerElement.style;
      style.minWidth = size != null && size.width ? size.width + 'px' : null;
      style.minHeight = size != null && size.height ? size.height + 'px' : null;
    }
  }

  /**
   * @private
   */
  _positionChildren(Map<int, Coords> pos) {
    // TODO
//    var kids = this._kids;
//    Object.keys(pos).forEach(key => {
//    var idx = key - this._first;
//    var child = kids[idx];
//    if (child) {
//    var {top, left} = pos[key];
//    child.style.position = 'absolute';
//    child.style.transform = `translate(${left}px, ${top}px)`;
//    }
//    });
    var kids = this._kids;
    pos.forEach((k, v) {
      var idx = k - this._first;
      var child = v;
      if (child != null) {
        var top = pos[k].top;
        var left = pos[k].left;
      }
    });
  }

  /**
   * @private
   */
  _adjustRange(RangeChangedEvent range) {
    this.num = range.num;
    this.first = range.first;
    this._incremental = !(range.stable);
    if (range.remeasure) {
      this.requestRemeasure();
    } else if (range.stable) {
      this._notifyStable();
    }
  }

  /**
   * @protected
   */
  _shouldRender() {
    if (!super._shouldRender() || this._layout == null) {
      return false;
    }
    // NOTE: we're about to render, but the ResizeObserver didn't execute yet.
    // Since we want to keep rAF timing, we compute _containerSize now. Would
    // be nice to have a way to flush ResizeObservers.
    if (this._containerSize == null) {
      var size = this._containerElement.getBoundingClientRect();
      this._containerSize = Size(width: size.width, height: size.height);
    }
    return this._containerSize.width > 0 || this._containerSize.height > 0;
  }

  /**
   * @private
   */
  _correctScrollError(err) {
    if (this._scrollTarget != null) {
      this._scrollTarget.scrollTop -= err.top;
      this._scrollTarget.scrollLeft -= err.left;
    } else {
      window.scroll(window.scrollX - err.left, window.scrollY - err.top);
    }
  }

  /**
   * @protected
   */
  _notifyStable() {
//    var {first, num} = this;
    var first = this.first;
    var num = this.num;
    var last = first + num - 1;
    this
        ._container
        .dispatchEvent(new RangeChangedEvent(first: first, last: last));
  }

  /**
   * @private
   */
  _containerSizeChanged(Size size) {
//    var {width, height} = size;
    this._containerSize = size;
    this._scheduleUpdateView();
  }

  /**
   * @private
   */
  _childrenSizeChanged() {
    if (this._skipNextChildrenSizeChanged) {
      this._skipNextChildrenSizeChanged = false;
    } else {
      this.requestRemeasure();
    }
  }
}

///////////////////////////////////////////////////////////////////////////////

class _Repeats {
  var _createElementFn = null;
  var _updateElementFn = null;
  var _recycleElementFn = null;
  var _elementKeyFn = null;

  Function _measureCallback = null;

  var _totalItems = 0;
  // Consider renaming this. count? visibleElements?
  int _num = 1000000000; // Infinity
  int _prevNum;
  // Consider renaming this. firstVisibleIndex?
  int _first = 0;
  int _last = 0;
  int _prevFirst = 0;
  int _prevLast = 0;

  bool _needsReset = false;
  bool _needsRemeasure = false;
  var _pendingRender = null;

  var _container = null;

  List _ordered = [];
  Map _active = {};
  Map _prevActive = {};

  // Both used for recycling purposes.
  Map _keyToChild = {};
  Map _childToKey = {};

  // Used to keep track of measures by index.
  Map _indexToMeasure = {};

  bool __incremental = false;

  //-------------------------------------

  get container {
    return this._container;
  }

  set container(container) {
    if (container == this._container) {
      return;
    }

    if (this._container != null) {
      // Remove children from old container.
      this._ordered.forEach((child) => this._removeChild(child));
    }

    this._container = container;

    if (container != null) {
      // Insert children in new container.
      this._ordered.forEach((child) => this._insertBefore(child, null));
    } else {
      this._ordered.length = 0;
      this._active.clear();
      this._prevActive.clear();
    }
    this.requestReset();
  }

  get createElement {
    return this._createElementFn;
  }

  set createElement(fn) {
    if (fn != this._createElementFn) {
      this._createElementFn = fn;
      this._keyToChild.clear();
      this.requestReset();
    }
  }

  get updateElement {
    return this._updateElementFn;
  }

  set updateElement(fn) {
    if (fn != this._updateElementFn) {
      this._updateElementFn = fn;
      this.requestReset();
    }
  }

  get recycleElement {
    return this._recycleElementFn;
  }

  set recycleElement(fn) {
    if (fn != this._recycleElementFn) {
      this._recycleElementFn = fn;
      this.requestReset();
    }
  }

  get elementKey {
    return this._elementKeyFn;
  }

  set elementKey(fn) {
    if (fn != this._elementKeyFn) {
      this._elementKeyFn = fn;
      this._keyToChild.clear();
      this.requestReset();
    }
  }

  get first {
    return this._first;
  }

  set first(int idx) {
    if (idx.runtimeType != int) {
      throw 'New value must be a number.';
    }

    var newFirst = math.max(0, math.min(idx, this._totalItems - this._num));
    if (newFirst != this._first) {
      this._first = newFirst;
      this._scheduleRender();
    }
  }

  get num {
    return this._num;
  }

  set num(n) {
    if (n != this._num) {
      this._num = n;
      this.first = this._first;
      this._scheduleRender();
    }
  }

  get totalItems {
    return this._totalItems;
  }

  set totalItems(int num) {
    // TODO(valdrin) should we check if it is a finite number?
    // Technically, Infinity would break Layout, not VirtualRepeater.
    if (num != this._totalItems) {
      this._totalItems = num;
      this.first = this._first;
      this.requestReset();
    }
  }

  get _incremental {
    return this.__incremental;
  }

  set _incremental(inc) {
    if (inc != this.__incremental) {
      this.__incremental = inc;
      this._scheduleRender();
    }
  }

  requestReset() {
    this._needsReset = true;
    this._scheduleRender();
  }

  requestRemeasure() {
    this._needsRemeasure = true;
    this._scheduleRender();
  }

  // Core functionality

  /**
   * @protected
   */
  _shouldRender() {
    return this.container != null && this.createElement != null;
  }

  /**
   * @private
   */
  _scheduleRender() {
    if (this._pendingRender == null) {
      this._pendingRender = window.requestAnimationFrame((_) {
        this._pendingRender = null;
        if (this._shouldRender()) {
          this._render();
        }
      });
    }
  }

  /**
   * Returns those children that are about to be displayed and that require to
   * be positioned. If reset or remeasure has been triggered, all children are
   * returned.
   * @return {{indices: Array<number>, children: Array<Element>}}
   * @private
   */
  get _toMeasure {
//    return this._ordered.reduce((toMeasure, c) {
//        var idx = this._first + i;
//        if (this._needsReset || this._needsRemeasure || idx < this._prevFirst ||
//        idx > this._prevLast) {
//      toMeasure.indices.push(idx);
//      toMeasure.children.push(c);
//    }
//    return toMeasure;
//  }, ToMeasure(indices: [], children: []);

    var toMeasure = ToMeasure();
    for (var i = 0; i < _ordered.length; i++) {
      var c = _ordered[i];
      var idx = this._first + i;
      if (this._needsReset ||
          this._needsRemeasure ||
          idx < this._prevFirst ||
          idx > this._prevLast) {
        toMeasure.indices.add(idx);
        toMeasure.children.add(c);
      }
    }
    return toMeasure;
  }

  /**
   * Measures each child bounds and builds a map of index/bounds to be passed
   * to the `_measureCallback`
   * @private
   */
  _measureChildren(ToMeasure toMeasure) {
    List pm = [];
    for (var i = 0; i < toMeasure.children.length; i++) {
      var c = toMeasure.children[i];
      if (_indexToMeasure.containsKey(i)) {
        pm.add(_indexToMeasure[i]);
      } else {
        pm.add(_measureChild(c));
      }
    }

    var mm = <int, Rectangle>{};
    for (var i = 0; i < pm.length; i++) {
      var cur = pm[i];
      mm[toMeasure.indices[i]] =
          this._indexToMeasure[toMeasure.indices[i]] = cur;
    }
    _measureCallback(mm);
  }

  /**
   * @protected
   */
  _render() {
    var rangeChanged =
        this._first != this._prevFirst || this._num != this._prevNum;
    // Create/update/recycle DOM.
    if (rangeChanged || this._needsReset) {
      this._last =
          this._first + math.min(this._num, this._totalItems - this._first) - 1;
      if (this._num != null || this._prevNum != null) {
        if (this._needsReset) {
          this._reset(this._first, this._last);
        } else {
          this._discardHead();
          this._discardTail();
          this._addHead();
          this._addTail();
        }
      }
    }
    if (this._needsRemeasure || this._needsReset) {
      this._indexToMeasure = {};
    }
    // Retrieve DOM to be measured.
    // Do it right before cleanup and reset of properties.
    var shouldMeasure = this._num > 0 &&
        this._measureCallback != null &&
        (rangeChanged || this._needsRemeasure || this._needsReset);
    var toMeasure = shouldMeasure ? this._toMeasure : null;

    // Cleanup.
    if (!this._incremental) {
      this._prevActive.forEach((idx, child) => this._unassignChild(child, idx));
      this._prevActive.clear();
    }
    // Reset internal properties.
    this._prevFirst = this._first;
    this._prevLast = this._last;
    this._prevNum = this._num;
    this._needsReset = false;
    this._needsRemeasure = false;

    // Notify render completed.
    this._didRender();
    // Measure DOM.
    if (toMeasure) {
      this._measureChildren(toMeasure);
    }
  }

  /**
   * Invoked after DOM is updated, and before it gets measured.
   * @protected
   */
  _didRender() {}

  /**
   * @private
   */
  _discardHead() {
    var o = this._ordered;
    for (var idx = this._prevFirst; o.length != 0 && idx < this._first; idx++) {
      this._unassignChild(o.removeAt(0), idx);
    }
  }

  /**
   * @private
   */
  _discardTail() {
    var o = this._ordered;
    for (var idx = this._prevLast; o.length != 0 && idx > this._last; idx--) {
      this._unassignChild(o.removeLast(), idx);
    }
  }

  /**
   * @private
   */
  _addHead() {
    var start = this._first;
    var end = math.min(this._last, this._prevFirst - 1);
    for (var idx = end; idx >= start; idx--) {
      var child = this._assignChild(idx);
      if (!this._childIsAttached(child)) {
        this._insertBefore(child, this._firstChild);
      }
      if (this.updateElement) {
        this.updateElement(child, idx);
      }
      this._ordered.insert(0, child);
    }
  }

  /**
   * @private
   */
  _addTail() {
    var start = math.max(this._first, this._prevLast + 1);
    var end = this._last;
    for (var idx = start; idx <= end; idx++) {
      var child = this._assignChild(idx);
      if (!this._childIsAttached(child)) {
        this._insertBefore(child, null);
      }
      if (this.updateElement) {
        this.updateElement(child, idx);
      }
      this._ordered.add(child);
    }
  }

  /**
   * @param {number} first
   * @param {number} last
   * @private
   */
  _reset(first, last) {
    // Explain why swap prevActive with active - affects _assignChild.
    var prevActive = this._active;
    this._active = this._prevActive;
    this._prevActive = prevActive;

    this._ordered.length = 0;
    var currentMarker = this._firstChild;
    for (var i = first; i <= last; i++) {
      var child = this._assignChild(i);
      this._ordered.add(child);

      if (currentMarker) {
        if (currentMarker == this._node(child)) {
          currentMarker = this._nextSibling(child);
        } else {
          this._insertBefore(child, currentMarker);
        }
      } else if (!this._childIsAttached(child)) {
        this._insertBefore(child, null);
      }

      if (this.updateElement) {
        this.updateElement(child, i);
      }
    }
  }

  /**
   * @param {number} idx
   * @private
   */
  _assignChild(idx) {
    var key = this.elementKey ? this.elementKey(idx) : idx;
    var child;
    if (child = this._keyToChild[key]) {
      this._prevActive.remove(child);
    } else {
      child = this.createElement(idx);
      this._keyToChild[key] = child;
      this._childToKey[child] = key;
    }
    this._showChild(child);
    this._active[child] = idx;
    return child;
  }

  /**
   * @param {*} child
   * @param {number} idx
   * @private
   */
  _unassignChild(child, idx) {
    this._hideChild(child);
    if (this._incremental) {
      this._active.remove(child);
      this._prevActive[child] = idx;
    } else {
      var key = this._childToKey[child];
      this._childToKey.remove(child);
      this._keyToChild.remove(key);
      this._active.remove(child);
      if (this.recycleElement) {
        this.recycleElement(child, idx);
      } else if (this._node(child).parentNode) {
        this._removeChild(child);
      }
    }
  }

  // TODO: Is this the right name?
  /**
   * @private
   */
  get _firstChild {
    return this._ordered.length != 0 && this._childIsAttached(this._ordered[0])
        ? this._node(this._ordered[0])
        : null;
  }

  // Overridable abstractions for child manipulation

  /**
   * @protected
   */
  _node(child) {
    return child;
  }

  /**
   * @protected
   */
  _nextSibling(child) {
    return child.nextSibling;
  }

  /**
   * @protected
   */
  _insertBefore(child, referenceNode) {
    this._container.insertBefore(child, referenceNode);
  }

  /**
   * Remove child.
   * Override to control child removal.
   *
   * @param {*} child
   * @protected
   */
  _removeChild(child) {
    child.parentNode.removeChild(child);
  }

  /**
   * @protected
   */
  _childIsAttached(child) {
    var node = this._node(child);
    return node && node.parentNode == this._container;
  }

  /**
   * @protected
   */
  _hideChild(child) {
    if (child.style) {
      child.style.display = 'none';
    }
  }

  /**
   * @protected
   */
  _showChild(child) {
    if (child.style) {
      child.style.display = null;
    }
  }

  /**
   * @param {!Element} child
   * @return {{
   *   width: number,
   *   height: number,
   *   marginTop: number,
   *   marginRight: number,
   *   marginBottom: number,
   *   marginLeft: number,
   * }} childMeasures
   * @protected
   */
  Rectangle _measureChild(Element child) {
    // offsetWidth doesn't take transforms in consideration, so we use
    // getBoundingClientRect which does.
    var rect = child.getBoundingClientRect();
    var width = rect.width;
    var height = rect.height;
//    return Object.assign({width, height}, getMargins(child));
  }
}

Margin getMargins(Element el) {
  var style = el.getComputedStyle();
  return Margin(
    marginTop: getMarginValue(style.marginTop),
    marginRight: getMarginValue(style.marginRight),
    marginBottom: getMarginValue(style.marginBottom),
    marginLeft: getMarginValue(style.marginLeft),
  );
}

num getMarginValue(String value) {
  // TODO handle edge cases?
//  value = value ? parseFloat(value) : NaN;
//  return Number.isNaN(value) ? 0 : value;
  return double.parse(value);
}

///////////////////////////////////////////////////////////////////////////////

class VirtualScroller extends _RepeatsAndScrolls {
  VirtualScroller({
    Layout1dBase layout,
    Element container,
    CreateElement createElement,
    UpdateElement updateElement,
    RecycleElement recycleElement,
  }) : super(
          layout: layout,
          container: container,
          createElement: createElement,
          updateElement: updateElement,
          recycleElement: recycleElement,
        );
}

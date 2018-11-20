# virtual_scroller

A Dart implementation of [virtual-scroller]() by Valdrin Koshi
([@valdrinkoshi](https://github.com/valdrinkoshi))

[virtual-scroller]: https://github.com/valdrinkoshi/virtual-scroller

## Usage - Vanilla Dart

- **Vanilla Dart** see /example (run `pub run build_runner serve example:8080`)
- **AngularDart** see [here][angulardart-example]

[angulardart-example]: https://github.com/johnpryan/virtual_scroller_dart_example



## ResizeObserver

It is recommended to use a [polyfill for
ResizeObserver](https://github.com/que-etc/resize-observer-polyfill) due to
[browser incompatability](https://caniuse.com/#feat=resizeobserver)
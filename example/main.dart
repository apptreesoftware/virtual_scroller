import 'dart:async';
import 'dart:html';

import 'package:virtual_scroller/layout.dart';
import 'package:virtual_scroller/virtual_scroller.dart';
import 'package:http/http.dart' as http;

class Sample {
  List items;
  Layout layout;
  Element container;
  VirtualScroller scroller;

  Sample() {
    items = [];
    layout = Layout();
    container = document.body;

    document.body.style.margin = '0';
    document.body.style.minHeight = '1000000px';
    _setUp();
  }

  void _setUp() {
    scroller = new VirtualScroller(
      layout: this.layout,
      container: this.container,
      createElement: (idx) {
        var item = this.items[idx];
        var type = item.runtimeType;
        if (type == Contact) {
          var card = document.createElement('div');
          card.style
            ..setProperty('padding', '10px')
            ..setProperty('border-bottom', '1px solid #CCC')
            ..setProperty('width', '100%')
            ..setProperty('box-sizing', 'border-box');
          var name = document.createElement('b');
          var text = document.createElement('p');
          text.contentEditable = 'true';
          card.append(name);
          card.append(text);
          return card;
        } else {
          var header = document.createElement('div');
          header.style
            ..setProperty('color', 'white')
            ..setProperty('background', '#2222DD')
            ..setProperty('padding', '10px')
            ..setProperty('border-bottom', '1px solid #CCC')
            ..setProperty('width', '100%')
            ..setProperty('box-sizing', 'border-box');
          return header;
        }
      },
      updateElement: (child, idx) {
//        var item = this.items[idx];
//        if (item.runtimeType == Contact) {
//          child._idx = idx;
//          child.querySelector('b').textContent =
//          `#${item.index} - ${item.first} ${item.last}`;
//        child.querySelector('p').textContent = item.longText;
//        } else {
//        child.textContent = item.title;
//        }
      },
      recycleElement: (child, idx) {},
    );
  }
  Future load(String url) async {
    var response = await http.get(url);
    print(response.body);
  }
}

void main() {
  var sample = new Sample();
  sample.load('./contacts.json');
}

class Contact {}

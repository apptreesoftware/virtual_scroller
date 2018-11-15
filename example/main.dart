import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:virtual_scroller/layout.dart';
import 'package:virtual_scroller/virtual_scroller.dart';
import 'package:http/http.dart' as http;

class Sample {
  List<dynamic> items;
  Layout layout;
  Element container;
  VirtualScroller scroller;
  List<Element> headerPool = [];
  List<Element> contactPool = [];

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
        var item = items[idx];
        var type = item.runtimeType;
        if (type == Contact && contactPool.isNotEmpty) {
          return contactPool.removeLast();
        }
        if (type == Header && headerPool.isNotEmpty) {
          return headerPool.removeLast();
        }
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
          text.addEventListener(
              'focus', (e) => _scrollToFocused(target: (e as FocusEvent).target as Element));
          text.addEventListener(
              'blur',
              (e) => _commitChange(
                  int.parse(card.attributes['_idx']), (e.target as Element).text));
          card.append(name);
          card.append(text);
          return card;
        } else {
          var header = document.createElement('div');
          header.style
            ..color = 'white'
            ..background = '#2222DD'
            ..padding = '10px'
            ..borderBottom = '1px solid #CCC'
            ..width = '100%'
            ..boxSizing = 'border-box';
          return header;
        }
      },
      updateElement: (child, idx) {
        var item = items[idx];
        if (item.runtimeType == Contact) {
          var item = this.items[idx];
          child.setAttribute('_idx', idx.toString());
          var b = child.querySelector('b');
          var p = child.querySelector('p');
          if (b == null || p == null) {
            print("updating $child for contact without p or p elements");
            return;
          }
          b.text = '${item.index} - ${item.first} ${item.last}';
          p.text = item.longText;
        } else {
          child.text = (item as Header).title;
        }
      },
      recycleElement: (child, idx) {
        var item = items[idx];
        if (item.runtimeType == Contact) {
          child.setAttribute('_idx', (-1).toString());
          var b = child.querySelector('b');
          var p = child.querySelector('p');
          if (b == null || p == null) {
            print("recycling $child for contact without p or p elements");
            return;
          }
          child.querySelector('b').text = '';
          child.querySelector('p').text = '';
          this.contactPool.add(child);
        } else {
          this.headerPool.add(child);
        }
      },
    );
  }

  void render() {
    scroller.totalItems = items.length;
  }

  Future load(String url) async {
    var response = await http.get(url);
    var body = response.body;
    var data = json.decode(body) as List;
    var contacts = data.map((d) => Contact.fromJson(d));
    var sorted = contacts.toList()..sort((a, b) => a.last.compareTo(b.last));
    List result = [];

    // add headers
    String prev;
    for (var item in sorted) {
      var cur = item.last.substring(0, 1);
      if (prev != cur) {
        result.add(Header(title: cur));
      }
      result.add(item);
      prev = cur;
    }

    items = result;
    render();
  }

  _scrollToFocused({Element target}) {
    new Future(() {
      target.parent.scrollIntoView();
    });
  }

  _commitChange(int idx, newVal) {
    if (idx == -1) return;
    var prevVal = this.items[idx];
    if (newVal != prevVal) {
      (this.items[idx] as Contact).longText = newVal;
      print("changing value to $newVal");
      // HACK(valdrin) Ideally we'd only do this.scroller.requestReset(),
      // but since lit-repeater & preact-repeater don't give access to that
      // method, we force reset by altering the items length.
      this.items.length++;
      this.render();
      this.items.length--;
      this.render();
    }
  }
}

void main() {
  var sample = new Sample();
  sample.load('./contacts.json');
}

class Contact {
  int index;
  String first;
  String last;
  String longText;

  Contact();

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact()
      ..index = json['index']
      ..first = json['first']
      ..last = json['last']
      ..longText = json['longText'];
  }
}

class Header {
  String title;
  Header({this.title});
}

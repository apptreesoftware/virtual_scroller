import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:virtual_scroller/layout.dart';
import 'package:virtual_scroller/virtual_scroller.dart';
import 'package:http/http.dart' as http;

class Sample {
  List<Contact> items;
  Layout layout;
  Element container;
  VirtualScroller scroller;
  List<Element> pool = [];

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
        if (pool.isNotEmpty) {
          return pool.removeLast();
        }
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
      },
      updateElement: (child, idx) {
        var item = this.items[idx];
        child.querySelector('b').text =
            '${item.index} - ${item.first} ${item.last}';
        child.querySelector('p').text = item.longText;
      },
      recycleElement: (child, idx) {
        child.querySelector('b').text = '';
        child.querySelector('p').text = '';
        this.pool.add(child);
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
    items = sorted;
    render();
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
  Header(this.title);
}

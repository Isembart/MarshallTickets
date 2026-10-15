import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db.dart';
import 'screens/concert_list.dart';
import 'theme.dart';

late final Db db;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    // sqflite has no Linux plugin; the FFI factory uses the system libsqlite3.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  db = await Db.open();
  runApp(MaterialApp(
    title: 'Bilety',
    theme: buildTheme(),
    home: const ConcertListScreen(),
  ));
}

const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
String monthShort(DateTime d) => _months[d.month - 1];

String formatDate(DateTime d) => '${_pad(d.day)}.${_pad(d.month)}.${d.year}';
String formatTime(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';
String _pad(int n) => n.toString().padLeft(2, '0');

Future<bool> confirm(BuildContext context, String title, String message, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

// main.dart
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'globals.dart';

void main() async {
  // Initialize FFI for Linux
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  WidgetsFlutterBinding.ensureInitialized();
  await initDatabases();
  runApp(memorizerApp());
}

// Main app widget as a function
Widget memorizerApp() => MaterialApp(
  title: 'Memorizer',
  theme: appTheme,
  home: homePage(),
);

// Home page as a function
Widget homePage() => Builder(
    builder: (context) {
      globalContext = context;

      return Scaffold(
        appBar: buildAppBar('Memorizer'),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: getItems(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final items = snapshot.data!;

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(items[index]['title']),
                  subtitle: Text(items[index]['content']),
                  onTap: () {
                    // Item tap functionality
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: buildAddButton(() {
          // Add new item functionality
        }),
      );
    }
);
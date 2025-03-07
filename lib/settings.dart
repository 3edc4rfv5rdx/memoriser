// settings.dart
import 'package:flutter/material.dart';
import 'globals.dart';

// Settings screen for theme selection
class SettingsPage extends StatelessWidget {
  final Function rebuildApp;
  
  const SettingsPage({Key? key, required this.rebuildApp}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: clUpBar,
        foregroundColor: clText,
        title: Text('Settings'),
      ),
      body: FutureBuilder<String?>(
        future: getSetting("Color theme"),
        builder: (context, snapshot) {
          final currentTheme = snapshot.hasData
              ? snapshot.data!
              : defSettings["Color theme"];

          return ListView(
            children: [
              ListTile(
                title: Text('Color Theme'),
                subtitle: Text(currentTheme!),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        backgroundColor: clFill,
                        title: Text('Select Theme'),
                        content: Container(
                          width: double.minPositive,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: appTHEMES.length,
                            itemBuilder: (BuildContext context, int index) {
                              return ListTile(
                                title: Text(appTHEMES[index]),
                                selected: appTHEMES[index] == currentTheme,
                                selectedTileColor: clSel,
                                onTap: () async {
                                  // Save the theme name, not the index
                                  await saveSetting("Color theme", appTHEMES[index]);
                                  Navigator.of(context).pop();

                                  // Call the rebuildApp function passed from main
                                  rebuildApp();
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              // Other settings
              SwitchListTile(
                title: Text('Newest First'),
                value: (defSettings["Newest first"] == "true"),
                onChanged: (bool value) async {
                  await saveSetting("Newest first", value.toString());
                  Navigator.of(context).pop();
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SettingsPage(rebuildApp: rebuildApp))
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

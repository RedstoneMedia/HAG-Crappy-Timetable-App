import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:stundenplan/profile_manager.dart';
import 'package:time_ago_provider/time_ago_provider.dart' as time_ago;
import 'package:connectivity/connectivity.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stundenplan/constants.dart';
import 'package:stundenplan/helper_functions.dart';
import 'package:stundenplan/pages/setup_page.dart';
import 'package:stundenplan/parsing/parse.dart';
import 'package:stundenplan/shared_state.dart';
import 'package:stundenplan/update_notify.dart';
import 'content.dart';
import 'widgets/custom_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.getInstance().then((prefs) {
    runApp(
      MaterialApp(
        home: MyApp(SharedState(prefs)),
      ),
    );
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();

  const MyApp(this.sharedState);

  final SharedState sharedState;
}

class _MyAppState extends State<MyApp> {
  SharedState sharedState;
  UpdateNotifier updateNotifier = UpdateNotifier();
  Connectivity connectivity = Connectivity();

  DateTime date;
  bool loading = true;
  String day;
  Timer everyMinute;

  GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    sharedState = widget.sharedState;
    sharedState.content = Content(Constants.width, sharedState.height);

    // Calls set state every minute to update current school hour if changed
    everyMinute = Timer.periodic(const Duration(minutes: 1), (Timer timer) {
      setState(() {});
    });

    if (sharedState.loadStateAndCheckIfFirstTime()) {
      openSetupPageAndCheckForFiles();
    } else {
      isInternetAvailable(connectivity).then((result) {
        if (result) {
          updateNotifier.init().then((value) {
            updateNotifier.checkForNewestVersionAndShowDialog(
                context, sharedState);
          });
          try {
            parsePlans(sharedState.content, sharedState)
                .then((value) => setState(() {
                      // ignore: avoid_print
                      print(
                          "State was set to : ${sharedState.content}"); //TODO: Remove Debug Message
                      sharedState.saveContent();
                      loading = false;
                    }));
          } on TimeoutException catch (_) {
            setState(() {
              // ignore: avoid_print
              print("Timeout !");
              sharedState.loadContent();
              loading = false;
            });
          }
        } else {
          setState(() {
            // ignore: avoid_print
            print("No connection !");
            sharedState.loadContent();
            loading = false;
          });
        }
      });
    }
  }

  Future<void> openSetupPageAndCheckForFiles() async {
    await loadProfileManagerAndThemeFromFiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SetupPage(sharedState)),
      );
    });
  }

  Future<void> loadProfileManagerAndThemeFromFiles() async {
    //This function uses root-level file access, which is only available on android
    if (!Platform.isAndroid) return;
    //Check if we have the storage Permission
    if (await Permission.storage.isDenied || await Permission.storage.isUndetermined) {
      await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text("Einstellungen Speichern"),
              content: const Text(
                  "Diese App benötigt zugriff auf den Speicher deines Gerätes um Fächer und Themes verlässlich zu speichern."),
                actions: <Widget>[
                  FlatButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Ok'),
                  ),

                ],
            );
          });
      if (await Permission.storage.request().isDenied) return;
    }
    try {
      final File saveFile =
          File("/storage/emulated/0/Android/data/stundenplan-profileData.save");

      final String data = await saveFile.readAsString();

      sharedState.profileManager =
          ProfileManager.fromJsonData(jsonDecode(data));
    } catch (e) {
      // ignore: avoid_print
      print("Error while loading profileData:\n$e");
    }

    try {
      final File saveFile =
          File("/storage/emulated/0/Android/data/stundenplan-themeData.save");

      final String data = await saveFile.readAsString();

      sharedState.theme = sharedState.themeFromJsonData(jsonDecode(data));
    } catch (e) {
      // ignore: avoid_print
      print("Error while loading themeData:\n$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        leading: Container(),
        title: Text(
          "Stundenplan",
          style: GoogleFonts.poppins(
            color: sharedState.theme.textColor,
          ),
        ),
        backgroundColor: sharedState.theme.backgroundColor,
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              color: sharedState.theme.textColor,
            ),
            onPressed: () {
              showSettingsWindow(context, sharedState);
            },
          ),
        ],
      ),
      body: Material(
        color: sharedState.theme.backgroundColor,
        child: SafeArea(
          child: loading
              ? Center(
                  child: Loader(sharedState),
                )
              : PullDownToRefresh(
                  onRefresh: () {
                    isInternetAvailable(connectivity).then((value) {
                      if (value) {
                        try {
                          setState(() {
                            parsePlans(sharedState.content, sharedState)
                                .then((value) {
                              sharedState.saveContent();
                              _refreshController.refreshCompleted();
                            });
                          });
                        } on TimeoutException catch (_) {
                          // ignore: avoid_print
                          print("Timeout !");
                          _refreshController.refreshFailed();
                        }
                      } else {
                        // ignore: avoid_print
                        print("no connection !");
                        _refreshController.refreshFailed();
                      }
                    });
                  },
                  sharedState: sharedState,
                  refreshController: _refreshController,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 8.0,
                          top: 8.0,
                          right: 8.0,
                        ),
                        child: TimeTable(
                            sharedState: sharedState,
                            content: sharedState.content),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Text(
                              "Zuletzt aktualisiert: ",
                              style: GoogleFonts.poppins(
                                  color: sharedState.theme.textColor
                                      .withAlpha(200),
                                  fontWeight: FontWeight.w300),
                            ),
                            Text(
                              time_ago.format(sharedState.content.lastUpdated,
                                  locale: "de"),
                              style: GoogleFonts.poppins(
                                  color: sharedState.theme.textColor
                                      .withAlpha(200),
                                  fontWeight: FontWeight.w200),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

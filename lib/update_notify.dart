import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:http/http.dart';
import 'package:stundenplan/constants.dart';
import 'package:stundenplan/shared_state.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yaml/yaml.dart'; // Contains a client for making API calls

class Version {
  int majorVersion;
  int minorVersion;
  int microVersion;

  Version(String versionString) {
    final regExp = RegExp(r"(?<major>\d).(?<minor>\d).(?<micro>\d)");
    final match = regExp.firstMatch(versionString);
    majorVersion = int.parse(match.namedGroup("major"));
    minorVersion = int.parse(match.namedGroup("minor"));
    microVersion = int.parse(match.namedGroup("micro"));
  }

  @override
  String toString() {
    return "$majorVersion.$minorVersion.$microVersion";
  }

  bool isOtherVersionGreater(Version other) {
    if (other.majorVersion > majorVersion) {
      return true;
    }
    if (other.minorVersion > minorVersion) {
      return true;
    }
    if (other.microVersion > microVersion) {
      return true;
    }
    return false;
  }
}

class UpdateNotifier {
  Version currentVersion;
  Client client;

  Future<void> init() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final versionString = packageInfo.version;
    currentVersion = Version(versionString);
    client = Client();
  }

  Future<Version> getNewestVersion() async {
    final response = await client.get(Uri.parse(Constants.newestVersionPubspecUrl));
    final pubspecYamlData = loadYaml(response.body);
    return Version(pubspecYamlData["version"].toString());
  }

  Future<void> checkForNewestVersionAndShowDialog(
      BuildContext context, SharedState sharedState) async {
    final newestVersion = await getNewestVersion();
    if (currentVersion.isOtherVersionGreater(newestVersion)) {
      await showNewVersionDialog(context, sharedState, newestVersion);
    }
  }

  Future<void> showNewVersionDialog(
      BuildContext context, SharedState sharedState, Version newVersion) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: sharedState.theme.backgroundColor,
          title: Text('Neue Version verfügbar',
              style: TextStyle(color: sharedState.theme.textColor)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Es ist eine neue Version verfügbar : $newVersion',
                    style: TextStyle(color: sharedState.theme.textColor))
              ],
            ),
          ),
          actions: <Widget>[
            RaisedButton(
              color: sharedState.theme.subjectColor.withOpacity(0.9),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Ok',
                  style: TextStyle(color: sharedState.theme.textColor)),
            ),
            RaisedButton(
              color: sharedState.theme.subjectColor,
              onPressed: () async {
                final newReleaseUrl = Constants.newestReleaseUrlPart + newVersion.toString();
                if (await canLaunch(newReleaseUrl)) {
                  await launch(newReleaseUrl);
                }
                Navigator.of(context).pop();
              },
              child: Text('Herunterladen',
                  style: TextStyle(color: sharedState.theme.textColor)),
            )
          ],
        );
      },
    );
  }
}

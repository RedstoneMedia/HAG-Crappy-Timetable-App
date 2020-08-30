import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart'; // Contains HTML parsers to generate a Document object
import 'package:http/http.dart';
import 'package:stundenplan/constants.dart';
import 'package:stundenplan/content.dart';
import 'package:stundenplan/parsing/parsing_util.dart'; // Contains a client for making API calls

Future<void> overwriteContentWithSubsitutionPlan(Constants constants, Client client, Content content, List<String> subjects, String schoolClassName) async {
  var weekDay = DateTime.now().weekday;
  if (weekDay > 5) {
    weekDay = 1;
  }

  List<HashMap<String, String>> plan = await getCourseSubsitutionPlan(schoolClassName, constants.substitutionLinkBase, client);
  List<HashMap<String, String>> coursePlan = await getCourseSubsitutionPlan("${constants.schoolGrade}K", constants.substitutionLinkBase, client);
  plan.addAll(coursePlan);
  for (int i = 0; i < plan.length; i++) {
    var hours = strip(plan[i]["Stunde"]).split("-");

    // Fill cell
    Cell cell = new Cell();
    cell.subject = strip(plan[i]["Fach"]);
    cell.originalSubject = strip(plan[i]["statt Fach"]);
    if (!subjects.contains(cell.originalSubject)) {  // If user dose not have that subject skip that class
      continue;
    }
    cell.teacher = strip(plan[i]["Vertretung"]);
    cell.originalTeacher = strip(plan[i]["statt Lehrer"]);
    cell.room = strip(plan[i]["Raum"]);
    cell.originalRoom = strip(plan[i]["statt Raum"]);
    cell.text = plan[i]["Text"];
    cell.isDropped = strip(plan[i]["Entfall"]) == "x";

    if (hours.length == 1) {
      // No hour range (5)
      var hour = int.parse(hours[0]);
      content.setCell(hour, weekDay, cell);
    } else if (hours.length == 2) {
      // Hour range (5-6)
      var hourStart = int.parse(hours[0]);
      var hourEnd = int.parse(hours[1]);
      for (var i = hourStart; i < hourEnd + 1; i++) {
        content.setCell(i-1, weekDay, cell);
      }
    }
  }
}

Future<List<HashMap<String, String>>> getCourseSubsitutionPlan(String course, String linkBase, client) async {
  Response response = await client.get('${linkBase}_${course}.htm');
  if (response.statusCode != 200) return new List<HashMap<String, String>>();

  var document = parse(response.body);
  List<dom.Element> tables = document.getElementsByTagName("table");
  for (int i = 0; i < tables.length; i++) {
    if (!tables[i].attributes.containsKey("rules")) {
      tables.removeAt(i);
    }
  }

  dom.Element mainTable = tables[0];
  List<dom.Element> rows = mainTable.getElementsByTagName("tr");
  List<String> headerInformation = [
    "Stunde",
    "Fach",
    "Vertretung",
    "Raum",
    "statt Fach",
    "statt Lehrer",
    "statt Raum",
    "Text",
    "Entfall"
  ];
  rows.removeAt(0);
  List<HashMap<String, String>> subsituions = new List<HashMap<String, String>>();

  for (var row in rows) {
    HashMap<String, String> substituion = new HashMap<String, String>();
    var coloumns = row.getElementsByTagName("td");
    for (int i = 0; i < coloumns.length; i++) {
      substituion[headerInformation[i]] =
          coloumns[i].text.replaceAll("\n", " ");
    }
    subsituions.add(substituion);
  }

  return subsituions;
}
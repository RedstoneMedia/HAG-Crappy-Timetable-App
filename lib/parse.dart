import 'dart:collection';
import 'dart:math';
import 'package:http/http.dart'; // Contains a client for making API calls
import 'package:html/parser.dart'; // Contains HTML parsers to generate a Document object
import 'package:html/dom.dart' as dom;
import 'package:stundenplan/content.dart'; // Contains DOM related classes for extracting data from elements

const String SUBSTITUTION_LINK_BASE = "https://hag-iserv.de/iserv/public/plan/show/Sch%C3%BCler-Stundenpl%C3%A4ne/b006cb5cf72cba5c/svertretung/svertretungen";
const String TIMETABLE_LINK_BASE = "https://hag-iserv.de/iserv/public/plan/show/Schüler-Stundenpläne/b006cb5cf72cba5c/splan/Kla1A";

String strip(String s) {
  return s.replaceAll(" ", "").replaceAll("\t", "").replaceAll("\n", "");
}


Future<void> initiate(course, Content content, List<String> subjects) async {
  var client = Client();
  var weekDay = DateTime.now().weekday;

  print("Parsing main time table");
  await fillTimeTable(course, TIMETABLE_LINK_BASE, client, content, subjects);
  print("Parsing course only time table");
  var courseTimeTableContent = new Content(6, 10);
  await fillTimeTable("11K", TIMETABLE_LINK_BASE, client, courseTimeTableContent, subjects);
  print("Combining both tables");
  content.combine(courseTimeTableContent);

  print("Parsing submission plan");
  List<HashMap<String, String>> plan = await getCourseSubsitutionPlan(course, SUBSTITUTION_LINK_BASE, client);
  List<HashMap<String, String>> coursePlan = await getCourseSubsitutionPlan("11K", SUBSTITUTION_LINK_BASE, client);
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
      content.setCell(hour, min(weekDay, 5), cell);
    } else if (hours.length == 2) {
      // Hour range (5-6)
      var hourStart = int.parse(hours[0]);
      var hourEnd = int.parse(hours[1]);
      for (var i = hourStart; i < hourEnd + 1; i++) {
        content.setCell(i-1, min(weekDay, 5), cell);
      }
    }
  }
}

Future<void> fillTimeTable(String course, String linkBase, client, Content content, List<String> subjects) async {
  Response response = await client.get('${linkBase}_${course}.htm');
  if (response.statusCode != 200) {
    print("Cannot get timetable");
    return;
  }

  var document = parse(response.body);

  // Find all elements with attr rules
  List<dom.Element> tables = new List<dom.Element>();
  List<dom.Element> elements = document.getElementsByTagName("body")[0].children[0].children;
  for (int i = 0; i < elements.length; i++) {
    if (elements[i].attributes.containsKey("rules")) {
      tables.add(elements[i]);
    }
  }
  var mainTimeTable = tables[0];
  var footnoteTable = tables[1];
  var footnoteMap = parseFootnoteTable(subjects, footnoteTable);
  parseMainTimeTable(content, subjects, mainTimeTable, footnoteMap);
}


class Area {
  int columnStart;
  int columnEnd;
  int rowStart;
  int rowEnd;

  @override
  String toString() {
    return "{Area columnStart:${columnStart},columnEnd:${columnEnd}, rowStart:${rowStart}, rowEnd:${rowEnd}}";
  }
}


HashMap<String,List<Footnote>> parseFootnoteTable(List<String> subjects, dom.Element footnoteTable) {
  List<dom.Element> rows = footnoteTable.children[0].children;

  List<String> headerColumnsText = new List<String>();
  HashMap<String, List<int>> headerColumnStringIndexMap = new HashMap<String, List<int>>();
  HashMap<int, List<String>> columnData = new HashMap<int, List<String>>();

  // Find column header text
  var headerColumns = rows[0].children;
  for (var i = 0; i < headerColumns.length; i++) {
    var headerColumn = headerColumns[i];
    headerColumnsText.add(strip(headerColumn.text));
    columnData[i] = new List<String>();
  }

  // Map column text to column indexes
  for (var i = 0; i < headerColumnsText.length; i++) {
    var headerColumnText = headerColumnsText[i];
    if (headerColumnStringIndexMap.containsKey(headerColumnText)) {
      headerColumnStringIndexMap[headerColumnText].add(i);
    } else {
      headerColumnStringIndexMap[headerColumnText] = [i];
    }
  }
  rows.removeAt(0);  // remove header from rows

  // Convert format to columns first instead of rows
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    var row = rows[rowIndex];
    var columns = row.children;
    for (var i = 0; i < columns.length; i++) {
      columnData[i].add(strip(columns[i].text).replaceAll("\n", ""));
    }
  }

  // Find footnote areas
  List<Area> areas = new List<Area>();
  List<String> areaFootnotes = new List<String>();

  // Loop over all columns with the header Nr.
  var nrList = headerColumnStringIndexMap["Nr."];
  for (var i = 0; i < nrList.length; i++) {
    var columnIndex = nrList[i];
    var column = columnData[columnIndex];
    var currentFootnoteIndex = column[0];

    // Get the columnStart and End
    var columnStart = columnIndex;
    int columnEnd;
    if (i >= nrList.length-1) {
      columnEnd = columnData.length-1;
    } else {
      columnEnd = nrList[i+1]-1;
    }

    // Setup first area
    var currentArea = new Area();
    currentArea.rowStart = 0;
    currentArea.columnStart = columnStart;
    currentArea.columnEnd = columnEnd;
    var lastJ = 0;

    // Loop over one column with the header Nr.
    for (var j = 0; j < column.length; j++) {
      var currentValue = column[j];
      lastJ = j;

      if (currentValue == " " || currentValue == currentFootnoteIndex) {  // No start of a new area
        continue;
      } else {  // Start of new area
        // Add old area to list
        currentArea.rowEnd = j-1;
        areaFootnotes.add(currentFootnoteIndex);
        areas.add(currentArea);

        // Init new area
        currentFootnoteIndex = column[j];
        currentArea = new Area();
        currentArea.rowStart = j;
        currentArea.columnStart = columnStart;
        currentArea.columnEnd = columnEnd;
      }
    }
    // Add last area to list
    currentArea.rowEnd = lastJ;
    areaFootnotes.add(currentFootnoteIndex);
    areas.add(currentArea);
  }


  // Parse footnote areas
  var lastFootnoteKey = "1)";
  HashMap<String,List<Footnote>> footnotesMap = new HashMap<String,List<Footnote>>();
  for (var i = 0; i < areas.length; i++) {
    var footnoteKey = areaFootnotes[i];
    var area = areas[i];
    var relevantColumns = new List<List<String>>();

    // Get relevant columns within area
    var columnTextList = new List<String>();
    for (var i = area.columnStart; i < area.columnEnd + 1; i++) {
      var relevantColumn = new List<String>();
      columnTextList.add(headerColumnsText[i]);
      for (var j = area.rowStart; j < area.rowEnd + 1; j++) {
        relevantColumn.add(columnData[i][j]);
      }
      relevantColumns.add(relevantColumn);
    }

    // Init footnotes
    var footnotes = new List<Footnote>();
    for (var i = 0; i < area.rowEnd-area.rowStart + 1; i++) {
      footnotes.add(new Footnote());
    }

    // Loop over all columns
    for (var columnIndex = 0; columnIndex < relevantColumns.length; columnIndex++) {
      // Loop over all rows
      for (var rowIndex = 0; rowIndex < relevantColumns[columnIndex].length; rowIndex++) {
        var value = relevantColumns[columnIndex][rowIndex];

        // Switch on current column header and set footnotes
        switch (columnTextList[columnIndex]) {
          case "Le.,Fa.,Rm.":
            var splitValue = value.split(",");
            if (splitValue.length >= 3) {
              footnotes[rowIndex].teacher = splitValue[0];
              footnotes[rowIndex].subject = splitValue[1];
              footnotes[rowIndex].room = splitValue[2];
            }
            break;
          case "Kla":
            footnotes[rowIndex].schoolClass = value;
            break;
          case "Schulwoche":
            footnotes[rowIndex].schoolWeek = value;
            break;
          case "Text":
            footnotes[rowIndex].text = value;
            break;
          default:
            break;
        }
      }
    }

    // Append footnote to last footnote if the current footnote key is " "
    if (footnoteKey == " ") {
      footnotesMap[lastFootnoteKey].addAll(footnotes);
    } else {
      footnotesMap[footnoteKey] = footnotes;
      lastFootnoteKey = footnoteKey;
    }
  }
  return footnotesMap;
}

void parseMainTimeTable(Content content, List<String> subjects, dom.Element mainTimeTable, HashMap<String,List<Footnote>> footnoteMap) {
  List<dom.Element> rows = mainTimeTable.children[0].children;
  rows.removeAt(0);

  for (var y = 0; y < rows.length; y++) {
    var row = rows[y];
    var columns = row.children;
    var tableX = 0;
    if (columns.length <= 0) {
      continue;
    }
    for (var x = 0; x < 6; x++) {
      if (x == 0) {
        parseOneCell(columns[x], x, y, content, subjects, footnoteMap);
        tableX++;
      } else {
        var doParseCell = true;
        if (y != 0) {
          var contentY = (y / 2).floor();
          if (contentY >= content.cells.length) {
            continue;
          }
          var isDoubleClass = content.cells[contentY][x].isDoubleClass;
          if (isDoubleClass) {
            doParseCell = false;
          }
        }
        if (doParseCell) {
          parseOneCell(columns[tableX], x, y, content, subjects, footnoteMap);
          tableX++;
        }
      }
    }
  }
}

void parseOneCell(dom.Element cellDom, int x, int y, Content content, List<String> subjects, HashMap<String,List<Footnote>> footnoteMap) {
  var cell = new Cell();
  // Sidebar
  if (x == 0) {
    return;
  }

  // Normal cell
  var hours = int.parse(cellDom.attributes["rowspan"]) / 2;
  cell.isDoubleClass = hours == 2;
  List<dom.Element> cellData = cellDom.children[0].children[0].children;
  if (cellData.length >= 2) {
    List<dom.Element> teacherAndRoom = cellData[0].children;
    List<dom.Element> subjectAndFootnote = cellData[1].children;
    cell.teacher = strip(teacherAndRoom[0].text);
    cell.room = strip(teacherAndRoom[1].text);
    cell.subject = strip(subjectAndFootnote[0].text);

    // Check if footnote exists
    if (subjectAndFootnote.length > 1) {
      // Get footnotes
      var footnoteKey = strip(subjectAndFootnote[1].text);
      var footnotes = footnoteMap[footnoteKey];

      // Filter out footnotes that don't matter to the user
      var requiredFootnotes = new List<Footnote>();
      for (var footnote in footnotes) {
        if (subjects.contains(footnote.subject)) {
          requiredFootnotes.add(footnote);
        }
      }

      // If only one required footnote set the subject room and teacher
      if (requiredFootnotes.length == 1) {
        cell.subject = requiredFootnotes[0].subject;
        cell.room = requiredFootnotes[0].room;
        cell.teacher = requiredFootnotes[0].teacher;
      }
      cell.footnotes = requiredFootnotes;  // Set footnotes of cell
    }
  }

  if (subjects.contains(cell.subject)) {  // If user dose not have that subject skip that class
    for (var i = 0; i < hours; i++) {
      content.setCell((y / 2).floor() + i, x, cell);
    }
  } else {
    for (var i = 0; i < hours; i++) {
      cell = content.cells[(y / 2).floor() + i][x];
      cell.isDoubleClass = true;
      content.setCell((y / 2).floor() + i, x, cell);
    }
  }
}

Future<List<HashMap<String, String>>> getCourseSubsitutionPlan(
    String course, String linkBase, client) async {
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

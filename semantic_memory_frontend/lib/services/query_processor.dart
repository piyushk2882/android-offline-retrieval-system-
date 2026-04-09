String processQuery(String query) {

  query = query.toLowerCase();

  List<String> removeWords = [
    "find",
    "me",
    "give",
    "show",
    "please",
    "i want",
    "can you",
  ];

  for (var word in removeWords) {
    query = query.replaceAll(word, "");
  }

  return query.trim();
}
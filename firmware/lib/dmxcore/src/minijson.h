// minijson.h – liest Felder aus einem flachen JSON-Objekt und schreibt Strings
// escaped. Reicht für die Einstellungen über USB, ohne Fremdbibliothek.
//   {"name":"Bühne","wifi":"ap","u0":0,"en1":true}
#pragma once
#include <cstdint>
#include <string>

namespace minijson {

// Rohwert eines Schlüssels finden. Strings werden entschlüsselt (\" \\ \n \uXXXX).
// type: 's' String, 'n' Zahl, 'b' true/false, '0' null.
bool find(const std::string& json, const char* key, std::string& value, char& type);

bool getString(const std::string& json, const char* key, std::string& out);
bool getInt(const std::string& json, const char* key, long& out);
bool getBool(const std::string& json, const char* key, bool& out);

// "text" mit Anführungszeichen und Escapes anhängen.
void appendString(std::string& out, const char* text);

}  // namespace minijson

#include "minijson.h"

#include <cstdlib>
#include <cstring>

namespace minijson {
namespace {

void skipWs(const std::string& s, size_t& i) {
  while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
}

void putUtf8(std::string& out, unsigned cp) {
  if (cp < 0x80) {
    out += static_cast<char>(cp);
  } else if (cp < 0x800) {
    out += static_cast<char>(0xC0 | (cp >> 6));
    out += static_cast<char>(0x80 | (cp & 0x3F));
  } else {
    out += static_cast<char>(0xE0 | (cp >> 12));
    out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
    out += static_cast<char>(0x80 | (cp & 0x3F));
  }
}

// String ab s[i] == '"' lesen. i steht danach hinter dem schließenden '"'.
bool readString(const std::string& s, size_t& i, std::string& out) {
  if (i >= s.size() || s[i] != '"') return false;
  ++i;
  out.clear();
  while (i < s.size()) {
    char c = s[i++];
    if (c == '"') return true;
    if (c != '\\') {
      out += c;
      continue;
    }
    if (i >= s.size()) return false;
    char e = s[i++];
    switch (e) {
      case 'n': out += '\n'; break;
      case 't': out += '\t'; break;
      case 'r': out += '\r'; break;
      case 'b': out += '\b'; break;
      case 'f': out += '\f'; break;
      case 'u': {
        if (i + 4 > s.size()) return false;
        unsigned cp = static_cast<unsigned>(std::strtoul(s.substr(i, 4).c_str(), nullptr, 16));
        i += 4;
        putUtf8(out, cp);
        break;
      }
      default: out += e; break;  // \" \\ \/
    }
  }
  return false;
}

// Beliebigen Wert überspringen bzw. als Rohtext liefern.
bool readValue(const std::string& s, size_t& i, std::string& value, char& type) {
  skipWs(s, i);
  if (i >= s.size()) return false;
  char c = s[i];
  if (c == '"') {
    type = 's';
    return readString(s, i, value);
  }
  if (c == '{' || c == '[') {  // verschachtelt: überspringen
    int depth = 0;
    bool inStr = false;
    size_t start = i;
    for (; i < s.size(); ++i) {
      char d = s[i];
      if (inStr) {
        if (d == '\\') ++i;
        else if (d == '"') inStr = false;
        continue;
      }
      if (d == '"') inStr = true;
      else if (d == '{' || d == '[') ++depth;
      else if ((d == '}' || d == ']') && --depth == 0) {
        ++i;
        value = s.substr(start, i - start);
        type = 'o';
        return true;
      }
    }
    return false;
  }
  size_t start = i;
  while (i < s.size() && s[i] != ',' && s[i] != '}' && s[i] != ' ' && s[i] != '\n' &&
         s[i] != '\r' && s[i] != '\t')
    ++i;
  value = s.substr(start, i - start);
  if (value == "true" || value == "false") type = 'b';
  else if (value == "null") type = '0';
  else type = 'n';
  return !value.empty();
}

}  // namespace

bool find(const std::string& s, const char* key, std::string& value, char& type) {
  size_t i = 0;
  skipWs(s, i);
  if (i >= s.size() || s[i] != '{') return false;
  ++i;
  std::string k;
  for (;;) {
    skipWs(s, i);
    if (i >= s.size() || s[i] == '}') return false;
    if (!readString(s, i, k)) return false;
    skipWs(s, i);
    if (i >= s.size() || s[i] != ':') return false;
    ++i;
    if (!readValue(s, i, value, type)) return false;
    if (k == key) return true;
    skipWs(s, i);
    if (i < s.size() && s[i] == ',') ++i;
  }
}

bool getString(const std::string& json, const char* key, std::string& out) {
  char t;
  std::string v;
  if (!find(json, key, v, t) || t != 's') return false;
  out = v;
  return true;
}

bool getInt(const std::string& json, const char* key, long& out) {
  char t;
  std::string v;
  if (!find(json, key, v, t) || t != 'n') return false;
  char* end = nullptr;
  long r = std::strtol(v.c_str(), &end, 10);
  if (end == v.c_str()) return false;
  out = r;
  return true;
}

bool getBool(const std::string& json, const char* key, bool& out) {
  char t;
  std::string v;
  if (!find(json, key, v, t) || t != 'b') return false;
  out = v == "true";
  return true;
}

void appendString(std::string& out, const char* text) {
  out += '"';
  for (const char* p = text; p && *p; ++p) {
    const unsigned char c = static_cast<unsigned char>(*p);
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          static const char hex[] = "0123456789abcdef";
          out += "\\u00";
          out += hex[c >> 4];
          out += hex[c & 0xF];
        } else {
          out += static_cast<char>(c);
        }
    }
  }
  out += '"';
}

}  // namespace minijson

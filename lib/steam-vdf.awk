# Original, bounded KV1 reader/editor for Steam local configuration.
# SPDX-License-Identifier: MIT
# Keep all input bytes except the selected LaunchOptions token/pair.
# Bash supplies the final-newline flag because ordinary awk strips record separators.
BEGIN { BINMODE = 3 }
{
    if (NR > 1) raw = raw "\n"
    raw = raw $0
}
function die(message) {
    print "Steam VDF: " message > "/dev/stderr"
    exit 2
}
function next_token(    c, n, out, start, closed) {
    while (pos <= length(raw)) {
        c = substr(raw, pos, 1)
        if (c ~ /[ \t\r\n]/) { pos++; continue }
        if (substr(raw, pos, 2) == "//") {
            while (pos <= length(raw) && substr(raw, pos, 1) != "\n") pos++
            continue
        }
        break
    }
    ts = pos
    tv = ""
    if (pos > length(raw)) return "eof"
    c = substr(raw, pos++, 1)
    if (c == "{" || c == "}" || c == "=") { te = pos - 1; return c }
    if (c == "\"") {
        out = ""; closed = 0
        while (pos <= length(raw)) {
            c = substr(raw, pos++, 1)
            if (c == "\"") { closed = 1; break }
            if (c == "\\") {
                if (pos > length(raw)) die("unterminated escape")
                n = substr(raw, pos++, 1)
                if (n == "n") c = "\n"
                else if (n == "r") c = "\r"
                else if (n == "t") c = "\t"
                else if (n == "\\" || n == "\"") c = n
                else c = "\\" n
            }
            out = out c
        }
        if (!closed) die("unterminated quoted token")
        tv = out; te = pos - 1
        return "string"
    }
    if (c == "#" || c == "[" || c == "]" || substr(raw, ts, 2) == "/*")
        die("directives, conditions and block comments require manual editing")
    out = c
    while (pos <= length(raw)) {
        c = substr(raw, pos, 1)
        if (c ~ /[ \t\r\n{}="]/ || substr(raw, pos, 2) == "//") break
        out = out c; pos++
    }
    tv = out; te = pos - 1
    return "string"
}
function parse(parent, nested, depth,    token, key, start, id) {
    if (depth > 64) die("nesting exceeds the supported limit")
    while (1) {
        token = next_token()
        if (token == "eof") {
            if (nested) die("missing closing brace")
            return
        }
        if (token == "}") {
            if (!nested) die("unexpected closing brace")
            closeAt[parent] = ts; finish[parent] = te
            return
        }
        if (token != "string") die("expected a key")
        key = tv; start = ts
        token = next_token()
        if (token == "=") token = next_token()
        if (token != "{" && token != "string") die("key has no value")
        id = ++count
        if (count > 500000) die("too many keys")
        owner[id] = parent; name[id] = tolower(key); beginAt[id] = start
        valueAt[id] = ts; finish[id] = te
        if (token == "{") {
            kind[id] = "object"
            parse(id, 1, depth + 1)
        } else {
            kind[id] = "scalar"; value[id] = tv
        }
    }
}
function child(parent, key,    i, found) {
    found = 0
    for (i = 1; i <= count; i++) {
        if (owner[i] == parent && name[i] == tolower(key)) {
            if (found) die("ambiguous duplicate key: " key)
            found = i
        }
    }
    return found
}
function object_child(parent, key,    id) {
    id = child(parent, key)
    if (id && kind[id] != "object") die("expected an object: " key)
    return id
}
function scalar_child(parent, key,    id) {
    id = child(parent, key)
    if (id && kind[id] != "scalar") die("expected a scalar: " key)
    return id
}
function safe_line(text) {
    if (text ~ /[\r\n\t]/) die("multiline paths/options require manual setup")
    return text
}
function quote(text,    i, c, out) {
    out = "\""
    for (i = 1; i <= length(text); i++) {
        c = substr(text, i, 1)
        if (c == "\\" || c == "\"") out = out "\\" c
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else out = out c
    }
    return out "\""
}
function apps_node(    id, i, parts) {
    split("UserLocalConfigStore/Software/Valve/Steam/apps", parts, "/")
    id = 0
    for (i = 1; i <= 5; i++) {
        id = object_child(id, parts[i])
        if (!id) return 0
    }
    return id
}
function insert_before_close(id, text,    where) {
    where = closeAt[id]
    return substr(raw, 1, where - 1) eol text eol substr(raw, where)
}
END {
    if (ENVIRON["STEAM_VDF_FINAL_NL"] == "1") raw = raw "\n"
    if (length(raw) > 16777216) die("file exceeds the 16 MiB automatic-edit limit")
    if (raw ~ /[\001-\010\013\014\016-\037]/ || index(raw, sprintf("%c", 0)))
        die("binary/control characters are not supported")
    pos = 1
    if (substr(raw, 1, 3) == "\357\273\277") pos = 4
    parse(0, 0, 0)
    action = ENVIRON["STEAM_VDF_ACTION"]
    if (action == "libraries") {
        root = object_child(0, "libraryfolders")
        if (!root) die("no libraryfolders object")
        for (i = 1; i <= count; i++) {
            if (owner[i] != root || name[i] !~ /^[0-9]+$/) continue
            if (kind[i] == "scalar") print safe_line(value[i])
            else {
                path = scalar_child(i, "path")
                if (path) print safe_line(value[path])
            }
        }
        exit 0
    }
    if (action == "installdir") {
        root = object_child(0, "AppState")
        if (!root) die("no AppState object")
        appid = scalar_child(root, "appid")
        path = scalar_child(root, "installdir")
        if (!appid || value[appid] != "22320" || !path) die("manifest is not Morrowind app 22320")
        print safe_line(value[path]); exit 0
    }
    apps = apps_node()
    app = apps ? object_child(apps, "22320") : 0
    option = app ? scalar_child(app, "LaunchOptions") : 0
    if (action == "get") {
        if (!option) exit 4
        printf "%s", safe_line(value[option]); exit 0
    }
    if (action != "set" && action != "remove") die("unknown operation")
    if (!apps) die("apps section is absent; open Steam once or use manual Launch Options")
    eol = index(raw, "\r\n") ? "\r\n" : "\n"
    if (action == "remove") {
        if (option) raw = substr(raw, 1, beginAt[option] - 1) substr(raw, finish[option] + 1)
    } else {
        replacement = quote(safe_line(ENVIRON["STEAM_VDF_VALUE"]))
        if (option) raw = substr(raw, 1, valueAt[option] - 1) replacement substr(raw, finish[option] + 1)
        else if (app) raw = insert_before_close(app, "\t\t\t\t\t\t\"LaunchOptions\"\t\t" replacement)
        else raw = insert_before_close(apps, "\t\t\t\t\t\"22320\"" eol "\t\t\t\t\t{" eol "\t\t\t\t\t\t\"LaunchOptions\"\t\t" replacement eol "\t\t\t\t\t}")
    }
    printf "%s", raw
}

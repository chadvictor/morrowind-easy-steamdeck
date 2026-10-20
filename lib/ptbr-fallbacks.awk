# Merge translated fallback keys, retaining original values for all other keys.
# Read UTF-8 bytes as-is; the game-data encoding is unrelated to config encoding.
function key(line, comma) {
    comma = index(line, ",")
    if (comma <= 10 || length(line) <= comma) return ""
    return substr(line, 10, comma - 10)
}
function fail(message) { print "PT-BR: " message > "/dev/stderr"; bad = 1; exit 1 }
{
    sub(/\r+$/, "")
    if (FNR == NR) {
        if ($0 == "" || /^#/) next
        if (!/^fallback=/) fail("Unexpected line in fallback fragment")
        k = key($0)
        if (k !~ /^[A-Za-z][A-Za-z0-9_]*$/ || k in translated) fail("Invalid/duplicate translated fallback")
        translated[k] = $0
        order[++count] = k
        next
    }
    if (!/^fallback=/) next
    k = key($0)
    if (k == "" || k in seen) fail("Invalid/duplicate original fallback")
    seen[k] = 1
    print (k in translated ? translated[k] : $0)
}
END {
    if (bad) exit 1
    if (count != 63) fail("Expected the 63 fallbacks from the pinned translation")
    for (i = 1; i <= count; i++) if (!(order[i] in seen)) print translated[order[i]]
}

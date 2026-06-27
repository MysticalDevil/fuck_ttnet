function should_remove(obj) {
  return obj ~ /"rule_id"[[:space:]]*:[[:space:]]*3011076/ &&
         obj ~ /"action"[[:space:]]*:[[:space:]]*"tc"/ &&
         obj ~ /"drop"[[:space:]]*:[[:space:]]*1/ &&
         obj ~ /"possibility"[[:space:]]*:[[:space:]]*100/ &&
         obj ~ /"host_group"[[:space:]]*:[[:space:]]*\[[^]]*"[*]"[^]]*\]/ &&
         obj ~ /"contain_group"[[:space:]]*:[[:space:]]*\[[^]]*"(\\\/|\/)"[^]]*\]/ &&
         obj ~ /"service_name"[[:space:]]*:[[:space:]]*"drop flow"/
}

function object_start(text, pos,    i, c, depth) {
  depth = 0
  for (i = pos; i >= 1; i--) {
    c = substr(text, i, 1)
    if (c == "}") {
      depth++
    } else if (c == "{") {
      if (depth == 0) {
        return i
      }
      depth--
    }
  }
  return 0
}

function object_end(text, pos,    i, c, depth, in_string, escaped) {
  depth = 0
  in_string = 0
  escaped = 0
  for (i = pos; i <= length(text); i++) {
    c = substr(text, i, 1)
    if (in_string) {
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        in_string = 0
      }
      continue
    }
    if (c == "\"") {
      in_string = 1
    } else if (c == "{") {
      depth++
    } else if (c == "}") {
      depth--
      if (depth == 0) {
        return i
      }
    }
  }
  return 0
}

function previous_non_space(text, pos,    i, c) {
  for (i = pos; i >= 1; i--) {
    c = substr(text, i, 1)
    if (c !~ /[[:space:]]/) {
      return i
    }
  }
  return 0
}

function next_non_space(text, pos,    i, c) {
  for (i = pos; i <= length(text); i++) {
    c = substr(text, i, 1)
    if (c !~ /[[:space:]]/) {
      return i
    }
  }
  return 0
}

{
  if (NR > 1) {
    json = json "\n"
  }
  json = json $0
}

END {
  offset = 1
  while ((rel = index(substr(json, offset), "3011076")) > 0) {
    pos = offset + rel - 1
    start = object_start(json, pos)
    end = object_end(json, start)
    if (start == 0 || end == 0) {
      offset = pos + 7
      continue
    }

    obj = substr(json, start, end - start + 1)
    if (!should_remove(obj)) {
      offset = end + 1
      continue
    }

    prev = previous_non_space(json, start - 1)
    nxt = next_non_space(json, end + 1)
    if (prev > 0 && substr(json, prev, 1) == ",") {
      json = substr(json, 1, prev - 1) substr(json, end + 1)
      offset = prev
    } else if (nxt > 0 && substr(json, nxt, 1) == ",") {
      json = substr(json, 1, start - 1) substr(json, nxt + 1)
      offset = start
    } else {
      json = substr(json, 1, start - 1) substr(json, end + 1)
      offset = start
    }
  }
  print json
}

// Type inference engine
//
// Parses a JSON string and recursively walks the dynamic value
// to build up a Schema IR.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import json2gleam/schema.{
  type Field, type Schema, Field, SBool, SDynamic, SFloat, SInt, SList,
  SNullable, SObject, SString,
}
import justin

/// things that might go wrong
pub type InferError {
  JsonParseError(String)
  EmptyInput
}

/// give it a JSON string, get back a schema.
/// The root_name is used for the top-level object type name.
pub fn infer_schema(
  json_string: String,
  root_name: String,
) -> Result(Schema, InferError) {
  case string.trim(json_string) {
    "" -> Error(EmptyInput)
    trimmed -> {
      case json.parse(trimmed, decode.dynamic) {
        Ok(value) -> Ok(infer_value(value, root_name))
        Error(_) -> Error(JsonParseError("invalid JSON"))
      }
    }
  }
}

/// Recursively figure out the schema for a dynamic value.
/// name_hint is used when we encounter an object (it becomes the type name)
fn infer_value(value: Dynamic, name_hint: String) -> Schema {
  case dynamic.classify(value) {
    "String" -> SString
    "Int" -> SInt
    "Float" -> SFloat
    "Bool" -> SBool

    // null → we don't know what type it is yet, just that it's nullable
    "Nil" -> SNullable(SDynamic)

    "List" -> infer_list(value, name_hint)

    // Erlang maps show up as "Dict" that's JSON objects
    _ -> infer_object_or_fallback(value, name_hint)
  }
}

/// Infer schema for a JSON array
/// Merges all elements so that if objects have different fields 
/// missing fields become optional in the merged schema
fn infer_list(value: Dynamic, name_hint: String) -> Schema {
  case decode.run(value, decode.list(decode.dynamic)) {
    Ok(items) -> {
      case items {
        [] -> SList(SDynamic)
        [first, ..rest] -> {
          let singular = singularize(name_hint)
          let base = infer_value(first, singular)
          let merged =
            list.fold(rest, base, fn(acc, item) {
              merge_schemas(acc, infer_value(item, singular))
            })
          SList(merged)
        }
      }
    }
    Error(_) -> SList(SDynamic)
  }
}

/// Try to decode as an object (dict), fall back to SDynamic
fn infer_object_or_fallback(value: Dynamic, name_hint: String) -> Schema {
  case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
    Ok(entries) -> infer_object(entries, name_hint)
    Error(_) -> SDynamic
  }
}

/// Build an SObject from a dict of string keys to dynamic values
fn infer_object(entries: dict.Dict(String, Dynamic), name: String) -> Schema {
  let fields =
    entries
    |> dict.to_list()
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(entry) {
      let #(key, value) = entry
      let gleam_name = sanitize_field_name(key)
      let child_name = to_pascal_case(key)
      Field(
        json_key: key,
        gleam_name: gleam_name,
        schema: infer_value(value, child_name),
        optional: False,
      )
    })
    |> deduplicate_field_names()

  SObject(name: to_pascal_case(name), fields: fields)
}

/// If two fields end up with the same gleam_name after sanitization
/// append _2, _3, etc. to make them unique.
fn deduplicate_field_names(fields: List(Field)) -> List(Field) {
  let #(result, _) =
    list.fold(fields, #([], dict.new()), fn(acc, field) {
      let #(done, seen) = acc
      let name = field.gleam_name
      case dict.get(seen, name) {
        Error(_) -> {
          // first time seeing this name
          #([field, ..done], dict.insert(seen, name, 1))
        }
        Ok(count) -> {
          // collision — append a number
          let new_name = name <> "_" <> int.to_string(count + 1)
          let new_field = Field(..field, gleam_name: new_name)
          #([new_field, ..done], dict.insert(seen, name, count + 1))
        }
      }
    })
  list.reverse(result)
}

/// Convert a key to a valid snake_case Gleam field name,
/// handling reserved words and weird characters
fn sanitize_field_name(key: String) -> String {
  let snake = justin.snake_case(key)

  // clean out any characters that aren't valid in Gleam identifiers
  let cleaned = clean_identifier(snake)

  // handle empty result (e.g. key was all special chars)
  let cleaned = case cleaned {
    "" -> "field_"
    _ -> cleaned
  }

  // Cannot start with a digit or underscore (underscore = discard in Gleam fields)
  let cleaned = case
    starts_with_digit(cleaned) || string.starts_with(cleaned, "_")
  {
    True -> "field_" <> cleaned
    False -> cleaned
  }

  // don't collide with Gleam reserved words
  case is_reserved(cleaned) {
    True -> cleaned <> "_"
    False -> cleaned
  }
}

/// Strip out anything that's not a letter digit or underscore
fn clean_identifier(s: String) -> String {
  s
  |> string.to_graphemes()
  |> list.filter(fn(c) { is_alphanumeric(c) || c == "_" })
  |> string.concat()
}

fn is_alphanumeric(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn starts_with_digit(s: String) -> Bool {
  case string.first(s) {
    Ok("0")
    | Ok("1")
    | Ok("2")
    | Ok("3")
    | Ok("4")
    | Ok("5")
    | Ok("6")
    | Ok("7")
    | Ok("8")
    | Ok("9") -> True
    _ -> False
  }
}

/// Gleam reserved words, if a field name matches, we add an underscore
fn is_reserved(name: String) -> Bool {
  case name {
    "as"
    | "assert"
    | "auto"
    | "case"
    | "const"
    | "delegate"
    | "derive"
    | "echo"
    | "else"
    | "fn"
    | "if"
    | "implement"
    | "import"
    | "let"
    | "macro"
    | "opaque"
    | "panic"
    | "pub"
    | "test"
    | "todo"
    | "type"
    | "use" -> True
    _ -> False
  }
}

/// PascalCase from any string, used for type names
pub fn to_pascal_case(s: String) -> String {
  justin.pascal_case(s)
}

/// Very naive singularization — just strip trailing 's' for type names
/// e.g. "Tags" → "Tag", "Items" → "Item"
/// Not perfect but good enough for most API responses
fn singularize(name: String) -> String {
  case string.ends_with(name, "s") && string.length(name) > 1 {
    True -> string.drop_end(name, 1)
    False -> name
  }
}

// schema merging

/// Merge two schemas into one
/// Used when array elements have different shapes fields in one but
/// not the other become optional, and null types get refined.
pub fn merge_schemas(a: Schema, b: Schema) -> Schema {
  case a, b {
    // identical primitives
    SString, SString -> SString
    SInt, SInt -> SInt
    SFloat, SFloat -> SFloat
    SBool, SBool -> SBool
    SDynamic, SDynamic -> SDynamic

    // Int + Float → Float (JSON doesn't distinguish 1 vs 1.0)
    SInt, SFloat | SFloat, SInt -> SFloat

    // nullable + nullable → merge inners
    SNullable(inner_a), SNullable(inner_b) ->
      SNullable(merge_schemas(inner_a, inner_b))

    // nullable(dynamic) + concrete → nullable(concrete) — refine the null
    SNullable(SDynamic), other -> SNullable(unwrap_nullable(other))
    other, SNullable(SDynamic) -> SNullable(unwrap_nullable(other))

    // nullable + non-nullable → nullable with merged inner
    SNullable(inner), other | other, SNullable(inner) ->
      SNullable(merge_schemas(inner, other))

    // lists merge their inner types
    SList(inner_a), SList(inner_b) -> SList(merge_schemas(inner_a, inner_b))

    // objects merge their fields
    SObject(name, fields_a), SObject(_, fields_b) ->
      merge_objects(name, fields_a, fields_b)

    // incompatible types → Dynamic
    _, _ -> SDynamic
  }
}

/// Unwrap one layer of SNullable to avoid double-wrapping
fn unwrap_nullable(schema: Schema) -> Schema {
  case schema {
    SNullable(inner) -> inner
    other -> other
  }
}

/// Merge two sets of object fields
/// Fields in both → merge schemas, keep optional if either was optional
/// Fields in only one side → mark as optional
fn merge_objects(
  name: String,
  fields_a: List(Field),
  fields_b: List(Field),
) -> Schema {
  let dict_a = fields_to_dict(fields_a)
  let dict_b = fields_to_dict(fields_b)

  let all_keys =
    list.append(
      list.map(fields_a, fn(f) { f.json_key }),
      list.map(fields_b, fn(f) { f.json_key }),
    )
    |> list.unique()
    |> list.sort(string.compare)

  let merged_fields =
    list.map(all_keys, fn(key) {
      case dict.get(dict_a, key), dict.get(dict_b, key) {
        // field in both samples
        Ok(fa), Ok(fb) ->
          Field(
            json_key: fa.json_key,
            gleam_name: fa.gleam_name,
            schema: merge_schemas(fa.schema, fb.schema),
            optional: fa.optional || fb.optional,
          )
        // only in first → optional
        Ok(fa), Error(_) -> Field(..fa, optional: True)
        // only in second → optional
        Error(_), Ok(fb) -> Field(..fb, optional: True)
        // unreachable
        Error(_), Error(_) -> panic as "unreachable"
      }
    })

  SObject(name, merged_fields)
}

/// Convert a list of fields to a dict keyed by json_key for fast lookup
fn fields_to_dict(fields: List(Field)) -> dict.Dict(String, Field) {
  list.fold(fields, dict.new(), fn(acc, f) { dict.insert(acc, f.json_key, f) })
}

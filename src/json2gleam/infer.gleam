// Type inference engine
//
// Parses a JSON string and recursively walks the dynamic value
// to build up a Schema IR.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import json2gleam/schema.{
  type Schema, Field, SBool, SDynamic, SFloat, SInt, SList, SNullable, SObject,
  SString,
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
fn infer_list(value: Dynamic, name_hint: String) -> Schema {
  case decode.run(value, decode.list(decode.dynamic)) {
    Ok(items) -> {
      case items {
        // empty array / can't tell what's inside
        [] -> SList(SDynamic)
        // peek at the first element to figure out the item type
        [first, ..] -> SList(infer_value(first, singularize(name_hint)))
      }
    }
    // shouldn't happen if classify said "List", but just in case
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

  SObject(name: to_pascal_case(name), fields: fields)
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

  // Cannot start with a digit
  let cleaned = case starts_with_digit(cleaned) {
    True -> "_" <> cleaned
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

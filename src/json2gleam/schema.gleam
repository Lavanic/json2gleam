/// Schema IR — the intermediate representation between parsed JSON and
/// emitted Gleam code.
///
/// JSON values are inferred into a Schema, which the emitter then walks
/// to produce type definitions, decoder functions, and encoder functions.
/// Represents the inferred schema of a JSON value.
pub type Schema {
  SString
  SInt
  SFloat
  SBool
  SDynamic
  SNullable(Schema)
  SList(Schema)
  SObject(name: String, fields: List(Field))
}

/// Check if a name is a Gleam reserved word
/// shared between infer (field names) and emit (encoder params)
pub fn is_reserved(name: String) -> Bool {
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

/// A single field within an SObject schema.
pub type Field {
  Field(
    /// Original JSON key exactly as it appears (e.g., "firstName")
    json_key: String,
    /// Snake-cased Gleam identifier (e.g., "first_name")
    gleam_name: String,
    /// The inferred type of this field's value
    schema: Schema,
    /// True if this field was absent in at least one sample
    optional: Bool,
  )
}

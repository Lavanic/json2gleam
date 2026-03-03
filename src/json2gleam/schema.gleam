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

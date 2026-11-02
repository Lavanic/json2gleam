/// json2gleam — Generate Gleam types, decoders, and encoders from JSON.
///
/// CLI entrypoint: parses arguments, reads JSON input, runs the
/// inference + emission pipeline, and writes the result.
import argv
import filepath
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/yielder
import glint
import json2gleam/emit
import json2gleam/infer
import justin
import simplifile
import stdin

// keep in sync with gleam.toml
const version = "0.1.0"

pub fn main() {
  glint.new()
  |> glint.with_name("json2gleam")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: run())
  |> glint.run(argv.load().arguments)
}

fn run() -> glint.Command(Nil) {
  // -- flags --
  use file_flag <- glint.flag(
    glint.string_flag("file")
    |> glint.flag_default("")
    |> glint.flag_help("Path to a JSON file. Omit to read from stdin."),
  )
  use root_name_flag <- glint.flag(
    glint.string_flag("root-name")
    |> glint.flag_help("Name for the root type (required)"),
  )
  use out_flag <- glint.flag(
    glint.string_flag("out")
    |> glint.flag_default("")
    |> glint.flag_help("Output file path (defaults to stdout)"),
  )
  use module_flag <- glint.flag(
    glint.string_flag("module")
    |> glint.flag_default("")
    |> glint.flag_help(
      "Module path (e.g. myapp/user). Sets output path if --out is not given.",
    ),
  )
  use no_encoders_flag <- glint.flag(
    glint.bool_flag("no-encoders")
    |> glint.flag_default(False)
    |> glint.flag_help("Skip encoder generation"),
  )
  use no_decoders_flag <- glint.flag(
    glint.bool_flag("no-decoders")
    |> glint.flag_default(False)
    |> glint.flag_help("Skip decoder generation"),
  )
  use no_singularize_flag <- glint.flag(
    glint.bool_flag("no-singularize")
    |> glint.flag_default(False)
    |> glint.flag_help(
      "Don't singularize array element type names (e.g. keep Users instead of User)",
    ),
  )
  use numbers_as_float_flag <- glint.flag(
    glint.bool_flag("numbers-as-float")
    |> glint.flag_default(False)
    |> glint.flag_help(
      "Treat all JSON numbers as Float (avoids Int/Float ambiguity)",
    ),
  )
  use version_flag <- glint.flag(
    glint.bool_flag("version")
    |> glint.flag_default(False)
    |> glint.flag_help("Print version and exit"),
  )
  use clipboard_flag <- glint.flag(
    glint.bool_flag("clipboard")
    |> glint.flag_default(False)
    |> glint.flag_help("Copy output to system clipboard instead of stdout"),
  )

  use <- glint.command_help(
    "Generate Gleam types, decoders, and encoders from JSON.",
  )
  use _named, _args, flags <- glint.command()

  // --version: print and exit
  case result.unwrap(version_flag(flags), False) {
    True -> {
      io.println("json2gleam " <> version)
      halt(0)
    }
    False -> Nil
  }

  let file = result.unwrap(file_flag(flags), "")

  // grab root-name: explicit flag, or infer from filename, or error
  let root_name = case root_name_flag(flags) {
    Ok("") | Error(_) ->
      case infer_root_name_from_file(file) {
        "" ->
          die(
            "--root-name is required when reading from stdin (use PascalCase, e.g. MyType)\nUsage: json2gleam --root-name=MyType [--file=input.json]",
          )
        name -> {
          io.println_error(
            "info: using root type name \"" <> name <> "\" from filename",
          )
          name
        }
      }
    Ok(name) -> name
  }

  // Gleam types must start with uppercase — auto-fix with a hint
  let root_name = case string.first(root_name) {
    Ok(first) ->
      case first == string.uppercase(first) {
        True -> root_name
        False -> {
          let fixed = justin.pascal_case(root_name)
          io.println_error(
            "hint: Gleam type names must start with uppercase. Using \""
            <> fixed
            <> "\"",
          )
          fixed
        }
      }
    _ -> root_name
  }

  let out = result.unwrap(out_flag(flags), "")
  let module = result.unwrap(module_flag(flags), "")
  let no_encoders = result.unwrap(no_encoders_flag(flags), False)
  let no_decoders = result.unwrap(no_decoders_flag(flags), False)
  let no_singularize = result.unwrap(no_singularize_flag(flags), False)
  let numbers_as_float = result.unwrap(numbers_as_float_flag(flags), False)
  let clipboard = result.unwrap(clipboard_flag(flags), False)

  // read JSON input
  let json_string = case file {
    "" -> read_stdin()
    path -> read_file(path)
  }

  case json_string {
    "" -> die("no JSON input provided")
    _ -> Nil
  }

  // infer schema
  let infer_options =
    infer.InferOptions(
      singularize: !no_singularize,
      numbers_as_float: numbers_as_float,
    )
  let schema = case
    infer.infer_schema_with_options(json_string, root_name, infer_options)
  {
    Ok(s) -> s
    Error(infer.EmptyInput) -> die("empty JSON input")
    Error(infer.JsonParseError(msg)) -> die(msg)
  }

  // build emit options
  let options = emit.EmitOptions(decoders: !no_decoders, encoders: !no_encoders)

  // gen the code
  let header = case module {
    "" -> ""
    m -> "// Generated by json2gleam — save as src/" <> m <> ".gleam\n\n"
  }
  let code = header <> emit.emit_module(schema, options)

  // figure out where to write
  let output_path = case out, module {
    "", "" -> ""
    "", m -> "src/" <> m <> ".gleam"
    path, _ -> path
  }

  // write output
  case output_path, clipboard {
    "", True -> {
      copy_to_clipboard(code)
      io.println_error("copied to clipboard!")
    }
    "", False ->
      case is_tty() {
        True -> io.print(colorize(code))
        False -> io.print(code)
      }
    path, _ -> {
      // make sure parent dirs exist
      let dir = filepath.directory_name(path)
      case dir {
        "" -> Nil
        d -> {
          let _ = simplifile.create_directory_all(d)
          Nil
        }
      }
      case simplifile.write(path, code) {
        Ok(_) -> io.println("wrote " <> path)
        Error(_) -> die("could not write to " <> path)
      }
    }
  }
}

/// Read all of stdin into one string
fn read_stdin() -> String {
  stdin.read_lines()
  |> yielder.to_list()
  |> string.join("\n")
}

/// Read a single JSON file
fn read_file(path: String) -> String {
  case simplifile.read(path) {
    Ok(content) -> content
    Error(_) -> die("could not read file " <> path)
  }
}

// ---- ANSI colorization ----

/// ANSI escape codes for terminal colors
const reset = "\u{001b}[0m"

const magenta = "\u{001b}[35m"

const cyan = "\u{001b}[36m"

const green = "\u{001b}[32m"

const dim = "\u{001b}[2m"

const yellow = "\u{001b}[33m"

/// Colorize generated Gleam code for terminal display.
/// Applies syntax highlighting: keywords, types, strings, comments.
fn colorize(code: String) -> String {
  code
  |> string.split("\n")
  |> list.map(colorize_line)
  |> string.join("\n")
}

fn colorize_line(line: String) -> String {
  let trimmed = string.trim(line)
  case string.starts_with(trimmed, "//") {
    // Comment lines → dim
    True -> dim <> line <> reset
    False ->
      case string.starts_with(trimmed, "import ") {
        // Import lines → cyan
        True -> cyan <> line <> reset
        False ->
          case string.starts_with(trimmed, "///") {
            // Doc comments → dim
            True -> dim <> line <> reset
            False ->
              line
              |> colorize_keywords()
              |> colorize_strings()
          }
      }
  }
}

/// Highlight Gleam keywords in magenta
fn colorize_keywords(line: String) -> String {
  line
  |> string.replace("pub type ", magenta <> "pub type " <> reset)
  |> string.replace("pub fn ", magenta <> "pub fn " <> reset)
  |> string.replace(
    "decode.success(",
    yellow <> "decode.success" <> reset <> "(",
  )
  |> string.replace("decode.field(", yellow <> "decode.field" <> reset <> "(")
  |> string.replace(
    "decode.optional_field(",
    yellow <> "decode.optional_field" <> reset <> "(",
  )
  |> string.replace(
    "decode.optional(",
    yellow <> "decode.optional" <> reset <> "(",
  )
  |> string.replace("decode.list(", yellow <> "decode.list" <> reset <> "(")
  |> string.replace("json.object(", yellow <> "json.object" <> reset <> "(")
  |> string.replace("json.array(", yellow <> "json.array" <> reset <> "(")
  |> string.replace("json.nullable(", yellow <> "json.nullable" <> reset <> "(")
}

/// Highlight string literals in green
fn colorize_strings(line: String) -> String {
  do_colorize_strings(line, "", False)
}

fn do_colorize_strings(
  remaining: String,
  acc: String,
  in_string: Bool,
) -> String {
  case string.pop_grapheme(remaining) {
    Error(_) ->
      case in_string {
        True -> acc <> reset
        False -> acc
      }
    Ok(#("\"", rest)) ->
      case in_string {
        False -> do_colorize_strings(rest, acc <> green <> "\"", True)
        True -> do_colorize_strings(rest, acc <> "\"" <> reset, False)
      }
    Ok(#(char, rest)) -> do_colorize_strings(rest, acc <> char, in_string)
  }
}

/// Check if stdout is a terminal (not piped to a file)
@external(erlang, "json2gleam_ffi", "is_tty")
fn is_tty() -> Bool

/// Copy text to the system clipboard.
/// Tries wl-copy (Wayland), xclip (X11), xsel (X11), pbcopy (macOS).
fn copy_to_clipboard(text: String) -> Nil {
  // Write to a temp file, then pipe it to a clipboard command.
  // This avoids shell escaping issues with the text content.
  let tmp = "/tmp/json2gleam_clip.txt"
  case simplifile.write(tmp, text) {
    Ok(_) -> {
      // Try clipboard commands in order — first success wins
      let commands = [
        "wl-copy < " <> tmp,
        "xclip -selection clipboard < " <> tmp,
        "xsel --clipboard --input < " <> tmp,
        "pbcopy < " <> tmp,
      ]
      let copied = list.any(commands, fn(cmd) { run_shell(cmd) == 0 })
      case copied {
        True -> {
          let _ = simplifile.delete(tmp)
          Nil
        }
        False -> {
          let _ = simplifile.delete(tmp)
          die(
            "could not copy to clipboard. Install wl-copy (Wayland), xclip, xsel, or pbcopy (macOS)",
          )
        }
      }
    }
    Error(_) -> die("could not write temp file for clipboard")
  }
}

/// Run a shell command and return the exit code
@external(erlang, "json2gleam_ffi", "run_shell")
fn run_shell(command: String) -> Int

/// Infer a PascalCase root type name from a file path.
/// "test_data/stripe_event.json" → "StripeEvent"
/// Returns "" if no filename or no usable base name.
fn infer_root_name_from_file(path: String) -> String {
  case path {
    "" -> ""
    _ -> {
      let base = filepath.base_name(path)
      // strip .json extension if present
      let name = case string.ends_with(base, ".json") {
        True -> string.drop_end(base, 5)
        False -> base
      }
      case name {
        "" -> ""
        _ -> justin.pascal_case(name)
      }
    }
  }
}

/// Exit w/ status code
@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

/// Print an error message then exit. Returns any type so it
/// satisfies the type checker
fn die(msg: String) -> a {
  io.println_error("error: " <> msg)
  halt(1)
  panic as "unreachable"
}

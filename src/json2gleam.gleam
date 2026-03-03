/// json2gleam — Generate Gleam types, decoders, and encoders from JSON.
///
/// CLI entrypoint: parses arguments, reads JSON input, runs the inference
/// and emission pipeline, and writes the result to stdout or a file.
import argv
import gleam/io
import glint

pub fn main() {
  glint.new()
  |> glint.with_name("json2gleam")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: run())
  |> glint.run(argv.load().arguments)
}

fn run() -> glint.Command(Nil) {
  use <- glint.command_help(
    "Generate Gleam types, decoders, and encoders from JSON.",
  )
  use _named, _args, _flags <- glint.command()
  // TODO: implement CLI logic in Chunk 6
  io.println("json2gleam — not yet implemented")
}

# json2gleam

Generates Gleam types, decoders, and encoders from a JSON sample, so you
don't have to write them by hand.

Given `user.json`:

```json
{
  "id": 1,
  "name": "Ollie",
  "tags": ["admin", "beta"],
  "active": true
}
```

`json2gleam --file=user.json` prints:

```gleam
import gleam/dynamic/decode
import gleam/json

pub type User {
  User(
    active: Bool,
    id: Int,
    name: String,
    tags: List(String),
  )
}

pub fn user_decoder() -> decode.Decoder(User) {
  use active <- decode.field("active", decode.bool)
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use tags <- decode.field("tags", decode.list(decode.string))
  decode.success(User(active:, id:, name:, tags:))
}

pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #("active", json.bool(user.active)),
    #("id", json.int(user.id)),
    #("name", json.string(user.name)),
    #("tags", json.array(user.tags, json.string)),
  ])
}
```

Nested objects get their own types, null and missing fields become `Option`,
and array element names are singularized (`users` becomes `User`).

## Usage

Read from a file or pipe JSON in:

```sh
json2gleam --file=payload.json
curl -s https://api.github.com/repos/gleam-lang/gleam | json2gleam --root-name=Repo
```

`--module=myapp/user` writes the output to `src/myapp/user.gleam`,
`--clipboard` copies it instead of printing. See `--help` for the rest.

## Install

Clone the repo and run it with Gleam, or build a standalone escript:

```sh
gleam run -- --file=sample.json
gleam run -m gleescript   # produces ./json2gleam
```

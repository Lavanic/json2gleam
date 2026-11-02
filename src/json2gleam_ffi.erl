%% FFI helpers for the json2gleam CLI.
-module(json2gleam_ffi).
-export([is_tty/0, run_shell/1]).

%% True when stdout is attached to a terminal (io:columns succeeds
%% only on a tty; it returns {error, enotsup} when piped).
is_tty() ->
    case io:columns() of
        {ok, _} -> true;
        _ -> false
    end.

%% Run a command through /bin/sh and return its exit code.
%% Output is discarded: it is redirected to /dev/null so that commands
%% which fork a long-lived child (e.g. wl-copy serving the clipboard)
%% cannot hold the port's pipes open and delay exit detection.
run_shell(Command) ->
    Full = <<Command/binary, " > /dev/null 2>&1">>,
    Port = open_port({spawn_executable, "/bin/sh"}, [
        {args, [<<"-c">>, Full]},
        exit_status
    ]),
    wait_for_exit(Port).

wait_for_exit(Port) ->
    receive
        {Port, {exit_status, Status}} -> Status;
        {Port, {data, _}} -> wait_for_exit(Port)
    end.

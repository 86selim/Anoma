# Anoma

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `anoma` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:anoma, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/anoma>.


## Contributing

This codebase follows a git style simialr to
[git](https://git-scm.com/) or
[linux](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git).

New code should be based on `base`, and no attempt to keep it up to
sync with `main` should be had. When one's topic is ready just submit
a PR on github and the maintiner will handle any merge conflicts.

Happy hacking, and don't be afraid to submit patches.

## Quick Testing

Using the command line or through vscode is quite slow, I recommend
not using it, instead here are some alternatives


If one is fine running all tests, then the following works:

```elixir
% MIX_ENV=test iex -S mix

iex(1)> Mix.Tasks.Test.run([]) # runs all tests
iex(2)> r AnomaTest.PartialTx  # reload the tests we care about
iex(3)> Mix.Tasks.Test.run([]) # runs only the single module
# ExUnit.run can also be ran equivalently as well after the first run!
```

Where after each tests it caches, so you will need to recompile the
test you want to rerun. Overall this works fine.



However if every test is slow, or you don't want to run every test in
a module, then the following will be more useful

```elixir
% iex -S mix

iex(1)> ExUnit.start
iex(2)> c "test/partialtx_test.exs" # only once
iex(3)> ExUnit.configure(exclude: [:test], include: [line: 12]) # test line
iex(4)> ExUnit.run
iex(5)> r AnomaTest.PartialTx
iex(6)> ExUnit.run
```

Tmp cheatsheet:

Starting phoenix:

```
$ iex -S mix phx.server
iex(1)> Supervisor.start_link([{Phoenix.PubSub, name: Webview.PubSub}],  [strategy: :one_for_one, name: Webview.Supervisor])
iex(2)> Webview.Endpoint.start_link
```

Setup for running tx flow demo:
```
Anoma.Node.Ordering.start_link
Anoma.Node.Storage.start_link
Anoma.Node.Storage.reset
import Anoma.Tx
import Anoma.Node.Ordering
```

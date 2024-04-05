defmodule Anoma.Cli do
  @spec argument_parser() :: Optimus.t()
  def argument_parser() do
    Optimus.new!(
      name: "anoma",
      description: """
      Starts up Anoma.
      """,
      allow_unknown_args: true,
      parse_double_dash: true,
      args: [],
      flags: [
        nohalt: [
          long: "--no-halt",
          help: "typical IEX command",
          required: false
        ],
        restore: [
          long: "--restore",
          help: "Restore from ",
          required: false
        ]
      ],
      options: [
        # Should take from home dir once it's ready
        snapshot_location: [
          long: "--snapshot-location",
          help: "Location of the snapshot",
          parser: :string,
          required: false,
          default: fn() -> "./" end
        ]
      ],
      subcommands: [
        nockma: Nock.Cli.argument_option()
      ]
    )
  end

  @doc """
  Provides taking CLI argument parsing to arguments used by the
  application
  """
  @spec cli_arguments_to_start_arguments(Optimus.ParseResult.t()) ::
          Keyword.t()
  def cli_arguments_to_start_arguments(%Optimus.ParseResult{
        args: _args,
        flags: _flags,
        options: _options,
        unknown: _unknown
      }) do
    []
  end

  # Optimus.t() is opaque so the help fails to type check, but it's OK
  @dialyzer {:nowarn_function, start_application: 1}
  @spec start_application([String.t()]) :: {:ok, pid()} | {:error, any()}
  def start_application(arguments) do
    start_anoma = fn parsed ->
      parsed
      |> cli_arguments_to_start_arguments()
      |> Anoma.start_logic()
    end

    case Optimus.parse(Anoma.Cli.argument_parser(), arguments) do
      # This will occur when you launch your repl
      {:ok, args = %{flags: %{nohalt: true}}} ->
        start_anoma.(args)

      # This will occur when one tries to test the codebase
      {:ok, args = %{unknown: [_, "test" | _]}} ->
        start_anoma.(args)

      {:ok, [:nockma], parsed} ->
        Nock.Cli.main(parsed)
        System.halt(0)

      :help ->
        IO.puts(Optimus.help(Anoma.Cli.argument_parser()))
        System.halt(0)

      _ ->
        IO.puts(Optimus.help(Anoma.Cli.argument_parser()))
        System.halt(1)
    end
  end
end

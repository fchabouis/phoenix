defmodule Mix.Tasks.Phx.Routes do
  use Mix.Task
  alias Phoenix.Router.ConsoleFormatter

  @shortdoc "Prints all routes"

  @moduledoc """
  Prints all routes for the default or a given router.

      $ mix phx.routes
      $ mix phx.routes MyApp.AnotherRouter

  The default router is inflected from the application
  name unless a configuration named `:namespace`
  is set inside your application configuration. For example,
  the configuration:

      config :my_app,
        namespace: My.App

  will exhibit the routes for `My.App.Router` when this
  task is invoked without arguments.

  Umbrella projects do not have a default router and
  therefore always expect a router to be given. An
  alias can be added to mix.exs to automate this:

      defp aliases do
        [
          "phx.routes": "phx.routes MyAppWeb.Router",
          # aliases...
        ]

  """

  @doc false
  def run(args, base \\ Mix.Phoenix.base()) do
    Mix.Task.run("compile", args)
    Mix.Task.reenable("phx.routes")

    {router_mod, opts} =
      case OptionParser.parse(args, switches: [endpoint: :string, router: :string, info: :string]) do
        {opts, [passed_router], _} -> {router(passed_router, base), opts}
        {opts, [], _} -> {router(opts[:router], base), opts}
      end

    case Keyword.get(opts, :info) do
      nil -> list_routes({router_mod, opts}, base)
      url -> get_url_info(url, {router_mod, opts})
    end
  end

  def get_url_info(url, {router_mod, _opts}) do
    %{path: path} = URI.parse(url)

    meta = Phoenix.Router.route_info(router_mod, "GET", path, "")
    %{plug: plug, plug_opts: plug_opts} = meta

    {module, func_name} =
      if log_mod = meta[:log_module] do
        {log_mod, meta[:log_function]}
      else
        {plug, plug_opts}
      end

    Mix.shell().info("Module: #{inspect(module)}")
    if func_name, do: Mix.shell().info("Function: #{inspect(func_name)}")

    file_path = get_file_path(module)

    if line = get_line_number(module, func_name) do
      Mix.shell().info("#{file_path}:#{line}")
    else
      Mix.shell().info("#{file_path}")
    end
  end

  def list_routes({router_mod, opts}, base) do
    router_mod
    |> ConsoleFormatter.format(endpoint(opts[:endpoint], base))
    |> Mix.shell().info()
  end

  defp endpoint(nil, base) do
    loaded(web_mod(base, "Endpoint"))
  end
  defp endpoint(module, _base) do
    loaded(Module.concat([module]))
  end

  defp router(nil, base) do
    if Mix.Project.umbrella?() do
      Mix.raise """
      umbrella applications require an explicit router to be given to phx.routes, for example:

          $ mix phx.routes MyAppWeb.Router

      An alias can be added to mix.exs aliases to automate this:

          "phx.routes": "phx.routes MyAppWeb.Router"

      """
    end
    web_router = web_mod(base, "Router")
    old_router = app_mod(base, "Router")

    loaded(web_router) || loaded(old_router) || Mix.raise """
    no router found at #{inspect web_router} or #{inspect old_router}.
    An explicit router module may be given to phx.routes, for example:

        $ mix phx.routes MyAppWeb.Router

    An alias can be added to mix.exs aliases to automate this:

        "phx.routes": "phx.routes MyAppWeb.Router"

    """
  end
  defp router(router_name, _base) do
    arg_router = Module.concat([router_name])
    loaded(arg_router) || Mix.raise "the provided router, #{inspect(arg_router)}, does not exist"
  end

  defp loaded(module) do
    if Code.ensure_loaded?(module), do: module
  end

  defp app_mod(base, name), do: Module.concat([base, name])

  defp web_mod(base, name), do: Module.concat(["#{base}Web", name])

  defp get_file_path(module_name) do
    [compile_infos] = Keyword.get_values(module_name.module_info(), :compile)
    [source] = Keyword.get_values(compile_infos, :source)
    source
  end

  defp get_line_number(_, nil), do: nil

  defp get_line_number(module, function_name) do
    {_, _, _, _, _, _, functions_list} = Code.fetch_docs(module)

    function_infos =
      functions_list
      |> Enum.find(fn {{type, name, _}, _, _, _, _} ->
        type == :function and name == function_name
      end)

    case function_infos do
      {_, line, _, _, _} -> line
      nil -> nil
    end
  end
end

defmodule Coxir.Commander do
  import __MODULE__.Helpers

  defmacro __using__(_opts) do
    quote do
      unquote reset()
      unquote definitions()
    end
  end

  defmacro __before_compile__(environment) do
    # Parameters
    module = environment
    |> Map.get(:module)

    commands = module
    |> Module.get_attribute(:commands)
    |> List.flatten
    |> Enum.reverse

    prefix = module
    |> Module.get_attribute(:prefix)
    |> List.wrap
    |> Enum.join(" ")

    length = prefix
    |> IO.iodata_length

    # Handler
    guard = quote do
      content
      |> binary_part(0, unquote(length))
      == unquote(prefix)
    end

    tuple = quote do
      {:MESSAGE_CREATE, %{content: content} = message}
    end

    default = quote do
      _other -> :ignore
    end

    clauses = commands
    |> Enum.map(&clause/1)
    |> Kernel.++([default])
    |> List.flatten

    handler = quote do
      length = unquote(prefix)
      |> String.length

      content
      |> String.split_at(length)
      |> Kernel.elem(1)
      |> case do
        unquote(clauses)
      end

      {:ok, state}
    end

    quote do
      def handle_event(event, state) do
        case event do
          unquote(tuple) when unquote(guard) ->
            unquote(handler)
          _other ->
            {:ok, state}
        end
      end
    end
  end

  defmacro command(function, body) do
    body = body
    |> blockify

    {name, func, arities} = \
    function |> inject(body)

    quote do
      unquote(arities)
      |> Enum.map(&
        @commands {
          __MODULE__,
          unquote(name),
          @space,
          @description,
          &1
        }
      )
      unquote func
      unquote reset()
    end
  end

  @params [:message, :author, :content,
          :channel, :member, :guild]
  defp blockify(do: block) do
    block = \
    quote do
      # Variables
      author = message[:author]
      content = message[:content]
      channel = message[:channel]
      member = channel[:guild_id]
      |> Coxir.Struct.Member.get(author[:id])

      guild = channel[:guild_id]
      |> Coxir.Struct.Guild.get

      # Warnings
      _author = author
      _content = content
      _channel = channel
      _member = member
      _guild = guild

      # Conditions
      [
        @channel == :any or \
        @channel == channel.id,
        @permit == :any or \
        permit?(author, channel, @permit)
      ]
      |> Enum.reduce(&and/2)
      |> case do
        true ->
          unquote(block)
        false ->
          :ignore
      end
    end
    |> Macro.postwalk(fn
      {name, [], _atom} = tuple when name in @params ->
        {:var!, [], [tuple]}
      other -> other
    end)

    [do: block]
  end

  defp clause({from, name, space, _description, arity}) do
    # Path
    path = space
    |> case do
      [{root, child}] ->
        [root, child]
      other -> other
    end
    |> List.wrap
    |> Kernel.++([name])
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> String.trim_leading

    path = arity
    |> case do
      1 -> path
      _ -> path <> " "
    end

    quote do
      unquote(path) <> rest ->
        from = unquote(from)
        name = unquote(name)
        rest = rest
        |> String.trim
        |> String.split(" ")
        |> case do
          [""] -> []
          list -> list
        end
        count = length(rest)
        arity = unquote(arity)
        |> :erlang.-(1)

        # Join as last param
        rest = \
        cond do
          count > arity ->
            {head, tail} = rest
            |> Enum.split(arity - 1)

            last = tail
            |> Enum.join(" ")

            head ++ [last]
          true ->
            rest
        end

        # Final
        rest = [message | rest]
        cond do
          length(rest) <= arity + 1 ->
            apply(from, name, rest)
          true ->
            :ignore
        end
    end
  end
end

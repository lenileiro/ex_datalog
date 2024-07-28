defmodule ExDatalog.Perm do
  defmacro sigil_PERM({:<<>>, _, [string]}, _opts) do
    calling_module = __CALLER__.module

    quote do
      ExDatalog.Perm.parse_and_validate_permission(unquote(string), unquote(calling_module))
    end
  end

  def parse_and_validate_permission(json_string, calling_module) do
    case Jason.decode(json_string) do
      {:ok, parsed} ->
        {:ok, parsed}

        validate_and_generate_rules(parsed, calling_module)

      {:error, %Jason.DecodeError{data: data, position: position, token: token}} ->
        raise "Invalid JSON at position #{position}: #{token} in #{data}"
    end
  end

  def validate_and_generate_rules(parsed, calling_module) when is_list(parsed) do
    Enum.each(parsed, &validate_rule_structure/1)

    module_ast = ExDatalog.RuleGenerator.create_module(parsed, calling_module)

    case Code.compile_quoted(module_ast) do
      [{module, _bytecode}] when is_atom(module) -> {:ok, parsed}
      other -> {:error, "Unexpected compilation result: #{inspect(other)}"}
    end
  end

  def validate_and_generate_rules(_parsed, _calling_module) do
    raise "Top level must be a list of rules"
  end

  defp validate_rule_structure(%{
         "name" => _name,
         "conditions" => conditions,
         "conclusions" => conclusions
       })
       when is_list(conditions) and is_list(conclusions) do
    Enum.each(conditions, &validate_condition/1)
    Enum.each(conclusions, &validate_conclusion/1)
  end

  defp validate_rule_structure(_) do
    raise "Each rule must have 'name', 'conditions', and 'conclusions'"
  end

  defp validate_condition(condition) when is_list(condition) and length(condition) == 6, do: :ok

  defp validate_condition(_) do
    raise "Each condition must be a list of 6 elements"
  end

  defp validate_conclusion(conclusion) when is_list(conclusion) and length(conclusion) == 6,
    do: :ok

  defp validate_conclusion(_) do
    raise "Each conclusion must be a list of 6 elements"
  end
end

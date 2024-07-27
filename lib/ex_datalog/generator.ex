defmodule ExDatalog.RuleGenerator do
  @moduledoc """
  Generates Elixir code for permission rules based on the parsed JSON structure.
  """

  @doc """
  Generates the module code containing all the permission rules.
  """
  def generate_module_code(rules) do
    functions = Enum.map(rules, &generate_rule_function/1)

    """
    defmodule ExDatalog.Perm.Rules do
    #{Enum.join(functions, "\n\n")}
    end
    """
  end

  defp generate_rule_function(rule) do
    %{"name" => name, "conditions" => conditions, "conclusions" => [conclusion]} = rule

    function_body =
      if length(conditions) == 1 do
        generate_single_condition_function(name, List.first(conditions), conclusion)
      else
        generate_double_condition_function(name, conditions, conclusion)
      end

    " #{function_body}"
  end

  defp generate_single_condition_function(name, condition, conclusion) do
    static_matches = extract_static_matches(condition)

    args = "arg0 = %{#{Enum.join(static_matches, ", ")}}"
    result = generate_result(conclusion, [condition])

    """
    def #{name}(#{args}) do
    #{result}
    end
    """
  end

  defp generate_double_condition_function(name, [condition1, condition2], conclusion) do
    static_matches1 = extract_static_matches(condition1)
    static_matches2 = extract_static_matches(condition2)
    shared_vars = find_shared_variables(condition1, condition2)

    args1 = static_matches1 ++ shared_vars
    args2 = static_matches2 ++ shared_vars

    arg_string1 = "arg0 = %{#{Enum.join(args1, ", ")}}"
    arg_string2 = "arg1 = %{#{Enum.join(args2, ", ")}}"

    result = generate_result(conclusion, [condition1, condition2])

    """
    def #{name}(#{arg_string1}, #{arg_string2}) do
    #{result}
    end
    """
  end

  defp extract_static_matches(condition) do
    condition
    |> Enum.zip([
      :object_namespace,
      :object_id,
      :object_relation,
      :subject_namespace,
      :subject_id,
      :subject_relation
    ])
    |> Enum.filter(fn {value, _} ->
      (is_binary(value) and not String.starts_with?(value, "$")) or is_nil(value)
    end)
    |> Enum.map(fn {value, key} ->
      if is_nil(value), do: "#{key}: nil", else: "#{key}: \"#{value}\""
    end)
  end

  defp find_shared_variables(condition1, condition2) do
    vars1 = extract_variables(condition1)
    vars2 = extract_variables(condition2)

    MapSet.intersection(vars1, vars2)
    |> Enum.map(fn var ->
      key =
        Enum.at(
          [
            :object_namespace,
            :object_id,
            :object_relation,
            :subject_namespace,
            :subject_id,
            :subject_relation
          ],
          Enum.find_index(condition1, &(&1 == "$#{var}"))
        )

      "#{key}: #{var}"
    end)
  end

  defp extract_variables(condition) do
    condition
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "$")))
    |> Enum.map(&String.trim_leading(&1, "$"))
    |> MapSet.new()
  end

  defp generate_result(conclusion, conditions) do
    vars =
      [
        :object_namespace,
        :object_id,
        :object_relation,
        :subject_namespace,
        :subject_id,
        :subject_relation
      ]
      |> Enum.zip(conclusion)
      |> Enum.map(fn {key, value} ->
        case value do
          "$" <> var ->
            arg_index =
              if length(conditions) > 1 and
                   Enum.at(List.last(conditions), Enum.find_index(conclusion, &(&1 == value))) ==
                     value,
                 do: 1,
                 else: 0

            "  #{key}: arg#{arg_index}.#{var}"

          nil ->
            "  #{key}: nil"

          value when is_binary(value) ->
            "  #{key}: \"#{value}\""

          _ ->
            "  #{key}: _"
        end
      end)

    " %{\n#{Enum.join(vars, ",\n")}\n }"
  end
end

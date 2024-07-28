defmodule ExDatalog.RuleGenerator do
  @moduledoc """
  Generates Elixir code for permission rules based on the parsed JSON structure.
  """

  @doc """
  Generates the module code containing all the permission rules.
  """
  def generate_module_code(rules, module_name) do
    functions = Enum.map(rules, &generate_rule_function/1)

    """
    defmodule #{module_name}.Rules do
    #{Enum.join(functions, "\n\n")}
    end
    """
  end

  def generate_rule_function(rule) do
    name = rule["name"]
    conditions = rule["conditions"]
    conclusion = List.first(rule["conclusions"])

    if length(conditions) == 1 do
      generate_single_condition_function(name, List.first(conditions), conclusion)
    else
      generate_double_condition_function(name, conditions, conclusion)
    end
  end

  def generate_single_condition_function(name, condition, conclusion) do
    static_matches = extract_static_matches(condition)
    args = "arg0 = %{#{Enum.join(static_matches, ", ")}}"
    result = generate_result(conclusion, [condition])

    """
    def #{name}(#{args}) do
      #{result}
    end
    """
  end

  def generate_double_condition_function(name, [condition1, condition2], conclusion) do
    ignored_vars_1 = find_ignored_variables(condition1, condition2)
    ignored_vars_2 = find_ignored_variables(condition2, condition1)
    arg1 = generate_arg_pattern(condition1, 0, ignored_vars_1)
    arg2 = generate_arg_pattern(condition2, 1, ignored_vars_2)

    result = generate_result(conclusion, [condition1, condition2])

    """
    def #{name}(#{arg1}, #{arg2}) do
      #{result}
    end
    """
  end

  def find_ignored_variables(condition1, condition2) do
    vars1 = extract_variables(condition1)
    vars2 = extract_variables(condition2)

    MapSet.difference(vars1, vars2)
    |> Enum.map(fn var ->
      index = Enum.find_index(condition1, &(&1 == "$#{var}"))

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
          index
        )

      "#{key}: #{var}"
    end)
  end

  defp generate_arg_pattern(condition, index, ignored_vars) do
    pattern =
      condition
      |> Enum.zip([
        :object_namespace,
        :object_id,
        :object_relation,
        :subject_namespace,
        :subject_id,
        :subject_relation
      ])
      |> Enum.map(fn
        {"$" <> var, key} -> "#{key}: #{var}"
        {nil, key} -> "#{key}: nil"
        {value, key} when is_binary(value) -> "#{key}: \"#{value}\""
      end)
      |> Enum.filter(&(&1 not in ignored_vars))
      |> Enum.join(", ")

    "arg#{index} = %{#{pattern}}"
  end

  def extract_static_matches(condition) do
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

  def find_shared_variables(condition1, condition2) do
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

  def extract_variables(condition) do
    condition
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "$")))
    |> Enum.map(&String.trim_leading(&1, "$"))
    |> MapSet.new()
  end

  def generate_result(conclusion, conditions) do
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
            {arg_index, source_key} = find_source(var, conditions)
            "#{key}: arg#{arg_index}.#{source_key}"

          nil ->
            "#{key}: nil"

          value when is_binary(value) ->
            "#{key}: \"#{value}\""

          _ ->
            "#{key}: _"
        end
      end)

    "%ExDatalog.Fact{\n  #{Enum.join(vars, ",\n  ")}\n}"
  end

  defp find_source(var, conditions) do
    Enum.with_index(conditions)
    |> Enum.find_value(fn {condition, index} ->
      source_key =
        Enum.zip(
          [
            :object_namespace,
            :object_id,
            :object_relation,
            :subject_namespace,
            :subject_id,
            :subject_relation
          ],
          condition
        )
        |> Enum.find(fn {_, value} -> value == "$#{var}" end)

      if source_key, do: {index, elem(source_key, 0)}
    end)
  end
end

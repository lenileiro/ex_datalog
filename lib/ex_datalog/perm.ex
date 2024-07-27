defmodule ExDatalog.Perm do
  def sigil_PERM(string, []), do: validate_permission(string)

  def validate_permission(json_string) do
    case Jason.decode(json_string) do
      {:ok, parsed} ->
        validate_structure(parsed)

      {:error, %Jason.DecodeError{data: data, position: position, token: token}} ->
        raise "Invalid JSON at position #{position}: #{token} in #{data}"
    end
  end

  defp validate_structure(parsed) when is_list(parsed) do
    Enum.each(parsed, &validate_rule/1)
    parsed
  end

  defp validate_structure(_), do: raise("Top level must be a list of rules")

  defp validate_rule(%{"name" => name, "conditions" => conditions, "conclusions" => conclusions})
       when is_binary(name) and is_list(conditions) and is_list(conclusions) do
    Enum.each(conditions, &validate_condition/1)
    Enum.each(conclusions, &validate_conclusion/1)
  end

  defp validate_rule(_), do: raise("Each rule must have 'name', 'conditions', and 'conclusions'")

  defp validate_condition(condition) when is_list(condition) and length(condition) == 6, do: :ok
  defp validate_condition(_), do: raise("Each condition must be a list of 6 elements")

  defp validate_conclusion(conclusion) when is_list(conclusion) and length(conclusion) == 6,
    do: :ok

  defp validate_conclusion(_), do: raise("Each conclusion must be a list of 6 elements")
end

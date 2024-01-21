defmodule ExDatalog.Fact do
  defstruct [
    :object_namespace,
    :object_id,
    :object_relation,
    :subject_namespace,
    :subject_id,
    :subject_relation
  ]
end

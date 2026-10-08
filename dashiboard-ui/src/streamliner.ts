/**
 * A streamliner card keeps a model only if its loss on the validation rows improved, and its
 * `partition` is what sets those rows aside. Without one, training runs but keeps no model, so
 * the train-then-predict a Run does cannot finish. Training alone still runs from a script, and
 * returns its statistics, but saves no weights.
 */

/** No `partition`, or one that names nothing. */
export function lacksPartition(card: Record<string, unknown>): boolean {
  if (card.type !== "streamliner") return false;
  const partition = card.partition;
  if (partition == null || partition === "") return true;
  if (typeof partition !== "object") return false;
  return Object.values(partition).every(
    (value) => value == null || value === "" || (Array.isArray(value) && value.length === 0),
  );
}

/** Training the card named `id` alone, from the workspace folder. The table must already hold
 *  what the card reads, as the cards before it write. */
export function trainingScript(id: string): string {
  return `using Pipelines, DuckDBUtils, JSON
using Base.ScopedValues: @with

doc = JSON.parsefile("pipeline/<document>.json")
pipeline = @with(
    Pipelines.MODEL_DIR => "model", Pipelines.TRAINING_DIR => "training",
    Pipelines.Pipeline(doc["nodes"], doc["groups"])
)
node = only(n for n in pipeline.nodes if n.id == ${JSON.stringify(id)})
repository = Repository("<database>.duckdb")
# The table must already hold every column this card reads.
Pipelines.train!(repository, node, "<table>", "<id column>")`;
}

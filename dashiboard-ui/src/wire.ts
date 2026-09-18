import { CARDS_STORE, FILTERS_STORE } from "./stores";
import { getFilters } from "./left-tabs/filtering";
import { getCards } from "./left-tabs/processing";

/**
 * The document as the wire takes it: `{filters, nodes, groups}`.
 *
 * One function because two places need it and they must not differ — the Run button sends it, and
 * "The document" pane claims to show what will be sent. Assembled separately, that pane could be
 * wrong in exactly the situation it exists for.
 *
 * Filters live in their own store and are converted here rather than held in this shape, following
 * the store-plus-getter split the rest of the app uses: `FILTERS_STORE` keeps what the panels edit,
 * `getFilters` emits what `DataIngestion.Filter` parses.
 */
export function wireDocument() {
  const [filters] = FILTERS_STORE;
  const [cards] = CARDS_STORE;
  return { filters: getFilters(filters), ...getCards(cards) };
}

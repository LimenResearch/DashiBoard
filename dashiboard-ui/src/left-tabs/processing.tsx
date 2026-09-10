// WIP!

import * as _ from "lodash";

import { createMemo, Store } from "solid-js";

import { DownloadJSONButton, UploadJSONButton } from "../components/JSON";
import { Card, CardPlus, cardValue } from "../cards/Card";
import { postRequest } from "../requests";
import { CARDS_STORE, CardsStore } from "../stores";

export function getCards(state: Store<CardsStore>) {
  return state.cards.map(cardValue);
}

export function Cards() {
  const [state, setState] = CARDS_STORE;
  const configs = createMemo(() =>
    postRequest("get-card-widgets", {}, null),
  );
  const safeConfigs = () => configs() || [];

  const options = () => safeConfigs().map((x: any) => x.label); // TODO update config
  const addCardAfter = (label: string, i: number) => {
    const config = safeConfigs().find((x: any) => x.label === label);
    // Deep clone to not overwrite original config
    setState((draft) =>
      {draft.cards = draft.cards.toSpliced(i + 1, 0, _.cloneDeep(config))},
    );
  };

  return (
    <>
      <CardPlus onClick={addCardAfter} options={options()}></CardPlus>
      <For each={state.cards}>
        {(card, index) => {
          return (
            <>
              <Card index={index()} {...card} />
              <CardPlus
                onClick={(label) => addCardAfter(label, index())}
                options={options()}
              />
            </>
          );
        }}
      </For>
      <DownloadJSON data={state} name="cards.json">
        Download cards
      </DownloadJSON>
      <UploadJSON def={state} onChange={setState}>
        Upload cards
      </UploadJSON>
    </>
  );
}

import {parseValue} from "./utils"

import {CardList, cardListInitialState} from "./components/card-list";
import {colNames} from "./data"

import {useState} from "react"

export function App(){
    const autocompleteOptions = colNames;

    const input = {
        options: autocompleteOptions,
        name: "Predictors",
        placeholder: "Predictors",
        className: "",
        key: "PredictorWidget"
    };

    const output = {
        options: autocompleteOptions,
        name: "Targets",
        placeholder: "Targets",
        className: "mb-8",
        key: "TargetWidget"
    };

    const textInputs = [input, output];

    const onValue = x => {
        const parsed = x.textInputs.map(({name, value}) => {
            return {name, value: parseValue(value)};
        });
        // TODO replace with API call
        alert(JSON.stringify(parsed));
    }

    const card = {name: "Streamliner", textInputs, onValue, key: "Streamliner"};
    const cardList = {cards: [card]};

    const initialState = cardListInitialState({cards: [card]});
    const [state, setState] = useState(initialState);

    return <CardList {...cardList} initialState={initialState} state={state} setState={setState}></CardList>;
}
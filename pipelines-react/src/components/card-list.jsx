import {Card, cardInitialState} from "./card"

export function cardListInitialState({cards}) {
    return {cards: cards.map(cardInitialState)};
}

export function CardList({cards, initialState, state, setState}) {
    state = Object.assign({}, state);
    state.cards = Array.from(state.cards);
    const cardWidgets = cards.map((x, i) => {
        let props = Object.assign({}, x);
        props.initialState = initialState.cards[i];
        props.state = state.cards[i];
        props.setState = (x) => {
            state.cards[i] = x;
            setState(state);
        }
        return <div key={props.key}>
            {Card(props)}
        </div>;
    });
    return <>
        {cardWidgets}
    </>;
}
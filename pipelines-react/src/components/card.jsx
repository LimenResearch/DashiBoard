import {TextInput, textInputInitialState} from "./text-input"
import {Button} from "./button"

export function cardInitialState(props) {
    const textInputs = props.textInputs.map(textInputInitialState);
    return {textInputs};
}

export function Card({name, textInputs, onValue, initialState, state, setState}) {
    if (state === null) {
        return null;
    }

    state = Object.assign({}, state); // ensure `state` is not mutated
    state.textInputs = Array.from(state.textInputs);

    const inputValues = state.textInputs.map((x, i) => {
        return {name: textInputs[i].name, value: x.value};
    });

    function handleClearing() {
        state.textInputs = initialState.textInputs;
        setState(state);
    }
    function handleClosing() {
        state = null;
        setState(state);
    }
    function handleProcess() {return onValue({textInputs: inputValues});}

    const className = "bg-white w-full p-8";

    const textInputWidgets = textInputs.map((x, i) => {
        const {name, key, ...props} = x;
        function setStateI(x) {
            state.textInputs[i] = x;
            setState(state);
        }
        const stateI = state.textInputs[i];
        return <div key={key}>
            <p className="text-blue-800 text-xl font-semibold py-4 w-full text-left">
                {name}
            </p>
            <TextInput {...props} state={stateI} setState={setStateI} />
        </div>
    });

    return <div className={className}>
        <span className="text-blue-800 text-2xl font-semibold">{name}</span>
        <span onClick={handleClosing}
              className="text-red-800 hover:text-red-900 text-2xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        {textInputWidgets}
        <div>
            <Button positive={true} onClick={handleProcess}>Process</Button>
            <Button positive={false} onClick={handleClearing}>Clear</Button>
        </div>
    </div>;
}